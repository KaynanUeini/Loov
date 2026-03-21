module Owner
  class CheckinsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :load_appointment, only: [:attend, :no_show, :revert, :update_service]

    # GET /owner/checkins/today
    def today
      car_wash = current_car_wash
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

      # Caixa do dia: para disponível, conta apenas o valor restante (65%)
      # pois os 35% são pré-pagos — o funcionário vai cobrar o restante
      revenue_today = appointments.select { |a| a[:status] == "attended" }.sum do |a|
        if a[:is_disponivel]
          a[:price] - a[:prepayment_amount].to_f
        else
          a[:price]
        end
      end

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
    # Ponto 1: para agendamentos disponível, captura o pagamento Stripe ao marcar como attended
    def attend
      ActiveRecord::Base.transaction do
        @appointment.update!(status: "attended")

        # Se é disponível e tem PaymentIntent, captura os 35% no Stripe
        if @appointment.disponivel? && @appointment.stripe_payment_intent_id.present?
          begin
            stripe_service = StripeService.new
            stripe_service.capture(@appointment.stripe_payment_intent_id)
          rescue Stripe::StripeError => e
            Rails.logger.error("Checkins#attend Stripe capture error: #{e.message}")
            # Não falha o attend por causa do Stripe — loga e segue
          end
        end
      end

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
      # Para disponível confirmado, volta para confirmed (não para pending_acceptance)
      new_status = @appointment.disponivel? ? "confirmed" : "confirmed"
      @appointment.update!(status: new_status)
      render json: { ok: true }.merge(serialize_appointment(@appointment))
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # PATCH /owner/checkins/:id/update_service
    def update_service
      car_wash = current_car_wash
      service  = car_wash.services.find_by(id: params[:service_id])
      return render json: { error: "Serviço não encontrado." }, status: :not_found unless service

      price = params[:price_override].present? ? params[:price_override].to_f : nil
      @appointment.update!(service: service, price_override: price)
      render json: { ok: true }.merge(serialize_appointment(@appointment))
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /owner/checkins/walk_in
    def walk_in
      car_wash = current_car_wash
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      service = car_wash.services.find_by(id: params[:service_id])
      return render json: { error: "Serviço não encontrado." }, status: :not_found unless service

      time_str     = params[:scheduled_at].presence || Time.current.strftime("%H:%M")
      hour, minute = time_str.split(":").map(&:to_i)
      scheduled_at = Time.current.beginning_of_day + hour.hours + minute.minutes
      price        = params[:price_override].present? ? params[:price_override].to_f : nil

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

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { error: "Acesso negado." }, status: :forbidden
      end
    end

    def load_appointment
      car_wash     = current_car_wash
      @appointment = car_wash.appointments.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Agendamento não encontrado." }, status: :not_found
    end

    def serialize_appointment(a)
      # Ponto 2: 4 dígitos finais do telefone + veículo do cliente
      phone_last4  = nil
      vehicle      = nil
      if a.user.present?
        phone = a.user.phone.to_s.gsub(/\D/, '')
        phone_last4 = phone.length >= 4 ? phone.last(4) : nil
        vehicle     = a.user.vehicle_model.presence
      end

      # Ponto 2: mostrar código 5 minutos antes do horário
      show_code = a.scheduled_at <= Time.current + 5.minutes &&
                  a.scheduled_at >= Time.current - 30.minutes &&
                  a.status == "confirmed"

      # Ponto 3: dados de disponível para mostrar valor restante
      is_disponivel    = a.disponivel? rescue false
      prepayment       = is_disponivel ? a.prepayment_amount.to_f : 0
      remaining_amount = is_disponivel ? (a.effective_price - prepayment).round(2) : nil

      {
        id:               a.id,
        time:             a.scheduled_at.strftime("%H:%M"),
        client:           a.display_client,
        service:          a.service.title,
        service_id:       a.service_id,
        price:            a.effective_price,
        price_original:   a.service.price.to_f,
        price_overridden: a.price_override.present?,
        walk_in:          a.walk_in?,
        status:           a.status,
        status_label:     status_label(a.status),
        status_color:     status_color(a.status),
        # Ponto 2
        phone_last4:      phone_last4,
        vehicle:          vehicle,
        show_code:        show_code,
        # Ponto 3
        is_disponivel:    is_disponivel,
        prepayment_amount: prepayment,
        remaining_amount:  remaining_amount
      }
    end

    def status_label(status)
      {
        "confirmed"          => "Aguardando",
        "pending_acceptance" => "Aguardando aceite",
        "attended"           => "Compareceu",
        "no_show"            => "Não veio",
        "rejected"           => "Recusado"
      }[status] || status
    end

    def status_color(status)
      {
        "confirmed"          => "yellow",
        "pending_acceptance" => "yellow",
        "attended"           => "green",
        "no_show"            => "red",
        "rejected"           => "red"
      }[status] || "gray"
    end
  end
end
