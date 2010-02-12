class Larch::ConnectionPool
  # Hash of currently allocated connections. Keys are IMAP URIs, and each value
  # is a hash of threads mapping to Net::IMAP instances.
  attr_reader :allocated

  # Hash of connections available for use by the pool. Keys are IMAP URIs,
  # values are arrays of Net::IMAP instances.
  attr_reader :available

  # Maximum number of connections the pool will create per server.
  attr_reader :max_connections

  # The following options may be specified:
  #
  # [:max_connections]
  #   Maximum number of connections to open per server (default: 2).
  #
  # [:pool_sleep]
  #   Time in seconds to sleep before attempting to acquire a connection again
  #   if one is not available (default: 0.01).
  #
  # [:pool_timeout]
  #   Number of seconds to wait to acquire a connection before raising a
  #   Larch::ConnectionPool::Timeout exception (default: 60).
  def initialize(options = {})
    @max_connections = Integer(options[:max_connections] || 2)
    raise ArgumentError, ':max_connections must be positive' if @max_connections < 1

    @mutex        = Mutex.new
    @allocated    = {}
    @available    = {}
    @pool_sleep   = Float(options[:pool_sleep] || 0.01)
    @pool_timeout = Integer(options[:pool_timeout] || 60)
  end

  def disconnect
  end

  # Acquires or creates a connection to the specified IMAP _uri_, passing a
  # connected Net::IMAP instance to the supplied block.
  #
  # If no connection is available and the pool is already using the maximum
  # number of connections to the specified server, the call will block until a
  # connection is available or the pool timeout expires.
  #
  # If the pool timeout expires before a connection can be acquired, a
  # Larch::ConnectionPool::Timeout exception is raised.
  def hold(uri)
    raise ArgumentError, 'must specify an IMAP URI' unless uri.is_a?(URI)

    thread = Thread.current

    if conn = allocated(uri, thread)
      return yield(conn)
    end

    begin
      unless conn = acquire(uri, thread)
        timeout = Time.now + @pool_timeout
        sleep @pool_sleep

        until conn = acquire(uri, thread)
          raise Timeout if Time.now > timeout
          sleep @pool_sleep
        end
      end

      yield conn

    # TODO: rescue disconnects?

    ensure
      sync { release(uri, thread) if conn }
    end
  end

  # Total number of open (either available or allocated) connections to all
  # servers, or to a single specific server if _uri_ is specified.
  def size(uri = nil)
    if uri
      (@allocated[uri_key_mailbox(uri)] || {}).length + (@available[uri_key_server(uri)] || []).length
    else
      total = 0

      @allocated.each_value {|threads| total += threads.length }
      @available.each_value {|conns| total += conns.length }

      total
    end
  end

  # Returns a URI that's guaranteed to be the same for all input URIs that
  # contain the same scheme, host, port, username, password, and path.
  def uri_key_mailbox(uri)
    uri.dup
  end

  # Returns a URI that's guaranteed to be the same for all URIs that contain the
  # same scheme, host, port, username, and password. This key disregards path
  # info, so two URIs with the same server info but a different path will still
  # return the same server key.
  def uri_key_server(uri)
    _uri = uri.dup
    _uri.path = ''
    _uri
  end

  private

  # Allocates a connection to the supplied thread for the given URI if one is
  # available. The caller should NOT already have a mutex lock.
  def acquire(uri, thread)
    sync do
      if conn == available
        (@allocated[uri_key_mailbox(uri)] ||= {})[thread] = conn
      end
    end
  end

  # Returns an available connection to the given URI, or tries to create a new
  # one if one isn't available. The caller should already have a mutex lock.
  def available(uri)
    (@available[uri_key_server] || []).pop || create(uri)
  end

  # Returns the connection allocated to the specified _thread_ for the given
  # _uri_, if any. The caller should NOT already have a mutex lock.
  def allocated(uri, thread)
    sync { (@allocated[uri_key_mailbox(uri)] || {})[thread] }
  end

  # Creates a new connection to the given URI if the size of the pool for that
  # URI is less than the maximum size. The caller should already have a mutex
  # lock.
  def create(uri)
    if (n = size(uri)) >= @max_size
      # Try to free up any dead allocated connections.
      (@allocated[uri_key_mailbox(uri)] || {}).each_key do |thread|
        release(uri, thread) unless thread.alive?
      end

      n = nil
    end

    
  end

  # Releases the connection assigned to the supplied URI and thread. The caller
  # should already have a mutex lock.
  def release(uri, thread)
    if conn = (@allocated[uri_key_mailbox(uri)] || {}).delete(thread)
      (@available[uri_key_server(uri)] ||= []) << conn
    end
  end

  # Yields to the given block while inside the mutex. The caller should NOT
  # already have a mutex lock.
  def sync
    @mutex.synchronize { yield }
  end

  class Timeout < Larch::Error; end
end
