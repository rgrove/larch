require 'rubygems'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'

$:.unshift(File.join(File.dirname(File.expand_path(__FILE__)), 'lib'))
$:.uniq!

require 'larch/version'

gemspec = Gem::Specification.new do |s|
  s.name     = 'larch'
  s.summary  = 'Larch copies messages from one IMAP server to another. Awesomely.'
  s.version  = "#{Larch::APP_VERSION}"
  s.author   = "#{Larch::APP_AUTHOR}"
  s.email    = "#{Larch::APP_EMAIL}"
  s.homepage = "#{Larch::APP_URL}"
  s.platform = Gem::Platform::RUBY

  s.executables           = ['larch']
  s.require_path          = 'lib'
  s.required_ruby_version = '>= 1.8.6'

  # s.add_dependency('highline',     '~> 1.5.0')
  # s.add_dependency('trollop',      '~> 1.13')

  s.files = FileList[
    'HISTORY',
    'LICENSE',
    'README.rdoc',
    # 'bin/larch',
    'lib/**/*.rb'
  ]
end

Rake::GemPackageTask.new(gemspec) do |p|
  p.need_tar = false
  p.need_zip = false
end

Rake::RDocTask.new do |rd|
  rd.main     = 'README.rdoc'
  rd.title    = 'Larch Documentation'
  rd.rdoc_dir = 'doc'

  rd.rdoc_files.include('README.rdoc', 'HISTORY', 'lib/**/*.rb')

  rd.options << '--line-numbers' << '--inline-source'
end

desc 'generate an updated gemspec'
task :gemspec do
  filename = File.join(File.dirname(__FILE__), "#{gemspec.name}.gemspec")
  File.open(filename, 'w') {|f| f << gemspec.to_ruby }
  puts "Created gemspec: #{filename}"
end
