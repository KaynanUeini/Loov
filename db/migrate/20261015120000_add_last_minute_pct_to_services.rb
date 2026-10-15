# O ajuste do Last Minute passa a ser por serviço: o dono pode subir uma
# lavagem, baixar outra e manter uma terceira. Copia o ajuste geral que o
# lava-rápido já tinha (car_washes.last_minute_pct) pras lavagens dele.
#
# As colunas antigas (car_washes.last_minute_pct e services.last_minute_price)
# ficam no banco e o código as ignora: removê-las aqui quebraria a versão que
# ainda está no ar durante o deploy, que lê essas colunas.
class AddLastMinutePctToServices < ActiveRecord::Migration[7.1]
  def up
    add_column :services, :last_minute_pct, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE services
         SET last_minute_pct = car_washes.last_minute_pct
        FROM car_washes
       WHERE services.car_wash_id = car_washes.id
         AND car_washes.last_minute_pct <> 0
         AND (services.category = 'Lavagem'
              OR (COALESCE(TRIM(services.category), '') = '' AND LOWER(services.title) LIKE '%lavagem%'))
    SQL
  end

  def down
    remove_column :services, :last_minute_pct
  end
end
