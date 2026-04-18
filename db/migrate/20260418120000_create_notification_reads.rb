class CreateNotificationReads < ActiveRecord::Migration[7.0]
  def change
    create_table :notification_reads do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :key,     null: false
      t.datetime :read_at, null: false
      t.timestamps
    end
    add_index :notification_reads, [:user_id, :key], unique: true
  end
end
