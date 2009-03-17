require 'rubygems'
require 'rake/gempackagetask'
require 'rake/rdoctask'

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
