class AddCapacityToOperatingHours < ActiveRecord::Migration[7.1]
  # Capacidade de atendimento simultâneo por dia da semana. O mercado é
  # informal: equipe menor no meio da semana, maior no fim de semana — um
  # número único obriga o dono a subdimensionar o sábado ou superdimensionar a
  # terça, e superdimensionar gera fila de espera e review ruim.
  #
  # Nullable de propósito: sem valor, cai no car_washes.capacity_per_slot, que
  # segue sendo o default. Nada muda pra quem não configurar por dia.
  def change
    add_column :operating_hours, :capacity, :integer, if_not_exists: true
  end
end
