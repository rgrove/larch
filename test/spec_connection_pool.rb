require 'bacon'
require 'larch'

# Larch expects a Dovecot IMAP server to be available for many of its tests. I
# plan to eventually provide a VirtualBox VM image containing a fully-configured
# test server.

IMAP_URI = URI('imap://larchtest:larchtest@larchtest')

describe 'Larch::ConnectionPool' do
  pool = Larch::ConnectionPool.new(IMAP_URI)

  it '#hold should acquire a connection and yield it to the block' do
    pool.hold do |imap|
      imap.should.satisfy {|imap| imap.is_a?(Larch::IMAP) }
      imap.uri.should.equal(IMAP_URI)
      pool.allocated[Thread.current].should.equal(imap)
    end
  end

  it '#size should return the number of open connections' do
    pool.size.should.equal(1)
  end

  it 'connections should be made available when not in use' do
    pool.allocated.length.should.equal(0)
    pool.available.length.should.equal(1)
  end

  it 'available connections should be reused' do
    pool.allocated.length.should.equal(0)
    pool.available.length.should.equal(1)

    pool.hold do |imap|
      pool.allocated.length.should.equal(1)
      pool.available.length.should.equal(0)
    end
  end

  it '#hold should be re-entrant' do
    pool.hold do |outer_imap|
      pool.size.should.equal(1)

      pool.hold do |inner_imap|
        pool.size.should.equal(1)
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
    timeout_pool = Larch::ConnectionPool.new(IMAP_URI, :max_connections => 1, :pool_timeout => 1)

    Thread.new do
      timeout_pool.hold do |imap|
        sleep 1.2
      end
    end

    sleep 0.05

    should.raise(Larch::ConnectionPool::Timeout) do
      timeout_pool.hold {|imap| should.flunk("#hold didn't time out") }
    end
  end
end
