# Quando o dono ou o funcionário viu o pedido do Last Minute na tela. O
# cliente que espera o aceite passa a ver "Visto às 12:58": é o sinal de que
# tem alguém do outro lado, e o que mais acalma nesses 3 minutos.
class VistoDoPedidoLastMinute < ActiveRecord::Migration[7.1]
  def change
    add_column :appointments, :acceptance_seen_at, :datetime
  end
end
