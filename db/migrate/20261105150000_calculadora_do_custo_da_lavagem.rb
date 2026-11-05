# As respostas da calculadora do custo de uma lavagem a mais (comissão do
# lavador por carro, gasto de produto no mês, contas de água e luz, carros num
# dia normal). Ficam guardadas pra o dono só ajustar o que mudou da próxima
# vez. O número que vale pro piso continua em custo_lavagem: a calculadora só
# sugere, o dono confirma.
class CalculadoraDoCustoDaLavagem < ActiveRecord::Migration[7.1]
  def change
    add_column :car_washes, :custo_lavagem_calc, :jsonb, default: {}, null: false
  end
end
