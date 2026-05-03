module Owner
  class ClosuresController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant, only: [:index]
    before_action :ensure_owner,              only: [:create, :destroy]

    # GET /owner/closures — lista fechamentos do car_wash do user (owner ou
    # atendente vinculado).
    def index
      car_wash = current_user.linked_car_wash
      return render json: [] unless car_wash

      closures = car_wash.car_wash_closures.upcoming_or_active.map do |c|
        {
          id:         c.id,
          start_date: c.start_date.iso8601,
          end_date:   c.end_date.iso8601,
          reason:     c.reason.to_s,
          period:     c.display_period,
          single_day: c.single_day?,
        }
      end
      render json: closures
    end

    def create
      cw_id    = params.dig(:closure, :car_wash_id)
      car_wash = if cw_id.present?
        current_user.car_washes.find(cw_id)
      else
        # Mobile app não manda car_wash_id — usa o linked.
        current_user.linked_car_wash
      end
      return render json: { ok: false, error: "Lava-rápido não encontrado." }, status: :not_found unless car_wash

      closure = car_wash.car_wash_closures.build(closure_params)

      if closure.save
        # Cancela agendamentos que caem dentro do fechamento
        cancelled_count = cancel_appointments_in_closure(car_wash, closure)

        render json: {
          ok:               true,
          id:               closure.id,
          period:           closure.display_period,
          reason:           closure.reason.presence || "Fechamento",
          cancelled_count:  cancelled_count
        }
      else
        render json: { ok: false, errors: closure.errors.full_messages }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Lava-rápido não encontrado." }, status: :not_found
    end

    def destroy
      closure  = CarWashClosure.find(params[:id])
      car_wash = current_user.car_washes.find(closure.car_wash_id)
      car_wash.car_wash_closures.find(params[:id]).destroy
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Não encontrado." }, status: :not_found
    end

    private

    def ensure_owner
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end

    def ensure_owner_or_attendant
      return if current_user&.owner? || current_user&.attendant?
      render json: { error: "Acesso negado." }, status: :forbidden
    end

    def closure_params
      params.require(:closure).permit(:start_date, :end_date, :reason)
    end

    def cancel_appointments_in_closure(car_wash, closure)
      # IMPORTANTE: Time.zone está configurado pra "America/Sao_Paulo"
      # (config/application.rb), então .in_time_zone retorna corretamente
      # o início/fim do dia em SP, e o Rails converte pra UTC ao comparar
      # com scheduled_at (stored como UTC). Isso evita o bug do timezone
      # double-conversion que ocorre com `AT TIME ZONE` em coluna sem TZ.
      range_start = closure.start_date.in_time_zone.beginning_of_day
      range_end   = closure.end_date.in_time_zone.end_of_day

      affected = car_wash.appointments
        .where(status: %w[confirmed pending_acceptance])
        .where(scheduled_at: range_start..range_end)
        .includes(:user, :service, :car_wash)

      Rails.logger.info(
        "[Closure ##{closure.id}] car_wash=#{car_wash.id} " \
        "period=#{closure.start_date}..#{closure.end_date} " \
        "range=#{range_start.iso8601}..#{range_end.iso8601} " \
        "affected_count=#{affected.size} ids=#{affected.map(&:id).inspect}"
      )

      reason_text = closure.reason.presence || "lava-rápido fechado"
      period_str  = closure.display_period

      count = 0
      affected.each do |appointment|
        appointment.update_columns(
          status:              "cancelled",
          cancelled_by_role:   "closure",
          cancellation_reason: "Lava-rápido fechado em #{period_str}#{reason_text.present? ? " (#{reason_text})" : ''}",
          updated_at:          Time.current,
        )

        # E-mail
        begin
          AppointmentMailer.closure_cancellation(appointment, closure).deliver_now
        rescue => e
          Rails.logger.error("[ClosuresController] Erro email appt ##{appointment.id}: #{e.message}")
        end

        # Push pro cliente — best-effort
        if appointment.user.present?
          begin
            shop_name = appointment.car_wash&.name || "Lava-rápido"
            svc_title = appointment.service&.title || "Serviço"
            when_str  = appointment.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m às %H:%M")
            ExpoPushNotifier.new.notify_user(
              appointment.user,
              title: "#{shop_name} cancelou sua reserva",
              body:  "#{svc_title} em #{when_str} foi cancelado: #{reason_text}.",
              data:  {
                type:           "appointment_cancelled",
                appointment_id: appointment.id,
                car_wash_id:    appointment.car_wash_id,
                reason:         "closure",
              }
            )
          rescue => e
            Rails.logger.error("[ClosuresController] Push falhou ##{appointment.id}: #{e.message}")
          end
        end

        count += 1
      end
      count
    end
  end
end
