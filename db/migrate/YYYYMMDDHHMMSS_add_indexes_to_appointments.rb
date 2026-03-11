class AddIndexesToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_index :appointments, :car_wash_id
    add_index :appointments, :scheduled_at
  end
end
