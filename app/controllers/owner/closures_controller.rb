module Owner
  class ClosuresController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner

    def create
      car_wash = current_user.car_washes.find(params[:closure][:car_wash_id])
      closure  = car_wash.car_wash_closures.build(closure_params)

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

    def closure_params
      params.require(:closure).permit(:start_date, :end_date, :reason)
    end

    def cancel_appointments_in_closure(car_wash, closure)
      # Busca todos os agendamentos confirmados ou pendentes dentro do período
      affected = car_wash.appointments
        .where(status: %w[confirmed pending_acceptance])
        .where(
          "DATE(scheduled_at AT TIME ZONE 'America/Sao_Paulo') BETWEEN ? AND ?",
          closure.start_date,
          closure.end_date
        )

      count = 0
      affected.each do |appointment|
        appointment.update_columns(status: "cancelled", updated_at: Time.current)
        # Envia e-mail de cancelamento
        begin
          AppointmentMailer.closure_cancellation(appointment, closure).deliver_now
        rescue => e
          Rails.logger.error("[ClosuresController] Erro ao enviar e-mail para appointment ##{appointment.id}: #{e.message}")
        end
        count += 1
      end
      count
    end
  end
end
