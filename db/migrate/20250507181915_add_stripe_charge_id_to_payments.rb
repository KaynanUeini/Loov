class AddStripeChargeIdToPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :payments, :stripe_charge_id, :string
  end
end
