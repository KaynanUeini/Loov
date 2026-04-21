class AddWaterElectricityToMonthlyCosts < ActiveRecord::Migration[7.1]
  def change
    add_column :monthly_costs, :water,       :decimal, precision: 12, scale: 2, default: 0
    add_column :monthly_costs, :electricity, :decimal, precision: 12, scale: 2, default: 0
  end
end
