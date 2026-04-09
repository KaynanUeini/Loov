class CreateSupportTickets < ActiveRecord::Migration[7.1]
  def change
    create_table :support_tickets do |t|
      t.references :user, null: true, foreign_key: true
      t.references :car_wash, null: false, foreign_key: true
      t.string :subject
      t.text :description
      t.string :status, default: "open", null: false
      t.string :category
      t.timestamps
    end

    add_index :support_tickets, :status
    add_index :support_tickets, :category
  end
end
