module Owner
  class MessagesController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :set_car_wash

    # GET /owner/messages — página de Mensagens no site, com os clientes de
    # hoje e as últimas enviadas embutidos (o app usa clients_today + create).
    def index
      @clients_json = clients_today_list
      @sent_json = OwnerMessage.where(car_wash: @car_wash).includes(:recipient).order(created_at: :desc).limit(8).map { |m| serialize_sent(m) }
    end

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

      render json: { ok: true, message_id: msg.id, message: serialize_sent(msg) }
    end

    # GET /owner/messages/clients_today
    # Retorna clientes com agendamento confirmado hoje (para o select do modal)
    def clients_today
      render json: clients_today_list
    end

    private

    def clients_today_list
      today = Time.current.beginning_of_day..Time.current.end_of_day
      appointments = @car_wash.appointments
        .where(scheduled_at: today)
        .where(status: %w[confirmed attended pending])
        .where.not(user_id: nil)
        .where(walk_in: false)
        .includes(:user)
        .order(:scheduled_at)

      appointments.map do |a|
        first_name = (a.user.full_name.presence || a.user.email).split.first
        time       = a.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
        { id: a.user_id, appointment_id: a.id, name: "#{first_name} · #{time}" }
      end
    end

    def serialize_sent(m)
      to = m.target == "user" && m.recipient ? (m.recipient.full_name.presence || m.recipient.email).split.first : nil
      { id: m.id, body: m.body, target: m.target, to: to, at: m.created_at.iso8601 }
    end

    def set_car_wash
      @car_wash = current_car_wash
      return if @car_wash
      return redirect_to(root_path) if request.format.html?
      render json: { ok: false, error: "Lava-rápido não encontrado." }, status: :not_found
    end

    def ensure_owner_or_attendant
      return if current_user&.owner? || current_user&.attendant?
      return redirect_to(root_path) if request.format.html?
      render json: { ok: false, error: "Acesso negado." }, status: :forbidden
    end
  end
end
