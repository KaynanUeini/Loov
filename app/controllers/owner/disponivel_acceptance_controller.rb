module Owner
  class DisponivelAcceptanceController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :set_car_wash
    before_action :expire_stale_acceptances!
    before_action :set_appointment, only: [:show, :accept, :reject]

    # GET /owner/disponivel_acceptance
    # Lista agendamentos disponíveis aguardando aceite (para polling do painel)
    def index
      @pending = Appointment
        .where(car_wash_id: visible_car_wash_ids)
        .disponivel
        .pending_acceptance
        .where("acceptance_expires_at > ?", Time.current)
        .includes(:user, :service, :car_wash)
        .order(:acceptance_expires_at)

      render json: @pending.map { |a| serialize(a) }
    end

    # GET /owner/disponivel_acceptance/:id (JSON)
    # Detalhes de um pedido específico — para o countdown individual
    def show
      render json: serialize(@appointment)
    end

    # PATCH /owner/disponivel_acceptance/:id/accept
    def accept
      if @appointment.acceptance_expired?
        render json: { error: "O tempo de aceite expirou." }, status: :unprocessable_entity
        return
      end

      stripe_service = StripeService.new

      if @appointment.accept!(stripe_service)
        render json: {
          ok:      true,
          message: "Agendamento aceito e pagamento capturado.",
          appointment: serialize(@appointment.reload)
        }
      else
        render json: { error: "Não foi possível aceitar o agendamento." }, status: :unprocessable_entity
      end
    end

    # PATCH /owner/disponivel_acceptance/:id/reject
    def reject
      stripe_service = StripeService.new

      if @appointment.reject!(stripe_service)
        render json: {
          ok:      true,
          message: "Agendamento recusado. Pagamento não realizado."
        }
      else
        render json: { error: "Não foi possível recusar o agendamento." }, status: :unprocessable_entity
      end
    end

    private

    def set_car_wash
      @car_wash = current_car_wash
    end

    # Todos os lava-rápidos que este usuário opera. O dono pode ter mais de um
    # (o cadastro nunca impediu), mas current_car_wash resolve pra
    # car_washes.first — então uma reserva feita no segundo ficava invisível no
    # painel, sem erro nenhum, como se o cliente nunca tivesse pedido.
    def visible_car_wash_ids
      return current_user.car_washes.pluck(:id) if current_user.owner?
      [current_car_wash&.id].compact
    end

    def set_appointment
      @appointment = Appointment
        .where(car_wash_id: visible_car_wash_ids)
        .disponivel
        .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Agendamento não encontrado." }, status: :not_found
    end

    # Delega para o método centralizado (throttled) no Appointment.
    def expire_stale_acceptances!
      Appointment.expire_stale_disponivel_acceptances!
    end

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { error: "Acesso negado." }, status: :forbidden
      end
    end

    def serialize(appointment)
      {
        id:             appointment.id,
        status:         appointment.status,
        seconds_left:   appointment.seconds_until_expiry,
        expires_at:     appointment.acceptance_expires_at&.iso8601,
        client_name:    appointment.display_client,
        # Qual unidade recebeu o pedido: sem isso, o dono com mais de um
        # lava-rápido não sabe pra onde o cliente está indo.
        car_wash_id:    appointment.car_wash_id,
        car_wash_name:  appointment.car_wash&.name,
        service_id:     appointment.service_id,
        service_name:   appointment.service.title,
        service_price:  appointment.effective_price,
        prepayment:     appointment.prepayment_amount,
        commission:     appointment.commission_amount,
        owner_net:      appointment.owner_prepayment_net,
        scheduled_at:   appointment.scheduled_at.strftime("%H:%M"),
        scheduled_date: appointment.scheduled_at.strftime("%d/%m/%Y")
      }
    end
  end
end
