require 'rubygems'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'

$:.unshift(File.join(File.dirname(File.expand_path(__FILE__)), 'lib'))
$:.uniq!

require 'larch/version'

gemspec = nil

File.open(File.join(File.dirname(__FILE__), 'larch.gemspec')) do |f|
  eval("gemspec = #{f.read}")
end

Rake::GemPackageTask.new(gemspec) do |p|
  p.need_tar = false
  p.need_zip = false
end

Rake::RDocTask.new do |rd|
  rd.main     = 'README.rdoc'
  rd.title    = 'Larch Documentation'
  rd.rdoc_dir = 'doc'

  rd.rdoc_files.include('README.rdoc', 'lib/**/*.rb')

  rd.options << '--line-numbers' << '--inline-source'
end

desc 'generate an updated gemspec'
task :gemspec do
  gemspec = <<-OUT
Gem::Specification.new do |s|
  s.name     = 'larch'
  s.summary  = 'Larch syncs messages from one IMAP server to another. Awesomely.'
  s.version  = "#{Larch::APP_VERSION}"
  s.author   = "#{Larch::APP_AUTHOR}"
  s.email    = "#{Larch::APP_EMAIL}"
  s.homepage = "#{Larch::APP_URL}"
  s.platform = Gem::Platform::RUBY

  s.executables           = ['larch']
  s.require_path          = 'lib'
  s.required_ruby_version = '>= 1.8.6'

  s.add_dependency('highline', '~> 1.5.0')
  s.add_dependency('trollop',  '~> 1.13')

  s.files = [
    'HISTORY',
    'LICENSE',
    'README.rdoc',
    'bin/larch',
    'lib/larch.rb',
    'lib/larch/errors.rb',
    'lib/larch/imap.rb',
    'lib/larch/logger.rb',
    'lib/larch/version.rb'
  ]
end
  OUT

  File.open(File.join(File.dirname(__FILE__), 'larch.gemspec'), 'w') do |file|
    file.puts(gemspec)
  end
end
