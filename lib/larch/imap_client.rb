require 'larch/connection_pool'

class Larch::IMAPClient
  attr_reader :uri

  # Initializes a new Larch::IMAPClient that will connect to the specified IMAP
  # URI.
  #
  # [:imap_options]
  #   Options Hash to pass to Larch::IMAP when creating a new connection. See
  #   the Larch::IMAP documentation for available options.
  #
  # [:max_connections]
  #   Maximum number of connections to open to the server (default: 4).
  #
  def initialize(uri, options = {})
    @mutex = Mutex.new
    @uri   = uri.is_a?(URI) ? uri : URI(uri)

    Larch::IMAP.validate_uri(@uri)

    pool_options = {}
    pool_options[:imap_options]    = options[:imap_options] if options[:imap_options]
    pool_options[:max_connections] = options[:max_connections] if options[:max_connections]

    @pool = Larch::ConnectionPool.new(@uri, pool_options)
  end

  # Iterates through all mailboxes, starting at the specified root mailbox (if
  # any) and traverses mailbox hierarchies in a depth-first manner, yielding
  # each mailbox to the supplied block in the form of a Net::IMAP::MailboxList
  # object.
  #
  # Mailboxes are iterated in alphanumeric order, with the exception of the
  # INBOX, which will always come first.
  def each_mailbox(mailbox = nil, &block)
    traverse_mailboxes(mailbox, &block)
  end

  # Same as #each_mailbox, but only iterates through subscribed mailboxes.
  def each_subscribed_mailbox(mailbox = nil, &block)
    traverse_mailboxes(mailbox, true, &block)
  end

  private

  def sync
    @mutex.synchronize { yield }
  end

  def traverse_mailboxes(mailbox = nil, subscribed = false, delim = '/', &block)
    mailbox = mailbox ? "#{mailbox.chomp(delim)}#{delim}%" : '%'

    mailboxes = @pool.hold do |imap|
      if subscribed
        imap.lsub('', mailbox)
      else
        imap.list('', mailbox)
      end
    end || []

    mailboxes = mailboxes.sort_by do |mb|
      name = mb.name.downcase.strip
      name == 'inbox' ? '' : name
    end

    mailboxes.each do |mb|
      yield mb

      unless mb.attr.include?(:Hasnochildren) || mb.attr.include?(:Noinferiors)
        traverse_mailboxes(mb.name, subscribed, mb.delim, &block)
      end
    end
  end
end
