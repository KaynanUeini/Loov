# Cor principal do logo que o dono subiu (calculada no site/app na hora do
# envio). A capa da página do lava-rápido, sem foto, fica nessa cor.
class AddCorMarcaToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :cor_marca, :string
  end
end
