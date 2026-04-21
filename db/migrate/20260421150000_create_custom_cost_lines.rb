class CreateCustomCostLines < ActiveRecord::Migration[7.1]
  def change
    create_table :custom_cost_lines do |t|
      t.references :monthly_cost, null: false, foreign_key: true
      t.string   :name,      null: false
      t.decimal  :amount,    precision: 12, scale: 2, default: 0, null: false
      t.string   :cost_type, null: false
      t.integer  :position,  default: 0
      t.timestamps
    end

    add_index :custom_cost_lines, [:monthly_cost_id, :cost_type]
  end
end
