module Owner
  class CheckinsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :load_appointment, only: [:attend, :no_show, :revert, :update_service, :cancel]

    # GET /owner/checkins/today
    def today
      car_wash = current_car_wash
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      today_start = Time.current.beginning_of_day
      today_end   = Time.current.end_of_day

      # ── Programa de fidelidade ─────────────────────────────────────────
      loyalty = car_wash.loyalty_program&.active? ? car_wash.loyalty_program : nil

      # Pré-carrega contagem de visitas por usuário (evita N+1)
      # Filtra pela data de criação do programa para respeitar o ciclo correto
      loyalty_counts = {}
      if loyalty
        user_ids = car_wash.appointments
          .where(scheduled_at: today_start..today_end)
          .where.not(status: "cancelled")
          .where.not(user_id: nil)
          .pluck(:user_id).uniq

        if user_ids.any?
          counts = Appointment
            .where(car_wash_id: car_wash.id, user_id: user_ids, status: "attended")
            .where("scheduled_at >= ?", loyalty.created_at)
            .group(:user_id)
            .count
          loyalty_counts = counts
        end
      end

      appointments = car_wash.appointments
        .where(scheduled_at: today_start..today_end)
        .where.not(status: "cancelled")
        .includes(:service, :user)
        .order(:scheduled_at)
        .map { |a| serialize_appointment(a, loyalty, loyalty_counts) }

      unresolved_past = car_wash.appointments
        .where(status: "confirmed")
        .where("scheduled_at < ?", today_start)
        .includes(:service, :user)
        .order(:scheduled_at)
        .map { |a| serialize_appointment(a, loyalty, loyalty_counts) }

      total_attended = appointments.count { |a| a[:status] == "attended" }
      total_no_show  = appointments.count { |a| a[:status] == "no_show" }
      total_pending  = appointments.count { |a| a[:status] == "confirmed" }

      revenue_today = appointments.select { |a| a[:status] == "attended" }.sum do |a|
        a[:is_disponivel] ? a[:price] - a[:prepayment_amount].to_f : a[:price]
      end

      avg_7_days = (1..7).map do |i|
        d_start = i.days.ago.beginning_of_day
        d_end   = i.days.ago.end_of_day
        car_wash.appointments
          .where(scheduled_at: d_start..d_end, status: "attended")
          .joins(:service).sum("services.price").to_f
      end.sum / 7.0

      services = car_wash.services.order(:title).map do |s|
        { id: s.id, title: s.title, price: s.price.to_f }
      end

      render json: {
        appointments:    appointments,
        unresolved_past: unresolved_past,
        services:        services,
        loyalty: loyalty ? {
          active:           true,
          visits_required:  loyalty.visits_required,
          reward_description: loyalty.reward_description
        } : { active: false },
        summary: {
          total:         appointments.count,
          attended:      total_attended,
          no_show:       total_no_show,
          pending:       total_pending,
          revenue_today: revenue_today.round(2),
          avg_7_days:    avg_7_days.round(2)
        }
      }
    end

    # PATCH /owner/checkins/:id/attend
    def attend
      ActiveRecord::Base.transaction do
        # attended_at marca o fim REAL do serviço — usado pelo cálculo de
        # capacidade pra liberar o slot mesmo quando o serviço terminou
        # antes da duração planejada (ex: lavagem rápida).
        @appointment.update!(status: "attended", attended_at: Time.current)

        if @appointment.disponivel? && @appointment.stripe_payment_intent_id.present?
          begin
            stripe_service = StripeService.new
            stripe_service.capture(@appointment.stripe_payment_intent_id)
          rescue Stripe::StripeError => e
            Rails.logger.error("Checkins#attend Stripe capture error: #{e.message}")
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
      @appointment.update!(status: "confirmed", attended_at: nil)
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
    # Parâmetros:
    #   service_id, scheduled_at (HH:MM), walk_in_name, price_override
    #   force (bool) — se true, ignora a validação de capacidade. O front passa
    #     isso depois que o dono confirma "sim, quero encaixar mesmo estando
    #     cheio". Sem force, retornamos 409 com os números para o app exibir o
    #     aviso e pedir confirmação.
    def walk_in
      car_wash = current_car_wash
      return render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      service = car_wash.services.find_by(id: params[:service_id])
      return render json: { error: "Serviço não encontrado." }, status: :not_found unless service

      time_str     = params[:scheduled_at].presence || Time.current.strftime("%H:%M")
      hour, minute = time_str.split(":").map(&:to_i)
      scheduled_at = Time.current.beginning_of_day + hour.hours + minute.minutes
      price        = params[:price_override].present? ? params[:price_override].to_f : nil
      force        = ActiveModel::Type::Boolean.new.cast(params[:force])

      # Pré-checagem de capacidade: usa pico de concorrência (sweep) — soma
      # direta de overlap conta atendimentos sequenciais que rodam back-to-back
      # como simultâneos, gerando falso "cheio".
      unless force
        cap          = [car_wash.capacity_per_slot.to_i, 1].max
        duration_min = service.duration.to_i
        if duration_min > 0
          end_at = scheduled_at + duration_min.minutes
          peak = Appointment.peak_concurrency_during(
            car_wash: car_wash,
            start_at: scheduled_at,
            end_at:   end_at
          )
          if peak + 1 > cap
            render json: {
              error:    "Capacidade excedida",
              warning:  "Capacidade excedida",
              overlap:  peak,
              capacity: cap,
              message:  "Neste horário a capacidade ficaria em #{peak + 1}/#{cap} simultâneos durante a janela. Encaixar mesmo assim?"
            }, status: :conflict
            return
          end
        end
      end

      appointment = car_wash.appointments.build(
        user:           nil,
        service:        service,
        scheduled_at:   scheduled_at,
        status:         "attended",
        walk_in:        true,
        walk_in_name:   params[:walk_in_name].presence || "Avulso",
        price_override: price
      )
      # Walk-in sempre pula a validação de capacidade do model — a decisão
      # foi feita pelo dono/atendente presencialmente (com ou sem override).
      appointment.skip_capacity_check = true

      if appointment.save
        render json: { ok: true }.merge(serialize_appointment(appointment))
      else
        render json: { error: appointment.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    # PATCH /owner/checkins/:id/cancel
    def cancel
      reason = params[:reason].to_s.strip.presence

      if @appointment.disponivel?
        render json: { error: "Agendamentos Disponível não podem ser cancelados por aqui. Entre em contato com o suporte." }, status: :unprocessable_entity
        return
      end

      # Walk-ins nascem com status "attended" (a cobrança/lavagem foi
      # registrada na hora). Permitimos cancelar walk-in caso o dono
      # tenha registrado errado. Para appointments regulares "attended"
      # significa serviço concluído e cobrado — bloqueio mantido.
      if @appointment.status == "attended" && !@appointment.walk_in?
        render json: { error: "Não é possível cancelar um agendamento já finalizado." }, status: :unprocessable_entity
        return
      end

      if @appointment.status == "cancelled"
        render json: { error: "Este agendamento já está cancelado." }, status: :unprocessable_entity
        return
      end

      @appointment.update_columns(
        status:               "cancelled",
        cancelled_by_id:      current_user.id,
        cancelled_by_role:    current_user.role,
        cancellation_reason:  reason,
        updated_at:           Time.current
      )

      # Notificação in-app automática (updated_at atualizado acima)
      # Email + push apenas se o agendamento tiver usuário cadastrado
      if @appointment.user.present?
        begin
          AppointmentMailer.owner_cancellation(@appointment).deliver_now
        rescue => e
          Rails.logger.error("[CheckinsController#cancel] Email error: #{e.message}")
        end

        begin
          shop     = @appointment.car_wash&.name || "o lava-rápido"
          svc      = @appointment.service&.title || "seu atendimento"
          when_str = @appointment.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m às %H:%M")

          body  = "#{svc} em #{when_str}."
          body << " #{reason}." if reason.present?
          body << " Abra o app para escolher um novo horário."

          ExpoPushNotifier.new.notify_user(
            @appointment.user,
            title: "#{shop} cancelou sua reserva",
            body:  body,
            data:  {
              type:           "appointment_cancelled",
              appointment_id: @appointment.id,
            }
          )
        rescue => e
          Rails.logger.error("[CheckinsController#cancel] Push error: #{e.message}")
        end
      end

      render json: { ok: true }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
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

    def serialize_appointment(a, loyalty = nil, loyalty_counts = {})
      phone_last4 = nil
      vehicle     = nil
      loyalty_data = nil

      if a.user.present?
        phone       = a.user.phone.to_s.gsub(/\D/, '')
        phone_last4 = phone.length >= 4 ? phone.last(4) : nil
        vehicle     = a.user.vehicle_model.presence
        # Sobrescreve display_client com primeiro nome real
        first_name  = (a.user.full_name.presence || a.user.email.split("@").first).split.first.capitalize

        if loyalty && a.user_id.present?
          base_visits = loyalty_counts[a.user_id].to_i
          goal        = loyalty.visits_required
          # Para agendamentos ainda não finalizados, projeta +1 (igual à visão do cliente)
          proj_visits  = a.status == "attended" ? base_visits : base_visits + 1
          proj_cycle   = proj_visits % goal
          milestone    = proj_cycle == 0
          filled       = milestone ? goal : proj_cycle
          loyalty_data = {
            visits:    proj_visits,
            goal:      goal,
            filled:    filled,
            milestone: milestone,
            reward:    loyalty.reward_description
          }
        end
      end

      show_code = a.scheduled_at <= Time.current + 5.minutes &&
                  a.scheduled_at >= Time.current - 30.minutes &&
                  a.status == "confirmed"

      is_disponivel    = a.disponivel? rescue false
      prepayment       = is_disponivel ? a.prepayment_amount.to_f : 0
      remaining_amount = is_disponivel ? (a.effective_price - prepayment).round(2) : nil

      {
        id:               a.id,
        date:             a.scheduled_at.strftime("%Y-%m-%d"),
        time:             a.scheduled_at.strftime("%H:%M"),
        scheduled_at:     a.scheduled_at.iso8601,
        duration:         a.service.duration.to_i,
        client:           a.walk_in? ? (a.walk_in_name.presence || "Avulso") : first_name,
        service:          a.service.title,
        service_id:       a.service_id,
        price:            a.effective_price,
        price_original:   a.service.price.to_f,
        price_overridden: a.price_override.present?,
        walk_in:          a.walk_in?,
        status:           a.status,
        status_label:     status_label(a.status),
        status_color:     status_color(a.status),
        phone_last4:      phone_last4,
        vehicle:          vehicle,
        show_code:        show_code,
        is_disponivel:    is_disponivel,
        prepayment_amount: prepayment,
        remaining_amount:  remaining_amount,
        loyalty:          loyalty_data
      }
    end

    def status_label(status)
      { "confirmed" => "Aguardando", "pending_acceptance" => "Aguardando aceite",
        "attended" => "Compareceu", "no_show" => "Não veio", "rejected" => "Recusado" }[status] || status
    end

    def status_color(status)
      { "confirmed" => "yellow", "pending_acceptance" => "yellow",
        "attended" => "green", "no_show" => "red", "rejected" => "red" }[status] || "gray"
    end
  end
end
