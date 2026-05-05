class AddBlockedAtToUsers < ActiveRecord::Migration[7.1]
  def up
    unless column_exists?(:users, :blocked_at)
      add_column :users, :blocked_at, :datetime
      add_index  :users, :blocked_at
    end
  end

  def down
    if column_exists?(:users, :blocked_at)
      remove_index  :users, :blocked_at
      remove_column :users, :blocked_at
    end
  end
end
