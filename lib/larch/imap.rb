module Larch

# Manages a connection to an IMAP server and all the glorious fun that entails.
#
# This class borrows heavily from Sup, the source code of which should be
# required reading if you're doing anything with IMAP in Ruby:
# http://sup.rubyforge.org
class IMAP
  include MonitorMixin

  # Maximum number of messages to fetch at once.
  MAX_FETCH_COUNT = 1024

  # Regex to capture the individual fields in an IMAP fetch command.
  REGEX_FIELDS = /([0-9A-Z\.]+\[[^\]]+\](?:<[0-9\.]+>)?|[0-9A-Z\.]+)/

  # Regex to capture a Message-Id header.
  REGEX_MESSAGE_ID = /message-id\s*:\s*(\S+)/i

  # URI format validation regex.
  REGEX_URI = URI.regexp(['imap', 'imaps'])

  # Minimum time (in seconds) allowed between mailbox scans.
  SCAN_INTERVAL = 60

  # Larch::IMAP::Message represents a transferable IMAP message which can be
  # passed between Larch::IMAP instances.
  Message = Struct.new(:id, :envelope, :rfc822, :flags, :internaldate)

  # Initializes a new Larch::IMAP instance that will connect to the specified
  # IMAP URI and authenticate using the specified _username_ and _password_.
  #
  # The following options may also be specified:
  #
  # [:create_mailbox]
  #   If +true+, the specified mailbox will be created if necessary.
  #
  # [:fast_scan]
  #   If +true+, a faster but less accurate method will be used to scan
  #   mailboxes. This will speed up the initial mailbox scan, but will also
  #   reduce the effectiveness of the message unique id generator. This is
  #   probably acceptable when copying a very large mailbox to an empty mailbox,
  #   but if the destination already contains messages, using this option is not
  #   advised.
  #
  # [:max_retries]
  #   After a recoverable error occurs, retry the operation up to this many
  #   times. Default is 3.
  #
  def initialize(uri, username, password, options = {})
    super()

    raise ArgumentError, "not an IMAP URI: #{uri}" unless uri.is_a?(URI) || uri =~ REGEX_URI
    raise ArgumentError, "must provide a username and password" unless username && password
    raise ArgumentError, "options must be a Hash" unless options.is_a?(Hash)

    @uri      = uri.is_a?(URI) ? uri : URI(uri)
    @username = username
    @password = password
    @options  = {:max_retries => 3}.merge(options)

    @ids         = {}
    @imap        = nil
    @last_id     = 0
    @last_scan   = nil

    # Create private convenience methods (debug, info, warn, etc.) to make
    # logging easier.
    Logger::LEVELS.each_key do |level|
      IMAP.class_eval do
        define_method(level) do |msg|
          Larch.log.log(level, "#{@username}@#{host}: #{msg}")
        end

        private level
      end
    end
  end

  # Appends the specified Larch::IMAP::Message to this mailbox if it doesn't
  # already exist. Returns +true+ if the message was appended successfully,
  # +false+ if the message already exists in the mailbox.
  def append(message)
    raise ArgumentError, "must provide a Larch::IMAP::Message object" unless message.is_a?(Message)
    return false if has_message?(message)

    safely do
      begin
        @imap.select(mailbox)
      rescue Net::IMAP::NoResponseError => e
        if @options[:create_mailbox]
          info "creating mailbox: #{mailbox}"
          @imap.create(mailbox)
          retry
        end

        raise
      end

      debug "appending message: #{message.id}"
      @imap.append(mailbox, message.rfc822, message.flags, message.internaldate)
    end

    true
  end
  alias << append

  # Connects to the IMAP server and logs in if a connection hasn't already been
  # established.
  def connect
    return if @imap
    safely {} # connect, but do nothing else
  end

  # Closes the IMAP connection if one is currently open.
  def disconnect
    return unless @imap

    synchronize do
      begin
        @imap.disconnect
      rescue Errno::ENOTCONN => e
        debug "#{e.class.name}: #{e.message}"
      end

      @imap = nil
    end

    info "disconnected"
  end

  # Iterates through Larch message ids in this mailbox, yielding each one to the
  # provided block.
  def each
    scan_mailbox
    ids = @ids

    ids.each_key {|id| yield id }
  end

  # Gets a Net::IMAP::Envelope for the specified message id.
  def envelope(message_id)
    scan_mailbox
    uid = @ids[message_id]

    raise NotFoundError, "message not found: #{message_id}" if uid.nil?

    debug "fetching envelope: #{message_id}"
    imap_uid_fetch([uid], 'ENVELOPE').first.attr['ENVELOPE']
  end

  # Fetches a Larch::IMAP::Message struct representing the message with the
  # specified Larch message id.
  def fetch(message_id, peek = false)
    scan_mailbox
    uid = @ids[message_id]

    raise NotFoundError, "message not found: #{message_id}" if uid.nil?

    debug "#{peek ? 'peeking at' : 'fetching'} message: #{message_id}"
    data = imap_uid_fetch([uid], [(peek ? 'BODY.PEEK[]' : 'BODY[]'), 'FLAGS', 'INTERNALDATE', 'ENVELOPE']).first

    Message.new(message_id, data.attr['ENVELOPE'], data.attr['BODY[]'],
        data.attr['FLAGS'], Time.parse(data.attr['INTERNALDATE']))
  end
  alias [] fetch

  # Returns +true+ if a message with the specified Larch <em>message_id</em>
  # exists in this mailbox, +false+ otherwise.
  def has_message?(message_id)
    scan_mailbox
    @ids.has_key?(message_id)
  end

  # Gets the IMAP hostname.
  def host
    @uri.host
  end

  # Gets the number of messages in this mailbox.
  def length
    scan_mailbox
    @ids.length
  end
  alias size length

  # Gets the IMAP mailbox.
  def mailbox
    mb = @uri.path[1..-1]
    mb.nil? || mb.empty? ? 'INBOX' : CGI.unescape(mb)
  end

  # Same as fetch, but doesn't mark the message as seen.
  def peek(message_id)
    fetch(message_id, true)
  end

  # Gets the IMAP port number.
  def port
    @uri.port || (ssl? ? 993 : 143)
  end

  # Fetches message headers from the current mailbox.
  def scan_mailbox
    synchronize do
      return if @last_scan && (Time.now - @last_scan) < SCAN_INTERVAL

      last_id = safely do
        begin
          @imap.examine(mailbox)
        rescue Net::IMAP::NoResponseError => e
          return if @options[:create_mailbox]
          raise FatalError, "unable to open mailbox: #{e.message}"
        end

        @imap.responses['EXISTS'].last
      end

      @last_scan = Time.now
      return if last_id == @last_id

      range    = (@last_id + 1)..last_id
      @last_id = last_id

      info "fetching message headers #{range}" <<
          (@options[:fast_scan] ? ' (fast scan)' : '')

      fields = if @options[:fast_scan]
        ['UID', 'RFC822.SIZE', 'INTERNALDATE']
      else
        "(UID BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)] RFC822.SIZE INTERNALDATE)"
      end

      imap_fetch(range, fields).each do |data|
        id = create_id(data)

        unless uid = data.attr['UID']
          error "UID not in IMAP response for message: #{id}"
          next
        end

        if @ids.has_key?(id) && Larch.log.level == :debug
          envelope = imap_uid_fetch([uid], 'ENVELOPE').first.attr['ENVELOPE']
          debug "duplicate message? #{id} (Subject: #{envelope.subject})"
        end

        @ids[id] = uid
      end
    end
  end

  # Gets the SSL status.
  def ssl?
    @uri.scheme == 'imaps'
  end

  # Gets the IMAP URI.
  def uri
    @uri.to_s
  end

  private

  # Creates an id suitable for uniquely identifying a specific message across
  # servers (we hope).
  #
  # If the given message data includes a valid Message-Id header, then that will
  # be used to generate an MD5 hash. Otherwise, the hash will be generated based
  # on the message's RFC822.SIZE and INTERNALDATE.
  def create_id(data)
    ['RFC822.SIZE', 'INTERNALDATE'].each do |a|
      raise FatalError, "requested data not in IMAP response: #{a}" unless data.attr[a]
    end

    if data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]'] =~ REGEX_MESSAGE_ID
      Digest::MD5.hexdigest($1)
    else
      Digest::MD5.hexdigest(sprintf('%d%d', data.attr['RFC822.SIZE'],
          Time.parse(data.attr['INTERNALDATE']).to_i))
    end
  end

  # Fetches the specified _fields_ for the specified message sequence id(s) from
  # the IMAP server.
  def imap_fetch(ids, fields)
    ids  = ids.to_a
    data = []
    pos  = 0

    safely do
      while pos < ids.length
        data += @imap.fetch(ids[pos, MAX_FETCH_COUNT], fields)
        pos  += MAX_FETCH_COUNT
      end
    end

    data
  end

  # Fetches the specified _fields_ for the specified UID(s) from the IMAP
  # server.
  def imap_uid_fetch(uids, fields)
    uids = uids.to_a
    data = []
    pos  = 0

    safely do
      while pos < uids.length
        data += @imap.uid_fetch(uids[pos, MAX_FETCH_COUNT], fields)
        pos  += MAX_FETCH_COUNT
      end
    end

    data
  end

  def safe_connect
    synchronize do
      return if @imap

      retries = 0

      begin
        unsafe_connect

      rescue Errno::EPIPE,
             Errno::ETIMEDOUT,
             IOError,
             Net::IMAP::NoResponseError,
             OpenSSL::SSL::SSLError => e

        raise unless (retries += 1) <= @options[:max_retries]
        info "#{e.class.name}: #{e.message} (will retry)"

        @imap = nil
        sleep 1 * retries
        retry
      end
    end

  rescue => e
    raise FatalError, "#{e.class.name}: #{e.message} (cannot recover)"
  end

  # Connect if necessary, execute the given block, retry up to 3 times if a
  # recoverable error occurs, die if an unrecoverable error occurs.
  def safely
    safe_connect

    synchronize do
      # Explicitly set Net::IMAP's client thread to the current thread to ensure
      # that exceptions aren't raised in a dead thread.
      @imap.client_thread = Thread.current
    end

    retries = 0

    begin
      yield

    rescue EOFError,
           IOError,
           Errno::ECONNRESET,
           Errno::ENOTCONN,
           Errno::EPIPE,
           Errno::ETIMEDOUT,
           Net::IMAP::ByeResponseError,
           OpenSSL::SSL::SSLError => e

      raise unless (retries += 1) <= @options[:max_retries]

      info "#{e.class.name}: #{e.message} (reconnecting)"

      synchronize { @imap = nil }
      sleep 1 * retries
      safe_connect
      retry

    rescue Net::IMAP::BadResponseError,
           Net::IMAP::NoResponseError,
           Net::IMAP::ResponseParseError => e

      raise unless (retries += 1) <= @options[:max_retries]

      info "#{e.class.name}: #{e.message} (will retry)"

      sleep 1 * retries
      retry
    end

  rescue Net::IMAP::Error => e
    raise Error, "#{e.class.name}: #{e.message} (giving up)"

  rescue Larch::Error => e
    raise

  rescue => e
    raise FatalError, "#{e.class.name}: #{e.message} (cannot recover)"
  end

  def unsafe_connect
    info "connecting..."

    @imap = Net::IMAP.new(host, port, ssl?)

    info "connected on port #{port}" << (ssl? ? ' using SSL' : '')

    auth_methods = ['PLAIN']
    tried        = []
    capability   = @imap.capability

    ['LOGIN', 'CRAM-MD5'].each do |method|
      auth_methods << method if capability.include?("AUTH=#{method}")
    end

    begin
      tried << method = auth_methods.pop

      debug "authenticating using #{method}"

      if method == 'PLAIN'
        @imap.login(@username, @password)
      else
        @imap.authenticate(method, @username, @password)
      end

      info "authenticated using #{method}"

    rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError => e
      debug "#{method} auth failed: #{e.message}"
      retry unless auth_methods.empty?

      raise e, "#{e.message} (tried #{tried.join(', ')})"
    end
  end
end

end
