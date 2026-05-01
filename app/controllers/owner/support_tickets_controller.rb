module Owner
  class SupportTicketsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant

    def index
      tickets = current_user.support_tickets.recent
      render json: tickets.map { |t|
        {
          id:              t.id,
          category:        t.category,
          status:          t.status,
          created_at:      t.created_at.strftime("%d/%m %H:%M"),
          updated_at:      t.updated_at.strftime("%d/%m %H:%M"),
          messages:        t.messages.chronological.map { |m|
            {
              body:       m.body,
              from_admin: m.from_admin?,
              author:     m.from_admin? ? "Suporte Loov" : current_user.full_name&.split&.first || "Você",
              created_at: m.created_at.strftime("%d/%m %H:%M")
            }
          },
          agent_draft:      t.agent_draft,
          agent_drafted_at: t.agent_drafted_at&.strftime("%d/%m %H:%M"),
          agent_sent:       t.agent_sent
        }
      }
    end

    def create
      ticket = current_user.support_tickets.build(
        category:    params[:category],
        status:      "open",
        description: params[:description]
      )

      # Associa ao lava-rápido do owner se existir
      ticket.car_wash = current_user.car_washes.first

      unless ticket.save
        render json: { ok: false, error: ticket.errors.full_messages.join(", ") }, status: :unprocessable_entity
        return
      end

      # Cria mensagem inicial com a descrição
      ticket.messages.create!(
        user:       current_user,
        body:       params[:description],
        from_admin: false
      )

      # ── Dispara agente autônomo imediatamente ─────────────────────────────
      # Para categorias de cancelamento/disponível, age sem esperar admin
      begin
        service = SupportAgentService.new(ticket)
        result  = service.run
        Rails.logger.info("[SupportTickets] Agente rodou no ticket ##{ticket.id}: #{result.inspect}")
      rescue => e
        Rails.logger.error("[SupportTickets] Erro ao rodar agente no ticket ##{ticket.id}: #{e.message}")
      end

      render json: { ok: true, ticket: serialize_ticket(ticket.reload) }
    end

    def message
      ticket = current_user.support_tickets.find(params[:id])
      ticket.messages.create!(user: current_user, body: params[:body], from_admin: false)
      ticket.update_columns(status: "in_progress", updated_at: Time.current)

      # Re-dispara agente após nova mensagem do owner
      begin
        service = SupportAgentService.new(ticket.reload)
        service.run
      rescue => e
        Rails.logger.error("[SupportTickets] Erro agente resposta ticket ##{ticket.id}: #{e.message}")
      end

      render json: { ok: true, ticket: serialize_ticket(ticket.reload) }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Ticket não encontrado." }, status: :not_found
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def close
      ticket = current_user.support_tickets.find(params[:id])
      ticket.update_columns(status: "resolved", resolved_at: Time.current, updated_at: Time.current)
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Ticket não encontrado." }, status: :not_found
    end

    private

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { ok: false, error: "Acesso negado." }, status: :forbidden
      end
    end

    def serialize_ticket(t)
      {
        id:         t.id,
        category:   t.category,
        status:     t.status,
        created_at: t.created_at.strftime("%d/%m %H:%M"),
        messages:   t.messages.chronological.map { |m|
          {
            body:       m.body,
            from_admin: m.from_admin?,
            author:     m.from_admin? ? "Suporte Loov" : current_user.full_name&.split&.first || "Você",
            created_at: m.created_at.strftime("%d/%m %H:%M")
          }
        },
        agent_draft:      t.agent_draft,
        agent_drafted_at: t.agent_drafted_at&.strftime("%d/%m %H:%M"),
        agent_sent:       t.agent_sent
      }
    end
  end
end
