class LoyaltyProgram < ApplicationRecord
  belongs_to :car_wash

  validates :visits_required,    presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :reward_description, presence: true, length: { maximum: 120 }

  # Cartão de carimbos de um cliente neste programa — o mesmo cálculo da
  # Conta, da tela Fidelidade e da página do lava-rápido (site e app).
  # Conta só lavagens concluídas depois que o programa foi criado. A
  # recompensa sai na visita que completa o cartão (o check-in do dono avisa).
  def cartao_para(user)
    visitas = if user
      user.appointments.where(car_wash_id: car_wash_id, status: "attended")
          .where("scheduled_at >= ?", created_at).count
    else
      0
    end
    meta     = visits_required
    ciclo    = visitas % meta
    completo = visitas.positive? && ciclo.zero?
    {
      car_wash_id:        car_wash_id,
      car_wash_name:      car_wash.name,
      reward_description: reward_description,
      visits_required:    meta,
      visits_total:       visitas,
      filled:             completo ? meta : ciclo,
      milestone:          completo
    }
  end
end
