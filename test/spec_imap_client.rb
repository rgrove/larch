require 'bacon'
require 'larch'

# Larch expects a Dovecot IMAP server to be available for many of its tests. I
# plan to eventually provide a VirtualBox VM image containing a fully-configured
# test server.

describe 'Larch::IMAPClient' do
  client = Larch::IMAPClient.new('imap://larchtest:larchtest@larchtest')

  it '#each_mailbox should traverse all mailboxes' do
    mailboxes = []
    client.each_mailbox {|mb| mailboxes << mb.name }

    # TODO: Make this test a bit more robust. Need a consistent set of mailboxes
    # first.
    mailboxes.should.not.be.empty
    mailboxes.should.include('INBOX')
  end
end
