module Client
  # GET /client/loyalty_cards
  # Os programas de fidelidade dos lava-rápidos que o cliente já visitou ao
  # menos 1 vez (depois do programa ter sido criado). Cálculo do cartão em
  # LoyaltyProgram#cartao_para.
  class LoyaltyCardsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    # JSON (app): os cartões com ao menos uma visita (com histórico e
    # endereço a mais — o formato antigo continua igual).
    # HTML (site): a tela Fidelidade, porte da ClientFidelidadeScreen.
    def index
      cards = LoyaltyProgram.where(active: true).includes(:car_wash)
                            .map { |lp| lp.cartao_para(current_user, historico: true) }
                            .select { |c| c[:visits_total].positive? }

      respond_to do |format|
        format.html do
          @cards  = cards
          @nearby = programas_perto(cards.map { |c| c[:car_wash_id] })
        end
        format.json { render json: cards }
      end
    end

    # GET /client/loyalty_cards/nearby?latitude=&longitude=
    # Lava-rápidos com programa ativo onde o cliente ainda não tem cartão,
    # do mais perto pro mais longe (sem localização, os mais recentes).
    def nearby
      com_cartao = LoyaltyProgram.where(active: true).includes(:car_wash)
                                 .select { |lp| lp.cartao_para(current_user)[:visits_total].positive? }
                                 .map(&:car_wash_id)
      render json: programas_perto(com_cartao)
    end

    private

    PERTO_LIMITE = 10

    def programas_perto(excluir_ids)
      programas = LoyaltyProgram.where(active: true).where.not(car_wash_id: excluir_ids)
                                .includes(:car_wash).to_a
      lat = params[:latitude].presence&.to_f
      lng = params[:longitude].presence&.to_f

      itens = programas.map do |lp|
        cw   = lp.car_wash
        dist = cw.distance_to([lat, lng], :km)&.round(1) if lat && lng && cw.has_valid_coordinates?
        {
          car_wash_id:        cw.id,
          car_wash_name:      cw.name,
          address:            cw.endereco_curto,
          distance_km:        dist,
          visits_required:    lp.visits_required,
          reward_description: lp.reward_description,
          created_at:         lp.created_at
        }
      end
      itens.sort_by { |i| [i[:distance_km] || Float::INFINITY, -i[:created_at].to_i] }
           .first(PERTO_LIMITE)
           .map { |i| i.except(:created_at) }
    end

    def ensure_client
      return if current_user&.client?
      respond_to do |format|
        format.html { redirect_to root_path }
        format.json { render json: { error: "Acesso negado." }, status: :forbidden }
      end
    end
  end
end
