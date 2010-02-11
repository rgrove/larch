module Larch

class Config
  attr_reader :filename, :section

  DEFAULT = {
    'all'              => false,
    'all-subscribed'   => false,
    'config'           => File.join('~', '.larch', 'config.yaml'),
    'database'         => File.join('~', '.larch', 'larch.db'),
    'delete'           => false,
    'dry-run'          => false,
    'exclude'          => [],
    'exclude-file'     => nil,
    'expunge'          => false,
    'from'             => nil,
    'from-folder'      => nil, # actually INBOX; see validate()
    'from-pass'        => nil,
    'from-user'        => nil,
    'max-retries'      => 3,
    'no-create-folder' => false,
    'no-recurse'       => false,
    'ssl-certs'        => nil,
    'ssl-verify'       => false,
    'sync-flags'       => false,
    'to'               => nil,
    'to-folder'        => nil, # actually INBOX; see validate()
    'to-pass'          => nil,
    'to-user'          => nil,
    'verbosity'        => 'info'
  }.freeze

  def initialize(section = 'default', filename = DEFAULT['config'], override = {})
    @section  = section.to_s
    @override = {}

    override.each do |k, v|
      opt = k.to_s.gsub('_', '-')
      @override[opt] = v if DEFAULT.has_key?(opt) && override["#{k}_given".to_sym] && v != DEFAULT[opt]
    end

    load_file(filename)
    validate
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

  # Validates the config and resolves conflicting settings.
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

    if @cached['all'] || @cached['all-subscribed']
      # A specific source folder wins over 'all' and 'all-subscribed'
      if @cached['from-folder']
        @cached['all']              = false
        @cached['all-subscribed']   = false
        @cached['to-folder']      ||= @cached['from-folder']

      elsif @cached['all'] && @cached['all-subscribed']
        # 'all' wins over 'all-subscribed'
        @cached['all-subscribed'] = false
      end

      # 'no-recurse' is not compatible with 'all' and 'all-subscribed'
      raise Error, "'no-recurse' option cannot be used with 'all' or 'all-subscribed'" if @cached['no-recurse']

    else
      @cached['from-folder'] ||= 'INBOX'
      @cached['to-folder']   ||= 'INBOX'
    end

    @cached['exclude'].flatten!
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
