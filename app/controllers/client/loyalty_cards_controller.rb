module Client
  # GET /client/loyalty_cards
  # Os programas de fidelidade dos lava-rápidos que o cliente já visitou ao
  # menos 1 vez (depois do programa ter sido criado). Cálculo do cartão em
  # LoyaltyProgram#cartao_para.
  class LoyaltyCardsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    # JSON (app): os cartões com ao menos uma visita, como sempre.
    # HTML (site): a tela Fidelidade, porte da ClientFidelidadeScreen.
    def index
      cards = LoyaltyProgram.where(active: true).includes(:car_wash)
                            .map { |lp| lp.cartao_para(current_user) }
                            .select { |c| c[:visits_total].positive? }

      respond_to do |format|
        format.html { @cards = cards }
        format.json { render json: cards }
      end
    end

    private

    def ensure_client
      return if current_user&.client?
      respond_to do |format|
        format.html { redirect_to root_path }
        format.json { render json: { error: "Acesso negado." }, status: :forbidden }
      end
    end
  end
end
