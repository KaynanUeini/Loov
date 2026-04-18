class DisponivelController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!, except: [:index]

  # GET /disponivel
  def index
    @lat = params[:latitude].presence&.to_f
    @lon = params[:longitude].presence&.to_f

    window_start = Time.current
    window_end = 30.minutes.from_now
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
    car_washes = car_washes.near([@lat, @lon], 5, units: :km) if @lat && @lon

    @available_slots = []

    car_washes.each do |cw|
      entry_services = cw.services.where("duration IS NULL OR duration <= 60").order(:price)
      next if entry_services.empty?

      slots = build_available_slots(cw, window_start, window_end)
      next if slots.empty?

      distance_km = (@lat && @lon && cw.has_valid_coordinates?) ?
        cw.distance_to([@lat, @lon], :km).round(2) : nil

      @available_slots << {
        car_wash:    cw,
        services:    entry_services,
        slots:       slots,
        min_price:   entry_services.minimum(:price),
        distance_km: distance_km
      }
    end

    @available_slots.sort_by! { |s| [s[:slots].first, s[:min_price]] }

    respond_to do |format|
      format.html
      format.json do
        render json: @available_slots.map { |s|
          cw = s[:car_wash]
          {
            car_wash: {
              id:          cw.id,
              name:        cw.name,
              address:     cw.address,
              cidade:      cw.cidade,
              uf:          cw.uf,
              latitude:    cw.latitude,
              longitude:   cw.longitude,
              distance_km: s[:distance_km]
            },
            services:  s[:services].map { |svc|
              {
                id:       svc.id,
                title:    svc.title,
                price:    svc.price.to_f,
                duration: svc.duration,
                category: svc.category
              }
            },
            slots:     s[:slots].map(&:iso8601),
            min_price: s[:min_price].to_f
          }
        }
      end
    end
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
  # Cria o agendamento sem pagamento no app — o cliente paga presencialmente
  # (dinheiro, PIX direto com o dono ou maquininha) no lava-rápido.
  def create
    car_wash = CarWash.find(params[:car_wash_id])
    service  = car_wash.services.find(params[:service_id])
    slot     = Time.zone.parse(params[:slot])

    unless slot_available?(car_wash, slot)
      render json: { error: "Este horário acabou de ser ocupado. Escolha outro." }, status: :unprocessable_entity
      return
    end

    expires_at  = Time.current + Appointment::ACCEPTANCE_TTL
    appointment = Appointment.new(
      user:                  current_user,
      car_wash:              car_wash,
      service:               service,
      scheduled_at:          slot,
      status:                "pending_acceptance",
      appointment_type:      "disponivel",
      acceptance_expires_at: expires_at
    )
    # Mantém os valores informativos (pré-pagamento teórico, comissão) — úteis para DRE/relatórios
    appointment.calculate_disponivel_amounts!

    if appointment.save
      ExpireDisponivelAcceptanceJob.set(wait: Appointment::ACCEPTANCE_TTL).perform_later(appointment.id)
      render json: {
        ok:             true,
        appointment_id: appointment.id,
        expires_at:     expires_at.iso8601,
        seconds:        Appointment::ACCEPTANCE_TTL.to_i,
        payment_status: "pending" # pagamento será feito presencialmente
      }
    else
      render json: { error: appointment.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

  rescue ActiveRecord::RecordNotFound
    render json: { error: "Lava-rápido ou serviço não encontrado." }, status: :not_found
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

    while current <= to
      booked = Appointment.where(car_wash: car_wash, scheduled_at: current)
      .where(status: %w[confirmed pending_acceptance]).count
      if booked < capacity
        return [current]
      end
      current += 30.minutes
    end
    []
  end
  def slot_available?(car_wash, slot)
    capacity = [car_wash.capacity_per_slot.to_i, 1].max
    booked   = Appointment.where(car_wash: car_wash, scheduled_at: slot).where(status: %w[confirmed pending_acceptance]).count
    booked < capacity
  end
end
