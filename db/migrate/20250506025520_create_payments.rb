class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.references :appointment, null: false, foreign_key: true
      t.decimal :amount
      t.string :stripe_payment_id
      t.string :status

      t.timestamps
    end
  end
end
