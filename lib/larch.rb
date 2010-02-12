require 'cgi'
require 'net/imap'
require 'uri'

module Larch
  class Error < StandardError; end
end

require 'larch/imap'
# require 'larch/imap_client'
require 'larch/connection_pool'
