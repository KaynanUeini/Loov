# O piso da Hora Off passa a sair do custo de UMA lavagem a mais (produto,
# comissão do lavador, um pouco de água e luz), informado pelo dono, e das
# taxas que incidem sobre a venda (imposto, cartão). Antes saía do custo total
# do mês dividido pelas lavagens registradas na Loov, o que misturava custo
# fixo com o variável e, com poucas lavagens no app, dava pisos acima da
# tabela (R$ 403 numa lavagem de R$ 50). Em horário que ia ficar vazio, o
# aluguel e os salários são pagos de qualquer jeito: só o variável conta.
class CustoDaLavagemNaHoraOff < ActiveRecord::Migration[7.1]
  def change
    change_table :car_washes, bulk: true do |t|
      t.decimal :custo_lavagem, precision: 8, scale: 2 # nil = sem piso
      t.integer :taxas_venda_pct, default: 10, null: false
    end
  end
end
