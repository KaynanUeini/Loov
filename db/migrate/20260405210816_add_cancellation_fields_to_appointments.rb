class AddCancellationFieldsToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :cancelled_by_id,       :integer
    add_column :appointments, :cancellation_reason,   :string
    add_column :appointments, :cancelled_by_role,     :string
    add_index  :appointments, :cancelled_by_id
  end
end
