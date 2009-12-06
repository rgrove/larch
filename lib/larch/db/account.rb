module Larch; module Database

class Account < Sequel::Model(:accounts)
  plugin :hook_class_methods

  one_to_many :mailboxes, :class => Larch::Database::Mailbox

  before_create do
    now = Time.now.to_i

    self.created_at = now
    self.updated_at = now
  end

  before_destroy do
    Mailbox.filter(:account_id => id).destroy
  end

  before_save do
    now = Time.now.to_i

    self.created_at = now if self.created_at.nil?
    self.updated_at = now
  end

  def touch
    update(:updated_at => Time.now.to_i)
  end
end

end; end
