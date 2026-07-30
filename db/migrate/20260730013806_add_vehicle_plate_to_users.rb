class AddVehiclePlateToUsers < ActiveRecord::Migration[7.1]
  # Placa em coluna própria. Antes vivia dentro do vehicle_model como texto
  # livre ("Honda Civic preto ABC-1234"), o que impede o dono de identificar o
  # carro no pátio de forma confiável — e é a placa, não o modelo, que
  # identifica. Registros antigos ficam como estão: o app pré-preenche a placa
  # quando reconhece o padrão no modelo e o cliente confirma salvando.
  def change
    add_column :users, :vehicle_plate, :string, if_not_exists: true
  end
end
