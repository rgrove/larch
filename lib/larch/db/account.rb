module Larch; module Database

class Account < Sequel::Model
  plugin :hook_class_methods
  one_to_many :mailboxes, :class => Larch::Database::Mailbox

  before_destroy do
    Mailbox.filter(:account_id => id).destroy
  end
end

end; end
