# encoding: utf-8
require './lib/larch/version'

Gem::Specification.new do |s|
  s.name     = 'larch'
  s.summary  = 'Larch copies messages from one IMAP server to another. Awesomely.'
  s.version  = Larch::APP_VERSION
  s.authors  = ['Ryan Grove']
  s.email    = 'ryan@wonko.com'
  s.homepage = 'https://github.com/rgrove/larch'
  s.platform = Gem::Platform::RUBY

  s.executables           = ['larch']
  s.require_path          = 'lib'
  s.required_ruby_version = '>= 1.8.6'

  # s.add_dependency('amalgalite', '~> 1.0')
  s.add_dependency('highline',   '~> 1.5')
  s.add_dependency('sequel',     '~> 3.14')
  s.add_dependency('sqlite3',    '~> 1.3')
  s.add_dependency('trollop',    '~> 1.13')

  s.files = [
    'HISTORY',
    'LICENSE',
    'README.rdoc',
    'bin/larch'
  ] + Dir.glob('lib/**/*.rb')
end
