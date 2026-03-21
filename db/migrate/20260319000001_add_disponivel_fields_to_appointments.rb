class AddDisponivelFieldsToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :appointment_type,          :string,  default: "regular", null: false
    add_column :appointments, :acceptance_expires_at,     :datetime
    add_column :appointments, :prepayment_amount,         :decimal, precision: 10, scale: 2
    add_column :appointments, :stripe_payment_intent_id,  :string
    add_column :appointments, :commission_amount,         :decimal, precision: 10, scale: 2

    add_index :appointments, :appointment_type
    add_index :appointments, :acceptance_expires_at
    add_index :appointments, :stripe_payment_intent_id, unique: true, where: "stripe_payment_intent_id IS NOT NULL"
  end
end
