# Rascunho da IA pedido pelo painel admin, fora da requisição (a chamada à IA
# pode passar do limite de 15 s do rack-timeout). O painel recarrega e mostra
# o rascunho no card do chamado.
class RascunhoAdminJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = SupportTicket.find_by(id: ticket_id)
    SupportAgentService.new(ticket).rascunho_para_admin if ticket
  end
end
