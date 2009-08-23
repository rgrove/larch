# Prepend this file's directory to the include path if it's not there already.
$:.unshift(File.dirname(File.expand_path(__FILE__)))
$:.uniq!

require 'cgi'
require 'digest/md5'
require 'fileutils'
require 'net/imap'
require 'time'
require 'uri'
require 'yaml'

require 'sequel'
require 'sequel/extensions/migration'

require 'larch/config'
require 'larch/errors'
require 'larch/imap'
require 'larch/imap/mailbox'
require 'larch/logger'
require 'larch/version'

module Larch

  class << self
    attr_reader :config, :db, :log, :exclude

    EXCLUDE_COMMENT = /#.*$/
    EXCLUDE_REGEX   = /^\s*\/(.*)\/\s*/
    GLOB_PATTERNS   = {'*' => '.*', '?' => '.'}
    LIB_DIR         = File.join(File.dirname(File.expand_path(__FILE__)), 'larch')

    def init(config)
      raise ArgumentError, "config must be a Larch::Config instance" unless config.is_a?(Config)

      @config = config
      @log    = Logger.new(@config[:verbosity])
      @db     = open_db(@config[:database])

      @exclude = @config[:exclude].map do |e|
        if e =~ EXCLUDE_REGEX
          Regexp.new($1, Regexp::IGNORECASE)
        else
          glob_to_regex(e.strip)
        end
      end

      load_exclude_file(@config[:exclude_file]) if @config[:exclude_file]

      Net::IMAP.debug = true if @log.level == :insane

      # Stats
      @copied = 0
      @failed = 0
      @total  = 0
    end

    # Recursively copies all messages in all folders from the source to the
    # destination.
    def copy_all(imap_from, imap_to, subscribed_only = false)
      raise ArgumentError, "imap_from must be a Larch::IMAP instance" unless imap_from.is_a?(IMAP)
      raise ArgumentError, "imap_to must be a Larch::IMAP instance" unless imap_to.is_a?(IMAP)

      @copied = 0
      @failed = 0
      @total  = 0

      imap_from.each_mailbox do |mailbox_from|
        next if excluded?(mailbox_from.name)
        next if subscribed_only && !mailbox_from.subscribed?

        mailbox_to = imap_to.mailbox(mailbox_from.name, mailbox_from.delim)
        mailbox_to.subscribe if mailbox_from.subscribed?

        copy_messages(mailbox_from, mailbox_to)
      end

    rescue => e
      @log.fatal e.message

    ensure
      summary
    end

    # Copies the messages in a single IMAP folder and all its subfolders
    # (recursively) from the source to the destination.
    def copy_folder(imap_from, imap_to)
      raise ArgumentError, "imap_from must be a Larch::IMAP instance" unless imap_from.is_a?(IMAP)
      raise ArgumentError, "imap_to must be a Larch::IMAP instance" unless imap_to.is_a?(IMAP)

      @copied = 0
      @failed = 0
      @total  = 0

      mailbox_from = imap_from.mailbox(imap_from.uri_mailbox || 'INBOX')
      mailbox_to   = imap_to.mailbox(imap_to.uri_mailbox || 'INBOX')

      copy_mailbox(mailbox_from, mailbox_to)

      imap_from.disconnect
      imap_to.disconnect

    rescue => e
      @log.fatal e.message

    ensure
      summary
    end

    # Opens a connection to the Larch message database, creating it if
    # necessary.
    def open_db(database)
      filename  = File.expand_path(database)
      directory = File.dirname(filename)

      unless File.exist?(directory)
        FileUtils.mkdir_p(directory)
        File.chmod(0700, directory)
      end

      begin
        db = Sequel.connect("sqlite://#{filename}")
        db.test_connection
      rescue => e
        @log.fatal "unable to open message database: #{e}"
        abort
      end

      # Ensure that the database schema is up to date.
      migration_dir = File.join(LIB_DIR, 'db', 'migrate')

      unless Sequel::Migrator.get_current_migration_version(db) ==
          Sequel::Migrator.latest_migration_version(migration_dir)
        begin
          Sequel::Migrator.apply(db, migration_dir)
        rescue => e
          @log.fatal "unable to migrate message database: #{e}"
          abort
        end
      end

      require 'larch/db/message'
      require 'larch/db/mailbox'
      require 'larch/db/account'

      db
    end

    def summary
      @log.info "#{@copied} message(s) copied, #{@failed} failed, #{@total - @copied - @failed} untouched out of #{@total} total"
    end

    private

    def copy_mailbox(mailbox_from, mailbox_to)
      raise ArgumentError, "mailbox_from must be a Larch::IMAP::Mailbox instance" unless mailbox_from.is_a?(Larch::IMAP::Mailbox)
      raise ArgumentError, "mailbox_to must be a Larch::IMAP::Mailbox instance" unless mailbox_to.is_a?(Larch::IMAP::Mailbox)

      return if excluded?(mailbox_from.name) || excluded?(mailbox_to.name)

      mailbox_to.subscribe if mailbox_from.subscribed?
      copy_messages(mailbox_from, mailbox_to)

      mailbox_from.each_mailbox do |child_from|
        next if excluded?(child_from.name)
        child_to = mailbox_to.imap.mailbox(child_from.name, child_from.delim)
        copy_mailbox(child_from, child_to)
      end
    end

    def copy_messages(mailbox_from, mailbox_to)
      raise ArgumentError, "mailbox_from must be a Larch::IMAP::Mailbox instance" unless mailbox_from.is_a?(Larch::IMAP::Mailbox)
      raise ArgumentError, "mailbox_to must be a Larch::IMAP::Mailbox instance" unless mailbox_to.is_a?(Larch::IMAP::Mailbox)

      return if excluded?(mailbox_from.name) || excluded?(mailbox_to.name)

      imap_from = mailbox_from.imap
      imap_to   = mailbox_to.imap

      @log.info "copying messages from #{imap_from.host}/#{mailbox_from.name} to #{imap_to.host}/#{mailbox_to.name}"

      @total += mailbox_from.length

      mailbox_from.each_guid do |guid|
        next if mailbox_to.has_guid?(guid)

        begin
          next unless msg = mailbox_from.peek(guid)

          if msg.envelope.from
            env_from = msg.envelope.from.first
            from = "#{env_from.mailbox}@#{env_from.host}"
          else
            from = '?'
          end

          @log.info "copying message: #{from} - #{msg.envelope.subject}"

          mailbox_to << msg
          @copied += 1

        rescue Larch::IMAP::Error => e
          @failed += 1
          @log.error e.message
          next
        end
      end
    end

    def excluded?(name)
      name = name.downcase

      @exclude.each do |e|
        return true if (e.is_a?(Regexp) ? !!(name =~ e) : File.fnmatch?(e, name))
      end

      return false
    end

    def glob_to_regex(str)
      str.gsub!(/(.)/) {|c| GLOB_PATTERNS[$1] || Regexp.escape(c) }
      Regexp.new("^#{str}$", Regexp::IGNORECASE)
    end

    def load_exclude_file(filename)
      @exclude ||= []
      lineno = 0

      File.open(filename, 'rb') do |f|
        f.each do |line|
          lineno += 1

          # Strip comments.
          line.sub!(EXCLUDE_COMMENT, '')
          line.strip!

          # Skip empty lines.
          next if line.empty?

          if line =~ EXCLUDE_REGEX
            @exclude << Regexp.new($1, Regexp::IGNORECASE)
          else
            @exclude << glob_to_regex(line)
          end
        end
      end

    rescue => e
      raise Larch::IMAP::FatalError, "error in exclude file at line #{lineno}: #{e}"
    end

  end

end
