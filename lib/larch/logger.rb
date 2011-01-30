class Larch::Logger
  attr_reader :level, :pipe
  attr_accessor :prefix

  LEVELS = {
    :fatal   => 0,
    :error   => 1,
    :warn    => 2,
    :warning => 2,
    :info    => 3,
    :debug   => 4,
    :imap    => 5,
    :insane  => 5
  }

  class << self
    # Global logger instance.
    def log
      @log ||= Larch::Logger.new
    end

    # Global default verbosity. Logger instances will fall back to this if they
    # don't have an explicit verbosity level of their own.
    def verbosity
      @verbosity ||= :info
    end

    def verbosity=(level)
      raise ArgumentError, "invalid verbosity level: #{level}" unless LEVELS.key?(level)
      @verbosity = level
    end
  end

  def initialize(prefix = '', level = :default, pipe = $stdout)
    @prefix    = prefix
    self.level = level
    self.pipe  = pipe
  end

  def const_missing(name)
    return LEVELS[name] if LEVELS.key?(name)
    super
  end

  def level=(level)
    level = level.to_sym

    if level == :default
      @level = Larch::Logger.verbosity
    else
      raise ArgumentError, "invalid log level: #{level}" unless LEVELS.key?(level)
      @level = level
    end
  end

  def log(level, message, prefix = @prefix, pipe = @pipe)
    return true if LEVELS[level] > LEVELS[@level] || message.nil? || message.empty?

    # If the prefix is callable, call it to generate a prefix on demand.
    # Otherwise, just cast it to a string.
    prefix = if prefix.respond_to?(:call)
      prefix.call.to_s
    else
      prefix.to_s
    end

    pipe.puts "[#{Time.new.strftime('%H:%M:%S')}] [#{level}] " <<
        (prefix.empty? ? "" : "#{prefix} ") <<
        message.to_s

    true

  rescue => e
    false
  end

  def method_missing(name, *args, &block)
    return log(name, *args) if LEVELS.key?(name)
    super
  end

  def pipe=(pipe)
    raise ArgumentError, "pipe must be an instance of class IO" unless pipe.is_a?(IO)
    @pipe = pipe
  end

  def respond_to_missing?(name, *)
    LEVELS.key?(name) || super
  end
end
