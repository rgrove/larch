# Provides thread-safe and mailbox-aware connection pooling for IMAP connections
# using Larch::IMAP.
class Larch::ConnectionPool
  # Hash of currently allocated connections. Keys are IMAP URIs, and each value
  # is a hash of threads mapping to Larch::IMAP instances.
  attr_reader :allocated

  # Hash of connections available for use by the pool. Keys are IMAP URIs,
  # values are arrays of Larch::IMAP instances.
  attr_reader :available

  # Hash of options to pass to Larch::IMAP when creating a new connection.
  attr_accessor :imap_options

  # Maximum number of connections the pool will create per server.
  attr_reader :max_connections

  # Returns a URI that's guaranteed to be the same for all input URIs that
  # contain the same scheme, host, port, username, password, and path.
  def self.uri_key_mailbox(uri)
    _uri = uri.is_a?(URI) ? uri.dup : URI(uri)
    _uri
  end

  # Returns a URI that's guaranteed to be the same for all URIs that contain the
  # same scheme, host, port, username, and password. This key disregards path
  # info, so two URIs with the same server info but a different path will still
  # return the same server key.
  def self.uri_key_server(uri)
    _uri = uri.is_a?(URI) ? uri.dup : URI(uri)
    _uri.path = ''
    _uri
  end

  # The following options may be specified:
  #
  # [:imap_options]
  #   Options Hash to pass to Larch::IMAP when creating a new connection. See
  #   the Larch::IMAP documentation for available options.
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
    @mutex           = Mutex.new
    @allocated       = {}
    @available       = {}
    @imap_options    = options[:imap_options] || {}
    @max_connections = Integer(options[:max_connections] || 2)
    @pool_sleep      = Float(options[:pool_sleep] || 0.01)
    @pool_timeout    = Integer(options[:pool_timeout] || 60)

    raise ArgumentError, ':imap_options must be a Hash' unless @imap_options.is_a?(Hash)
    raise ArgumentError, ':max_connections must be positive' if @max_connections < 1
    raise ArgumentError, ':pool_sleep must be positive' if @pool_sleep <= 0
    raise ArgumentError, ':pool_timeout must be positive' if @pool_timeout < 1
  end

  # Removes all connections currently available for the specified _uri_, or for
  # all URIs if none is specified, optionally yielding each connection to the
  # given block before disconnecting it. Does not remove connections that are
  # currently allocated.
  def disconnect(uri = nil, &block)
    unless uri.nil?
      uri = uri.is_a?(URI) ? uri : URI(uri)
    end

    sync do
      if uri
        connections = @available[uri] || []

        connections.each do |conn|
          block.call(conn) if block
          conn.disconnect
        end

        connections.clear
      else
        @available.each_value do |connections|
          connections.each do |conn|
            block.call(conn) if block
            conn.disconnect
          end
        end

        @available.clear
      end
    end
  end

  # Acquires or creates a connection to the specified IMAP _uri_, passing a
  # Larch::IMAP instance to the supplied block.
  #
  # If no connection is available and the pool is already using the maximum
  # number of connections to the specified server, the call will block until a
  # connection is available or the pool timeout expires.
  #
  # If the pool timeout expires before a connection can be acquired, a
  # Larch::ConnectionPool::Timeout exception is raised.
  #
  # This method is re-entrant, so it can be called recursively in the same
  # thread without blocking.
  def hold(uri)
    uri = uri.is_a?(URI) ? uri : URI(uri)
    Larch::IMAP.validate_uri(uri)

    thread = Thread.current

    if conn = allocated_connection(uri, thread)
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

      yield(conn)

    ensure
      sync { release(uri, thread) if conn }
    end
  end

  # Total number of open (either available or allocated) connections to all
  # servers, or to a single specific server if _uri_ is specified.
  def size(uri = nil)
    if uri
      (@allocated[Larch::ConnectionPool.uri_key_mailbox(uri)] || {}).length +
          (@available[Larch::ConnectionPool.uri_key_server(uri)] || []).length
    else
      total = 0

      @allocated.each_value {|threads| total += threads.length }
      @available.each_value {|conns| total += conns.length }

      total
    end
  end

  private

  # Allocates a connection to the supplied thread for the given URI if one is
  # available. The caller should NOT already have a mutex lock.
  def acquire(uri, thread)
    sync do
      if conn = available_connection(uri)
        (@allocated[Larch::ConnectionPool.uri_key_mailbox(uri)] ||= {})[thread] = conn
        conn.start
        conn
      end
    end
  end

  # Returns an available connection to the given URI, or tries to create a new
  # one if one isn't available. The caller should already have a mutex lock.
  def available_connection(uri)
    server_key      = Larch::ConnectionPool.uri_key_server(uri)
    available_array = @available[server_key] || []

    if conn = available_array.pop
      @available.delete(server_key) if available_array.empty?
      conn
    else
      create(uri)
    end
  end

  # Returns the connection allocated to the specified _thread_ for the given
  # _uri_, if any. The caller should NOT already have a mutex lock.
  def allocated_connection(uri, thread)
    sync { (@allocated[Larch::ConnectionPool.uri_key_mailbox(uri)] || {})[thread] }
  end

  # Creates a new connection to the given URI if the size of the pool for that
  # URI is less than the maximum size. The caller should already have a mutex
  # lock.
  def create(uri)
    if (n = size(uri)) >= @max_connections
      # Try to free up any dead allocated connections.
      (@allocated[Larch::ConnectionPool.uri_key_mailbox(uri)] || {}).each_key do |thread|
        release(uri, thread) unless thread.alive?
      end

      n = nil
    end

    Larch::IMAP.new(uri, @imap_options) if (n || size(uri)) < @max_connections
  end

  # Releases the connection assigned to the supplied URI and thread. The caller
  # should already have a mutex lock.
  def release(uri, thread)
    mailbox_key    = Larch::ConnectionPool.uri_key_mailbox(uri)
    allocated_hash = @allocated[mailbox_key] || {}

    if conn = allocated_hash.delete(thread)
      conn.clear_response_handlers
      @allocated.delete(mailbox_key) if allocated_hash.empty?
      (@available[Larch::ConnectionPool.uri_key_server(uri)] ||= []) << conn
    end
  end

  # Yields to the given block while inside the mutex. The caller should NOT
  # already have a mutex lock.
  def sync
    @mutex.synchronize { yield }
  end

  class Timeout < Larch::Error; end
end
