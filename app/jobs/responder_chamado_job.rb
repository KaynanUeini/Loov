# Resposta do agente de suporte FORA da requisição que abriu (ou respondeu) o
# chamado. Dentro dela, a chamada à IA — um prompt grande, de 5 a 20 s — batia
# no limite do rack-timeout (15 s) e o app recebia "Internal Server Error"
# mesmo com o chamado salvo. Agora a pessoa vê a própria mensagem na hora e a
# resposta chega alguns segundos depois (a tela de suporte atualiza sozinha).
class ResponderChamadoJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = SupportTicket.find_by(id: ticket_id)
    return unless ticket
    result = SupportAgentService.new(ticket).run
    Rails.logger.info("[ResponderChamadoJob] ticket ##{ticket_id}: #{result.inspect}")
  rescue => e
    Rails.logger.error("[ResponderChamadoJob] ticket ##{ticket_id}: #{e.class}: #{e.message}")
  end
end
