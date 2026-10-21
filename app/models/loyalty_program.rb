class LoyaltyProgram < ApplicationRecord
  belongs_to :car_wash
  belongs_to :reward_service, class_name: "Service", optional: true

  # O que o cliente ganha ao completar o cartão (ver LoyaltyReward):
  #   percent       reward_value % de desconto na próxima visita
  #   fixed         R$ reward_value de desconto na próxima visita
  #   free_service  reward_service grátis na próxima visita
  #   gift          brinde (reward_description), entregue no balcão
  REWARD_TYPES = LoyaltyReward::TYPES
  VALIDADE_PADRAO = 45

  validates :visits_required,    presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :reward_description, presence: true, length: { maximum: 120 }
  validates :reward_type,        inclusion: { in: REWARD_TYPES }
  validates :reward_value,       numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: -> { reward_type == "percent" }
  validates :reward_value,       numericality: { greater_than: 0, less_than_or_equal_to: 10_000 }, if: -> { reward_type == "fixed" }
  validates :valid_days,         numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }
  validate  :servico_do_lava_rapido, if: -> { reward_type == "free_service" }

  # Nos tipos que o sistema calcula, a frase que o cliente vê sai da regra —
  # não tem como o texto dizer uma coisa e o desconto ser outra.
  before_validation :gerar_descricao

  def gerar_descricao
    case reward_type
    when "percent"
      self.reward_description = "#{reward_value.to_f.round}% de desconto na próxima visita" if reward_value.present?
    when "fixed"
      self.reward_description = "R$ #{dinheiro(reward_value)} de desconto na próxima visita" if reward_value.present?
    when "free_service"
      self.reward_description = "#{reward_service.title} grátis na próxima visita" if reward_service
    end
  end

  # Cria o vale do cliente que completou o cartão no atendimento `appointment`.
  # Idempotente (um vale por atendimento que completou). Condições congeladas.
  def emitir_vale!(appointment, avisar: true)
    vale = LoyaltyReward.create!(
      user_id:               appointment.user_id,
      car_wash_id:           car_wash_id,
      earned_appointment_id: appointment.id,
      reward_type:           reward_type,
      # free_service guarda o preço do serviço de hoje: se o cliente escolher
      # outro serviço, abate até esse valor.
      reward_value:          reward_type == "free_service" ? reward_service&.price : reward_value,
      reward_service_id:     reward_type == "free_service" ? reward_service_id : nil,
      reward_service_title:  reward_type == "free_service" ? reward_service&.title : nil,
      description:           reward_description,
      expires_at:            (Time.current + valid_days.days).in_time_zone("America/Sao_Paulo").end_of_day
    )
    avisar_vale(vale) if avisar
    vale
  rescue ActiveRecord::RecordNotUnique
    LoyaltyReward.find_by(earned_appointment_id: appointment.id)
  end

  # Cartão de carimbos de um cliente neste programa — o mesmo cálculo da
  # Conta, da tela Fidelidade e da página do lava-rápido (site e app).
  # Conta só lavagens concluídas depois que o programa foi criado, fora a
  # que usou o vale (Appointment.que_contam_carimbo). A visita que completa
  # o cartão gera um vale (LoyaltyReward) pra próxima visita; depois que o
  # vale é usado, o cartão novo começa vazio.
  #
  # historico: true acrescenta as visitas do ciclo deste cartão (data +
  # serviço, mais recente primeiro) pro verso do cartão na tela Fidelidade —
  # as lavagens de cartões anteriores ficam nos cartões delas.
  def cartao_para(user, historico: false)
    visitas_scope = if user
      user.appointments.where(car_wash_id: car_wash_id, status: "attended")
          .where("scheduled_at >= ?", created_at).que_contam_carimbo
    end
    visitas  = visitas_scope ? visitas_scope.count : 0
    meta     = visits_required
    ciclo    = visitas % meta
    completo = visitas.positive? && ciclo.zero? && !vale_usado_depois?(user, visitas_scope)
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
      address: car_wash.endereco_curto,
      history: historico_de(visitas_scope, cartao[:filled])
    )
  end

  private

  # O cliente já usou o vale do cartão que completou por último: o cartão
  # do momento é o novo, ainda sem carimbo.
  def vale_usado_depois?(user, visitas_scope)
    ultima = visitas_scope.maximum(:scheduled_at)
    uso = LoyaltyReward.where(user_id: user.id, car_wash_id: car_wash_id).where.not(used_at: nil)
                       .joins(:appointment).maximum("appointments.scheduled_at")
    ultima && uso && uso > ultima
  end

  def dinheiro(v)
    format("%.2f", v.to_f).sub(".", ",").sub(",00", "")
  end

  def servico_do_lava_rapido
    errors.add(:base, "Escolha o serviço que sai de graça.") unless reward_service && reward_service.car_wash_id == car_wash_id
  end

  def avisar_vale(vale)
    validade = vale.expires_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m")
    ExpoPushNotifier.new.notify_user(
      vale.user,
      title: "Você ganhou: #{vale.resumo_curto} 🎁",
      body:  "Cartão completo no #{car_wash.name}. Vale na próxima visita, até #{validade}.",
      data:  { type: "loyalty_reward", car_wash_id: car_wash_id, reward_id: vale.id }
    )
  rescue => e
    Rails.logger.error("[LoyaltyProgram] aviso do vale ##{vale&.id} falhou: #{e.message}")
  end

  def historico_de(scope, limite)
    return [] unless scope
    scope.includes(:service).order(scheduled_at: :desc).limit(limite).map do |a|
      { at: (a.attended_at || a.scheduled_at)&.iso8601, service: a.service&.title }
    end
  end
end
