module Owner
  class CarWashAppointmentsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner

    def index
      car_wash = current_user.car_washes.first
      if car_wash.nil?
        respond_to do |format|
          format.html { redirect_to root_path, alert: "Você não tem um lava-rápido associado." }
          format.json { render json: { error: "Lava-rápido não encontrado." }, status: :not_found }
        end
        return
      end

      # Usa a mesma regra que `available_times` aplica pra bloquear
      # capacidade — assim o que o dono vê aqui bate EXATAMENTE com o
      # que impede o cliente de agendar.
      @appointments = car_wash.appointments
        .occupying_capacity
        .where("scheduled_at::date >= CURRENT_DATE")

      # HTML-only filters preservados (period / search)
      if params[:period].present?
        case params[:period]
        when "last_7_days"
          @appointments = @appointments.where("scheduled_at >= ?", 7.days.ago)
        when "next_7_days"
          @appointments = @appointments.where("scheduled_at <= ?", 7.days.from_now)
        when "custom"
          if params[:start_date].present? && params[:end_date].present?
            start_date = Date.parse(params[:start_date]).beginning_of_day
            end_date = Date.parse(params[:end_date]).end_of_day
            @appointments = @appointments.where(scheduled_at: start_date..end_date)
          end
        end
      end

      if params[:search].present?
        search_term = "%#{params[:search].downcase}%"
        @appointments = @appointments.joins(:user).where(
          "LOWER(users.email) LIKE ?", search_term
        ).or(
          @appointments.joins(:service).where("LOWER(services.title) LIKE ?", search_term)
        ).references(:user, :services)
      end

      @appointments = @appointments.order(scheduled_at: :asc)

      respond_to do |format|
        format.html do
          grouped_by_date = @appointments.group_by { |a| a.scheduled_at.to_date }
          sorted_dates = grouped_by_date.keys.sort
          @appointments_by_date = {}
          sorted_dates.each { |date| @appointments_by_date[date] = grouped_by_date[date] }
        end

        format.json do
          days = params[:days].to_i
          days = 30 if days <= 0
          end_of_window = (Date.current + (days - 1).days).end_of_day

          scope = @appointments.where("scheduled_at <= ?", end_of_window)
                               .includes(:user, :service)

          groups = scope.group_by { |a| a.scheduled_at.to_date }.sort.map do |date, appts|
            {
              date:         date.iso8601,
              label:        json_group_label(date),
              weekday:      %w[DOM SEG TER QUA QUI SEX SÁB][date.wday],
              day:          date.day,
              month:        date.month,
              year:         date.year,
              count:        appts.size,
              appointments: appts.map { |a| appointment_json(a) }
            }
          end

          render json: { groups: groups, total: scope.count }
        end
      end
    end

    def show
      car_wash = current_user.car_washes.first
      if car_wash.nil?
        respond_to do |format|
          format.html { redirect_to root_path, alert: "Você não tem um lava-rápido associado." }
          format.json { render json: { error: "Lava-rápido não encontrado." }, status: :not_found }
        end
        return
      end

      @appointment = car_wash.appointments.find(params[:id])

      respond_to do |format|
        format.html
        format.json { render json: appointment_json(@appointment, full: true) }
      end
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { redirect_to owner_car_wash_appointments_path, alert: "Agendamento não encontrado." }
        format.json { render json: { error: "Agendamento não encontrado." }, status: :not_found }
      end
    end

    private

    def ensure_owner
      return if current_user&.owner?
      if request.format.json?
        render json: { error: "Acesso restrito a donos de lava-rápidos." }, status: :forbidden
      else
        redirect_to root_path, alert: "Acesso restrito a donos de lava-rápidos."
      end
    end

    def json_group_label(date)
      today = Date.current
      if date == today
        "HOJE"
      elsif date == today + 1
        "AMANHÃ"
      else
        weekday = %w[DOM SEG TER QUA QUI SEX SÁB][date.wday]
        "#{weekday} · #{date.strftime('%d/%m')}"
      end
    end

    def appointment_json(a, full: false)
      tz = "America/Sao_Paulo"
      hash = {
        id:               a.id,
        scheduled_at:     a.scheduled_at.iso8601,
        time:             a.scheduled_at.in_time_zone(tz).strftime('%H:%M'),
        status:           a.status,
        appointment_type: a.appointment_type,
        walk_in:          a.walk_in,
        client_name:      a.display_client,
        service_title:    a.service&.title,
        service_duration: a.service&.duration,
        price:            a.effective_price.to_f
      }
      if full
        hash.merge!(
          client_email:      a.user&.email,
          service_category:  a.service&.category,
          service_desc:      a.service&.description,
          walk_in_name:      a.walk_in_name,
          created_at:        a.created_at.iso8601,
          prepayment_amount: a.prepayment_amount&.to_f,
          commission_amount: a.commission_amount&.to_f
        )
      end
      hash
    end
  end
end
