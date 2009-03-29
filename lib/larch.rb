# Append this file's directory to the include path if it's not there already.
$:.unshift(File.dirname(File.expand_path(__FILE__)))
$:.uniq!

require 'cgi'
require 'digest/md5'
require 'net/imap'
require 'monitor'
require 'time'
require 'uri'

require 'larch/errors'
require 'larch/imap'
require 'larch/imap/mailbox'
require 'larch/logger'
require 'larch/version'

module Larch

  class << self
    attr_reader :log

    def init(log_level = :info)
      @log = Logger.new(log_level)

      @copied = 0
      @failed = 0
      @total  = 0
    end

    # Copies messages from _source_ to _dest_ if they don't already exist in
    # _dest_. Both _source_ and _dest_ must be instances of Larch::IMAP.
    def copy_folder(source, dest)
      raise ArgumentError, "source must be a Larch::IMAP instance" unless source.is_a?(IMAP)
      raise ArgumentError, "dest must be a Larch::IMAP instance" unless dest.is_a?(IMAP)

      @copied = 0
      @failed = 0
      @total  = 0

      source_mb_name = source.uri_mailbox || 'INBOX'
      dest_mb_name   = dest.uri_mailbox || 'INBOX'

      @log.info "copying messages from #{source.host}/#{source_mb_name} to #{dest.host}/#{dest_mb_name}"

      source.connect
      dest.connect

      source_mb = source.mailbox(source_mb_name)
      dest_mb   = dest.mailbox(dest_mb_name)

      @total = source_mb.length

      source_mb.each do |id|
        next if dest_mb.has_message?(id)

        begin
          msg = source_mb.peek(id)

          if msg.envelope.from
            env_from = msg.envelope.from.first
            from = "#{env_from.mailbox}@#{env_from.host}"
          else
            from = '?'
          end

          @log.info "copying message: #{from} - #{msg.envelope.subject}"

          dest_mb << msg
          @copied += 1

        rescue Larch::IMAP::Error => e
          # TODO: Keep failed message envelopes in a buffer for later output?
          @failed += 1
          @log.error e.message
          next
        end
      end

      source.disconnect
      dest.disconnect

    rescue => e
      @log.fatal e.message

    ensure
      summary
    end

    def summary
      @log.info "#{@copied} message(s) copied, #{@failed} failed, #{@total - @copied - @failed} untouched out of #{@total} total"
    end
  end

end