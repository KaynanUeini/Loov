module Owner
  class SupportTicketsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant

    def index
      tickets = current_user.support_tickets.recent.includes(:messages)
      render json: tickets.map { |t| serialize_ticket(t) }
    end

    # POST .../support_tickets/:id/seen — a pessoa abriu a conversa. Marca a
    # última resposta da Loov como vista (mesma chave da central de
    # notificações do dono), pra "Nova resposta" sumir no site e no app.
    def seen
      ticket = current_user.support_tickets.find(params[:id])
      last   = ticket.messages.chronological.last
      if last&.from_admin?
        nr = NotificationRead.find_or_initialize_by(user: current_user, key: chave_resposta(ticket, last))
        nr.read_at = Time.current
        nr.save!
      end
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Conversa não encontrada." }, status: :not_found
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

      responder_depois(ticket)
      render json: { ok: true, ticket: serialize_ticket(ticket.reload) }
    rescue => e
      Rails.logger.error("[SupportTickets#create] #{e.class}: #{e.message}")
      render json: { ok: false, error: "Não foi possível abrir o chamado agora. Tente de novo em instantes." },
             status: :internal_server_error
    end

    def message
      ticket = current_user.support_tickets.find(params[:id])
      ticket.messages.create!(user: current_user, body: params[:body], from_admin: false)
      ticket.update_columns(status: "in_progress", updated_at: Time.current)

      responder_depois(ticket)

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

    # O agente (IA) responde em segundo plano: ver ResponderChamadoJob.
    def responder_depois(ticket)
      ResponderChamadoJob.perform_later(ticket.id)
    rescue => e
      Rails.logger.error("[SupportTickets] agente não enfileirado ##{ticket.id}: #{e.message}")
    end

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { ok: false, error: "Acesso negado." }, status: :forbidden
      end
    end

    def chave_resposta(ticket, message)
      "support_reply-#{ticket.id}-#{message.id}"
    end

    def serialize_ticket(t)
      msgs = t.messages.sort_by(&:created_at)
      last = msgs.last
      @lidas ||= current_user.notification_reads.where("key LIKE 'support_reply-%'").pluck(:key).to_set
      {
        id:         t.id,
        category:   t.category,
        status:     t.status,
        created_at: t.created_at.strftime("%d/%m %H:%M"),
        updated_at: t.updated_at.strftime("%d/%m %H:%M"),
        # Resposta da Loov que a pessoa ainda não abriu (ver #seen).
        unread_reply: t.status != "resolved" && !!last&.from_admin? && !@lidas.include?(chave_resposta(t, last)),
        messages:   msgs.map { |m|
          {
            body:       m.body,
            from_admin: m.from_admin?,
            author:     m.from_admin? ? "Suporte Loov" : current_user.full_name&.split&.first || "Você",
            created_at: m.created_at.strftime("%d/%m %H:%M")
          }
        }
        # Sem agent_draft: é o rascunho interno da equipe (pode trazer notas
        # como "[Escalado: …]") e só o painel admin deve ver.
      }
    end
  end
end
