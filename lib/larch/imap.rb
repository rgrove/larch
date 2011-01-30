# The Larch::IMAP class is a delegating wrapper for (but not a subclass of) the
# Net::IMAP class.
#
# Larch::IMAP automatically translates mailbox names in method arguments to
# modified UTF-7 strings before sending them to the server, so you should always
# use UTF-8 for mailbox names. Mailbox names returned from the server are not
# automatically translated, however.
class Larch::IMAP
  # Net::IMAP instance methods that don't require authentication.
  NOAUTH_METHODS = [
    :capability, :client_thread, :greeting, :login, :logout, :responses,
    :starttls
  ]

  # Net::IMAP instance methods that are wrapped by Larch::IMAP::Mailbox and
  # shouldn't be called directly.
  MAILBOX_METHODS = [
    :check, :close, :expunge, :fetch, :search, :sort, :store, :thread,
    :uid_fetch, :uid_search, :uid_sort, :uid_store, :uid_thread
  ]

  # Array of strings representing the server's advertised capabilities.
  attr_reader :capability

  # Larch::IMAP::Mailbox object representing the currently-open mailbox, or
  # +nil+ if no mailbox is open.
  attr_reader :mailbox

  # Hash of options specified when this Larch::IMAP object was instantiated.
  attr_reader :options

  # Hash of bools indicating whether or not this server has certain known quirks
  # that Larch::IMAP will try to work around.
  #
  # Possible keys include:
  #
  # [:gmail]
  #   Server appears to be Gmail.
  #
  # [:yahoo]
  #   Server appears to be Yahoo! Mail.
  attr_reader :quirks

  # Array of registered response handlers that will be called whenever an IMAP
  # response is received.
  attr_reader :response_handlers

  # URI for this connection.
  attr_reader :uri

  def self.const_missing(name) # :nodoc:
    unless Net::IMAP.const_defined?(name)
      raise NameError, "uninitialized constant Larch::IMAP::#{name}"
    end

    Net::IMAP.const_get(name)
  end

  # Validates the specified IMAP _uri_ (which must be a URI instance) and raises
  # a Larch::IMAP::InvalidURI exception if it's not a valid IMAP URI.
  def self.validate_uri(uri)
    raise InvalidURI, "not a valid IMAP URI: #{uri}" unless uri.scheme == 'imap' || uri.scheme == 'imaps'
    raise InvalidURI, "URI must include a host" unless uri.host
    raise InvalidURI, "URI must include a username and password" unless uri.user && uri.password
  end

  # Creates a new Larch::IMAP object, but doesn't open a connection.
  #
  # The _uri_ parameter must be an IMAP URI with an 'imap' or 'imaps' scheme,
  # a username and password, and a hostname. Unless a custom port is specified,
  # port 143 will be used for 'imap' and port 993 for 'imaps'.
  #
  # In addition to the URI, the following options may be specified as hash
  # params:
  #
  # [:max_retries]
  #   After a recoverable error occurs, retry the operation up to this many
  #   times. Default is 3.
  #
  # [:ssl_certs]
  #   Path to a trusted certificate bundle to use to verify server SSL
  #   certificates. You can download a bundle of certificate authority root
  #   certs at http://curl.haxx.se/ca/cacert.pem (it's up to you to verify that
  #   this bundle hasn't been tampered with, however; don't trust it blindly).
  #
  # [:ssl_verify]
  #   If +true+, server SSL certificates will be verified against the trusted
  #   certificate bundle specified in +ssl_certs+. By default, server SSL
  #   certificates are not verified.
  def initialize(uri, options = {})
    @uri = uri.is_a?(URI) ? uri : URI(uri)

    Larch::IMAP.validate_uri(@uri)

    @authenticated     = false
    @capability        = []
    @conn              = nil # Net::IMAP instance
    @delim             = nil # mailbox hierarchy delimiter
    @log               = Larch::Logger.new(method(:log_prefix))
    @mailbox           = nil
    @options           = {:max_retries => 3, :ssl_verify => false}.merge(options)
    @quirks            = {}
    @response_handlers = []
  end

  # Adds a response handler. See Net::IMAP#add_response_handler for details.
  def add_response_handler(handler = Proc.new)
    @response_handlers.push(handler)
  end

  # Logs into the IMAP server using the best available authentication method and
  # the username and password specified in the URI.
  #
  # The following authentication methods will be tried, in this order, if the
  # server claims to support them:
  #
  #   - CRAM-MD5
  #   - LOGIN
  #   - PLAIN
  #
  # If the server does not support any of these authentication methods, a
  # Larch::IMAP::NoSupportedAuthMethod exception will be raised.
  def authenticate
    raise NotConnected, "must connect before authenticating" unless connected?
    return true if authenticated?

    auth_methods  = []
    methods_tried = []

    ['PLAIN', 'LOGIN', 'CRAM-MD5'].each do |method|
      auth_methods << method if @capability.include?("AUTH=#{method}")
    end

    # Remove PLAIN and LOGIN from the list if the capability list includes
    # LOGINDISABLED, in order to avoid sending the user's credentials in the
    # clear when we know the server won't accept them.
    if @capability.include?('LOGINDISABLED')
      auth_methods.delete('PLAIN')
      auth_methods.delete('LOGIN')
    end

    begin
      methods_tried << method = auth_methods.pop

      response = if method == 'PLAIN'
        @conn.login(username, password)
      else
        @conn.authenticate(method, username, password)
      end

    rescue Net::IMAP::BadResponseError,
           Net::IMAP::NoResponseError => e

      retry unless auth_methods.empty?

      raise e, "#{e.message} (tried #{methods_tried.join(', ')})"
    end

    update_capability(response)

    @authenticated = true
  end

  # Returns +true+ if connected and authenticated.
  def authenticated?
    connected? && @authenticated
  end

  # Removes all response handlers.
  def clear_response_handlers
    @response_handlers.clear
  end

  # Opens a connection to the IMAP server. If a connection is already open, it
  # will be closed and reopened.
  def connect
    @authenticated = false
    mailbox_closed if @mailbox

    @conn = Net::IMAP.new(host, port, ssl?,
        ssl? && @options[:ssl_verify] ? @options[:ssl_certs] : nil,
        @options[:ssl_verify])

    @conn.add_response_handler(method(:handle_response))

    check_quirks

    # If this is Yahoo! Mail, we have to send a special command before it'll let
    # us authenticate.
    if @quirks[:yahoo]
      @conn.instance_eval { send_command('ID ("guid" "1")') }
    end

    # Capability check must come after the Yahoo! hack, since Yahoo! doesn't
    # send a capability list in the greeting or respond to CAPABILITY before the
    # hack.
    update_capability(@conn.greeting)
    true
  end

  # Returns +true+ if connected to the server.
  def connected?
    !disconnected?
  end

  # Gets the server's mailbox hierarchy delimiter, defaulting to '.' if the
  # server doesn't want to tell us what its preferred delimiter is.
  def delim
    require_auth
    @delim ||= @conn.list('', '')[0].delim || '.'
  end

  # Disconnects from the server.
  def disconnect
    if connected?
      @conn.disconnect
      @conn = nil
      @authenticated = false
      mailbox_closed if @mailbox
    end
  end

  # Returns +true+ if disconnected from the server.
  def disconnected?
    !@conn || @conn.disconnected?
  end

  # Sends an EXAMINE command to select the specified _mailbox_. Works just like
  # #select, except the mailbox is opened in read-only mode. The _mailbox_
  # parameter should be a UTF-8 string. It will be converted to UTF-7
  # automatically.
  def examine(mailbox)
    require_auth
    mailbox = Net::IMAP.encode_utf7(mailbox)
    @conn.examine(mailbox)
    mailbox_factory(mailbox, :read_only => true)
  end

  # Gets the IMAP hostname.
  def host
    @uri.host
  end

  def method_missing(name, *args, &block) # :nodoc:
    if !Net::IMAP.method_defined?(name) ||
        Larch::IMAP::MAILBOX_METHODS.include?(name)
      raise NoMethodError, "undefined method `#{name}' for Larch::IMAP"
    end

    require_connection
    require_auth unless Larch::IMAP::NOAUTH_METHODS.include?(name)

    @conn.send(name, *args, &block)
  end

  # Gets the IMAP password.
  def password
    CGI.unescape(@uri.password)
  end

  # Gets the IMAP port number.
  def port
    @uri.port || (ssl? ? 993 : 143)
  end

  # Removes the specified response handler.
  def remove_response_handler(handler)
    @response_handlers.delete(handler)
  end

  # Connects and authenticates if necessary, executes the given block, retries
  # if a recoverable error occurs, raises an exception if an unrecoverable error
  # occurs.
  def safely
    retries = 0

    begin
      start

      yield

    rescue Errno::ECONNABORTED,
           Errno::ECONNREFUSED,
           Errno::ECONNRESET,
           Errno::ENOTCONN,
           Errno::EPIPE,
           Errno::ETIMEDOUT,
           IOError,
           Net::IMAP::ByeResponseError,
           OpenSSL::SSL::SSLError,
           SocketError => e

      raise unless (retries += 1) <= @options[:max_retries]

      # Special check to ensure that we don't retry on OpenSSL certificate
      # verification errors.
      raise if e.is_a?(OpenSSL::SSL::SSLError) && e.message =~ /certificate verify failed/

      @conn          = nil
      @authenticated = false
      mailbox_closed if @mailbox

      sleep 1 * retries
      retry
    end
  end

  # Sends a SELECT command to select the specified _mailbox_.
  def select(mailbox)
    require_auth
    mailbox = Net::IMAP.encode_utf7(mailbox)
    @conn.select(mailbox)
    mailbox_factory(mailbox)
  end

  # Starts an IMAP session by connecting and authenticating. If already
  # connected and authenticated, this method does nothing.
  def start
    connect unless connected?
    authenticate unless authenticated?
  end

  # Gets the SSL status.
  def ssl?
    @uri.scheme == 'imaps'
  end

  # Translates all occurrences of the specified hierarchy delimiter in the given
  # mailbox _name_ into the hierarchy delimiter supported by this connection.
  def translate_delim(name, delim = '/')
    name.gsub(delim, self.delim)
  end

  # Gets the IMAP username.
  def username
    CGI.unescape(@uri.user)
  end

  private

  # Tries to identify server implementations with certain quirks that we'll need
  # to work around.
  def check_quirks
    return unless @conn &&
        @conn.greeting.kind_of?(Net::IMAP::UntaggedResponse) &&
        @conn.greeting.data.kind_of?(Net::IMAP::ResponseText)

    if @conn.greeting.data.text =~ /^Gimap ready/
      @quirks[:gmail] = true
    elsif host =~ /^imap(?:-ssl)?\.mail\.yahoo\.com$/
      @quirks[:yahoo] = true
    end
  end

  # Handles incoming IMAP responses and dispatches them to other registered
  # response handlers.
  def handle_response(response)
    @response_handlers.each {|handler| handler.call(response) }
  end

  # Generates a prefix string for log messages.
  def log_prefix
    # TODO: indicate whether this connection is the source or the destination
    # using [<] or [>].
    @mailbox && @mailbox.raw_name ? "#{@mailbox.raw_name}:" : ""
  end

  # Called by a Larch::IMAP::Mailbox instance to let us know that the mailbox it
  # represents has been closed or unselected and that we should kill the Mailbox
  # instance.
  def mailbox_closed
    @mailbox = nil
  end

  # Creates a new Larch::IMAP::Mailbox object mixing in the specified options,
  # assigns it to @mailbox, and returns it.
  def mailbox_factory(name, options = {})
    options = {
      :close_handler => method(:mailbox_closed),
      :connection    => @conn,
      :delim         => delim,
      :imap          => self,
      :read_only     => false
    }.merge(options)

    @mailbox.instance_eval { self_destruct } if @mailbox
    @mailbox = Larch::IMAP::Mailbox.new(name, options)
  end

  def require_connection
    raise NotConnected, "not connected" unless connected?
  end

  def require_auth
    require_connection
    raise NotAuthenticated, "not authenticated" unless authenticated?
  end

  # Looks for a capability list in the specified IMAP _response_, or sends a
  # CAPABILITY request if no response is given or if the given response doesn't
  # contain a capability list.
  #
  # Updates @capability with the results and returns it.
  def update_capability(response = nil)
    if response.is_a?(Net::IMAP::UntaggedResponse) ||
        response.is_a?(Net::IMAP::TaggedResponse)

      if (data = response.data).is_a?(Net::IMAP::ResponseText) &&
          data.code.is_a?(Net::IMAP::ResponseCode) &&
          data.code.name == 'CAPABILITY'

        return @capability = data.code.data.split(' ')
      end
    end

    require_connection

    @capability = @conn.capability
  end

  class Error < Larch::Error; end
  class InvalidURI < Error; end
  class MailboxClosed < Error; end
  class NoSupportedAuthMethod < Error; end
  class NotAuthenticated < Error; end
  class NotConnected < Error; end
end
