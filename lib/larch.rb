# Prepend this file's directory to the include path if it's not there already.
$:.unshift(File.dirname(File.expand_path(__FILE__)))
$:.uniq!

require 'cgi'
require 'digest/md5'
require 'net/imap'
require 'time'
require 'uri'

require 'larch/errors'
require 'larch/imap'
require 'larch/imap/mailbox'
require 'larch/logger'
require 'larch/version'

module Larch

  class << self
    attr_reader :log, :exclude

    EXCLUDE_COMMENT = /#.*$/
    EXCLUDE_REGEX   = /^\s*\/(.*)\/\s*/
    GLOB_PATTERNS   = {'*' => '.*', '?' => '.'}

    def init(log_level = :info, exclude = [], exclude_file = nil)
      @log = Logger.new(log_level)

      @exclude = exclude.map do |e|
        if e =~ EXCLUDE_REGEX
          Regexp.new($1, Regexp::IGNORECASE)
        else
          glob_to_regex(e.strip)
        end
      end

      load_exclude_file(exclude_file) if exclude_file

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
        next if subscribed_only && !mailbox_from.subscribed?

        mailbox_to = imap_to.mailbox(mailbox_from.name, mailbox_from.delim)
        mailbox_to.subscribe if mailbox_from.subscribed?

        copy_messages(imap_from, mailbox_from, imap_to, mailbox_to)
      end

    rescue => e
      @log.fatal e.message

    ensure
      summary
    end

    # Copies the messages in a single IMAP folder (non-recursively) from the
    # source to the destination.
    def copy_folder(imap_from, imap_to)
      raise ArgumentError, "imap_from must be a Larch::IMAP instance" unless imap_from.is_a?(IMAP)
      raise ArgumentError, "imap_to must be a Larch::IMAP instance" unless imap_to.is_a?(IMAP)

      @copied = 0
      @failed = 0
      @total  = 0

      copy_messages(imap_from, imap_from.mailbox(imap_from.uri_mailbox || 'INBOX'),
          imap_to, imap_to.mailbox(imap_to.uri_mailbox || 'INBOX'))

      imap_from.disconnect
      imap_to.disconnect

    rescue => e
      @log.fatal e.message

    ensure
      summary
    end

    def summary
      @log.info "#{@copied} message(s) copied, #{@failed} failed, #{@total - @copied - @failed} untouched out of #{@total} total"
    end

    private

    def copy_messages(imap_from, mailbox_from, imap_to, mailbox_to)
      raise ArgumentError, "imap_from must be a Larch::IMAP instance" unless imap_from.is_a?(IMAP)
      raise ArgumentError, "mailbox_from must be a Larch::IMAP::Mailbox instance" unless mailbox_from.is_a?(IMAP::Mailbox)
      raise ArgumentError, "imap_to must be a Larch::IMAP instance" unless imap_to.is_a?(IMAP)
      raise ArgumentError, "mailbox_to must be a Larch::IMAP::Mailbox instance" unless mailbox_to.is_a?(IMAP::Mailbox)

      return if excluded?(mailbox_from.name) || excluded?(mailbox_to.name)

      @log.info "copying messages from #{imap_from.host}/#{mailbox_from.name} to #{imap_to.host}/#{mailbox_to.name}"

      imap_from.connect
      imap_to.connect

      @total += mailbox_from.length

      mailbox_from.each do |id|
        next if mailbox_to.has_message?(id)

        begin
          msg = mailbox_from.peek(id)

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
          # TODO: Keep failed message envelopes in a buffer for later output?
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
