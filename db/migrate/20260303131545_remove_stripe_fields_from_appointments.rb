class RemoveStripeFieldsFromAppointments < ActiveRecord::Migration[7.1]
  def change
    remove_column :appointments, :payment_intent_id, :string if column_exists?(:appointments, :payment_intent_id)
    remove_column :appointments, :payment_method_id, :string if column_exists?(:appointments, :payment_method_id)
  end
end
