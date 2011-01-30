# encoding: utf-8

require 'bacon'
require 'larch'

# Larch expects a Dovecot IMAP server to be available for many of its tests. I
# plan to eventually provide a VirtualBox VM image containing a fully-configured
# test server.

describe 'Larch::IMAP::Mailbox' do
  imap = Larch::IMAP.new('imap://larchtest:larchtest@larchtest')
  imap.start

  inbox = lambda do |mb|
    mb.is_a?(Larch::IMAP::Mailbox) && mb.name == 'INBOX'
  end

  ok_response = lambda do |response|
    response.is_a?(Net::IMAP::TaggedResponse) &&
        response.name == 'OK'
  end

  fetch_data = lambda do |messages|
    messages.is_a?(Array) &&
        messages.all? {|m| m.is_a?(Net::IMAP::FetchData) }
  end

  mailbox = imap.examine('INBOX')

  it '#check should request a checkpoint' do
    mailbox.check.should.be(ok_response)
  end

  it '#delim should return the hierarchy delimiter' do
    mailbox.delim.should.equal('.')
  end

  it '#close should close the mailbox' do
    imap.examine('INBOX')
    imap.mailbox.should.be(inbox)
    imap.mailbox.close.should.be(ok_response)
    imap.mailbox.should.be.nil
  end

  # it '#expunge should expunge deleted messages' do
  #   # TODO: Net::IMAP doesn't actually return a response from EXPUNGE, which
  #   # makes this untestable until we actually delete some messages.
  #   imap.select('INBOX').expunge.should.be(ok_response)
  # end

  it '#fetch should fetch a wildcard range' do
    messages = imap.examine('INBOX').fetch(1..-1, ['UID', 'INTERNALDATE'])
    messages.should.be(fetch_data)
    messages.length.should.be {|len| len > 1}

    imap.mailbox.fetch(1..-1, ['UID', 'INTERNALDATE']) do |messages|
      messages.should.be(fetch_data)
      messages.length.should.be {|len| len > 1}
    end

    chunks = 0

    imap.examine('small').fetch(1..-1, 'UID', 10) do |messages|
      chunks += 1
      messages.should.be(fetch_data)
      messages.length.should.be {|len| len <= 10}
    end

    chunks.should.be {|c| c > 3 }
  end

  it '#fetch should fetch a finite range' do
    messages = imap.examine('INBOX').fetch(1..200, 'UID')
    messages.should.be(fetch_data)
    messages.length.should.be {|len| len > 1}

    imap.mailbox.fetch(1..200, 'UID') do |messages|
      messages.should.be(fetch_data)
      messages.length.should.be {|len| len > 1}
    end

    chunks = 0

    imap.examine('small').fetch(1..200, 'UID', 10) do |messages|
      chunks += 1
      messages.should.be(fetch_data)
      messages.length.should.be {|len| len <= 10}
    end

    chunks.should.be {|c| c > 3 }
  end

  it '#fetch should fetch a single UID' do
    uid      = imap.examine('INBOX').fetch(1..-1, 'UID').first.attr['UID']
    messages = imap.mailbox.fetch(uid, 'UID')
    messages.should.be(fetch_data)
    messages.length.should.equal(1)

    imap.mailbox.fetch(uid, 'UID') do |messages|
      messages.should.be(fetch_data)
      messages.length.should.equal(1)
    end
  end

  it '#fetch should fetch an Array of UIDs' do
    uids = []
    imap.examine('INBOX').fetch(1..-1, 'UID') do |messages|
      messages.each {|msg| uids << msg.attr['UID'] }
    end

    messages = imap.mailbox.fetch(uids, 'UID')
    messages.should.be(fetch_data)
    messages.length.should.be {|len| len > 1 }

    imap.mailbox.fetch(uids, 'UID') do |messages|
      messages.should.be(fetch_data)
      messages.length.should.be {|len| len > 1}
    end
  end

  it '#name and #raw_name should be UTF-8, #raw_name_utf7 should be UTF-7' do
    mb = imap.examine('円グラフ良いです')
    mb.name.should.equal('円グラフ良いです')
    mb.raw_name.should.equal('円グラフ良いです')
    mb.raw_name_utf7.should.equal('&UYYwsDDpMNWCbzBEMGcwWQ-')
  end

  # TODO: test #search
  # TODO: test #sort
  # TODO: test #store

  it '#subscribed? should indicate subscription status' do
    imap.examine('INBOX').subscribed?.should.be.true
    imap.examine('unsubscribed').subscribed?.should.be.false
  end

  it '#unselect should close the mailbox without expunging' do
    imap.select('INBOX')
    imap.mailbox.should.be(inbox)
    imap.mailbox.unselect.should.be(ok_response)
    imap.mailbox.should.be.nil
  end

  it 'mailbox methods should raise Larch::IMAP::MailboxClosed after the mailbox is closed' do
    imap.select('INBOX')
    mailbox = imap.mailbox
    mailbox.should.be(inbox)
    mailbox.close.should.be(ok_response)
    mailbox.should.be(inbox)
    should.raise(Larch::IMAP::MailboxClosed) { mailbox.check }
  end
end
