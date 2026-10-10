class AppointmentsController < ApplicationController
  before_action :authenticate_user!
  # O app manda o login no cabeçalho Authorization, sem o token CSRF do
  # formulário. O cancelamento fica livre só nesse caso: um site de terceiros
  # não consegue enviar esse cabeçalho, então no navegador a proteção segue.
  skip_before_action :verify_authenticity_token, if: -> {
    action_name.in?(%w[create authorized]) ||
      (action_name == 'cancel' && request.authorization.to_s.start_with?('Bearer '))
  }
  before_action :set_appointment, only: [:show, :cancel, :help, :authorized]
  before_action :set_car_wash, only: [:new, :create]
  # Cleanup lazy de Disponíveis vencidos a cada acesso. Throttled no model
  # (1x/30s app-wide) — não pesa no banco mesmo com polling frequente.
  before_action -> { Appointment.expire_stale_disponivel_acceptances! }, only: [:index, :create]

  def new
    if @car_wash.nil?
      redirect_to car_washes_path, alert: "Lava-rápido não encontrado."
      return
    end
    if @car_wash.services.empty?
      redirect_to car_washes_path, alert: "O lava-rápido selecionado não tem serviços disponíveis."
      return
    end
    @appointment = Appointment.new(car_wash: @car_wash)
  end

  def index
    respond_to do |format|
      format.html do
        # A página do site é o porte da aba Agenda do app e lê o mesmo JSON,
        # embutido nela (sem esperar uma segunda requisição).
        @payload = appointments_payload
      end

      format.json do
        render json: appointments_payload
      end
    end
  rescue StandardError => e
    Rails.logger.error("Erro em AppointmentsController#index: #{e.message}")
    render json: { error: "Erro interno: #{e.message}" }, status: :internal_server_error
  end

  def create
    @appointment      = Appointment.new(appointment_params.except(:date, :time))
    @appointment.user = current_user
    # status é setado para 'confirmed' dentro da transação (linha ~237)
    # após o lock e o check de overlap — evita persistir em estado inválido.

    scheduled_date = params[:appointment][:date]
    scheduled_time = params[:appointment][:time]

    unless scheduled_date.present? && scheduled_time.present?
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Data e horário são obrigatórios." }
        format.json { render json: { error: "Data e horário são obrigatórios." }, status: :unprocessable_entity }
      end
      return
    end

    begin
      date_parts = scheduled_date.split('-').map(&:to_i)
      time_parts = scheduled_time.split(':').map(&:to_i)
      @appointment.scheduled_at = DateTime.new(
        date_parts[0], date_parts[1], date_parts[2],
        time_parts[0], time_parts[1], 0, '-03:00'
      )
    rescue
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Data ou horário inválidos." }
        format.json { render json: { error: "Data ou horário inválidos." }, status: :unprocessable_entity }
      end
      return
    end

    unless params[:appointment][:service_id].present?
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Por favor, selecione um serviço." }
        format.json { render json: { error: "Selecione um serviço." }, status: :unprocessable_entity }
      end
      return
    end

    current_time_with_tolerance = DateTime.now.in_time_zone("America/Sao_Paulo") - 5.minutes
    if @appointment.scheduled_at < current_time_with_tolerance
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Não é possível agendar para um horário no passado." }
        format.json { render json: { error: "Não é possível agendar para um horário no passado." }, status: :unprocessable_entity }
      end
      return
    end

    minutes_until = ((@appointment.scheduled_at.in_time_zone("America/Sao_Paulo") - Time.current.in_time_zone("America/Sao_Paulo")) / 60).to_i
    if @appointment.regular? && minutes_until < 45 && minutes_until >= 0
      respond_to do |format|
        format.html { redirect_to disponivel_index_path, alert: "Este horário só pode ser reservado pelo Disponível." }
        format.json { render json: { error: "Este horário só pode ser reservado pelo Disponível." }, status: :unprocessable_entity }
      end
      return
    end

    service    = Service.find(params[:appointment][:service_id])
    start_time = @appointment.scheduled_at
    end_time   = start_time + service.duration.minutes

    operating_hours = @car_wash.operating_hours.where(day_of_week: start_time.wday)
    unless operating_hours.any?
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "O lava-rápido não está disponível no dia selecionado." }
        format.json { render json: { error: "O lava-rápido não está disponível no dia selecionado." }, status: :unprocessable_entity }
      end
      return
    end

    within_operating_hours = operating_hours.any? do |oh|
      start_min = start_time.hour * 60 + start_time.min
      end_min   = end_time.hour * 60   + end_time.min
      opens_at  = oh.opens_at.hour * 60  + oh.opens_at.min
      closes_at = oh.closes_at.hour * 60 + oh.closes_at.min
      start_min >= opens_at && end_min <= closes_at
    end

    unless within_operating_hours
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "O horário selecionado está fora do horário de funcionamento." }
        format.json { render json: { error: "Horário fora do funcionamento." }, status: :unprocessable_entity }
      end
      return
    end

    # Pausa do dono. Vale aqui e não só na listagem: listar e criar sempre
    # precisam concordar, e nesta base já custou cinco correções descobrir isso
    # do jeito difícil. A mensagem diz até quando, senão o cliente só sabe que
    # não pode e não sabe quando poderá.
    # Limite e faltas (User#restricao_agendamento). Vem antes da pausa e da
    # disponibilidade: se a pessoa não pode agendar, o motivo é este, não o
    # horário.
    if @appointment.regular?
      erro = regra_de_agendamento(start_time)
      if erro
        status = erro[:code] == "card_required" ? :payment_required : :unprocessable_entity
        respond_to do |format|
          format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: erro[:error] }
          format.json { render json: erro, status: status }
        end
        return
      end
    end
    com_sinal = @appointment.regular? && current_user.restricao_agendamento&.dig(:tipo) == :sinal

    if @car_wash.pausado_para?(start_time)
      volta = @car_wash.paused_until.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
      msg   = "O lava-rápido pausou os agendamentos até #{volta}. Escolha um horário depois disso."
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end

    saved    = false
    conflict = false

    ActiveRecord::Base.transaction do
      @car_wash.lock!

      # Inclui pending_acceptance (reserva Disponível em trânsito) e attended
      # (slot já foi usado) — sem eles, dois fluxos paralelos (regular vs
      # disponível, ou um attended histórico) colidiriam no mesmo horário.
      overlapping = Appointment
        .occupying_capacity
        .joins(:service)
        .where(car_wash_id: @car_wash.id)
        .where(
          "appointments.scheduled_at < ? AND (appointments.scheduled_at + (services.duration * interval '1 minute')) > ?",
          end_time, start_time
        )
        .count

      if overlapping >= @car_wash.capacity_for(start_time)
        conflict = true
        raise ActiveRecord::Rollback
      end

      # Com sinal, o horário fica preso só enquanto o banco cobra (como o
      # Last Minute no 3DS) e não aparece pro dono até virar confirmed.
      if com_sinal
        @appointment.status = 'awaiting_payment'
        @appointment.acceptance_expires_at = Time.current + Appointment::PAYMENT_AUTH_TTL
      else
        @appointment.status = 'confirmed'
      end
      saved = @appointment.save
      raise ActiveRecord::Rollback unless saved
    end

    if conflict
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Horário indisponível. Por favor, escolha outro." }
        format.json { render json: { error: "Horário indisponível. Escolha outro." }, status: :conflict }
      end
      return
    end

    unless saved
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Erro ao criar o agendamento." }
        format.json { render json: { error: @appointment.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
      return
    end

    if com_sinal
      resultado, detalhe = @appointment.cobrar_sinal!
      if resultado == :declined
        render json: { error: detalhe, code: "card_declined" }, status: :payment_required
        return
      end
      if resultado == :action
        begin
          ExpireDisponivelAcceptanceJob.set(wait: Appointment::PAYMENT_AUTH_TTL).perform_later(@appointment.id)
        rescue => e
          Rails.logger.warn("[Appointments#create] expiração do sinal não enfileirada: #{e.message}")
        end
        render json: {
          ok: true, requires_action: true, appointment_id: @appointment.id, client_secret: detalhe,
          publishable_key: ENV["STRIPE_PUBLISHABLE_KEY"].presence || Rails.application.credentials.dig(:stripe, :publishable_key),
          deposit: @appointment.prepayment_amount.to_f
        }
        return
      end
    end

    enviar_confirmacao(@appointment)

    respond_to do |format|
      format.html { redirect_to appointments_path, notice: "Agendamento criado com sucesso!" }
      format.json { render json: { message: "Agendamento confirmado!", appointment_id: @appointment.id,
                                   deposit: @appointment.stripe_payment_intent_id.present? ? @appointment.prepayment_amount.to_f : nil },
                           status: :created }
    end
  end

  # POST /appointments/:id/authorized — o banco confirmou o sinal (3DS). O
  # servidor confere com o Stripe; o que o aparelho diz não é confiado.
  def authorized
    a = @appointment
    return render(json: { ok: true, appointment_id: a.id, deposit: a.prepayment_amount.to_f }) if a.status == "confirmed"
    unless a.status == "awaiting_payment" && a.stripe_payment_intent_id.present?
      return render json: { error: "O tempo para confirmar no banco acabou e o horário foi liberado.", code: "expired" },
                    status: :unprocessable_entity
    end

    intent = StripeService.new.retrieve(a.stripe_payment_intent_id)
    unless intent.status == "requires_capture"
      _, msg = a.recusar_sinal!(a.stripe_payment_intent_id, "O banco não confirmou o sinal. Nada foi cobrado; tente de novo ou use outro cartão.")
      return render json: { error: msg, code: "card_declined" }, status: :payment_required
    end

    a.with_lock { a.confirmar_sinal! if a.status == "awaiting_payment" }
    enviar_confirmacao(a.reload)
    render json: { ok: true, appointment_id: a.id, deposit: a.prepayment_amount.to_f }
  rescue Stripe::StripeError => e
    Rails.logger.error("[Appointments#authorized] #{e.class}: #{e.message}")
    render json: { error: "Não conseguimos confirmar com o banco agora. Tente de novo em instantes." }, status: :bad_gateway
  end

  # Mesmo JSON da aba Agenda do app; a página HTML também o usa (embutido).
  private def appointments_payload
    # awaiting_payment é a reserva ainda na janela do banco (3DS): não é
    # agendamento até o banco confirmar.
    all = current_user.appointments
      .where.not(status: "awaiting_payment")
      .includes(:service, :car_wash, :review)
      .order(scheduled_at: :desc)

    # Último 4 dígitos do próprio telefone do cliente — usado no card do
    # app pro cliente ver qual código dizer ao lava-rápido quando chegar.
    phone_digits = current_user.phone.to_s.gsub(/\D/, "")
    phone_last4  = phone_digits.length >= 4 ? phone_digits.last(4) : nil

    all.map { |a|
      # show_code: de 15 min antes do horário agendado até 5 min depois
      # (buffer pequeno pra quando o cliente chega atrasado). Só em
      # confirmed — depois de attended/no_show/cancelled não faz sentido.
      show_code = a.status == "confirmed" &&
                  a.scheduled_at <= Time.current + 15.minutes &&
                  a.scheduled_at >= Time.current - 5.minutes

      review_data = a.review ? {
        id:      a.review.id,
        rating:  a.review.rating,
        tags:    a.review.tags_list,
        comment: a.review.comment
      } : nil

      {
        id:               a.id,
        status:            a.status,
        appointment_type:  a.appointment_type,
        scheduled_at:      a.scheduled_at,
        reviewed:          a.review.present?,
        review_id:         a.review&.id,
        review:            review_data,
        phone_last4:       phone_last4,
        show_code:         show_code,
        # Sinal pago no app (agendamento comum de quem tem faltas recentes):
        # volta pro cartão se cancelar dentro do prazo.
        deposit:           (a.regular? && a.stripe_payment_intent_id.present?) ? a.prepayment_amount.to_f : nil,
        car_wash: {
          id:   a.car_wash.id,
          name: a.car_wash.name,
          # Coordenada e endereço pro botão "Ver rota" do card abrir o app de
          # mapas direto. Sem isso o app só conseguia levar pra tela do
          # lava-rápido, que não é rota.
          latitude:  a.car_wash.latitude,
          longitude: a.car_wash.longitude,
          address:   a.car_wash.address
        },
        service: {
          id:       a.service.id,
          title:    a.service.title,
          price:    a.service.price,
          duration: a.service.duration
        }
      }
    }
  end

  def show
  end

  def cancel
    current_time = Time.current.in_time_zone("America/Sao_Paulo")

    # Só confirmados podem ser cancelados. Impede cancelar attended/no_show/
    # rejected/cancelled (edge cases em que status != 'cancelled' deixava passar).
    unless @appointment.status == 'confirmed'
      message = "Apenas agendamentos confirmados podem ser cancelados."
      respond_to do |format|
        format.html { redirect_to appointments_path, alert: message }
        format.json { render json: { error: message }, status: :unprocessable_entity }
      end
      return
    end

    if @appointment.disponivel?
      message = "Agendamentos Disponíveis não podem ser cancelados por aqui."
      respond_to do |format|
        format.html { redirect_to appointments_path, alert: message }
        format.json { render json: { error: message }, status: :unprocessable_entity }
      end
      return
    end

    minutes_until = ((@appointment.scheduled_at - current_time) / 60).to_i
    if minutes_until <= 120
      deadline = @appointment.scheduled_at.in_time_zone("America/Sao_Paulo") - 2.hours
      message = "Prazo de cancelamento encerrou em #{deadline.strftime('%H:%M')} de #{deadline.strftime('%d/%m')}."
      respond_to do |format|
        format.html { redirect_to appointments_path, alert: message }
        format.json { render json: { error: message }, status: :unprocessable_entity }
      end
      return
    end

    @appointment.update_columns(status: 'cancelled')
    # Cancelou dentro do prazo: o sinal (quem tinha) volta pro cartão.
    estorno = @appointment.estornar_prepagamento!
    respond_to do |format|
      format.html { redirect_to appointments_path, notice: "Agendamento cancelado. O horário foi liberado." }
      format.json { render json: { ok: true, status: 'cancelled', refund: estorno } }
    end
  end

  def help
    flash[:notice] = "Entre em contato com o suporte para assistência com o agendamento ##{@appointment.id}."
    redirect_to appointments_path
  end

  private

  def enviar_confirmacao(appointment)
    AppointmentMailer.confirmation(appointment).deliver_now
  rescue => e
    Rails.logger.error("[Appointments] Email falhou: #{e.message}")
  end

  # nil quando pode agendar; senão o JSON de erro com um code que o app e o
  # site usam pra mostrar a tela certa.
  def regra_de_agendamento(start_time)
    r = current_user.restricao_agendamento
    if r&.dig(:tipo) == :bloqueio
      return { code: "no_show_block", until: r[:ate].iso8601,
               error: "Por causa de #{r[:faltas]} faltas recentes, o agendamento comum está bloqueado até " \
                      "#{r[:ate].in_time_zone('America/Sao_Paulo').strftime('%d/%m')}. O Last Minute continua liberado." }
    end

    ativos = current_user.agendamentos_comuns_ativos
    if ativos.count >= User::LIMITE_AGENDAMENTOS
      return { code: "limit_reached",
               error: "Você já tem #{User::LIMITE_AGENDAMENTOS} agendamentos marcados. Pra marcar outro, cancele um " \
                      "ou espere um deles acontecer." }
    end

    dia = start_time.in_time_zone("America/Sao_Paulo").to_date
    mesmo_dia = current_user.appointments
      .where(car_wash_id: @car_wash.id, status: %w[confirmed awaiting_payment pending_acceptance])
      .where(scheduled_at: dia.in_time_zone("America/Sao_Paulo").all_day)
    if mesmo_dia.exists?
      return { code: "same_day", error: "Você já tem um horário neste lava-rápido nesse dia." }
    end

    if r&.dig(:tipo) == :sinal && !current_user.has_payment_method?
      return { code: "card_required",
               error: "Por causa de faltas recentes, o agendamento comum pede um sinal de " \
                      "#{(Appointment::PREPAYMENT_PCT * 100).round}% no cartão até " \
                      "#{r[:ate].in_time_zone('America/Sao_Paulo').strftime('%d/%m')}. Cadastre um cartão pra continuar." }
    end
    nil
  end

  def end_time(a)
    a.scheduled_at + a.service.duration.minutes
  end

  def active_status?(a)
    %w[pending confirmed pending_acceptance].include?(a.status)
  end

  def set_appointment
    @appointment = Appointment.find(params[:id])
    unless @appointment.user_id == current_user.id
      redirect_to root_path, alert: 'Acesso não autorizado.'
    end
  end

  def set_car_wash
    car_wash_id = params[:car_wash_id] || params[:appointment]&.dig(:car_wash_id)
    @car_wash   = CarWash.find(car_wash_id) if car_wash_id.present?
  rescue ActiveRecord::RecordNotFound
    @car_wash = nil
  end

  def appointment_params
    params.require(:appointment).permit(:car_wash_id, :service_id)
  end
end
