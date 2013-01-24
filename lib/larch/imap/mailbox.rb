module Larch; class IMAP

# Represents an IMAP mailbox.
class Mailbox
  attr_reader :attr, :db_mailbox, :delim, :flags, :imap, :name, :perm_flags, :state, :subscribed

  # Maximum number of message headers to fetch with a single IMAP command.
  FETCH_BLOCK_SIZE = 1024

  # Regex to capture a Message-Id header.
  REGEX_MESSAGE_ID = /message-id\s*:\s*(\S+)/i

  # Minimum time (in seconds) allowed between mailbox scans.
  SCAN_INTERVAL = 60

  def initialize(imap, name, delim, subscribed, *attr)
    raise ArgumentError, "must provide a Larch::IMAP instance" unless imap.is_a?(Larch::IMAP)

    @attr       = attr.flatten
    @delim      = delim
    @flags      = []
    @imap       = imap
    @last_scan  = nil
    @name       = name
    @name_utf7  = Net::IMAP.encode_utf7(@name)
    @perm_flags = []
    @subscribed = subscribed

    # Valid mailbox states are :closed (no mailbox open), :examined (mailbox
    # open and read-only), or :selected (mailbox open and read-write).
    @state = :closed

    # Create/update this mailbox in the database.
    mb_data = {
      :name       => @name,
      :delim      => @delim,
      :attr       => @attr.map{|a| a.to_s }.join(','),
      :subscribed => @subscribed ? 1 : 0
    }

    @db_mailbox = imap.db_account.mailboxes_dataset.filter(:name => @name).first

    if @db_mailbox
      @db_mailbox.update(mb_data)
    else
      @db_mailbox = Database::Mailbox.create(mb_data)
      imap.db_account.add_mailbox(@db_mailbox)
    end

    # Create private convenience methods (debug, info, warn, etc.) to make
    # logging easier.
    Logger::LEVELS.each_key do |level|
      next if Mailbox.private_method_defined?(level)

      Mailbox.class_eval do
        define_method(level) do |msg|
          Larch.log.log(level, "#{@imap.options[:log_label]} #{@name}: #{msg}")
        end

        private level
      end
    end
  end

  # Appends the specified Larch::IMAP::Message to this mailbox if it doesn't
  # already exist. Returns +true+ if the message was appended successfully,
  # +false+ if the message already exists in the mailbox.
  def append(message)
    raise ArgumentError, "must provide a Larch::IMAP::Message object" unless message.is_a?(Larch::IMAP::Message)
    return false if has_guid?(message.guid)

    @imap.safely do
      unless imap_select(!!@imap.options[:create_mailbox])
        raise Larch::IMAP::Error, "mailbox cannot contain messages: #{@name}"
      end

      debug "appending message: #{message.guid}"
      @imap.conn.append(@name_utf7, message.rfc822, get_supported_flags(message.flags), message.internaldate) unless @imap.options[:dry_run]
    end

    true
  end
  alias << append

  # Deletes the message in this mailbox with the specified guid. Returns +true+
  # on success, +false+ on failure.
  def delete_message(guid)
    if @imap.quirks[:gmail]
      return false unless db_message = fetch_db_message(guid)

      debug "moving message to Gmail trash: #{guid}"

      @imap.safely { @imap.conn.uid_copy(db_message.uid, '[Gmail]/Trash') } &&
          set_flags(guid, [:Deleted], true)
    else
      set_flags(guid, [:Deleted], true)
    end
  end

  # Iterates through messages in this mailbox, yielding a
  # Larch::Database::Message object for each to the provided block.
  def each_db_message # :yields: db_message
    scan
    @db_mailbox.messages_dataset.all {|db_message| yield db_message }
  end

  # Iterates through messages in this mailbox, yielding the Larch message guid
  # of each to the provided block.
  def each_guid # :yields: guid
    each_db_message {|db_message| yield db_message.guid }
  end

  # Iterates through mailboxes that are first-level children of this mailbox,
  # yielding a Larch::IMAP::Mailbox object for each to the provided block.
  def each_mailbox # :yields: mailbox
    mailboxes.each {|mb| yield mb }
  end

  # Expunges this mailbox, permanently removing all messages with the \Deleted
  # flag.
  def expunge
    return false unless imap_select

    @imap.safely do
      debug "expunging deleted messages"

      @last_scan = nil
      @imap.conn.expunge unless @imap.options[:dry_run]
    end
  end

  # Returns a Larch::IMAP::Message struct representing the message with the
  # specified Larch _guid_, or +nil+ if the specified guid was not found in this
  # mailbox.
  def fetch(guid, peek = false)
    scan

    unless db_message = fetch_db_message(guid)
      warning "message not found in local db: #{guid}"
      return nil
    end

    debug "#{peek ? 'peeking at' : 'fetching'} message: #{guid}"

    imap_uid_fetch([db_message.uid], [(peek ? 'BODY.PEEK[]' : 'BODY[]'), 'FLAGS', 'INTERNALDATE', 'ENVELOPE']) do |fetch_data|
      data = fetch_data.first
      check_response_fields(data, 'BODY[]', 'FLAGS', 'INTERNALDATE', 'ENVELOPE')

      return Message.new(guid, data.attr['ENVELOPE'], data.attr['BODY[]'],
          data.attr['FLAGS'], Time.parse(data.attr['INTERNALDATE']))
    end

    warning "message not found on server: #{guid}"
    return nil
  end
  alias [] fetch

  # Returns a Larch::Database::Message object representing the message with the
  # specified Larch _guid_, or +nil+ if the specified guide was not found in
  # this mailbox.
  def fetch_db_message(guid)
    scan
    @db_mailbox.messages_dataset.filter(:guid => guid).first
  end

  # Returns +true+ if a message with the specified Larch guid exists in this
  # mailbox, +false+ otherwise.
  def has_guid?(guid)
    scan
    @db_mailbox.messages_dataset.filter(:guid => guid).count > 0
  end

  # Gets the number of messages in this mailbox.
  def length
    scan
    @db_mailbox.messages_dataset.count
  end
  alias size length

  # Returns an Array of Larch::IMAP::Mailbox objects representing mailboxes that
  # are first-level children of this mailbox.
  def mailboxes
    return [] if @attr.include?(:Noinferiors)

    all        = @imap.safely{ @imap.conn.list('', "#{@name_utf7}#{@delim}%") } || []
    subscribed = @imap.safely{ @imap.conn.lsub('', "#{@name_utf7}#{@delim}%") } || []

    all.map{|mb| Mailbox.new(@imap, mb.name, mb.delim,
        subscribed.any?{|s| s.name == mb.name}, mb.attr) }
  end

  # Same as fetch, but doesn't mark the message as seen.
  def peek(guid)
    fetch(guid, true)
  end

  # Resets the mailbox state.
  def reset
    @state = :closed
  end

  # Fetches message headers from this mailbox.
  def scan
    now = Time.now.to_i
    return if @last_scan && (now - @last_scan) < SCAN_INTERVAL

    first_scan = @last_scan.nil?
    @last_scan = now

    # Compare the mailbox's current status with its last known status.
    begin
      return unless status = imap_status('MESSAGES', 'UIDNEXT', 'UIDVALIDITY')
    rescue Error => e
      return if @imap.options[:create_mailbox]
      raise
    end

    flag_range = nil
    full_range = nil

    if @db_mailbox.uidvalidity && @db_mailbox.uidnext &&
        status['UIDVALIDITY'] == @db_mailbox.uidvalidity

      # The UIDVALIDITY is the same as what we saw last time we scanned this
      # mailbox, which means that all the existing messages in the database are
      # still valid. We only need to request headers for new messages.
      #
      # If this is the first scan of this mailbox during this Larch session,
      # then we'll also update the flags of all messages in the mailbox.

      flag_range = 1...@db_mailbox.uidnext if first_scan
      full_range = @db_mailbox.uidnext...status['UIDNEXT']

    else

      # The UIDVALIDITY has changed or this is the first time we've scanned this
      # mailbox (ever). Either way, all existing messages in the database are no
      # longer valid, so we have to throw them out and re-request everything.

      @db_mailbox.remove_all_messages
      full_range = 1...status['UIDNEXT']
    end

    @db_mailbox.update(:uidvalidity => status['UIDVALIDITY'])

    need_flag_scan = flag_range && flag_range.max && flag_range.min && flag_range.max - flag_range.min >= 0
    need_full_scan = full_range && full_range.max && full_range.min && full_range.max - full_range.min >= 0

    return unless need_flag_scan || need_full_scan

    fetch_flags(flag_range) if need_flag_scan

    if need_full_scan
      fetch_headers(full_range, {
        :progress_start => @db_mailbox.messages_dataset.count + 1,
        :progress_total => status['MESSAGES']
      })
    end

    @db_mailbox.update(:uidnext => status['UIDNEXT'])
    return
  end

  # Sets the IMAP flags for the message specified by _guid_. _flags_ should be
  # an array of symbols for standard flags, strings for custom flags.
  #
  # If _merge_ is +true+, the specified flags will be merged with the message's
  # existing flags. Otherwise, all existing flags will be cleared and replaced
  # with the specified flags.
  #
  # Note that the :Recent flag cannot be manually set or removed.
  #
  # Returns +true+ on success, +false+ on failure.
  def set_flags(guid, flags, merge = false)
    raise ArgumentError, "flags must be an Array" unless flags.is_a?(Array)

    return false unless db_message = fetch_db_message(guid)

    merged_flags    = merge ? (db_message.flags + flags).uniq : flags
    supported_flags = get_supported_flags(merged_flags)

    return true if db_message.flags == supported_flags

    return false if !imap_select
    @imap.safely { @imap.conn.uid_store(db_message.uid, 'FLAGS.SILENT', supported_flags) } unless @imap.options[:dry_run]

    true
  end

  # Subscribes to this mailbox.
  def subscribe(force = false)
    return false if subscribed? && !force

    @imap.safely { @imap.conn.subscribe(@name_utf7) } unless @imap.options[:dry_run]
    @subscribed = true
    @db_mailbox.update(:subscribed => 1)

    true
  end

  # Returns +true+ if this mailbox is subscribed, +false+ otherwise.
  def subscribed?
    @subscribed
  end

  # Unsubscribes from this mailbox.
  def unsubscribe(force = false)
    return false unless subscribed? || force

    @imap.safely { @imap.conn.unsubscribe(@name_utf7) } unless @imap.options[:dry_run]
    @subscribed = false
    @db_mailbox.update(:subscribed => 0)

    true
  end

  private

  # Checks the specified Net::IMAP::FetchData object and raises a
  # Larch::IMAP::Error unless it contains all the specified _fields_.
  #
  # _data_ can be a single object or an Array of objects; if it's an Array, then
  # only the first object in the Array will be checked.
  def check_response_fields(data, *fields)
    check_data = data.is_a?(Array) ? data.first : data

    fields.each do |f|
      raise Error, "required data not in IMAP response: #{f}" unless check_data.attr.has_key?(f)
    end

    true
  end

  # Creates a globally unique id suitable for identifying a specific message
  # on any mail server (we hope) based on the given IMAP FETCH _data_.
  #
  # If the given message data includes a valid Message-Id header, then that will
  # be used to generate an MD5 hash. Otherwise, the hash will be generated based
  # on the message's RFC822.SIZE and INTERNALDATE.
  def create_guid(data)
    if message_id = parse_message_id(data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]'])
      Digest::MD5.hexdigest(message_id)
    else
      check_response_fields(data, 'RFC822.SIZE', 'INTERNALDATE')

      Digest::MD5.hexdigest(sprintf('%d%d', data.attr['RFC822.SIZE'],
          Time.parse(data.attr['INTERNALDATE']).to_i))
    end
  end

  # Returns only the flags from the specified _flags_ array that can be set in
  # this mailbox. Emits a warning message for any unsupported flags.
  def get_supported_flags(flags)
    supported_flags = flags.dup

    supported_flags.delete_if do |flag|
      # The \Recent flag is read-only, so we shouldn't try to set it.
      next true if flag == :Recent

      unless @flags.include?(flag) || @perm_flags.include?(:*) || @perm_flags.include?(flag)
        warning "flag not supported on destination: #{flag}"
        true
      end
    end

    supported_flags
  end

  # Fetches the latest flags from the server for the specified range of message
  # UIDs.
  def fetch_flags(flag_range)
    return unless imap_examine

    info "fetching latest message flags..."

    # Load the expected UIDs and their flags into a Hash for quicker lookups.
    expected_uids = {}
    @db_mailbox.messages_dataset.all do |db_message|
      expected_uids[db_message.uid] = db_message.flags
    end

    imap_uid_fetch(flag_range, "(UID FLAGS)", 16384) do |fetch_data|
      # Check the fields in the first response to ensure that everything we
      # asked for is there.
      check_response_fields(fetch_data.first, 'UID', 'FLAGS') unless fetch_data.empty?

      Larch.db.transaction do
        fetch_data.each do |data|
          uid         = data.attr['UID']
          flags       = data.attr['FLAGS']
          local_flags = expected_uids[uid]

          # If we haven't seen this message before, or if its flags have
          # changed, update the database.
          unless local_flags && local_flags == flags
            @db_mailbox.messages_dataset.filter(:uid => uid).update(:flags => flags.map{|f| f.to_s }.join(','))
          end

          expected_uids.delete(uid)
        end
      end
    end

    # Any UIDs that are in the database but weren't in the response have been
    # deleted from the server, so we need to delete them from the database as
    # well.
    unless expected_uids.empty?
      debug "removing #{expected_uids.length} deleted messages from the database..."

      Larch.db.transaction do
        expected_uids.each_key do |uid|
          @db_mailbox.messages_dataset.filter(:uid => uid).destroy
        end
      end
    end

    expected_uids = nil
    fetch_data    = nil
  end

  # Fetches the latest headers from the server for the specified range of
  # message UIDs.
  def fetch_headers(header_range, options = {})
    return unless imap_examine

    options = {
      :progress_start => 0,
      :progress_total => 0
    }.merge(options)

    fetched       = 0
    progress      = 0
    show_progress = options[:progress_total] - options[:progress_start] > FETCH_BLOCK_SIZE * 4

    info "fetching message headers #{options[:progress_start]} through #{options[:progress_total]}..."

    last_good_uid = nil

    imap_uid_fetch(header_range, "(UID BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)] RFC822.SIZE INTERNALDATE FLAGS)") do |fetch_data|
      # Check the fields in the first response to ensure that everything we
      # asked for is there.
      check_response_fields(fetch_data, 'UID', 'RFC822.SIZE', 'INTERNALDATE', 'FLAGS')

      Larch.db.transaction do
        fetch_data.each do |data|
          uid = data.attr['UID']

          Database::Message.create(
            :mailbox_id   => @db_mailbox.id,
            :guid         => create_guid(data),
            :uid          => uid,
            :message_id   => parse_message_id(data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]']),
            :rfc822_size  => data.attr['RFC822.SIZE'].to_i,
            :internaldate => Time.parse(data.attr['INTERNALDATE']).to_i,
            :flags        => data.attr['FLAGS']
          )

          last_good_uid = uid
        end

        # Set this mailbox's uidnext value to the last known good UID that
        # was stored in the database, plus 1. This will allow Larch to
        # resume where the error occurred on the next attempt rather than
        # having to start over.
        @db_mailbox.update(:uidnext => last_good_uid + 1)
      end

      if show_progress
        fetched       += fetch_data.length
        last_progress  = progress
        progress       = ((100 / (options[:progress_total] - options[:progress_start]).to_f) * fetched).round

        info "#{progress}% complete" if progress > last_progress
      end
    end
  end

  # Examines this mailbox. If _force_ is true, the mailbox will be examined even
  # if it is already selected (which isn't necessary unless you want to ensure
  # that it's in a read-only state).
  #
  # Returns +false+ if this mailbox cannot be examined, which may be the case if
  # the \Noselect attribute is set.
  def imap_examine(force = false)
    return false if @attr.include?(:Noselect)
    return true if @state == :examined || (!force && @state == :selected)

    @imap.safely do
      begin
        @imap.conn.close unless @state == :closed
        @state = :closed

        debug "examining mailbox"
        @imap.conn.examine(@name_utf7)
        refresh_flags

        @state = :examined

      rescue Net::IMAP::NoResponseError => e
        raise Error, "unable to examine mailbox: #{e.message}"
      end
    end

    return true
  end

  # Selects the mailbox if it is not already selected. If the mailbox does not
  # exist and _create_ is +true+, it will be created. Otherwise, a
  # Larch::IMAP::Error will be raised.
  #
  # Returns +false+ if this mailbox cannot be selected, which may be the case if
  # the \Noselect attribute is set.
  def imap_select(create = false)
    return false if @attr.include?(:Noselect)
    return true if @state == :selected

    @imap.safely do
      begin
        @imap.conn.close unless @state == :closed
        @state = :closed

        debug "selecting mailbox"
        @imap.conn.select(@name_utf7)
        refresh_flags

        @state = :selected

      rescue Net::IMAP::NoResponseError => e
        raise Error, "unable to select mailbox: #{e.message}" unless create

        info "creating mailbox: #{@name}"

        begin
          @imap.conn.create(@name_utf7) unless @imap.options[:dry_run]
          retry
        rescue => e
          raise Error, "unable to create mailbox: #{e.message}"
        end
      end
    end

    return true
  end

  # Sends an IMAP STATUS command and returns the status of the requested
  # attributes. Supported attributes include:
  #
  #   - MESSAGES
  #   - RECENT
  #   - UIDNEXT
  #   - UIDVALIDITY
  #   - UNSEEN
  def imap_status(*attr)
    @imap.safely do
      begin
        debug "getting mailbox status"
        @imap.conn.status(@name_utf7, attr)
      rescue Net::IMAP::NoResponseError => e
        raise Error, "unable to get status of mailbox: #{e.message}"
      end
    end
  end

  # Fetches the specified _fields_ for the specified _set_ of UIDs, which can be
  # a number, Range, or Array of UIDs.
  #
  # If _set_ is a number, an Array containing a single Net::IMAP::FetchData
  # object will be yielded to the given block.
  #
  # If _set_ is a Range or Array of UIDs, Arrays of up to <i>block_size</i>
  # Net::IMAP::FetchData objects will be yielded until all requested messages
  # have been fetched.
  #
  # However, if _set_ is a Range with an end value of -1, a single Array
  # containing all requested messages will be yielded, since it's impossible to
  # divide an infinite range into finite blocks.
  def imap_uid_fetch(set, fields, block_size = FETCH_BLOCK_SIZE, &block) # :yields: fetch_data
    if set.is_a?(Numeric) || (set.is_a?(Range) && set.last < 0)
      data = @imap.safely do
        imap_examine
        @imap.conn.uid_fetch(set, fields)
      end

      yield data unless data.nil?
      return
    end

    blocks = []
    pos    = 0

    if set.is_a?(Array)
      while pos < set.length
        blocks += set[pos, block_size]
        pos    += block_size
      end

    elsif set.is_a?(Range)
      pos = set.min - 1

      while pos < set.max
        blocks << ((pos + 1)..[set.max, pos += block_size].min)
      end
    end

    blocks.each do |block|
      data = @imap.safely do
        imap_examine

        begin
          data = @imap.conn.uid_fetch(block, fields)

        rescue Net::IMAP::NoResponseError => e
          raise unless e.message == 'Some messages could not be FETCHed (Failure)'

          # Workaround for stupid Gmail shenanigans.
          warning "Gmail error: '#{e.message}'; continuing anyway"
        end

        next data
      end

      yield data unless data.nil?
    end
  end

  # Parses a Message-Id header out of _str_ and returns it, or +nil+ if _str_
  # doesn't contain a valid Message-Id header.
  def parse_message_id(str)
    return str =~ REGEX_MESSAGE_ID ? $1 : nil
  end

  # Refreshes the list of valid flags for this mailbox.
  def refresh_flags
    return unless @imap.conn.responses.has_key?('FLAGS') &&
        @imap.conn.responses.has_key?('PERMANENTFLAGS')

    @flags      = Array(@imap.conn.responses['FLAGS'].first)
    @perm_flags = Array(@imap.conn.responses['PERMANENTFLAGS'].first)
  end

end

end; end
