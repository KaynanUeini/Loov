# Foto de capa da página do lava-rápido (CapaStorage), que o dono sobe em
# Gerenciar > Informações básicas.
class AddCapaKeyToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :capa_key, :string
  end
end
