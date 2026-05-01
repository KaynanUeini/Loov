class DisponivelController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!, except: [:index]
  before_action :expire_stale_acceptances!

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

    car_washes_scope = CarWash.where(id: open_car_wash_ids).distinct
    car_washes_scope = car_washes_scope.near([@lat, @lon], 5, units: :km) if @lat && @lon

    # Filtro por car_wash específico — usado pelo BookingScreen quando o
    # cliente clica num slot disponivel_only e quer ir direto pro Last
    # Minute desse lava-rápido.
    if params[:car_wash_id].present?
      car_washes_scope = car_washes_scope.where(id: params[:car_wash_id])
    end

    # Dedup em Ruby como rede de segurança — geocoder .near pode adicionar
    # JOINs que fazem o mesmo car_wash aparecer mais de uma vez no .each.
    raw_car_washes    = car_washes_scope.to_a
    dedup_car_washes  = raw_car_washes.uniq(&:id)
    if raw_car_washes.size != dedup_car_washes.size
      Rails.logger.warn("[Disponivel#index] duplicata detectada: raw=#{raw_car_washes.size} dedup=#{dedup_car_washes.size} ids=#{raw_car_washes.map(&:id)}")
    end

    @available_slots = []

    dedup_car_washes.each do |cw|
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

    # Belt-and-suspenders: dedup final pelo id do car_wash
    @available_slots.uniq! { |s| s[:car_wash].id }
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
              logradouro:  cw.logradouro,
              numero:      cw.numero,
              bairro:      cw.bairro,
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

    if @slot < Time.current.in_time_zone("America/Sao_Paulo")
      redirect_to disponivel_index_path, alert: "Este horário já passou."
      return
    end

    unless slot_available?(@car_wash, @slot, @service)
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
    log_tag = "[Disponivel#create]"
    Rails.logger.info("#{log_tag} IN user_id=#{current_user&.id} params=#{params.permit(:car_wash_id, :service_id, :slot).to_h.inspect}")

    car_wash = CarWash.find(params[:car_wash_id])
    service  = car_wash.services.find(params[:service_id])
    slot     = Time.zone.parse(params[:slot])

    Rails.logger.info("#{log_tag} resolved car_wash_id=#{car_wash.id} service_id=#{service.id} slot=#{slot.iso8601}")

    appointment   = nil
    slot_taken    = false
    save_error    = nil

    # Transação + row-level lock na car_wash serializa todas as tentativas
    # de reserva concorrentes para o mesmo lava-rápido. Sem isso, dois
    # clientes clicando "Reservar" ao mesmo tempo poderiam passar pelo
    # slot_available? simultaneamente e ambos criar agendamento no mesmo
    # slot → overbooking.
    ActiveRecord::Base.transaction do
      car_wash.lock!

      unless slot_available?(car_wash, slot, service)
        slot_taken = true
        raise ActiveRecord::Rollback
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
      # Valores informativos (pré-pagamento teórico, comissão) — úteis para DRE/relatórios
      appointment.calculate_disponivel_amounts!

      unless appointment.save
        save_error = appointment.errors.full_messages.join(", ")
        raise ActiveRecord::Rollback
      end
    end

    if slot_taken
      Rails.logger.warn("#{log_tag} slot_taken car_wash_id=#{car_wash.id} slot=#{slot.iso8601}")
      render json: { error: "Este horário acabou de ser ocupado. Escolha outro." }, status: :unprocessable_entity
      return
    end

    if save_error
      Rails.logger.warn("#{log_tag} save_error car_wash_id=#{car_wash.id} slot=#{slot.iso8601} errors=#{save_error.inspect}")
      render json: { error: save_error }, status: :unprocessable_entity
      return
    end

    Rails.logger.info("#{log_tag} OK appointment_id=#{appointment.id}")

    # Job é enfileirado fora da transação — se falhar, a lazy expiration
    # (expire_stale_acceptances!) ainda cobre o caso.
    begin
      ExpireDisponivelAcceptanceJob.set(wait: Appointment::ACCEPTANCE_TTL).perform_later(appointment.id)
    rescue => job_err
      Rails.logger.warn("Disponivel#create: falha ao enfileirar ExpireDisponivelAcceptanceJob: #{job_err.message}")
    end

    render json: {
      ok:             true,
      appointment_id: appointment.id,
      expires_at:     appointment.acceptance_expires_at.iso8601,
      seconds:        Appointment::ACCEPTANCE_TTL.to_i,
      payment_status: "pending" # pagamento será feito presencialmente
    }

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("#{log_tag} not_found user_id=#{current_user&.id} car_wash_id=#{params[:car_wash_id].inspect} service_id=#{params[:service_id].inspect} msg=#{e.message}")
    render json: { error: "Lava-rápido ou serviço não encontrado." }, status: :not_found
  rescue => e
    Rails.logger.error("#{log_tag} error #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
    render json: {
      error: e.message,
      trace: e.backtrace&.first(3)
    }, status: :internal_server_error
  end

  # GET /disponivel/:id/confirmacao
  def confirmacao
    @appointment = Appointment.find(params[:id])
    redirect_to root_path, alert: "Acesso negado." unless @appointment.user == current_user
  end

  # PATCH /disponivel/:id/cancel
  # Cliente desiste da reserva antes do dono aceitar. Só permite enquanto o
  # status ainda é pending_acceptance — depois disso (confirmed/cancelled/
  # rejected) a transição não faz sentido e retorna 422.
  def cancel
    appointment = Appointment.find(params[:id])

    unless appointment.user_id == current_user.id
      render json: { error: "Acesso negado." }, status: :forbidden
      return
    end

    unless appointment.status == "pending_acceptance"
      render json: {
        error: "Esta reserva não pode mais ser cancelada.",
        status: appointment.status
      }, status: :unprocessable_entity
      return
    end

    appointment.update!(status: "cancelled")
    render json: { ok: true, status: appointment.status }

  rescue ActiveRecord::RecordNotFound
    render json: { error: "Reserva não encontrada." }, status: :not_found
  rescue => e
    Rails.logger.error("Disponivel#cancel error: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
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

  # Delega para Appointment.expire_stale_disponivel_acceptances! — método
  # throttled e centralizado (Render free tier pode não rodar o job async).
  def expire_stale_acceptances!
    Appointment.expire_stale_disponivel_acceptances!
  end

  # Pico de concorrência durante [slot, slot+new_duration_min). Delega
  # para Appointment.peak_concurrency_during — sweep de eventos para não
  # super-contar atendimentos que rodam em sequência (back-to-back).
  def peak_at(car_wash, slot, new_duration_min)
    Appointment.peak_concurrency_during(
      car_wash: car_wash,
      start_at: slot,
      end_at:   slot + new_duration_min.minutes
    )
  end

  def build_available_slots(car_wash, from, to)
    capacity      = [car_wash.capacity_per_slot.to_i, 1].max
    now_minutes   = from.hour * 60 + from.min
    next_slot_min = (now_minutes / 30.0).ceil * 30
    current       = from.beginning_of_day + next_slot_min.minutes

    while current <= to
      # Granularidade do slot é 30min.
      return [current] if peak_at(car_wash, current, 30) < capacity
      current += 30.minutes
    end
    []
  end

  def slot_available?(car_wash, slot, service = nil)
    capacity = [car_wash.capacity_per_slot.to_i, 1].max
    duration = service&.duration.to_i
    duration = 30 if duration <= 0
    peak_at(car_wash, slot, duration) < capacity
  end
end
