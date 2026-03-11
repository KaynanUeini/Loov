class AddProfileFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :full_name, :string
    add_column :users, :phone, :string
    add_column :users, :cpf, :string
    add_column :users, :vehicle_model, :string
  end
end
