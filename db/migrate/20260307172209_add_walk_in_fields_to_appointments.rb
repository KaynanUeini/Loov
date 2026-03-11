class AddWalkInFieldsToAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :price_override, :decimal, precision: 10, scale: 2
    add_column :appointments, :walk_in, :boolean, default: false, null: false
    add_column :appointments, :walk_in_name, :string
    change_column_null :appointments, :user_id, true
  end
end
