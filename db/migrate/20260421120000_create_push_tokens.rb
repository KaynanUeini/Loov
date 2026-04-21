class CreatePushTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :push_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :token,    null: false
      t.string     :platform
      t.datetime   :last_seen_at
      t.timestamps
    end

    add_index :push_tokens, :token, unique: true
  end
end
