module Admin
  class SupportTicketsController < Admin::BaseController

    def index
      tickets = SupportTicket.all.order(updated_at: :desc)

      tickets = tickets.where(status: params[:status]) if params[:status].present?

      users     = User.where(id: tickets.map(&:user_id).uniq).index_by(&:id)
      car_washes = CarWash.where(id: users.values.map { |u| u.car_washes.first&.id }.compact).index_by(&:id)

      render json: tickets.map { |t|
        user     = users[t.user_id]
        car_wash = user&.car_washes&.first
        messages = t.messages.chronological.map do |m|
          {
            id:         m.id,
            body:       m.body,
            from_admin: m.from_admin,
            author:     m.from_admin? ? "Loov" : (user&.email&.split("@")&.first&.capitalize || "Owner"),
            created_at: m.created_at.strftime("%d/%m %H:%M")
          }
        end

        {
          id:               t.id,
          category:         t.category,
          status:           t.status,
          created_at:       t.created_at.strftime("%d/%m/%Y %H:%M"),
          updated_at:       t.updated_at.strftime("%d/%m/%Y %H:%M"),
          owner_email:      user&.email,
          owner_name:       user&.email&.split("@")&.first&.capitalize,
          car_wash_name:    car_wash&.name,
          messages:         messages,
          message_count:    messages.count,
          # Campos do agente autônomo
          agent_draft:      t.agent_draft,
          agent_drafted_at: t.agent_drafted_at&.strftime("%d/%m %H:%M"),
          agent_sent:       t.agent_sent
        }
      }
    end

    def message
      ticket = SupportTicket.find(params[:id])
      ticket.messages.create!(
        user:       current_user,
        body:       params[:body],
        from_admin: true
      )
      ticket.update_columns(status: "in_progress", updated_at: Time.current)
      render json: { ok: true }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def resolve
      ticket = SupportTicket.find(params[:id])
      ticket.update_columns(status: "resolved", resolved_at: Time.current, updated_at: Time.current)
      render json: { ok: true, message: "Ticket ##{ticket.id} resolvido." }
    end

    def reopen
      ticket = SupportTicket.find(params[:id])
      ticket.update_columns(status: "open", resolved_at: nil, updated_at: Time.current)
      render json: { ok: true, message: "Ticket ##{ticket.id} reaberto." }
    end

    # Aprova o rascunho do agente e envia como resposta oficial
    def approve_draft
      ticket = SupportTicket.find(params[:id])

      # Permite editar o rascunho antes de aprovar
      custom_body = params[:body].presence

      service = SupportAgentService.new(ticket)
      success = service.approve_and_send!(current_user, custom_body)

      if success
        render json: { ok: true, message: "Rascunho enviado como resposta oficial." }
      else
        render json: { error: "Não foi possível enviar o rascunho." }, status: :unprocessable_entity
      end
    end

    # Descarta o rascunho do agente (admin vai responder manualmente)
    def discard_draft
      ticket = SupportTicket.find(params[:id])
      ticket.update_columns(agent_draft: nil, agent_drafted_at: nil)
      render json: { ok: true }
    end

    # Dispara o agente manualmente para um ticket específico
    def run_agent
      ticket = SupportTicket.find(params[:id])
      service = SupportAgentService.new(ticket)
      result  = service.generate_draft

      if result.nil?
        render json: { ok: false, message: "Agente não conseguiu gerar rascunho." }
      elsif result[:escalate]
        render json: { ok: false, escalate: true, message: "Agente indica escalação: #{result[:reason]}" }
      else
        render json: { ok: true, draft: ticket.reload.agent_draft }
      end
    end

  end
end
