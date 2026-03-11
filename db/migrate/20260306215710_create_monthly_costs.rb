class CreateMonthlyCosts < ActiveRecord::Migration[7.1]
  def change
    create_table :monthly_costs do |t|
      t.references :car_wash, null: false, foreign_key: true
      t.integer :year
      t.integer :month
      t.decimal :rent
      t.decimal :salaries
      t.decimal :utilities
      t.decimal :products
      t.decimal :maintenance
      t.decimal :other_fixed
      t.decimal :other_variable
      t.text :notes

      t.timestamps
    end
  end
end
