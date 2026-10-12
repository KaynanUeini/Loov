# Chamado de CLIENTE não tem lava-rápido. A tabela nasceu com car_wash_id
# obrigatório (quando só o dono abria chamado) e o model já tratava como
# opcional; em produção o banco recusava o INSERT e o app mostrava "Não foi
# possível abrir o chamado". O schema local divergia (coluna já aceitava
# nulo), por isso o erro não aparecia em desenvolvimento.
class PermitirChamadoSemLavaRapido < ActiveRecord::Migration[7.1]
  def up
    change_column_null :support_tickets, :car_wash_id, true
  end

  def down
    # Sem volta: chamados de cliente já gravados ficariam inválidos.
  end
end
