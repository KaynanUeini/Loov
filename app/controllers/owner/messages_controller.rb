module Owner
  class MessagesController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :set_car_wash

    # POST /owner/messages
    def create
      target    = params[:target].to_s  # "all" | "user"
      body      = params[:body].to_s.strip
      recipient = target == "user" ? User.find_by(id: params[:recipient_id]) : nil

      if body.blank?
        render json: { ok: false, error: "A mensagem não pode estar vazia." }, status: :unprocessable_entity
        return
      end

      if body.length > 300
        render json: { ok: false, error: "Máximo de 300 caracteres." }, status: :unprocessable_entity
        return
      end

      if target == "user" && recipient.nil?
        render json: { ok: false, error: "Cliente não encontrado." }, status: :unprocessable_entity
        return
      end

      msg = OwnerMessage.create!(
        car_wash:  @car_wash,
        sender:    current_user,
        recipient: recipient,
        body:      body,
        target:    target == "user" ? "user" : "all"
      )

      render json: { ok: true, message_id: msg.id }
    end

    # GET /owner/messages/clients_today
    # Retorna clientes com agendamento confirmado hoje (para o select do modal)
    def clients_today
      today = Time.current.beginning_of_day..Time.current.end_of_day
      appointments = @car_wash.appointments
        .where(scheduled_at: today)
        .where(status: %w[confirmed attended pending])
        .where.not(user_id: nil)
        .where(walk_in: false)
        .includes(:user)
        .order(:scheduled_at)

      clients = appointments.map do |a|
        first_name = (a.user.full_name.presence || a.user.email).split.first
        time       = a.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
        { id: a.user_id, appointment_id: a.id, name: "#{first_name} · #{time}" }
      end

      render json: clients
    end

    private

    def set_car_wash
      @car_wash = current_car_wash
      render json: { ok: false, error: "Lava-rápido não encontrado." }, status: :not_found unless @car_wash
    end

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { ok: false, error: "Acesso negado." }, status: :forbidden
      end
    end
  end
end
