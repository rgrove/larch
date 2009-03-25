Gem::Specification.new do |s|
  s.name     = 'larch'
  s.summary  = 'Larch syncs messages from one IMAP server to another. Awesomely.'
  s.version  = '1.0.0.1'
  s.author   = 'Ryan Grove'
  s.email    = 'ryan@wonko.com'
  s.homepage = 'http://github.com/rgrove/larch/'
  s.platform = Gem::Platform::RUBY

  s.executables           = ['larch']
  s.require_path          = 'lib'
  s.required_ruby_version = '>= 1.8.6'

  s.add_dependency('highline', '~> 1.5.0')
  s.add_dependency('trollop',  '~> 1.13')

  s.files = [
    'LICENSE',
    'bin/larch',
    'lib/larch.rb',
    'lib/larch/errors.rb',
    'lib/larch/imap.rb',
    'lib/larch/logger.rb',
    'lib/larch/version.rb'
  ]
end
