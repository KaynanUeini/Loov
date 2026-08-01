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

  # Flag para pular a validação de capacidade quando o caller tem um motivo
  # explícito (walk-in com override do dono, seed, migração, etc.). Todo caminho
  # "normal" de criação (cliente via app ou Disponível) continua obrigatório
  # a respeitar capacidade — a checagem no model é a rede de segurança final.
  attr_accessor :skip_capacity_check

  # Validações de "é um horário válido para marcar" rodam só na criação ou
  # quando o horário muda. Uma vez criado, o agendamento fica imune — senão
  # mudanças de status (compareceu/ausente) quebrariam em casos limítrofes
  # (ex: owner editou operating_hours depois, ou validação ficou mais estrita).
  validate :within_operating_hours, unless: :walk_in?,
           if: -> { new_record? || will_save_change_to_scheduled_at? || will_save_change_to_service_id? }
  validate :not_during_closure, unless: :walk_in?,
           if: -> { new_record? || will_save_change_to_scheduled_at? }
  validate :service_allows_disponivel, if: :disponivel?
  validate :fits_in_capacity, unless: :skip_capacity_check,
           if: -> { new_record? || will_save_change_to_scheduled_at? || will_save_change_to_service_id? }

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

  # ÚNICA fonte de verdade para "este agendamento ocupa uma vaga da
  # capacidade do lava-rápido agora". Use em todo lugar que precise
  # contar quantos agendamentos sobrepõem um horário — assim não dá
  # pra uma parte do código ficar out-of-sync com outra.
  #
  # Inclui:
  #   - confirmed       (reserva regular aceita)
  #   - attended        (inclui walk-ins, que são criados já como attended)
  #   - pending_acceptance apenas se o TTL do aceite ainda não expirou.
  #     Se o job de limpeza travar (Render free tier pode engolir jobs
  #     async), esse filtro evita que um pendente-zumbi bloqueie slot.
  scope :occupying_capacity, -> {
    where(
      "appointments.status IN (?) OR " \
      "(appointments.status = ? AND appointments.acceptance_expires_at > ?)",
      %w[confirmed attended],
      "pending_acceptance",
      Time.current
    )
  }

  # Expira aceites pendentes que já passaram do TTL de 3 min. Em Render free
  # tier o ActiveJob :async não é confiável (jobs morrem entre requests), então
  # a expiração é lazy: qualquer request relevante pode chamar este método
  # como rede de segurança. Throttled via cache pra não martelar o banco.
  # Retorna o número de registros expirados (0 se throttled ou nada a fazer).
  def self.expire_stale_disponivel_acceptances!
    # Throttle: no máximo uma execução por 30 segundos, app-wide. Se o cache
    # não estiver configurado ou falhar, roda mesmo assim (fail-open).
    if Rails.cache.respond_to?(:exist?) && Rails.cache.exist?("appointments:expire_stale:last_run")
      return 0
    end

    count = where(status: "pending_acceptance", appointment_type: "disponivel")
              .where("acceptance_expires_at < ?", Time.current)
              .update_all(status: "cancelled", updated_at: Time.current)

    begin
      Rails.cache.write("appointments:expire_stale:last_run", Time.current, expires_in: 30.seconds)
    rescue
      # cache indisponível — sem problema, na próxima chamada roda de novo
    end

    count
  rescue => e
    Rails.logger.warn("Appointment.expire_stale_disponivel_acceptances! failed: #{e.message}")
    0
  end

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
    return walk_in_name.presence || "Avulso" if walk_in?
    return "Cliente" unless user

    raw = user.full_name.presence
    # Nome é "limpo" se tem espaço (e.g. "Maria Silva") OU não tem
    # underscore nem dígito (registros legais sem espaço como "Carla").
    return raw if raw && (raw.include?(" ") || (!raw.include?("_") && !raw.match?(/\d/)))

    # Fallback: nome ausente ou parece username de email (ex: seeds legacy
    # com full_name = "premium_mariavalenina4"). Limpa prefixo comum,
    # remove dígitos finais e formata cada palavra capitalizada.
    base = (raw || user.email.to_s.split("@").first.to_s).downcase
    cleaned = base.sub(/\A(premiumm?_|free_|trial_|user_|client_)/, "")
                  .gsub(/\d+\z/, "")
                  .tr("_.", " ")
                  .strip
    return "Cliente" if cleaned.empty?
    cleaned.split.map(&:capitalize).join(" ")
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
    day_of_week    = scheduled_at.wday
    operating_hour = car_wash.operating_hours.find_by(day_of_week: day_of_week)

    unless operating_hour
      errors.add(:scheduled_at, "fora do intervalo de funcionamento: nenhum horário definido para este dia")
      return
    end

    opens_at          = Time.parse(operating_hour.opens_at.to_s).seconds_since_midnight
    closes_at         = Time.parse(operating_hour.closes_at.to_s).seconds_since_midnight
    scheduled_seconds = scheduled_at.to_time.seconds_since_midnight

    # Considera a duração do serviço: o fim do atendimento também precisa caber
    # dentro do horário de funcionamento. Ex: fecha 17:00, serviço de 60 min;
    # 16:30 seria rejeitado porque termina 17:30.
    duration_seconds = service&.duration.to_i * 60
    end_seconds      = scheduled_seconds + duration_seconds

    unless scheduled_seconds >= opens_at && end_seconds <= closes_at
      errors.add(:scheduled_at, "fora do intervalo de funcionamento")
    end
  end

  # Rede de segurança final — qualquer caminho que salva um Appointment sem
  # ter checado capacidade explicitamente cai aqui. Conta quantos outros
  # agendamentos ocupam a mesma janela (mesma regra do `available_times`)
  # e falha se já está no limite da capacidade do lava-rápido.
  #
  # Para pular essa checagem (walk-in com override do dono, seed, etc.):
  #   appointment.skip_capacity_check = true
  def fits_in_capacity
    return unless car_wash && service && scheduled_at

    cap = car_wash.capacity_for(scheduled_at)
    duration_min = service.duration.to_i
    return if duration_min <= 0

    end_at = scheduled_at + duration_min.minutes
    peak = self.class.peak_concurrency_during(
      car_wash:   car_wash,
      start_at:   scheduled_at,
      end_at:     end_at,
      exclude_id: persisted? ? id : nil
    )

    if peak + 1 > cap
      errors.add(:scheduled_at, "horário sem capacidade disponível (#{peak + 1}/#{cap} simultâneos durante a janela)")
    end
  end

  # Pico de concorrência durante [start_at, end_at) entre agendamentos que
  # ocupam capacidade no car_wash. Sweep de eventos (+1 entrada, -1 saída):
  # contar overlap direto somaria atendimentos sequenciais que terminam e
  # começam back-to-back, super-estimando o uso real da pista.
  #
  # Fim efetivo de cada agendamento = COALESCE(attended_at, scheduled_at +
  # duração). Quando o dono clica "Finalizado" antes da duração planejada
  # acabar (ex: lavagem rápida), attended_at libera o slot a partir dali.
  # Walk-ins não têm attended_at e seguem usando a duração planejada.
  EFFECTIVE_END_SQL = "COALESCE(appointments.attended_at, " \
                      "appointments.scheduled_at + (services.duration * interval '1 minute'))".freeze

  def self.peak_concurrency_during(car_wash:, start_at:, end_at:, exclude_id: nil)
    scope = occupying_capacity
      .joins(:service)
      .where(car_wash_id: car_wash.id)
      .where(
        "appointments.scheduled_at < ? AND #{EFFECTIVE_END_SQL} > ?",
        end_at, start_at
      )
    scope = scope.where.not(id: exclude_id) if exclude_id

    ranges = scope.pluck(
      Arel.sql("appointments.scheduled_at"),
      Arel.sql(EFFECTIVE_END_SQL)
    )
    return 0 if ranges.empty?

    events = ranges.flat_map { |s, e|
      cs = [s, start_at].max
      ce = [e, end_at].min
      [[cs, +1], [ce, -1]]
    }.sort_by { |t, d| [t, d] } # -1 antes de +1 no mesmo instante (back-to-back não acumula)

    peak = 0
    current = 0
    events.each do |_t, d|
      current += d
      peak = current if current > peak
    end
    peak
  end

  # O Last Minute vende lavagem — de qualquer duração. O corte aqui era por
  # tempo (≤ 60 min), o que recusava a "Lavagem Completa" mesmo quando ela
  # cabia folgada antes do fechamento, e ao mesmo tempo deixava passar
  # polimento e higienização curtos, que não são o produto.
  #
  # Caber no horário não é problema desta validação: within_operating_hours já
  # exige que o atendimento TERMINE dentro do expediente, e a listagem só
  # oferece slot em que o serviço cabe.
  def service_allows_disponivel
    return unless service.present?
    return if service.last_minute?

    errors.add(:service, "não disponível no Last Minute — só serviços de lavagem. Use o agendamento normal.")
  end

  # Bloqueia agendamentos em dias que o owner marcou como fechado (ex: férias,
  # manutenção). Roda em todos os paths de criação (regular, disponível, API)
  # porque é validação de model — controllers não precisam duplicar.
  #
  # Fail-open: se a tabela car_wash_closures não existir (migration pendente
  # no ambiente) ou outra falha de schema, permite o agendamento e loga. Não
  # queremos derrubar o fluxo de reserva por causa de uma validação opcional.
  def not_during_closure
    return unless scheduled_at && car_wash
    return unless closures_table_present?

    closing = car_wash.car_wash_closures.where(
      "start_date <= ? AND end_date >= ?",
      scheduled_at.to_date,
      scheduled_at.to_date
    ).first
    if closing
      reason = closing.reason.presence || "fechamento programado"
      errors.add(:scheduled_at, "lava-rápido fechado neste dia: #{reason}")
    end
  rescue => e
    Rails.logger.warn("not_during_closure skipped: #{e.class}: #{e.message}")
  end

  def closures_table_present?
    # Memoizado no process — só consulta information_schema uma vez.
    self.class.closures_table_present?
  end

  def self.closures_table_present?
    @closures_table_present ||= ActiveRecord::Base.connection.data_source_exists?("car_wash_closures")
  rescue
    false
  end
end
