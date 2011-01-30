require 'trollop'

class Larch::CLI
  attr_reader :config, :options

  CONFIG_PATH   = File.join(Larch::CONFIG_DIR, 'config.rb')
  DATABASE_PATH = File.join(Larch::CONFIG_DIR, 'larch.db')

  def initialize
    @log = Larch::Logger.log

    parse_args
    load_config
    trap_signals
  end

  private

  def load_config
    if @options[:config_given] && !File.exist(@options[:config])
      Trollop.die :config, ": file not found: #{@options[:config]}"
    end

    # Load the default and user config files.
    @config = Larch::Config.new(@options[:config] || CONFIG_PATH,
        @options[:section])

    # Mix in command-line options, if any.
    override = {}
    @options.each do |k, v|
      override[k] = v if @options["#{k}_given".to_sym]
    end
    @config.override(override)

    # Validate the resulting merged configuration.
    @config.validate

    # Enact the configuration.
    Larch::Logger.verbosity = @config[:verbosity]
  end

  def parse_args
    banner_text = <<-EOS
      Larch copies messages from one IMAP server to another. Awesomely.

      Usage:
        larch <config section> [options]

      Edit #{CONFIG_PATH} to configure copy operations and advanced options.

      Options:
    EOS

    @options = Trollop.options do
      version "Larch #{Larch::APP_VERSION}\n" << Larch::APP_COPYRIGHT
      banner banner_text.gsub(/^ {6}/, '')

      opt :config,
          "Use this config file instead of the default.",
          :short => '-c', :default => CONFIG_PATH

      opt :database,
          "Use this message database instead of the default.",
          :short => :none, :default => DATABASE_PATH

      opt :dry_run,
          "Simulate all changes, but don't actually change anything.",
          :short => '-n'

      opt :verbosity,
          "Output verbosity. From least to most verbose: fatal, error, warn, info, debug, imap",
          :short => '-V', :default => 'info'
    end

    # The first argument left after all options have been parsed should be the
    # config section.
    @options[:section] = ARGV.shift
  end

  def trap_signals
    return if RUBY_PLATFORM =~ /mswin|mingw|bccwin|wince|java/

    for sig in [:SIGINT, :SIGQUIT, :SIGTERM]
      trap(sig) { @log.fatal "Interrupted (#{sig})"; Kernel.exit }
    end

  rescue => e
    @log.debug("unable to trap signals: #{e}")
  end
end
