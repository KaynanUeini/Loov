class AddCapacityPerSlotToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :capacity_per_slot, :integer, default: 2, null: false
  end
end
