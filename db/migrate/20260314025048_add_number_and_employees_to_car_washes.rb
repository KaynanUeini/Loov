class AddNumberAndEmployeesToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :numero, :string
    add_column :car_washes, :num_employees, :integer
  end
end
