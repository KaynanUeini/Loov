module Owner
  class CheckinsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner
    before_action :load_appointment, only: [:attend, :no_show, :revert, :update_service]

    # GET /owner/checkins/today
    def today
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      today_start  = Time.current.beginning_of_day
      today_end    = Time.current.end_of_day
      appointments = car_wash.appointments
      .where(scheduled_at: today_start..today_end)
      .where.not(status: "cancelled")
      .includes(:service, :user)
      .order(:scheduled_at)
      .map { |a| serialize_appointment(a) }

      total_attended = appointments.count { |a| a[:status] == "attended" }
      total_no_show  = appointments.count { |a| a[:status] == "no_show" }
      total_pending  = appointments.count { |a| a[:status] == "confirmed" }
      revenue_today  = appointments.select { |a| a[:status] == "attended" }.sum { |a| a[:price] }

      # Serviços disponíveis para troca
      services = car_wash.services.order(:title).map do |s|
        { id: s.id, title: s.title, price: s.price.to_f }
      end

      render json: {
        appointments: appointments,
        services:     services,
        summary: {
          total:         appointments.count,
          attended:      total_attended,
          no_show:       total_no_show,
          pending:       total_pending,
          revenue_today: revenue_today.round(2)
        }
      }
    end

    # PATCH /owner/checkins/:id/attend
    def attend
      @appointment.update!(status: "attended")
      render json: { ok: true }.merge(serialize_appointment(@appointment))
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # PATCH /owner/checkins/:id/no_show
    def no_show
      @appointment.update!(status: "no_show")
      render json: { ok: true }.merge(serialize_appointment(@appointment))
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # PATCH /owner/checkins/:id/revert
    def revert
      @appointment.update!(status: "confirmed")
      render json: { ok: true }.merge(serialize_appointment(@appointment))
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # PATCH /owner/checkins/:id/update_service
    # Body: { service_id: X, price_override: Y }
    def update_service
      car_wash = current_user.car_washes.first
      service  = car_wash.services.find_by(id: params[:service_id])
      return render json: { error: "Serviço não encontrado." }, status: :not_found unless service

      price = params[:price_override].present? ? params[:price_override].to_f : nil
      @appointment.update!(service: service, price_override: price)
      render json: { ok: true }.merge(serialize_appointment(@appointment))
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /owner/checkins/walk_in
    # Body: { service_id: X, price_override: Y, walk_in_name: "Nome", scheduled_at: "HH:MM" }
    def walk_in
      car_wash = current_user.car_washes.first
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      service = car_wash.services.find_by(id: params[:service_id])
      return render json: { error: "Serviço não encontrado." }, status: :not_found unless service

      time_str     = params[:scheduled_at].presence || Time.current.strftime("%H:%M")
      hour, minute = time_str.split(":").map(&:to_i)
      scheduled_at = Time.current.beginning_of_day + hour.hours + minute.minutes

      price = params[:price_override].present? ? params[:price_override].to_f : nil

      appointment = car_wash.appointments.build(
        user:           nil,
        service:        service,
        scheduled_at:   scheduled_at,
        status:         "attended",
        walk_in:        true,
        walk_in_name:   params[:walk_in_name].presence || "Avulso",
        price_override: price
        )

      if appointment.save
        render json: { ok: true }.merge(serialize_appointment(appointment))
      else
        render json: { error: appointment.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    private

    def ensure_owner
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end

    def load_appointment
      car_wash     = current_user.car_washes.first
      @appointment = car_wash.appointments.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Agendamento não encontrado." }, status: :not_found
    end

    def serialize_appointment(a)
      {
        id:           a.id,
        time:         a.scheduled_at.strftime("%H:%M"),
        client:       a.display_client,
        service:      a.service.title,
        service_id:   a.service_id,
        price:        a.effective_price,
        price_original: a.service.price.to_f,
        price_overridden: a.price_override.present?,
        walk_in:      a.walk_in?,
        status:       a.status,
        status_label: status_label(a.status),
        status_color: status_color(a.status)
      }
    end

    def status_label(status)
      { "confirmed" => "Aguardando", "attended" => "Compareceu", "no_show" => "Não veio", "pending" => "Pendente" }[status] || status
    end

    def status_color(status)
      { "confirmed" => "yellow", "attended" => "green", "no_show" => "red", "pending" => "gray" }[status] || "gray"
    end
  end
end
