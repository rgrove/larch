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

    # Copies the messages in a single IMAP folder (non-recursively) from the
    # source to the destination.
    def copy_folder(imap_from, imap_to)
      raise ArgumentError, "source must be a Larch::IMAP instance" unless imap_from.is_a?(IMAP)
      raise ArgumentError, "dest must be a Larch::IMAP instance" unless imap_to.is_a?(IMAP)

      @copied = 0
      @failed = 0
      @total  = 0

      mailbox_from_name = imap_from.uri_mailbox || 'INBOX'
      mailbox_to_name   = imap_to.uri_mailbox || 'INBOX'

      @log.info "copying messages from #{imap_from.host}/#{mailbox_from_name} to #{imap_to.host}/#{mailbox_to_name}"

      imap_from.connect
      imap_to.connect

      mailbox_from = imap_from.mailbox(mailbox_from_name)
      mailbox_to   = imap_to.mailbox(mailbox_to_name)

      @total = mailbox_from.length

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
  end

end