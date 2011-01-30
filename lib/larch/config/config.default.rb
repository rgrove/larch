# Default settings that will apply to all Larch operations unless overridden in
# another config section or by a command line option.
:default => {
  # Create folders on the destination if they don't already exist.
  :create_folders => true,

  # Path to the Larch message database. This database is used to store message
  # header and flag information (but not contents) to speed up mailbox syncing.
  :database => "#{Larch::CONFIG_DIR}/larch.db",

  # Delete messages from the source after copying them, or after verifying that
  # they already exist at the destination.
  :delete => false,

  # If true, all changes will be simulated, but no changes will actually be made
  # and no messages will actually be copied.
  :dry_run => false,

  # Names or regular expressions that match folders that should be excluded.
  :exclude => [],

  # Expunge deleted messages from the source. If this is false, deleted messages
  # will be flagged as deleted, but won't actually be removed until a mail
  # client (or the server) expunges them.
  :expunge => false,

  # Folders to copy from the source to the destination. Possible values are:
  #
  #   :all                  - Copy all folders.
  #   :subscribed           - Only copy subscribed folders.
  #   array of folder names - Copy every named folder from the source to a
  #                           the folder with the same name on the destination.
  #   hash of folder names  - Hash that maps source folder names to destination
  #                           folder names (which may differ from the source
  #                           names).
  :folders => :all,

  # Maximum number of times to retry an operation after a recoverable error.
  :max_retries => 3,

  # Recurse into subfolders. If this is false, subfolders will be ignored unless
  # they're explicitly included in the folder listing.
  :recursive => true,

  # Path to a trusted SSL certificate authority (CA) bundle that can be used to
  # verify server SSL certificates.
  :ssl_certs => "#{Larch::LIB_CONFIG_DIR}/cacert.pem",

  # Whether or not to verify server SSL certificates.
  :ssl_verify => true,

  # Sync message flags from the source to the destination for messages that
  # already exist on the destination. For example, if a message is marked read
  # on the source, but unread on the destination, the destination message will
  # be marked read.
  :sync_flags => true,

  # Logging verbosity. Possible values (from least to most verbose) are:
  #
  #   :fatal - Fatal errors from which recovery is impossible.
  #   :error - Errors that may be recoverable.
  #   :warn  - Non-critical warning messages.
  #   :info  - Informational and status messages.
  #   :debug - Debugging messages.
  #   :imap  - All IMAP requests and responses (including sensitive data like
  #            usernames, passwords, and message contents).
  #
  # Setting the verbosity to a more verbose level will automatically include
  # less verbose messages as well, so :info also includes :warn, :error, and
  # :fatal (but not :debug or :imap).
  :verbosity => :info
},

# Config sections can override any of the default settings, and can also specify
# "from" (source) and "to" (destination) settings for the copy operation.
'example section' => {
  # The "from" settings specify information for connecting to the source server
  # (the server that messages are copied from).
  :from => {
    # Hostname or IP address of the source server.
    :host => 'mail.example.com',

    # Port number to connect to on the source server. This is optional; if
    # omitted, it will default to 143 (or 993 if SSL is enabled).
    :port => 993,

    # Source username.
    :user => 'username',

    # Source password.
    :pass => 'password',

    # Whether or not to use SSL.
    :ssl  => true,
  },

  # The "to" settings specify information for connecting to the destination
  # server (the server that messages are copied to).
  :to => {
    # Host, port, user, pass, and ssl options are the same as for the "from"
    # settings.
  }
}
