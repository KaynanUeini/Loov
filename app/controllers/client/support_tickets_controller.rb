module Client
  # Chat de suporte do cliente: mesma conversa do dono (lista, abrir chamado,
  # responder, encerrar), mesmo JSON, só que liberado pra quem é cliente.
  # A diferença de comportamento — material de apoio próprio do cliente e sem
  # ações automáticas — fica no SupportAgentService.
  class SupportTicketsController < Owner::SupportTicketsController
    skip_before_action :ensure_owner_or_attendant
    before_action :ensure_client

    private

    def ensure_client
      unless current_user&.client?
        render json: { ok: false, error: "Acesso negado." }, status: :forbidden
      end
    end
  end
end
