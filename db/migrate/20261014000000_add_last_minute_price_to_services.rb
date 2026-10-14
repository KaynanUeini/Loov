# Preço próprio do serviço no Last Minute. NULL = mesmo preço do agendamento
# comum (o padrão; nenhum serviço existente muda).
class AddLastMinutePriceToServices < ActiveRecord::Migration[7.1]
  def change
    add_column :services, :last_minute_price, :decimal
  end
end
