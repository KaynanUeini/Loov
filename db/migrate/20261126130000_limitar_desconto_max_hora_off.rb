# O maior desconto que a Hora Off dá é 20% no Last Minute, mais 5% com chuva.
# Teto acima de 25% não mudava preço nenhum e confundia o dono (escolher 30%
# ou 35% "não fazia nada"). Quem tinha mais fica com 25%: o preço não muda.
class LimitarDescontoMaxHoraOff < ActiveRecord::Migration[7.1]
  def up
    execute "UPDATE car_washes SET hora_off_desconto_max = 25 WHERE hora_off_desconto_max > 25"
  end

  def down; end
end
