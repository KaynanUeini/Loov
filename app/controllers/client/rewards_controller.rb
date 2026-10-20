module Client
  # Vales de fidelidade do cliente (LoyaltyReward).
  #
  #   GET /client/rewards                — os vales disponíveis e reservados
  #   GET /client/rewards/preview        — o que o vale abate de um serviço,
  #       ?car_wash_id=&service_id=&kind=regular|disponivel
  #       (o resumo do agendamento e do Last Minute mostram antes de confirmar)
  class RewardsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    def index
      vales = LoyaltyReward.nao_usados.where(user_id: current_user.id)
                           .where("expires_at > ?", Time.current)
                           .includes(:car_wash, :appointment).order(:expires_at)
      render json: vales.map(&:as_cliente)
    end

    def preview
      car_wash = CarWash.find(params[:car_wash_id])
      service  = car_wash.services.find(params[:service_id])
      base     = params[:kind] == "disponivel" ? service.preco_last_minute : service.price.to_f
      vale     = LoyaltyReward.disponivel_para(current_user, car_wash)
      desconto = vale ? vale.desconto_para(service, base) : 0
      render json: {
        reward:   vale&.as_cliente,
        base:     base,
        discount: desconto,
        total:    (base - desconto).round(2)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Lava-rápido ou serviço não encontrado." }, status: :not_found
    end

    private

    def ensure_client
      return if current_user&.client?
      render json: { error: "Acesso negado." }, status: :forbidden
    end
  end
end
