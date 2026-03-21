class HomeController < ApplicationController
  def index
    Rails.logger.info("Renderizando Home#index para usuário: #{current_user&.email}")
    @car_washes = CarWash.all

    if params[:latitude].present? && params[:longitude].present?
      begin
        latitude  = params[:latitude].to_f
        longitude = params[:longitude].to_f
        with_coords    = @car_washes.select(&:has_valid_coordinates?).sort_by { |cw| cw.distance_to([latitude, longitude], :km) }
        without_coords = @car_washes.reject(&:has_valid_coordinates?)
        @car_washes    = with_coords + without_coords
      rescue => e
        Rails.logger.error("Erro ao calcular distância: #{e.message}")
      end
    end

    if params[:search].present?
      @car_washes = @car_washes.select do |cw|
        cw.name.match?(/#{params[:search]}/i) || cw.address.to_s.match?(/#{params[:search]}/i)
      end
    end

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
                            .joins(:service).sum("services.price").to_f
        @upcoming_count = @car_wash.appointments
                            .where(status: "confirmed")
                            .where(scheduled_at: Time.current..7.days.from_now)
                            .count
      end
    end

    # ── ABA DISPONÍVEIS ────────────────────────────────────────────────────
    # Sempre inicializa — a seção aparece mesmo vazia (com mensagem)
    @disponivel_slots       = []
    @disponivel_has_location = params[:latitude].present? && params[:longitude].present?

    if user_signed_in? && current_user.client? && @disponivel_has_location
      lat        = params[:latitude].to_f
      lon        = params[:longitude].to_f
      now        = Time.current
      window_end = now + 30.minutes
      today_dow  = Date.current.wday

      # Próximo slot redondo de 30min (sem ceil_to que não existe no Rails)
      now_minutes   = now.hour * 60 + now.min
      next_slot_min = (now_minutes / 30.0).ceil * 30
      next_slot     = now.beginning_of_day + next_slot_min.minutes

      # Verifica quais lava-rápidos estão abertos agora
      # Compara usando o horário atual em segundos desde meia-noite
      # para evitar problemas de tipo com a coluna time do PostgreSQL
      now_seconds = now.seconds_since_midnight.to_i

      open_car_wash_ids = OperatingHour
        .where(day_of_week: today_dow)
        .select { |oh|
          opens_sec  = oh.opens_at.seconds_since_midnight.to_i  rescue 0
          closes_sec = oh.closes_at.seconds_since_midnight.to_i rescue 86400
          now_seconds >= opens_sec && now_seconds <= closes_sec
        }
        .map(&:car_wash_id)
        .uniq

      nearby_open = CarWash
        .where(id: open_car_wash_ids)
        .select(&:has_valid_coordinates?)
        .select { |cw| cw.distance_to([lat, lon], :km) <= 5.0 }
        .sort_by { |cw| cw.distance_to([lat, lon], :km) }
        .first(6)

      nearby_open.each do |cw|
        # Serviços de lavagem (duração ≤ 60min) — se duration for nil, inclui também
        wash_services = cw.services.where("duration IS NULL OR duration <= 60").order(:price)
        next if wash_services.empty?

        capacity       = [cw.capacity_per_slot.to_i, 1].max
        available_slot = nil
        slot_candidate = next_slot

        while slot_candidate <= window_end
          booked = Appointment
            .where(car_wash: cw, scheduled_at: slot_candidate)
            .where(status: %w[confirmed pending_acceptance])
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
