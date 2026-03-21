class ExpireDisponivelAcceptanceJob < ApplicationJob
  queue_as :default

  # Roda para um agendamento específico após 3 minutos do aceite
  # Agendado no momento da criação do agendamento disponível
  def perform(appointment_id)
    appointment = Appointment.find_by(id: appointment_id)
    return unless appointment.present?
    return unless appointment.pending_acceptance? && appointment.disponivel?

    # Só expira se o aceite ainda não aconteceu
    if appointment.acceptance_expired?
      Rails.logger.info("[ExpireDisponivel] Expirando appointment ##{appointment_id}")

      stripe_service = StripeService.new
      appointment.expire!(stripe_service)

      Rails.logger.info("[ExpireDisponivel] Appointment ##{appointment_id} expirado e estornado.")
    else
      Rails.logger.info("[ExpireDisponivel] Appointment ##{appointment_id} já foi aceito/rejeitado, nada a fazer.")
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("[ExpireDisponivel] Appointment ##{appointment_id} não encontrado.")
  end
end
