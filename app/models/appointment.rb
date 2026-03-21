class Appointment < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :car_wash
  belongs_to :service
  has_one :review, dependent: :destroy

  # ── TIPOS ─────────────────────────────────────────────────────────────────
  TYPES = %w[regular disponivel].freeze

  # ── STATUS ────────────────────────────────────────────────────────────────
  # regular:            confirmed → attended | no_show | cancelled
  # disponivel:         pending_acceptance → confirmed → attended | no_show | cancelled
  #                     pending_acceptance → rejected  (dono recusou ou timeout)
  STATUSES = %w[confirmed pending_acceptance attended no_show cancelled rejected].freeze

  # ── COMISSÃO E PRÉ-PAGAMENTO ──────────────────────────────────────────────
  PREPAYMENT_PCT   = 0.35  # 35% do valor total pago no app
  COMMISSION_PCT   = 0.05  # 5% do valor total retido pela Loov
  ACCEPTANCE_TTL   = 3.minutes # timeout para aceite do dono

  # ── VALIDAÇÕES ────────────────────────────────────────────────────────────
  validates :scheduled_at,  presence: true
  validates :appointment_type, inclusion: { in: TYPES }
  validates :walk_in_name,  presence: true, if: :walk_in?

  validate :within_operating_hours, unless: :walk_in?
  validate :service_duration_allows_disponivel, if: :disponivel?

  # ── SCOPES ────────────────────────────────────────────────────────────────
  scope :regular,            -> { where(appointment_type: "regular") }
  scope :disponivel,         -> { where(appointment_type: "disponivel") }
  scope :pending_acceptance, -> { where(status: "pending_acceptance") }
  scope :confirmed,          -> { where(status: "confirmed") }
  scope :attended,           -> { where(status: "attended") }
  scope :no_show,            -> { where(status: "no_show") }
  scope :cancelled,          -> { where(status: "cancelled") }
  scope :rejected,           -> { where(status: "rejected") }

  # Agendamentos disponíveis com aceite expirado (para o job de limpeza)
  scope :expired_pending, -> {
    pending_acceptance
      .disponivel
      .where("acceptance_expires_at < ?", Time.current)
  }

  # ── HELPERS DE TIPO ───────────────────────────────────────────────────────
  def disponivel?
    appointment_type == "disponivel"
  end

  def regular?
    appointment_type == "regular"
  end

  # ── HELPERS DE STATUS ─────────────────────────────────────────────────────
  def pending_acceptance?
    status == "pending_acceptance"
  end

  def confirmed?
    status == "confirmed"
  end

  def attended?
    status == "attended"
  end

  def rejected?
    status == "rejected"
  end

  def cancelled?
    status == "cancelled"
  end

  # Tempo restante para aceite (em segundos), nil se não aplicável
  def seconds_until_expiry
    return nil unless pending_acceptance? && acceptance_expires_at.present?
    [(acceptance_expires_at - Time.current).to_i, 0].max
  end

  def acceptance_expired?
    acceptance_expires_at.present? && acceptance_expires_at < Time.current
  end

  # ── VALORES ───────────────────────────────────────────────────────────────
  def effective_price
    price_override.present? ? price_override.to_f : service.price.to_f
  end

  # Calcula e armazena os valores de pré-pagamento e comissão
  def calculate_disponivel_amounts!
    total = effective_price
    self.prepayment_amount = (total * PREPAYMENT_PCT).round(2)
    self.commission_amount = (total * COMMISSION_PCT).round(2)
  end

  # Valor que vai para o dono após a comissão (do pré-pagamento)
  def owner_prepayment_net
    return 0 unless prepayment_amount.present? && commission_amount.present?
    (prepayment_amount - commission_amount).round(2)
  end

  # ── DISPLAY ───────────────────────────────────────────────────────────────
  def display_client
    if walk_in?
      walk_in_name.presence || "Avulso"
    else
      user&.email&.split("@")&.first&.capitalize || "Cliente"
    end
  end

  def reviewable?
    status == "confirmed" && scheduled_at < Time.current && review.nil? && !walk_in?
  end

  # ── TRANSIÇÕES DE STATUS (DISPONÍVEL) ────────────────────────────────────

  # Dono aceita → captura o pré-pagamento e confirma
  def accept!(stripe_service = nil)
    return false unless pending_acceptance? && disponivel?
    return false if acceptance_expired?

    ActiveRecord::Base.transaction do
      # Captura o PaymentIntent no Stripe (de autorizado para capturado)
      if stripe_payment_intent_id.present? && stripe_service.present?
        stripe_service.capture(stripe_payment_intent_id)
      end

      update!(
        status:               "confirmed",
        acceptance_expires_at: nil  # limpa o timer
      )
    end

    true
  rescue => e
    Rails.logger.error("Appointment#accept! failed: #{e.message}")
    false
  end

  # Dono rejeita → cancela o PaymentIntent (sem cobrança) e rejeita
  def reject!(stripe_service = nil)
    return false unless pending_acceptance? && disponivel?

    ActiveRecord::Base.transaction do
      if stripe_payment_intent_id.present? && stripe_service.present?
        stripe_service.cancel(stripe_payment_intent_id)
      end

      update!(status: "rejected")
    end

    true
  rescue => e
    Rails.logger.error("Appointment#reject! failed: #{e.message}")
    false
  end

  # Timeout expirou → cancela sem cobrança
  def expire!(stripe_service = nil)
    return false unless pending_acceptance? && disponivel?

    ActiveRecord::Base.transaction do
      if stripe_payment_intent_id.present? && stripe_service.present?
        stripe_service.cancel(stripe_payment_intent_id)
      end

      update!(status: "cancelled")
    end

    true
  rescue => e
    Rails.logger.error("Appointment#expire! failed: #{e.message}")
    false
  end

  # ── VALIDAÇÕES PRIVADAS ───────────────────────────────────────────────────
  private

  def within_operating_hours
    return unless scheduled_at && car_wash
    day_of_week   = scheduled_at.wday
    operating_hour = car_wash.operating_hours.find_by(day_of_week: day_of_week)

    unless operating_hour
      errors.add(:scheduled_at, "fora do intervalo de funcionamento: nenhum horário definido para este dia")
      return
    end

    scheduled_time    = scheduled_at.to_time
    opens_at          = Time.parse(operating_hour.opens_at.to_s).seconds_since_midnight
    closes_at         = Time.parse(operating_hour.closes_at.to_s).seconds_since_midnight
    scheduled_seconds = scheduled_time.seconds_since_midnight

    unless scheduled_seconds.between?(opens_at, closes_at)
      errors.add(:scheduled_at, "fora do intervalo de funcionamento")
    end
  end

  # Aba Disponíveis só aceita serviços de curta duração (≤ 60 min)
  # Serviços longos (polimento, vitrificação, etc.) não cabem no modelo de "agora"
  def service_duration_allows_disponivel
    return unless service.present?
    if service.duration.to_i > 60
      errors.add(:service, "não disponível na aba Disponíveis — duração acima de 60 minutos. Use o agendamento normal.")
    end
  end
end
