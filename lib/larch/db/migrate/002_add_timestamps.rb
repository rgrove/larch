class AddTimestamps < Sequel::Migration
  def down
    alter_table :accounts do
      drop_column :created_at
      drop_column :updated_at
    end
  end

  def up
    alter_table :accounts do
      add_column :created_at, :integer
      add_column :updated_at, :integer
    end
  end
end
