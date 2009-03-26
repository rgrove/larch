module Larch

class Logger
  attr_reader :level, :output

  LEVELS = {
    :fatal  => 0,
    :error  => 1,
    :warn   => 2,
    :info   => 3,
    :debug  => 4,
    :insane => 5
  }

  def initialize(level = :info, output = $stdout)
    self.level  = level.to_sym
    self.output = output
  end

  def const_missing(name)
    return LEVELS[name] if LEVELS.key?(name)
    raise NameError, "uninitialized constant: #{name}"
  end

  def method_missing(name, *args)
    return log(name, *args) if LEVELS.key?(name)
    raise NoMethodError, "undefined method: #{name}"
  end

  def level=(level)
    raise ArgumentError, "invalid log level: #{level}" unless LEVELS.key?(level)
    @level = level
  end

  def log(level, msg)
    return true if LEVELS[level] > LEVELS[@level] || msg.nil? || msg.empty?
    @output.puts "[#{Time.new.strftime('%b %d %H:%M:%S')}] [#{level}] #{msg}"
    true

  rescue => e
    false
  end

  def output=(output)
    raise ArgumentError, "output must be an instance of class IO" unless output.is_a?(IO)
    @output = output
  end
end

end
