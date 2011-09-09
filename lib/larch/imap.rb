module Larch

# Manages a connection to an IMAP server and all the glorious fun that entails.
#
# This class borrows heavily from Sup, the source code of which should be
# required reading if you're doing anything with IMAP in Ruby:
# http://sup.rubyforge.org
class IMAP
  attr_reader :conn, :db_account, :mailboxes, :options, :quirks

  # URI format validation regex.
  REGEX_URI = URI.regexp(['imap', 'imaps'])

  # Larch::IMAP::Message represents a transferable IMAP message which can be
  # passed between Larch::IMAP instances.
  Message = Struct.new(:guid, :envelope, :rfc822, :flags, :internaldate)

  # Initializes a new Larch::IMAP instance that will connect to the specified
  # IMAP URI.
  #
  # In addition to the URI, the following options may be specified:
  #
  # [:create_mailbox]
  #   If +true+, mailboxes that don't already exist will be created if
  #   necessary.
  #
  # [:dry_run]
  #   If +true+, read-only operations will be performed as usual and all change
  #   operations will be simulated, but no changes will actually be made. Note
  #   that it's not actually possible to simulate mailbox creation, so
  #   +:dry_run+ mode always behaves as if +:create_mailbox+ is +false+.
  #
  # [:log_label]
  #   Label to use for this connection in log output. If not specified, the
  #   default label is "[username@host]".
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
  #
  def initialize(uri, options = {})
    raise ArgumentError, "not an IMAP URI: #{uri}" unless uri.is_a?(URI) || uri =~ REGEX_URI
    raise ArgumentError, "options must be a Hash" unless options.is_a?(Hash)

    @uri     = uri.is_a?(URI) ? uri : URI(uri)
    @options = {
      :log_label   => "[#{username}@#{host}]",
      :max_retries => 3,
      :ssl_verify  => false
    }.merge(options)

    raise ArgumentError, "must provide a username and password" unless @uri.user && @uri.password

    @conn      = nil
    @mailboxes = {}

    @quirks    = {
      :gmail => false,
      :yahoo => false
    }

    @db_account = Database::Account.find_or_create(
      :hostname => host,
      :username => username
    )

    @db_account.touch

    # Create private convenience methods (debug, info, warn, etc.) to make
    # logging easier.
    Logger::LEVELS.each_key do |level|
      next if IMAP.private_method_defined?(level)

      IMAP.class_eval do
        define_method(level) do |msg|
          Larch.log.log(level, "#{@options[:log_label]} #{msg}")
        end

        private level
      end
    end
  end

  # Connects to the IMAP server and logs in if a connection hasn't already been
  # established.
  def connect
    return if @conn
    safely {} # connect, but do nothing else
  end

  # Gets the server's mailbox hierarchy delimiter.
  def delim
    @delim ||= safely { @conn.list('', '')[0].delim || '.'}
  end

  # Closes the IMAP connection if one is currently open.
  def disconnect
    return unless @conn

    begin
      @conn.disconnect
    rescue Errno::ENOTCONN => e
      debug "#{e.class.name}: #{e.message}"
    end

    reset

    info "disconnected"
  end

  # Iterates through all mailboxes in the account, yielding each one as a
  # Larch::IMAP::Mailbox instance to the given block.
  def each_mailbox
    update_mailboxes
    @mailboxes.each_value {|mailbox| yield mailbox }
  end

  # Gets the IMAP hostname.
  def host
    @uri.host
  end

  # Gets a Larch::IMAP::Mailbox instance representing the specified mailbox. If
  # the mailbox doesn't exist and the <tt>:create_mailbox</tt> option is
  # +false+, or if <tt>:create_mailbox</tt> is +true+ and mailbox creation
  # fails, a Larch::IMAP::MailboxNotFoundError will be raised.
  def mailbox(name, delim = '/')
    retries = 0

    name.gsub!(/^(inbox\/?)/i){ $1.upcase }
    name.gsub!(delim, self.delim)

    # Gmail doesn't allow folders with leading or trailing whitespace.
    name.strip! if @quirks[:gmail]
    
    #Rackspace namespaces everything under INDEX.
    name.sub!(/^|inbox\./i, "INBOX.") if @quirks[:rackspace] && name != 'INBOX'

    begin
      @mailboxes.fetch(name) do
        update_mailboxes
        return @mailboxes[name] if @mailboxes.has_key?(name)
        raise MailboxNotFoundError, "mailbox not found: #{name}"
      end

    rescue MailboxNotFoundError => e
      raise unless @options[:create_mailbox] && retries == 0

      info "creating mailbox: #{name}"
      safely { @conn.create(Net::IMAP.encode_utf7(name)) } unless @options[:dry_run]

      retries += 1
      retry
    end
  end

  # Sends an IMAP NOOP command.
  def noop
    safely { @conn.noop }
  end

  # Gets the IMAP password.
  def password
    CGI.unescape(@uri.password)
  end

  # Gets the IMAP port number.
  def port
    @uri.port || (ssl? ? 993 : 143)
  end

  # Connect if necessary, execute the given block, retry if a recoverable error
  # occurs, die if an unrecoverable error occurs.
  def safely
    safe_connect

    retries = 0

    begin
      yield

    rescue Errno::ECONNABORTED,
           Errno::ECONNRESET,
           Errno::ENOTCONN,
           Errno::EPIPE,
           Errno::ETIMEDOUT,
           IOError,
           Net::IMAP::ByeResponseError,
           OpenSSL::SSL::SSLError => e

      raise unless (retries += 1) <= @options[:max_retries]

      warning "#{e.class.name}: #{e.message} (reconnecting)"

      reset
      sleep 1 * retries
      safe_connect
      retry

    rescue Net::IMAP::BadResponseError,
           Net::IMAP::NoResponseError,
           Net::IMAP::ResponseParseError => e

      raise unless (retries += 1) <= @options[:max_retries]

      warning "#{e.class.name}: #{e.message} (will retry)"

      sleep 1 * retries
      retry
    end

  rescue Larch::Error => e
    raise

  rescue Net::IMAP::Error => e
    raise Error, "#{e.class.name}: #{e.message} (giving up)"

  rescue => e
    raise FatalError, "#{e.class.name}: #{e.message} (cannot recover)"
  end

  # Gets the SSL status.
  def ssl?
    @uri.scheme == 'imaps'
  end

  # Gets the IMAP URI.
  def uri
    @uri.to_s
  end

  # Gets the IMAP mailbox specified in the URI, or +nil+ if none.
  def uri_mailbox
    mb = @uri.path[1..-1]
    mb.nil? || mb.empty? ? nil : CGI.unescape(mb)
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
      debug "looks like Gmail"

    elsif host =~ /^imap(?:-ssl)?\.mail\.yahoo\.com$/
      @quirks[:yahoo] = true
      debug "looks like Yahoo! Mail"
          
    elsif host =~ /emailsrvr\.com/
      @quirks[:rackspace] = true
      debug "looks like Rackspace Mail"
    end
  end

  # Resets the connection and mailbox state.
  def reset
    @conn = nil
    @mailboxes.each_value {|mb| mb.reset }
  end

  def safe_connect
    return if @conn

    retries = 0

    begin
      unsafe_connect

    rescue Errno::ECONNRESET,
           Errno::EPIPE,
           Errno::ETIMEDOUT,
           OpenSSL::SSL::SSLError => e

      raise unless (retries += 1) <= @options[:max_retries]

      # Special check to ensure that we don't retry on OpenSSL certificate
      # verification errors.
      raise if e.is_a?(OpenSSL::SSL::SSLError) && e.message =~ /certificate verify failed/

      warning "#{e.class.name}: #{e.message} (will retry)"

      reset
      sleep 1 * retries
      retry
    end

  rescue => e
    raise FatalError, "#{e.class.name}: #{e.message} (cannot recover)"
  end

  def unsafe_connect
    debug "connecting..."

    exception = nil

    Thread.new do
      begin
        @conn = Net::IMAP.new(host, port, ssl?,
            ssl? && @options[:ssl_verify] ? @options[:ssl_certs] : nil,
            @options[:ssl_verify])

        info "connected to #{host} on port #{port}" << (ssl? ? ' using SSL' : '')

        check_quirks

        # If this is Yahoo! Mail, we have to send a special command before
        # it'll let us authenticate.
        if @quirks[:yahoo]
          @conn.instance_eval { send_command('ID ("guid" "1")') }
        end

        auth_methods = ['PLAIN']
        tried        = []
        capability   = @conn.capability

        ['LOGIN', 'CRAM-MD5'].each do |method|
          auth_methods << method if capability.include?("AUTH=#{method}")
        end

        begin
          tried << method = auth_methods.pop

          debug "authenticating using #{method}"

          if method == 'PLAIN'
            @conn.login(username, password)
          else
            @conn.authenticate(method, username, password)
          end

          debug "authenticated using #{method}"

        rescue Net::IMAP::BadResponseError, Net::IMAP::NoResponseError => e
          debug "#{method} auth failed: #{e.message}"
          retry unless auth_methods.empty?

          raise e, "#{e.message} (tried #{tried.join(', ')})"
        end

      rescue => e
        exception = e
      end
    end.join

    raise exception if exception
  end

  def update_mailboxes
    debug "updating mailboxes"

    all        = safely { @conn.list('', '*') } || []
    subscribed = safely { @conn.lsub('', '*') } || []

    # Remove cached mailboxes that no longer exist.
    @mailboxes.delete_if {|k, v| !all.any?{|mb| Net::IMAP.decode_utf7(mb.name) == k}}

    # Update cached mailboxes.
    all.each do |mb|
      name = Net::IMAP.decode_utf7(mb.name)
      name = 'INBOX' if name.downcase == 'inbox'

      @mailboxes[name] ||= Mailbox.new(self, name, mb.delim || '.',
          subscribed.any?{|s| s.name == mb.name}, mb.attr)
    end

    # Remove mailboxes that no longer exist from the database.
    @db_account.mailboxes_dataset.all do |db_mailbox|
      db_mailbox.destroy unless @mailboxes.has_key?(db_mailbox.name)
    end
  end

end

end
