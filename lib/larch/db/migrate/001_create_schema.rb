class CreateSchema < Sequel::Migration
  def down
    drop_table :accounts, :mailboxes, :messages
  end

  def up
    create_table :accounts do
      primary_key :id
      text :hostname, :null => false
      text :username, :null => false

      unique [:hostname, :username]
    end

    create_table :mailboxes do
      primary_key :id
      foreign_key :account_id, :table => :accounts
      text :name, :null => false
      text :delim, :null => false
      text :attr, :null => false, :default => ''
      integer :subscribed, :null => false, :default => 0
      integer :uidvalidity
      integer :uidnext

      unique [:account_id, :name, :uidvalidity]
    end

    create_table :messages do
      primary_key :id
      foreign_key :mailbox_id, :table => :mailboxes
      integer :uid, :null => false
      text :guid, :null => false
      text :message_id
      integer :rfc822_size, :null => false
      integer :internaldate, :null => false
      text :flags, :null => false, :default => ''

      index :guid
      unique [:mailbox_id, :uid]
    end
  end
end
