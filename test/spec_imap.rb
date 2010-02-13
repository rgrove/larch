require 'bacon'
require 'larch'

# Larch expects a Dovecot IMAP server to be available for many of its tests. I
# plan to eventually provide a VirtualBox VM image containing a fully-configured
# test server.

CONNECTED_URI    = URI('imap://larchtest:larchtest@larchtest')
DISCONNECTED_URI = URI('imap://user:pass@example.com/mailbox')

describe 'Larch::IMAP (disconnected)' do
  imap = Larch::IMAP.new(DISCONNECTED_URI)

  should 'delegate constants to Net::IMAP' do
    Larch::IMAP::SEEN.should.equal(Net::IMAP::SEEN)
  end

  it '#new should raise a Larch::IMAP::InvalidURI exception when an invalid URI is specified' do
    should.raise(ArgumentError) { Larch::IMAP.new }
    should.raise(Larch::IMAP::InvalidURI) { Larch::IMAP.new('http://user:pass@example.com') }
    should.raise(Larch::IMAP::InvalidURI) { Larch::IMAP.new('imap://example.com') }
    should.not.raise(Larch::IMAP::InvalidURI) { Larch::IMAP.new('imap://user:pass@example.com') }
  end

  it '#authenticate should raise Larch::IMAP::NotConnected' do
    should.raise(Larch::IMAP::NotConnected) { imap.authenticate }
  end

  it '#authenticated? should return false' do
    imap.authenticated?.should.be.false
  end

  it '#connected? should return false' do
    imap.connected?.should.be.false
  end

  it '#disconnected? should return true' do
    imap.disconnected?.should.be.true
  end

  it '#host should return the hostname' do
    imap.host.should.equal(DISCONNECTED_URI.host)
  end

  it '#mailbox should return the mailbox' do
    imap.mailbox.should.equal('mailbox')
    Larch::IMAP.new('imap://user:pass@example.com').mailbox.should.be.nil
  end

  it '#password should return the password' do
    imap.password.should.equal(CGI.unescape(DISCONNECTED_URI.password))
  end

  it '#port should return the port' do
    imap.port.should.equal(143)
    Larch::IMAP.new('imap://user:pass@example.com:993').port.should.equal(993)
  end

  it '#port should default to 993 for imaps' do
    Larch::IMAP.new('imaps://user:pass@example.com').port.should.equal(993)
  end

  it '#ssl? should return the SSL status' do
    imap.ssl?.should.be.false
    Larch::IMAP.new('imaps://user:pass@example.com').ssl?.should.be.true
  end

  it '#uri should return the current URI' do
    imap.uri.should.equal(DISCONNECTED_URI)
  end

  it '#username should return the username' do
    imap.username.should.equal(CGI.unescape(DISCONNECTED_URI.user))
  end
end

describe 'Larch::IMAP (safely)' do
  should 'safely connect, authenticate, and send a NOOP command' do
    imap = Larch::IMAP.new(CONNECTED_URI)
    imap.safely { imap.noop }.should.satisfy do |response|
      response.is_a?(Net::IMAP::TaggedResponse) &&
          response.name == 'OK'
    end
  end
end

describe 'Larch::IMAP (connected)' do
  imap = Larch::IMAP.new(CONNECTED_URI)

  ok_response = lambda do |response|
    response.is_a?(Net::IMAP::TaggedResponse) &&
        response.name == 'OK'
  end

  it '#authenticate should require a connection' do
    should.raise(Larch::IMAP::NotConnected) { imap.authenticate }
  end

  it '#connect should connect' do
    imap.connect.should.be.true
  end

  it '#authenticated? should return false' do
    imap.authenticated?.should.be.false
  end

  it '#connected? should return true' do
    imap.connected?.should.be.true
  end

  it '#disconnected? should return false' do
    imap.disconnected?.should.be.false
  end

  it '#examine should require authentication' do
    should.raise(Larch::IMAP::NotAuthenticated) { imap.examine('INBOX') }
  end

  it '#authenticate should authenticate' do
    imap.authenticate.should.be.true
  end

  it '#delim should get the mailbox hierarchy delimiter' do
    imap.delim.should.equal('.')
  end

  it '#examine should open the INBOX' do
    imap.mailbox.should.be.nil
    imap.examine('INBOX').should.be(ok_response)
    imap.mailbox.should.equal('INBOX')
  end

  it '#close should close the INBOX' do
    imap.mailbox.should.equal('INBOX')
    imap.close.should.be(ok_response)
    imap.mailbox.should.be.nil
  end

  it '#select should open the INBOX' do
    imap.mailbox.should.be.nil
    imap.select('INBOX').should.be(ok_response)
    imap.mailbox.should.equal('INBOX')
  end

  it '#unselect should close the INBOX without expunging' do
    imap.mailbox.should.equal('INBOX')
    imap.unselect.should.be(ok_response)
    imap.mailbox.should.be.nil
  end

  it '#translate_delim should translate mailbox hierarchy delimiters' do
    imap.translate_delim('foo/bar/baz').should.equal('foo.bar.baz')
    imap.translate_delim('foo_bar_baz', '_').should.equal('foo.bar.baz')
  end

  it '#disconnect should disconnect' do
    imap.disconnected?.should.be.false
    imap.disconnect
    imap.disconnected?.should.be.true
  end 
end
