class CreateOwnerMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :owner_messages do |t|
      t.references :car_wash,    null: false, foreign_key: true
      t.references :sender,      null: false, foreign_key: { to_table: :users }
      t.references :recipient,   null: true,  foreign_key: { to_table: :users }
      t.string     :body,        null: false
      t.string     :target,      null: false, default: "all"  # "all" | "user"
      t.timestamps
    end
    add_index :owner_messages, [:recipient_id, :created_at]
    add_index :owner_messages, [:car_wash_id,  :created_at]
  end
end
