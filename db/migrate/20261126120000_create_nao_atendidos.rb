# Cliente de Last Minute pagou e não foi atendido (botão Ajuda no card). O
# dono tem 24h pra confirmar ou discordar; confirmado ou sem resposta, o
# cliente recebe o pago no app de volta e o caso conta pra suspensão do Last
# Minute da loja (3 em 60 dias). Discordou: a equipe decide.
class CreateNaoAtendidos < ActiveRecord::Migration[7.1]
  def change
    create_table :nao_atendidos do |t|
      t.references :appointment, null: false, foreign_key: true, index: { unique: true }
      t.references :user,        null: false, foreign_key: true
      t.references :car_wash,    null: false, foreign_key: true
      t.text     :relato
      t.string   :status, null: false, default: "aguardando"
      t.datetime :prazo_em, null: false
      t.text     :resposta_dono
      t.bigint   :respondido_por_id
      t.datetime :respondido_em
      t.bigint   :decidido_por_id
      t.datetime :decidido_em
      t.decimal  :valor, precision: 10, scale: 2
      t.string   :estorno            # ok | failed
      t.datetime :contado_em         # quando passou a contar pra suspensão
      t.references :support_ticket, foreign_key: true
      t.timestamps
    end
    add_index :nao_atendidos, [:car_wash_id, :contado_em]
    add_index :nao_atendidos, [:status, :prazo_em]
  end
end
