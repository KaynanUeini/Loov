class AddAddressToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :cep, :string
    add_column :car_washes, :logradouro, :string
    add_column :car_washes, :bairro, :string
    add_column :car_washes, :cidade, :string
    add_column :car_washes, :uf, :string
  end
end
