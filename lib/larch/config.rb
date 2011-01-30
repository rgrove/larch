class Larch::Config
  def initialize(filename, section = nil)
    @cached  = {}
    @section = section

    load(filename)
  end

  # Adds the specified config Hash to the end of the config lookup chain. Any
  # configuration values in _config_ will be used as defaults unless they're
  # specified earlier in the lookup chain.
  def <<(config)
    raise ArgumentError, "config must be a Hash" unless config.is_a?(Hash)

    (@lookup ||= []) << config
    cache_config

    @lookup
  end

  def fetch(name, default = nil)
    @cached[name] || default
  end
  alias [] fetch

  def key?(name)
    @cached.has_key?(name)
  end
  alias has_key? key?
  alias include? key?
  alias member? key?

  def load(filename)
    @lookup = []

    filename = File.expand_path(filename)

    [filename, File.join(Larch::LIB_CONFIG_DIR, 'config.default.rb')].each do |filename|
      next unless File.exist?(filename)

      config = eval("{#{File.read(filename)}}", nil, filename)

      @lookup << config[@section] if @section && config.key?(@section)
      @lookup << config[:default] if config.key?(:default)
    end

    cache_config
  end

  # Adds the specified config Hash to the front of the config lookup chain. Any
  # configuration values in _config_ will take precedence over values later in
  # the chain.
  def override(config)
    raise ArgumentError, "config must be a Hash" unless config.is_a?(Hash)

    (@lookup ||= []).unshift(config)
    cache_config

    @lookup
  end

  def validate
    [:from, :to].each do |field|
      c = fetch(field)

      if !c[:host] || c[:host].empty?
        raise Error, "#{field}: no host specified."
      end

      if !c[:user] || c[:user].empty? || !c[:pass] # empty pass is allowed
        raise Error, "#{field}: user or pass not specified."
      end
    end

    folders = fetch(:folders)
    unless folders == :all || folders == :subscribed || folders.is_a?(Array) || folders.is_a?(Hash)
      raise Error, "folders: must be :all, :subscribed, an array, or a hash."
    end

    unless Larch::Logger::LEVELS.has_key?(fetch(:verbosity))
      raise Error, "verbosity: must be one of #{Larch::Logger::LEVELS.keys.join(', ')}"
    end
  end

  private

  # Merges configs such that those earlier in the lookup chain override those
  # later in the chain.
  def cache_config
    @cached = {}

    @lookup.reverse.each do |c|
      c.each {|k, v| @cached[k] = config_merge(@cached[k] || {}, v) }
    end
  end

  def config_merge(master, value)
    if value.is_a?(Hash)
      value.each {|k, v| master[k] = config_merge(master[k] || {}, v) }
      return master
    end

    value
  end

  class Error < Larch::Error; end
end
