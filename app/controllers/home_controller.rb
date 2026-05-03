class HomeController < ApplicationController
  def index
    Rails.logger.info("Renderizando Home#index para usuário: #{current_user&.email}")

    # ── IDs de lava-rápidos abertos AGORA ─────────────────────────────────
    now       = Time.current.in_time_zone("America/Sao_Paulo")
    now_sec   = now.seconds_since_midnight.to_i
    today_dow = now.wday

    @open_car_wash_ids = OperatingHour
      .where(day_of_week: today_dow)
      .select do |oh|
        opens  = oh.opens_at.seconds_since_midnight.to_i  rescue 0
        closes = oh.closes_at.seconds_since_midnight.to_i rescue 86400
        now_sec >= opens && now_sec < closes
      end
      .map(&:car_wash_id)
      .to_set

    # ── BASE ───────────────────────────────────────────────────────────────
    @car_washes = CarWash.all

    # ── ORDENAR POR DISTÂNCIA ──────────────────────────────────────────────
    if params[:latitude].present? && params[:longitude].present?
      begin
        latitude       = params[:latitude].to_f
        longitude      = params[:longitude].to_f
        with_coords    = @car_washes.select(&:has_valid_coordinates?).sort_by { |cw| cw.distance_to([latitude, longitude], :km) }
        without_coords = @car_washes.reject(&:has_valid_coordinates?)
        @car_washes    = with_coords + without_coords
      rescue => e
        Rails.logger.error("Erro ao calcular distância: #{e.message}")
      end
    end

    # ── BUSCA: nome, endereço e serviço ───────────────────────────────────
    @search_results = []
    if params[:search].present?
      term = params[:search].strip
      cw_ids_by_service = Service
        .where("title ILIKE ?", "%#{term}%")
        .pluck(:car_wash_id)
        .uniq

      matched = @car_washes.select do |cw|
        cw.name.match?(/#{Regexp.escape(term)}/i) ||
        cw.address.to_s.match?(/#{Regexp.escape(term)}/i) ||
        cw_ids_by_service.include?(cw.id)
      end

      @search_results = matched.sort_by { |cw| @open_car_wash_ids.include?(cw.id) ? 0 : 1 }
    end

    # ── SEÇÕES: abertos primeiro ───────────────────────────────────────────
    # Aumentado de 8 → 50 pra suportar dezenas de lava-rápidos seedados
    # (60+ bairros de SP, agora também Osasco). Os filtros client-side
    # (Aberto agora / Perto de mim / Melhores avaliados / categoria) já
    # filtram visualmente; o gargalo era apenas o cap no controller.
    @nearby_car_washes = @car_washes
      .first(80)
      .sort_by { |cw| @open_car_wash_ids.include?(cw.id) ? 0 : 1 }
      .first(50)

    @top_car_washes = CarWash.all
      .select { |cw| cw.reviews.any? }
      .sort_by { |cw| [@open_car_wash_ids.include?(cw.id) ? 0 : 1, -cw.reviews.average(:rating).to_f] }
      .first(20)

    @location_name = params[:location_name].presence

    # ── DASHBOARD OWNER/ATTENDANT ──────────────────────────────────────────
    if user_signed_in? && (current_user.owner? || current_user.attendant?)
      @car_wash = current_car_wash
      if @car_wash
        today_start     = Time.current.beginning_of_day
        today_end       = Time.current.end_of_day
        @today_total    = @car_wash.appointments.where(scheduled_at: today_start..today_end).where.not(status: "cancelled").count
        @today_attended = @car_wash.appointments.where(scheduled_at: today_start..today_end, status: "attended").count
        @today_pending  = @car_wash.appointments.where(scheduled_at: today_start..today_end, status: "confirmed").count
        @today_revenue  = @car_wash.appointments
                            .where(scheduled_at: today_start..today_end, status: "attended")
                            .joins(:service)
                            .sum("services.price - COALESCE(appointments.commission_amount, 0)").to_f
        @upcoming_count = @car_wash.appointments
                            .where(status: "confirmed")
                            .where(scheduled_at: Time.current..7.days.from_now)
                            .count

        # ── CHECKLIST DE ATIVAÇÃO ─────────────────────────────────────────
        if current_user.owner?
          step_hours   = @car_wash.operating_hours.any?
          step_service = @car_wash.services.any?
          @activation_complete = step_hours && step_service

          unless @activation_complete
            @activation_steps = [
              {
                key:   :hours,
                done:  step_hours,
                label: "Cadastre seus horários de funcionamento",
                cta:   "Configurar",
                url:   manage_car_wash_path(@car_wash, anchor: "hours"),
                icon:  "fa-clock"
              },
              {
                key:   :service,
                done:  step_service,
                label: "Adicione pelo menos um serviço",
                cta:   "Adicionar",
                url:   manage_car_wash_path(@car_wash, anchor: "services"),
                icon:  "fa-tag"
              }
            ]
          end
        end
      end
    end

    # ── ABA DISPONÍVEIS ────────────────────────────────────────────────────
    @disponivel_slots        = []
    @disponivel_has_location = params[:latitude].present? && params[:longitude].present?

    if user_signed_in? && current_user.client? && @disponivel_has_location
      lat        = params[:latitude].to_f
      lon        = params[:longitude].to_f
      window_end = now + 30.minutes

      now_minutes   = now.hour * 60 + now.min
      next_slot_min = (now_minutes / 30.0).ceil * 30
      next_slot     = now.beginning_of_day + next_slot_min.minutes

      nearby_open = CarWash
        .where(id: @open_car_wash_ids.to_a)
        .select(&:has_valid_coordinates?)
        .select { |cw| cw.distance_to([lat, lon], :km) <= 5.0 }
        .sort_by { |cw| cw.distance_to([lat, lon], :km) }
        .first(6)

      nearby_open.each do |cw|
        wash_services = cw.services.where("duration IS NULL OR duration <= 60").order(:price)
        next if wash_services.empty?

        capacity       = [cw.capacity_per_slot.to_i, 1].max
        available_slot = nil
        slot_candidate = next_slot

        while slot_candidate <= window_end
          booked = Appointment
            .occupying_capacity
            .where(car_wash: cw, scheduled_at: slot_candidate)
            .count

          if booked < capacity
            available_slot = slot_candidate
            break
          end
          slot_candidate += 30.minutes
        end

        next unless available_slot

        @disponivel_slots << {
          car_wash:    cw,
          slot:        available_slot,
          services:    wash_services,
          min_price:   wash_services.minimum(:price),
          distance_km: cw.distance_to([lat, lon], :km).round(1)
        }
      end
    end
  end
end
