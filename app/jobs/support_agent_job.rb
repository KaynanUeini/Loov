class SupportAgentJob < ApplicationJob
  queue_as :default

  # Roda a cada hora via Sidekiq-Cron (configurar no config/schedule.rb ou initializer)
  # Processar tickets abertos sem resposta do admin há mais de 2h
  def perform
    Rails.logger.info("[SupportAgentJob] Iniciando verificação de tickets — #{Time.current}")

    eligible_tickets = find_eligible_tickets
    Rails.logger.info("[SupportAgentJob] #{eligible_tickets.count} ticket(s) elegíveis para rascunho")

    eligible_tickets.each do |ticket|
      process_ticket(ticket)
      # Pequena pausa entre chamadas para não sobrecarregar a API
      sleep(0.5)
    end

    Rails.logger.info("[SupportAgentJob] Concluído")
  end

  private

  def find_eligible_tickets
    SupportTicket
      .where(status: %w[open in_progress])
      .where(agent_sent: false)
      .where("support_tickets.created_at < ?", 2.hours.ago)
      .joins(:messages)
      .group("support_tickets.id")
      .having("MAX(CASE WHEN support_ticket_messages.from_admin = true THEN 1 ELSE 0 END) = 0")
      .includes(:messages, :user)
  end

  def process_ticket(ticket)
    Rails.logger.info("[SupportAgentJob] Processando ticket ##{ticket.id} — categoria: #{ticket.category}")

    service = SupportAgentService.new(ticket)
    result  = service.generate_draft

    if result.nil?
      Rails.logger.warn("[SupportAgentJob] Ticket ##{ticket.id} — sem rascunho gerado")
      return
    end

    if result[:escalate]
      Rails.logger.info("[SupportAgentJob] Ticket ##{ticket.id} — escalado para admin: #{result[:reason]}")
      # Aqui você pode futuramente enviar um email/notificação para o admin
      return
    end

    Rails.logger.info("[SupportAgentJob] Ticket ##{ticket.id} — rascunho gravado com sucesso")

  rescue => e
    Rails.logger.error("[SupportAgentJob] Erro ao processar ticket ##{ticket.id}: #{e.message}")
  end
end
