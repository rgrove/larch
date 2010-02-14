# Provides thread-safe and mailbox-aware connection pooling for IMAP connections
# to a single server using Larch::IMAP.
class Larch::ConnectionPool
  # Hash of currently allocated connections. Keys are threads, and each value
  # is a Larch::IMAP instance.
  attr_reader :allocated

  # Array of Larch::IMAP instances available for use by the pool.
  attr_reader :available

  # Hash of options to pass to Larch::IMAP when creating a new connection.
  attr_accessor :imap_options

  # Maximum number of connections the pool will create per server.
  attr_reader :max_connections

  # IMAP URI for which this pool will manage connections.
  attr_reader :uri

  # Creates a new connection pool for the server specified in the given IMAP
  # URI. Any mailbox information in the URI will be discarded.
  #
  # In addition to the URI, the following options may be specified:
  #
  # [:imap_options]
  #   Options Hash to pass to Larch::IMAP when creating a new connection. See
  #   the Larch::IMAP documentation for available options.
  #
  # [:max_connections]
  #   Maximum number of connections to open to the server (default: 4).
  #
  # [:pool_sleep]
  #   Time in seconds to sleep before attempting to acquire a connection again
  #   if one is not available (default: 0.01).
  #
  # [:pool_timeout]
  #   Number of seconds to wait to acquire a connection before raising a
  #   Larch::ConnectionPool::Timeout exception (default: 60).
  def initialize(uri, options = {})
    @uri      = uri.is_a?(URI) ? uri : URI(uri)
    @uri.path = ''

    Larch::IMAP.validate_uri(@uri)

    @mutex           = Mutex.new
    @allocated       = {}
    @available       = []
    @imap_options    = options[:imap_options] || {}
    @max_connections = Integer(options[:max_connections] || 4)
    @pool_sleep      = Float(options[:pool_sleep] || 0.01)
    @pool_timeout    = Integer(options[:pool_timeout] || 60)

    raise ArgumentError, ':imap_options must be a Hash' unless @imap_options.is_a?(Hash)
    raise ArgumentError, ':max_connections must be positive' if @max_connections < 1
    raise ArgumentError, ':pool_sleep must be positive' if @pool_sleep <= 0
    raise ArgumentError, ':pool_timeout must be positive' if @pool_timeout < 1
  end

  # Removes all currently available connections, optionally yielding each
  # connection to the given block before disconnecting it. Does not remove
  # connections that are currently allocated.
  def disconnect(&block)
    sync do
      @available.each do |conn|
        block.call(conn) if block
        conn.disconnect
      end

      @available.clear
    end
  end

  # Acquires or creates a connection and passes a connected and authenticated
  # Larch::IMAP instance to the supplied block.
  #
  # If no connection is available and the pool is already using the maximum
  # number of connections, the call will block until a connection is available
  # or the pool timeout expires.
  #
  # If the pool timeout expires before a connection can be acquired, a
  # Larch::ConnectionPool::Timeout exception is raised.
  #
  # This method is re-entrant, so it can be called recursively in the same
  # thread without blocking.
  def hold
    thread = Thread.current

    if conn = allocated_connection(thread)
      return yield(conn)
    end

    begin
      unless conn = acquire(thread)
        timeout = Time.now + @pool_timeout
        sleep @pool_sleep

        until conn = acquire(thread)
          raise Timeout if Time.now > timeout
          sleep @pool_sleep
        end
      end

      yield(conn)

    ensure
      sync { release(thread) if conn }
    end
  end

  # Returns the total number of open (either available or allocated)
  # connections.
  def size
    @available.length + @allocated.length
  end

  private

  # Allocates a connection to the supplied thread if one is available. The
  # caller should NOT already have a mutex lock.
  def acquire(thread)
    sync do
      if conn = available_connection
        @allocated[thread] = conn
        conn.start
        conn
      end
    end
  end

  # Returns an available connection, or tries to create a new one if one isn't
  # available. The caller should already have a mutex lock.
  def available_connection
    @available.pop || create
  end

  # Returns the connection allocated to the specified _thread_, if any. The
  # caller should NOT already have a mutex lock.
  def allocated_connection(thread)
    sync { @allocated[thread] }
  end

  # Creates a new connection if the size of the pool is less than the maximum
  # size. The caller should already have a mutex lock.
  def create
    if (n = size) >= @max_connections
      # Try to free up any dead allocated connections.
      @allocated.each_key {|thread| release(thread) unless thread.alive? }
      n = nil
    end

    Larch::IMAP.new(@uri, @imap_options) if (n || size) < @max_connections
  end

  # Releases the connection assigned to the supplied _thread_. The caller should
  # already have a mutex lock.
  def release(thread)
    if conn = @allocated.delete(thread)
      conn.clear_response_handlers

      if conn.mailbox
        conn.mailbox.unselect
      end

      @available << conn
    end
  end

  # Yields to the given block while inside the mutex. The caller should NOT
  # already have a mutex lock.
  def sync
    @mutex.synchronize { yield }
  end

  class Timeout < Larch::Error; end
end
