# A recompensa do programa de fidelidade deixa de ser só um texto e vira uma
# regra que o sistema calcula (tipo + valor), e completar o cartão passa a
# gerar um vale na conta do cliente, usado na PRÓXIMA visita — no agendamento
# comum, no Last Minute ou no balcão.
#
#   loyalty_programs.reward_type   percent | fixed | free_service | gift
#   loyalty_programs.reward_value  % ou R$ (percent/fixed)
#   loyalty_programs.reward_service_id  o serviço grátis (free_service)
#   loyalty_programs.valid_days    validade do vale (padrão 45 dias)
#
# Programas que já existem viram "gift" (brinde): o texto que o dono escreveu
# continua valendo e o atendente entrega no balcão, até ele escolher um tipo.
#
# loyalty_rewards guarda as condições congeladas do momento em que o cliente
# ganhou: mudar o programa depois não muda o vale de quem já ganhou.
# appointments.reward_discount é quanto o vale abateu daquele atendimento.
class CriarValesDeFidelidade < ActiveRecord::Migration[7.1]
  def change
    add_column :loyalty_programs, :reward_type,       :string,  default: "gift", null: false
    add_column :loyalty_programs, :reward_value,      :decimal, precision: 10, scale: 2
    add_column :loyalty_programs, :reward_service_id, :bigint
    add_column :loyalty_programs, :valid_days,        :integer, default: 45, null: false

    create_table :loyalty_rewards do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :car_wash, null: false, foreign_key: true
      t.bigint  :earned_appointment_id, null: false
      t.bigint  :appointment_id
      t.string  :reward_type,  null: false
      t.decimal :reward_value, precision: 10, scale: 2
      t.bigint  :reward_service_id
      t.string  :reward_service_title
      t.string  :description,  null: false
      t.datetime :expires_at,  null: false
      t.datetime :used_at
      t.datetime :reminder_sent_at
      t.timestamps
    end
    add_index :loyalty_rewards, :earned_appointment_id, unique: true
    add_index :loyalty_rewards, :appointment_id
    add_index :loyalty_rewards, [:user_id, :car_wash_id, :used_at]

    add_column :appointments, :reward_discount, :decimal, precision: 10, scale: 2
  end
end
