class HomeController < ApplicationController
  def index
    Rails.logger.info("Renderizando Home#index para usuário: #{current_user&.email}")

    @car_washes = CarWash.all

    if params[:latitude].present? && params[:longitude].present?
      begin
        latitude  = params[:latitude].to_f
        longitude = params[:longitude].to_f
        @car_washes = @car_washes.select(&:has_valid_coordinates?).sort_by do |cw|
          cw.distance_to([latitude, longitude], :km)
        end
      rescue => e
        Rails.logger.error("Erro ao calcular distância: #{e.message}")
      end
    end

    if params[:search].present?
      @car_washes = @car_washes.select do |cw|
        cw.name.match?(/#{params[:search]}/i) || cw.address.to_s.match?(/#{params[:search]}/i)
      end
    end

    if user_signed_in? && current_user.owner?
      @car_wash = current_user.car_washes.first

      if @car_wash
        today_start      = Time.current.beginning_of_day
        today_end        = Time.current.end_of_day
        @today_total     = @car_wash.appointments.where(scheduled_at: today_start..today_end).where.not(status: "cancelled").count
        @today_attended  = @car_wash.appointments.where(scheduled_at: today_start..today_end, status: "attended").count
        @today_pending   = @car_wash.appointments.where(scheduled_at: today_start..today_end, status: "confirmed").count
        @today_revenue   = @car_wash.appointments
                             .where(scheduled_at: today_start..today_end, status: "attended")
                             .joins(:service).sum("services.price").to_f

        # Próximos agendamentos (hoje + amanhã) para o contexto da IA
        @upcoming_count  = @car_wash.appointments
                             .where(status: "confirmed")
                             .where(scheduled_at: Time.current..7.days.from_now)
                             .count
      end
    end
  end
end
