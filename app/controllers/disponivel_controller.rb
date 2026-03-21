class DisponivelController < ApplicationController
  before_action :authenticate_user!, except: [:index]

  # GET /disponivel
  def index
    @lat = params[:latitude].presence&.to_f
    @lon = params[:longitude].presence&.to_f

    window_start = Time.current
    window_end   = 2.hours.from_now
    today_dow    = Date.current.wday
    now_seconds  = Time.current.seconds_since_midnight.to_i

    open_car_wash_ids = OperatingHour
      .where(day_of_week: today_dow)
      .select { |oh|
        opens_sec  = oh.opens_at.seconds_since_midnight.to_i  rescue 0
        closes_sec = oh.closes_at.seconds_since_midnight.to_i rescue 86400
        now_seconds >= opens_sec && now_seconds <= closes_sec
      }
      .map(&:car_wash_id).uniq

    car_washes = CarWash.where(id: open_car_wash_ids)
    car_washes = car_washes.near([@lat, @lon], 20, units: :km) if @lat && @lon

    @available_slots = []

    car_washes.each do |cw|
      entry_services = cw.services.where("duration IS NULL OR duration <= 60").order(:price)
      next if entry_services.empty?

      slots = build_available_slots(cw, window_start, window_end)
      next if slots.empty?

      @available_slots << {
        car_wash:  cw,
        services:  entry_services,
        slots:     slots,
        min_price: entry_services.minimum(:price)
      }
    end

    @available_slots.sort_by! { |s| [s[:slots].first, s[:min_price]] }
  end

  # GET /disponivel/checkout
  # Mostra o resumo da reserva.
  # A verificação de cartão acontece apenas no POST /disponivel (create).
  def checkout
    @car_wash = CarWash.find(params[:car_wash_id])
    @service  = @car_wash.services.find(params[:service_id])
    @slot     = Time.zone.parse(params[:slot])

    if @service.duration.to_i > 60
      redirect_to disponivel_index_path, alert: "Serviço indisponível na aba Disponíveis."
      return
    end

    if @slot < Time.current
      redirect_to disponivel_index_path, alert: "Este horário já passou."
      return
    end

    unless slot_available?(@car_wash, @slot)
      redirect_to disponivel_index_path, alert: "Este horário acabou de ser ocupado."
      return
    end

    @total_price = @service.price.to_f
    @prepayment  = (@total_price * Appointment::PREPAYMENT_PCT).round(2)
    @remaining   = (@total_price - @prepayment).round(2)
    @has_card    = current_user.has_payment_method?
    @card_display = current_user.card_display

  rescue ActiveRecord::RecordNotFound
    redirect_to disponivel_index_path, alert: "Lava-rápido ou serviço não encontrado."
  end

  # POST /disponivel
  # Cria o agendamento usando o cartão salvo.
  # Se não tiver cartão, retorna redirect para o perfil.
  def create
    car_wash = CarWash.find(params[:car_wash_id])
    service  = car_wash.services.find(params[:service_id])
    slot     = Time.zone.parse(params[:slot])

    # Sem cartão → informa o cliente para cadastrar
    unless current_user.has_payment_method?
      session[:return_to_after_card] = checkout_disponivel_index_path(
        car_wash_id: params[:car_wash_id],
        service_id:  params[:service_id],
        slot:        params[:slot]
      )
      render json: {
        error:    "Nenhum cartão cadastrado.",
        redirect: edit_client_profile_path(add_card: true)
      }, status: :unprocessable_entity
      return
    end

    unless slot_available?(car_wash, slot)
      render json: { error: "Este horário acabou de ser ocupado. Escolha outro." }, status: :unprocessable_entity
      return
    end

    total      = service.price.to_f
    prepayment = (total * Appointment::PREPAYMENT_PCT).round(2)

    customer = current_user.stripe_customer!

    intent = Stripe::PaymentIntent.create({
      amount:               (prepayment * 100).to_i,
      currency:             "brl",
      customer:             customer.id,
      payment_method:       current_user.stripe_payment_method_id,
      capture_method:       :manual,
      confirm:              true,
      off_session:          true,
      metadata: {
        car_wash_id: car_wash.id,
        service_id:  service.id,
        slot:        slot.iso8601,
        user_id:     current_user.id,
        total_price: total,
        source:      "loov_disponivel"
      }
    })

    expires_at  = Time.current + Appointment::ACCEPTANCE_TTL
    appointment = Appointment.new(
      user:                     current_user,
      car_wash:                 car_wash,
      service:                  service,
      scheduled_at:             slot,
      status:                   "pending_acceptance",
      appointment_type:         "disponivel",
      acceptance_expires_at:    expires_at,
      stripe_payment_intent_id: intent.id
    )
    appointment.calculate_disponivel_amounts!

    if appointment.save
      ExpireDisponivelAcceptanceJob.set(wait: Appointment::ACCEPTANCE_TTL).perform_later(appointment.id)
      render json: { ok: true, appointment_id: appointment.id, expires_at: expires_at.iso8601, seconds: Appointment::ACCEPTANCE_TTL.to_i }
    else
      Stripe::PaymentIntent.cancel(intent.id) rescue nil
      render json: { error: appointment.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

  rescue Stripe::CardError => e
    render json: { error: "Cartão recusado: #{e.message}", redirect: edit_client_profile_path(add_card: true) }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Lava-rápido ou serviço não encontrado." }, status: :not_found
  rescue Stripe::StripeError => e
    Rails.logger.error("Disponivel#create Stripe error: #{e.message}")
    render json: { error: "Erro no pagamento. Tente novamente." }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error("Disponivel#create error: #{e.message}")
    render json: { error: "Erro inesperado." }, status: :internal_server_error
  end

  # GET /disponivel/:id/confirmacao
  def confirmacao
    @appointment = Appointment.find(params[:id])
    redirect_to root_path, alert: "Acesso negado." unless @appointment.user == current_user
  end

  # GET /disponivel/:id (JSON polling)
  def show
    appointment = Appointment.find(params[:id])
    unless appointment.user == current_user
      render json: { error: "Acesso negado." }, status: :forbidden
      return
    end
    render json: {
      status:        appointment.status,
      seconds_left:  appointment.seconds_until_expiry,
      car_wash_name: appointment.car_wash.name,
      service_name:  appointment.service.title,
      scheduled_at:  appointment.scheduled_at.strftime("%d/%m/%Y às %H:%M"),
      prepayment:    appointment.prepayment_amount,
      total:         appointment.effective_price
    }
  end

  private

  def build_available_slots(car_wash, from, to)
    capacity      = [car_wash.capacity_per_slot.to_i, 1].max
    now_minutes   = from.hour * 60 + from.min
    next_slot_min = (now_minutes / 30.0).ceil * 30
    current       = from.beginning_of_day + next_slot_min.minutes
    slots         = []
    while current <= to
      booked = Appointment.where(car_wash: car_wash, scheduled_at: current).where(status: %w[confirmed pending_acceptance]).count
      slots << current if booked < capacity
      current += 30.minutes
    end
    slots
  end

  def slot_available?(car_wash, slot)
    capacity = [car_wash.capacity_per_slot.to_i, 1].max
    booked   = Appointment.where(car_wash: car_wash, scheduled_at: slot).where(status: %w[confirmed pending_acceptance]).count
    booked < capacity
  end
end
