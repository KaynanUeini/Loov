class AddPaymentIntentClientSecretToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :payment_intent_client_secret, :string
  end
end
