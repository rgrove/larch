# Represents an open IMAP mailbox.
#
# Don't instantiate this class directly. Larch::IMAP::Mailbox instances are
# created as needed by Larch::IMAP, and should be accessed via the
# Larch::IMAP#mailbox attribute.
class Larch::IMAP::Mailbox
  # Hierarchy delimiter for this mailbox.
  attr_reader :delim

  # Name of this mailbox encoded as a UTF-8 string, with hierarchy delimiters
  # normalized to '/' regardless of the actual delimiter in use on this server.
  attr_reader :name

  # Name of this mailbox encoded as a UTF-8 string, with the original hierarchy
  # delimiters as returned by the server.
  attr_reader :raw_name

  # Name of this mailbox encoded as a modified UTF-7 string, with the original
  # hierarchy delimiters as returned by the server.
  attr_reader :raw_name_utf7

  # Returns +true+ if this mailbox is in read-only (EXAMINE) mode as opposed to
  # read-write (SELECT) mode.
  attr_reader :read_only

  def initialize(name, options = {}) # :nodoc:
    @closed        = false
    @close_handler = options[:close_handler]
    @conn          = options[:connection]
    @imap          = options[:imap]
    @delim         = options[:delim] || @imap.delim
    @raw_name      = Net::IMAP.decode_utf7(name)
    @raw_name_utf7 = Net::IMAP.encode_utf7(@raw_name)
    @name          = @raw_name.gsub(@delim, '/')
    @read_only     = !!options[:read_only]

    raise ArgumentError, "connection must be a Net::IMAP instance" unless @conn.is_a?(Net::IMAP)
    raise ArgumentError, "imap must be a Larch::IMAP instance" unless @imap.is_a?(Larch::IMAP)

    @imap.add_response_handler(method(:handle_response))
  end

  # Sends a CHECK command to request a checkpoint of this mailbox. This performs
  # implementation-specific housekeeping that differs from server to server,
  # such as reconciling the mailbox's in-memory and on-disk state.
  def check
    require_open
    @conn.check
  end

  # Closes this mailbox. If the mailbox is in read/write mode (SELECTed),
  # closing it will permanently expunge all messages with the
  # <code>\Deleted</code> flag set. Use #unselect to close a mailbox without
  # expunging deleted messages.
  def close
    require_open
    response = @conn.close
    self_destruct
    response
  end

  # Sends an EXPUNGE command to permanently remove all messages in this mailbox
  # that have the <code>\Deleted</code> flag set.
  def expunge
    require_open
    @conn.expunge
  end

  # Sends a FETCH command to retrieve data associated with one or more messages
  # in this mailbox.
  #
  # The _uid_set_ parameter should be a UID, an Array of UIDs, or a Range of
  # UIDs. To specify a wildcard fetch range like '1:*', use a Range with
  # <code>-1</code> in place of the <code>*</code>, like <code>1..-1</code>
  #
  # The _attributes_ parameter is a list of message attributes to fetch. See
  # Net::IMAP::FetchData for a list of valid attributes.
  #
  # If a block is given, results will be yielded to the block in Arrays of up to
  # <em>fetch_size</em> items until the fetch is complete. If no block is given,
  # a single Array containing all fetched items will be returned.
  def fetch(uid_set, attributes, fetch_size = 512)
    require_open

    # TODO: workaround for Gmail "some messages could not be fetched" error?

    if !block_given? || uid_set.is_a?(Numeric) ||
        (uid_set.is_a?(Range) && uid_set.last < 0)

      data = @conn.uid_fetch(uid_set, attributes)

      if block_given?
        until (chunk = data.slice!(0, fetch_size)).empty?
          yield chunk
        end

        return
      else
        return data || []
      end
    end

    sets   = []
    chunks = []

    if uid_set.is_a?(Range)
      pos = uid_set.min - 1

      while pos < uid_set.max
        sets << ((pos + 1)..[uid_set.max, pos += fetch_size].min)
      end
    elsif uid_set.is_a?(Array)
      until (set = uid_set.slice!(0, fetch_size)).empty?
        sets << set
      end
    end

    sets.each do |set|
      data = @conn.uid_fetch(set, attributes)
      yield data unless data.nil?
    end
  end

  # def peek
  #   require_open
  # end

  # Sends a SEARCH command to search this mailbox for messages that match the
  # given search criteria, and returns message UIDs. See Net::IMAP#search for
  # details.
  def search(keys, charset = nil)
    require_open
    @conn.uid_search(uid_keys, charset)
  end

  # Sends a SORT command to sort messages in this mailbox. Returns an Array of
  # message UIDs. See Net::IMAP#sort for details.
  def sort(sort_keys, search_keys, charset)
    require_open
    @conn.uid_sort(sort_keys, search_keys, charset)
  end

  # Sends a STORE command to alter data associated with messages in this
  # mailbox, in particular their flags. See Net::IMAP#store for details.
  def store(uid_set, attributes, flags)
    require_open
    @conn.uid_store(uid_set, attributes, flags)
  end

  # Returns +true+ if this mailbox is subscribed.
  def subscribed?
    require_open
    (@conn.lsub('', @raw_name_utf7) || []).length == 1
  end

  # Closes this mailbox without expunging deleted messages. This method sends
  # the UNSELECT command if the server supports it; otherwise, it EXAMINEs the
  # current mailbox to make it read-only, then CLOSEs it.
  def unselect
    require_open

    if @imap.capability.include?('UNSELECT')
      # Use the UNSELECT command to close the mailbox without expunging. See
      # RFC 3691: http://www.networksorcery.com/enp/rfc/rfc3691.txt
      response = @conn.instance_eval { send_command('UNSELECT') }
      self_destruct
    else
      # Server doesn't support UNSELECT, so just EXAMINE the current mailbox and
      # then CLOSE it.
      @conn.examine(@name_utf7)
      response = close
    end

    response
  end

  private

  def handle_response(response)
  end

  def require_open
    raise Larch::IMAP::MailboxClosed, "this mailbox is closed" if @closed
  end

  def self_destruct
    @imap.remove_response_handler(method(:handle_response))
    @close_handler.call
    @closed = true
  end
end
