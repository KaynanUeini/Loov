module Owner
  class SupportTicketsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :set_ticket, only: [:message, :close]

    def index
      tickets = current_user.support_tickets.includes(:messages).recent
      render json: tickets.map { |t| serialize(t) }
    end

    def create
      open_ticket = current_user.support_tickets.pending.first
      if open_ticket
        render json: {
          ok: false,
          error: "Você já tem um chamado aberto (##{open_ticket.id}). Responda nele ou aguarde o encerramento para abrir um novo."
        }, status: :unprocessable_entity
        return
      end

      car_wash = current_user.owner? ? current_user.car_washes.first : current_car_wash

      ticket = current_user.support_tickets.build(
        category:    params[:category],
        description: params[:description],
        car_wash:    car_wash,
        status:      "open"
      )

      if ticket.save
        ticket.messages.create!(
          user:       current_user,
          body:       params[:description],
          from_admin: false
        )
        render json: { ok: true, ticket: serialize(ticket) }
      else
        render json: { ok: false, errors: ticket.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def message
      if @ticket.resolved?
        render json: { ok: false, error: "Este chamado já está encerrado." }, status: :unprocessable_entity
        return
      end

      body = params[:body].to_s.strip
      if body.blank?
        render json: { ok: false, error: "Mensagem não pode estar vazia." }, status: :unprocessable_entity
        return
      end

      @ticket.messages.create!(user: current_user, body: body, from_admin: false)
      @ticket.touch
      render json: { ok: true, ticket: serialize(@ticket.reload) }
    end

    def close
      if @ticket.resolved?
        render json: { ok: false, error: "Chamado já encerrado." }, status: :unprocessable_entity
        return
      end

      @ticket.update!(status: "resolved", resolved_at: Time.current)
      render json: { ok: true, message: "Chamado ##{@ticket.id} encerrado." }
    end

    private

    def set_ticket
      @ticket = current_user.support_tickets.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Chamado não encontrado." }, status: :not_found
    end

    def serialize(ticket)
      {
        id:           ticket.id,
        category:     ticket.category,
        description:  ticket.description,
        status:       ticket.status,
        status_label: ticket.status_label,
        car_wash:     ticket.car_wash&.name,
        created_at:   ticket.created_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m/%Y %H:%M"),
        messages:     ticket.messages.chronological.map { |m|
          {
            id:         m.id,
            body:       m.body,
            from_admin: m.from_admin?,
            author:     m.from_admin? ? "Suporte Loov" : m.user&.display_name,
            created_at: m.created_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m %H:%M")
          }
        }
      }
    end

    def ensure_owner_or_attendant
      unless current_user.owner? || current_user.attendant?
        render json: { error: "Acesso não autorizado." }, status: :forbidden
      end
    end
  end
end
