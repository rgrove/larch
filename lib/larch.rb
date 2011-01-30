module Larch
  CONFIG_DIR     = File.expand_path('~/.larch')
  LIB_DIR        = File.expand_path(File.join(File.dirname(__FILE__), 'larch'))
  LIB_CONFIG_DIR = File.join(LIB_DIR, 'config')

  class Error < StandardError; end
end

require 'larch/config'
require 'larch/imap_client'
require 'larch/version'
