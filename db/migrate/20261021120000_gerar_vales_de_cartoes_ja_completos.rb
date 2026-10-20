# Cartões que já estavam completos antes do vale existir: pela regra antiga a
# recompensa "saía na visita que completava", e o cliente ficava sem nada pra
# usar no app. Gera o vale do último cartão completado de cada cliente, se
# ele completou nos últimos 45 dias e ainda não tem vale nesse lava-rápido.
# Sem push (é acerto de dados, não um prêmio novo); vale 45 dias a partir de
# hoje.
class GerarValesDeCartoesJaCompletos < ActiveRecord::Migration[7.1]
  def up
    LoyaltyProgram.reset_column_information
    LoyaltyReward.reset_column_information

    LoyaltyProgram.where(active: true).find_each do |prog|
      meta = prog.visits_required.to_i
      next if meta <= 0

      visitas = Appointment.where(car_wash_id: prog.car_wash_id, status: "attended")
                           .where.not(user_id: nil)
                           .where("scheduled_at >= ?", prog.created_at)
      visitas.group(:user_id).count.each do |user_id, total|
        next if total < meta
        next if LoyaltyReward.exists?(user_id: user_id, car_wash_id: prog.car_wash_id)

        ganho = visitas.where(user_id: user_id).order(:scheduled_at, :id).offset((total / meta) * meta - 1).first
        next unless ganho
        next if (ganho.attended_at || ganho.scheduled_at) < 45.days.ago

        prog.emitir_vale!(ganho, avisar: false)
      rescue => e
        say "vale do usuário #{user_id} no lava-rápido #{prog.car_wash_id} falhou: #{e.message}"
      end
    end
  end

  def down
    # Não apaga vales: podem já ter sido usados.
  end
end
