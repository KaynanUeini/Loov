# Ajuste do Last Minute em % sobre o preço do agendamento, valendo pra todas
# as lavagens do lava-rápido (0 = mesmo preço). Fica no lava-rápido, não no
# serviço: mudar o preço de uma lavagem ou cadastrar outra já sai certo.
class AddLastMinutePctToCarWashes < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :last_minute_pct, :integer, default: 0, null: false
  end
end
