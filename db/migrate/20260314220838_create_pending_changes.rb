class CreatePendingChanges < ActiveRecord::Migration[7.1]
  def change
    create_table :pending_changes do |t|
      t.integer :car_wash_id
      t.integer :attendant_id
      t.string :change_type
      t.text :payload
      t.string :status
      t.string :description

      t.timestamps
    end
  end
end
