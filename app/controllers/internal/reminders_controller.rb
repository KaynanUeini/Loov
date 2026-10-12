module Internal
  # Gatilho do lembrete da véspera (e do aviso da análise de IA), chamado pelo GitHub Actions
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

      # Aviso da análise de IA pega carona no mesmo gatilho diário (só faz
      # algo no dia 15 e no último dia do mês). Os workflows do GitHub só são
      # editados pelo site, então um gatilho novo exigiria mexer lá.
      ia = begin
        AiInsightReminders.run!
      rescue => e
        Rails.logger.error("[Internal::Reminders] aviso de IA falhou: #{e.message}")
        { ai_reminders: "erro" }
      end
      render json: AppointmentReminders.run!.merge(ia)
    end
  end
end
