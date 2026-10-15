class LoyaltyProgram < ApplicationRecord
  belongs_to :car_wash

  validates :visits_required,    presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :reward_description, presence: true, length: { maximum: 120 }

  # Cartão de carimbos de um cliente neste programa — o mesmo cálculo da
  # Conta, da tela Fidelidade e da página do lava-rápido (site e app).
  # Conta só lavagens concluídas depois que o programa foi criado. A
  # recompensa sai na visita que completa o cartão (o check-in do dono avisa).
  #
  # historico: true acrescenta as visitas (data + serviço, mais recente
  # primeiro) pro verso do cartão na tela Fidelidade.
  def cartao_para(user, historico: false)
    visitas_scope = if user
      user.appointments.where(car_wash_id: car_wash_id, status: "attended")
          .where("scheduled_at >= ?", created_at)
    end
    visitas  = visitas_scope ? visitas_scope.count : 0
    meta     = visits_required
    ciclo    = visitas % meta
    completo = visitas.positive? && ciclo.zero?
    cartao = {
      car_wash_id:        car_wash_id,
      car_wash_name:      car_wash.name,
      reward_description: reward_description,
      visits_required:    meta,
      visits_total:       visitas,
      filled:             completo ? meta : ciclo,
      milestone:          completo
    }
    return cartao unless historico

    cartao.merge(
      address:        car_wash.endereco_curto,
      rewards_earned: visitas / meta,
      history:        historico_de(visitas_scope, [meta, 12].max)
    )
  end

  private

  def historico_de(scope, limite)
    return [] unless scope
    scope.includes(:service).order(scheduled_at: :desc).limit(limite).map do |a|
      { at: (a.attended_at || a.scheduled_at)&.iso8601, service: a.service&.title }
    end
  end
end
