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
    def copy(source, dest)
      raise ArgumentError, "source must be a Larch::IMAP instance" unless source.is_a?(IMAP)
      raise ArgumentError, "dest must be a Larch::IMAP instance" unless dest.is_a?(IMAP)

      msgq  = SizedQueue.new(8)
      mutex = Mutex.new

      @copied = 0
      @failed = 0
      @total  = 0

      @log.info "copying messages from #{source.uri} to #{dest.uri}"

      source.connect
      dest.connect

      source_thread = Thread.new do
        begin
          source.scan_mailbox
          mutex.synchronize { @total = source.length }

          source.each do |id|
            next if dest.has_message?(id)

            begin
              Thread.current[:fetching] = true
              msgq << source.peek(id)
              Thread.current[:fetching] = false

            rescue Larch::IMAP::Error => e
              # TODO: Keep failed message envelopes in a buffer for later output?
              mutex.synchronize { @failed += 1 }
              @log.error e.message
              next
            end
          end

        rescue Larch::WatchdogError => e
          Thread.current[:fetching] = false

          @log.error "#{source.username}@#{source.host}: server dropped connection unexpectedly"
          source.noop
          retry

        rescue => e
          @log.fatal "#{e.class.name}: #{e.message}"
          Kernel.abort

        ensure
          msgq << :finished
        end
      end

      dest_thread = Thread.new do
        begin
          dest.scan_mailbox

          while msg = msgq.pop do
            break if msg == :finished

            if msg.envelope.from
              env_from = msg.envelope.from.first
              from = "#{env_from.mailbox}@#{env_from.host}"
            else
              from = '?'
            end

            @log.info "copying message: #{from} - #{msg.envelope.subject}"
            dest << msg

            mutex.synchronize { @copied += 1 }
          end

        rescue Larch::IMAP::Error => e
          mutex.synchronize { @failed += 1 }
          @log.error e.message
          retry

        rescue => e
          @log.fatal "#{e.class.name}: #{e.message}"
          Kernel.abort
        end
      end

      watchdog_thread = Thread.new do
        loop do
          sleep 10

          if msgq.length == 0 && source_thread[:fetching]
            source_thread.raise(WatchdogError)
          end
        end
      end

      dest_thread.join

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