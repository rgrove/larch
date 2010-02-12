require 'bacon'
require 'larch'

# Larch expects a Dovecot IMAP server to be available for many of its tests. I
# plan to eventually provide a VirtualBox VM image containing a fully-configured
# test server.

IMAP_URI = URI('imap://larchtest:larchtest@larchtest')

describe 'Larch::ConnectionPool' do
  it '#uri_key_mailbox should consider mailbox paths' do
    uri1 = 'imap://user:pass@example.com'
    uri2 = 'imap://user:pass@example.com/INBOX'
    uri3 = 'imap://user:pass@example.com/foo/bar'

    Larch::ConnectionPool.uri_key_mailbox(uri1).should.equal(
        Larch::ConnectionPool.uri_key_mailbox(uri1))

    Larch::ConnectionPool.uri_key_mailbox(uri1).should.not.equal(
        Larch::ConnectionPool.uri_key_mailbox(uri2))

    Larch::ConnectionPool.uri_key_mailbox(uri2).should.not.equal(
        Larch::ConnectionPool.uri_key_mailbox(uri3))
  end

  it '#uri_key_server should not consider mailbox paths' do
    uri1 = 'imap://user:pass@example.com'
    uri2 = 'imap://user:pass@example.com/INBOX'
    uri3 = 'imap://user:pass@example.com/foo/bar'
    uri4 = 'imap://user:pass@foo.com'
    uri5 = 'imap://user2:pass@example.com'

    Larch::ConnectionPool.uri_key_server(uri1).should.not.equal(
        Larch::ConnectionPool.uri_key_server(uri4))

    Larch::ConnectionPool.uri_key_server(uri1).should.not.equal(
        Larch::ConnectionPool.uri_key_server(uri5))

    Larch::ConnectionPool.uri_key_server(uri1).should.equal(
        Larch::ConnectionPool.uri_key_server(uri2))

    Larch::ConnectionPool.uri_key_server(uri2).should.equal(
        Larch::ConnectionPool.uri_key_server(uri3))
  end

  pool = Larch::ConnectionPool.new

  it '#hold should acquire a connection and yield it to the block' do
    pool.hold(IMAP_URI) do |imap|
      imap.should.satisfy {|imap| imap.is_a?(Larch::IMAP) }
      imap.uri.should.equal(IMAP_URI)
      pool.allocated[IMAP_URI][Thread.current].should.equal(imap)
    end
  end

  it '#size should return the number of open connections to all servers' do
    pool.size.should.equal(1)
  end

  it '#size(uri) should return the number of open connections to a specific server' do
    pool.size(IMAP_URI).should.equal(1)
    pool.size('imap://user:pass@example.com').should.equal(0)
  end

  it 'connections should be made available when not in use' do
    pool.allocated.length.should.equal(0)
    pool.available.length.should.equal(1)
  end

  it 'available connections should be reused' do
    pool.allocated.length.should.equal(0)
    pool.available.length.should.equal(1)

    pool.hold(IMAP_URI) do |imap|
      pool.allocated.length.should.equal(1)
      pool.available.length.should.equal(0)
    end
  end

  it '#hold should be re-entrant' do
    pool.hold(IMAP_URI) do |outer_imap|
      pool.size(IMAP_URI).should.equal(1)

      pool.hold(IMAP_URI) do |inner_imap|
        pool.size(IMAP_URI).should.equal(1)
        inner_imap.should.be.same_as(outer_imap)
      end
    end
  end

  it '#disconnect should remove all available connections' do
    pool.available.length.should.equal(1)
    pool.disconnect
    pool.available.length.should.equal(0)
  end

  it '#hold should raise Larch::ConnectionPool::Timeout on pool timeout' do
    timeout_pool = Larch::ConnectionPool.new(:max_connections => 1, :pool_timeout => 1)

    Thread.new do
      timeout_pool.hold(IMAP_URI) do |imap|
        sleep 1.2
      end
    end

    sleep 0.05

    should.raise(Larch::ConnectionPool::Timeout) do
      timeout_pool.hold(IMAP_URI) {|imap| should.flunk("#hold didn't time out") }
    end
  end
end
