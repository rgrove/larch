module Larch

class Config
  attr_reader :filename, :section

  DEFAULT = {
    'all'              => false,
    'all-subscribed'   => false,
    'config'           => File.join('~', '.larch', 'config.yaml'),
    'database'         => File.join('~', '.larch', 'larch.db'),
    'dry-run'          => false,
    'exclude'          => [],
    'exclude-file'     => nil,
    'from'             => nil,
    'from-folder'      => 'INBOX',
    'from-pass'        => nil,
    'from-user'        => nil,
    'max-retries'      => 3,
    'no-create-folder' => false,
    'ssl-certs'        => nil,
    'ssl-verify'       => false,
    'to'               => nil,
    'to-folder'        => 'INBOX',
    'to-pass'          => nil,
    'to-user'          => nil,
    'verbosity'        => 'info'
  }.freeze

  def initialize(section = 'default', filename = DEFAULT['config'], override = {})
    @section  = section.to_s
    @override = {}

    override.each do |k, v|
      k = k.to_s.gsub('_', '-')
      @override[k] = v if DEFAULT.has_key?(k) && v != DEFAULT[k]
    end

    load_file(filename)
  end

  def fetch(name)
    (@cached || {})[name.to_s.gsub('_', '-')] || nil
  end
  alias [] fetch

  def load_file(filename)
    @filename = File.expand_path(filename)

    config = {}

    if File.exist?(@filename)
      begin
        config = YAML.load_file(@filename)
      rescue => e
        raise Larch::Config::Error, "config error in #{filename}: #{e}"
      end
    end

    @lookup = [@override, config[@section] || {}, config['default'] || {}, DEFAULT]
    cache_config
  end

  def method_missing(name)
    fetch(name)
  end

  def validate
    ['from', 'to'].each do |s|
      raise Error, "'#{s}' must be a valid IMAP URI (e.g. imap://example.com)" unless fetch(s) =~ IMAP::REGEX_URI
    end

    unless Logger::LEVELS.has_key?(verbosity.to_sym)
      raise Error, "'verbosity' must be one of: #{Logger::LEVELS.keys.join(', ')}"
    end

    if exclude_file
      raise Error, "exclude file not found: #{exclude_file}" unless File.file?(exclude_file)
      raise Error, "exclude file cannot be read: #{exclude_file}" unless File.readable?(exclude_file)
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

end

end
