module Larch; module Database

class Mailbox < Sequel::Model
  plugin :hook_class_methods
  one_to_many :messages, :class => Larch::Database::Message

  before_destroy do
    Larch::Database::Message.filter(:mailbox_id => id).destroy
  end
end

end; end
