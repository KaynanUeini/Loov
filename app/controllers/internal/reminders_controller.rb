module Internal
  # Gatilho do lembrete da véspera, chamado pelo GitHub Actions
  # (.github/workflows/lembretes-vespera.yml).
  #
  # Herda de ActionController::Base, não de ApplicationController: não tem
  # usuário logado, e os filtros do app (Devise, onboarding de dono) não se
  # aplicam. A proteção é o segredo compartilhado em CRON_SECRET.
  class RemindersController < ActionController::Base
    skip_forgery_protection

    def create
      secret = ENV["CRON_SECRET"].to_s
      return head :service_unavailable if secret.empty?

      token = request.authorization.to_s.delete_prefix("Bearer ").strip
      return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(token, secret)

      render json: AppointmentReminders.run!
    end
  end
end
