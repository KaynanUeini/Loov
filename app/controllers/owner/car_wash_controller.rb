module Owner
  class CarWashController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    # Atendente pode ler info do car_wash que está vinculado (nome aparece
    # no header do dashboard). Tudo que muda dados (update etc) segue
    # restrito ao dono via ensure_owner.
    before_action :ensure_owner_or_attendant, only: [:show, :update]
    before_action :ensure_owner,               except: [:show, :update]
    before_action :set_car_wash

    def show
      render json: {
        id:                @car_wash.id,
        name:              @car_wash.name,
        cep:               @car_wash.cep,
        logradouro:        @car_wash.logradouro,
        numero:            @car_wash.numero,
        bairro:            @car_wash.bairro,
        cidade:            @car_wash.cidade,
        uf:                @car_wash.uf,
        address:           @car_wash.address,
        capacity_per_slot: @car_wash.capacity_per_slot,
        latitude:          @car_wash.latitude,
        longitude:         @car_wash.longitude,
        operating_hours: @car_wash.operating_hours.order(:day_of_week).map { |oh|
          {
            id:          oh.id,
            day_of_week: oh.day_of_week,
            opens_at:    oh.opens_at&.strftime('%H:%M'),
            closes_at:   oh.closes_at&.strftime('%H:%M'),
          }
        },
        services: @car_wash.services.order(:title).map { |s|
          {
            id:          s.id,
            title:       s.title,
            category:    s.category,
            description: s.description,
            price:       s.price.to_f,
            duration:    s.duration,
          }
        }
      }
    end

    def update
      update_params = params.require(:car_wash).permit(
        :name, :cep, :logradouro, :numero, :bairro, :cidade, :uf, :address,
        :capacity_per_slot, :latitude, :longitude,
        operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
        services_attributes:        [:id, :title, :category, :description, :price, :duration, :_destroy]
      )

      attendant_change = current_user.attendant?

      if @car_wash.update(update_params)
        # Atendente alterou Gerenciar lava-rápido — aplicado direto, mas o
        # dono recebe push avisando.
        notify_owner_of_attendant_change!(@car_wash, current_user, update_params) if attendant_change
        render json: { ok: true }
      else
        render json: { error: @car_wash.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # GET /owner/car_wash/slot_diagnostics?date=YYYY-MM-DD&duration=30
    #
    # Retorna, para cada slot do dia, a contagem e a lista completa de
    # agendamentos que bloqueiam aquele horário. Espelha exatamente a lógica
    # do `available_times` — mas com transparência total. Útil pro dono
    # entender "por que o cliente não consegue marcar nesse horário?".
    def slot_diagnostics
      Appointment.expire_stale_disponivel_acceptances!

      tz = "America/Sao_Paulo"
      begin
        date = Date.parse(params[:date].to_s)
      rescue ArgumentError, TypeError
        date = Date.current
      end
      duration = params[:duration].to_i
      duration = 30 if duration <= 0

      capacity = [@car_wash.capacity_per_slot.to_i, 1].max
      operating_hour = @car_wash.operating_hours.find_by(day_of_week: date.wday)

      unless operating_hour
        render json: {
          date:               date.iso8601,
          capacity_per_slot:  capacity,
          duration:           duration,
          closed:             true,
          slots:              []
        } and return
      end

      opens_at_min  = (operating_hour.opens_at.hour  * 60) + operating_hour.opens_at.min
      closes_at_min = (operating_hour.closes_at.hour * 60) + operating_hour.closes_at.min

      now_sp    = Time.current.in_time_zone(tz)
      is_today  = date == Date.current
      now_min   = is_today ? now_sp.hour * 60 + now_sp.min : 0
      lock_threshold = now_min + 45

      grid_opens = if is_today && now_min >= opens_at_min
        slots_passed = ((now_min - opens_at_min).to_f / duration).ceil
        opens_at_min + (slots_passed * duration)
      else
        opens_at_min
      end

      appts = @car_wash.appointments
        .occupying_capacity
        .where("DATE(scheduled_at) = ?", date)
        .includes(:service, :user)
        .to_a

      slots = []
      current = grid_opens
      while current + duration <= closes_at_min
        time_end = current + duration

        blocking = appts.select do |a|
          s = (a.scheduled_at.in_time_zone(tz).hour * 60) + a.scheduled_at.in_time_zone(tz).min
          d = a.service&.duration.to_i
          next false if d <= 0
          current < (s + d) && time_end > s
        end

        disp_only = is_today && current < lock_threshold
        slots << {
          time:              format("%02d:%02d", current / 60, current % 60),
          count:             blocking.size,
          capacity:          capacity,
          regular_available: blocking.size < capacity && !disp_only,
          disponivel_only:   disp_only,
          blocking:          blocking.map { |a| diagnostics_appt_json(a, tz) }
        }
        current += duration
      end

      render json: {
        date:              date.iso8601,
        now:               is_today ? now_sp.strftime("%H:%M") : nil,
        capacity_per_slot: capacity,
        duration:          duration,
        lock_minutes:      45,
        operating_hours: {
          opens_at:  operating_hour.opens_at.strftime("%H:%M"),
          closes_at: operating_hour.closes_at.strftime("%H:%M")
        },
        slots: slots
      }
    end

    private

    def diagnostics_appt_json(a, tz)
      {
        id:           a.id,
        time:         a.scheduled_at.in_time_zone(tz).strftime("%H:%M"),
        duration:     a.service&.duration,
        service:      a.service&.title,
        client:       a.walk_in? ? (a.walk_in_name.presence || "Avulso") : (a.user&.display_name || "—"),
        status:       a.status,
        walk_in:      a.walk_in,
        acceptance_expires_at: a.acceptance_expires_at&.iso8601
      }
    end

    def set_car_wash
      # Usa linked_car_wash pra resolver tanto pro dono (car_washes.first)
      # quanto pro atendente (attendant_invitations.accepted.first.car_wash).
      @car_wash = current_user&.linked_car_wash
      render json: { error: 'Lava-rápido não encontrado.' }, status: :not_found unless @car_wash
    end

    def ensure_owner
      render json: { error: 'Acesso negado.' }, status: :forbidden unless current_user&.owner?
    end

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { error: 'Acesso negado.' }, status: :forbidden
      end
    end

    # Push pro dono quando atendente altera o Gerenciar lava-rápido.
    # Não bloqueia a request — falha silenciosamente.
    def notify_owner_of_attendant_change!(car_wash, attendant, params)
      owner = car_wash.user
      return unless owner && owner != attendant

      summary = summarize_car_wash_change(params)
      title   = "Atendente alterou o lava-rápido"
      body    = "#{attendant.display_name} editou: #{summary}"

      # Persiste pra aparecer na lista do dono em /owner/notifications.
      AttendantActivity.create!(
        car_wash:  car_wash,
        attendant: attendant,
        action:    "manage_car_wash",
        title:     title,
        body:      body,
      )

      # Push imediato (best-effort).
      ExpoPushNotifier.new.notify_user(
        owner,
        title: title,
        body:  body,
        data:  { type: "attendant_car_wash_change", car_wash_id: car_wash.id }
      )
    rescue => e
      Rails.logger.warn("[CarWashController] notify falhou: #{e.class}: #{e.message}")
    end

    def summarize_car_wash_change(params)
      labels = []
      field_names = {
        "name" => "nome", "address" => "endereço", "cep" => "CEP",
        "logradouro" => "logradouro", "numero" => "número",
        "bairro" => "bairro", "cidade" => "cidade", "uf" => "UF",
        "capacity_per_slot" => "capacidade", "latitude" => "latitude",
        "longitude" => "longitude"
      }
      params.to_h.each do |k, _|
        next if %w[operating_hours_attributes services_attributes].include?(k)
        labels << (field_names[k] || k)
      end

      hours = params[:operating_hours_attributes]
      if hours.respond_to?(:any?) && hours.any?
        n = hours.respond_to?(:size) ? hours.size : Array(hours).size
        labels << "#{n} #{n == 1 ? 'horário' : 'horários'}"
      end

      services = params[:services_attributes]
      if services.respond_to?(:any?) && services.any?
        n = services.respond_to?(:size) ? services.size : Array(services).size
        labels << "#{n} #{n == 1 ? 'serviço' : 'serviços'}"
      end

      labels.empty? ? "configurações do lava-rápido" : labels.join(", ")
    end
  end
end
