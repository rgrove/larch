require 'rubygems'
require 'hanna/rdoctask'
require 'open-uri'
require 'rake/clean'
require 'rake/gempackagetask'

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
  s.required_ruby_version = '>= 1.8.7'

  s.add_dependency('amalgalite', '~> 1.0.0')
  s.add_dependency('highline',   '~> 1.5.0')
  s.add_dependency('sequel',     '~> 3.14')
  s.add_dependency('trollop',    '~> 1.13')

  s.add_development_dependency('bacon', '~> 1.1')
  s.add_development_dependency('hanna', '~> 0.1.12')
  s.add_development_dependency('rake',  '~> 0.8')

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

  rd.rdoc_files.include('README.rdoc', 'lib/**/*.rb')

  rd.options << '--line-numbers' << '--inline-source' <<
      '--webcvs=http://github.com/rgrove/larch/tree/refactor/'
end

task :default => [:test]

desc 'Update CA root certificate bundle'
task :update_certs do
  url = 'http://curl.haxx.se/ca/cacert.pem'

  print "Updating CA root certificates from #{url}..."

  File.open(File.join(File.dirname(__FILE__), 'lib', 'larch', 'config', 'cacert.pem'), 'w') do |f|
    open(url) {|http| f.write(http.read) }
  end

  puts "done"
end

desc 'Run tests'
task :test do
  sh 'bacon -a'
end

desc 'Generate an updated gemspec'
task :gemspec do
  filename = File.join(File.dirname(__FILE__), "#{gemspec.name}.gemspec")
  File.open(filename, 'w') {|f| f << gemspec.to_ruby }
  puts "Created gemspec: #{filename}"
end
