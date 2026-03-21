class AddStripeFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :stripe_customer_id,            :string
    add_column :users, :stripe_payment_method_id,      :string
    add_column :users, :stripe_card_last4,             :string
    add_column :users, :stripe_card_brand,             :string

    add_index :users, :stripe_customer_id, unique: true, where: "stripe_customer_id IS NOT NULL"
  end
end
