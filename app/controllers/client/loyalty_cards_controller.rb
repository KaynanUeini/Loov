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
      com_cartao = cards.map { |c| c[:car_wash_id] }
      # Depois de usar o vale, o cartão novo só aparece com o primeiro
      # carimbo — vazio não tem o que mostrar.
      cards = com_cartoes_completos(cards).reject { |c| c[:filled].zero? }

      respond_to do |format|
        format.html do
          @cards  = cards
          @nearby = programas_perto(com_cartao)
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

    # Cartão completo vira um cartão à parte, com o vale que ele deu, até o
    # vale ser usado; a visita seguinte já abre um cartão novo do mesmo
    # lava-rápido (antes o mesmo cartão só zerava e o vale "sumia" junto).
    # Enquanto a visita que completou é a última, o cartão do momento É o
    # completo — o novo começa na próxima visita.
    def com_cartoes_completos(cards)
      vales = LoyaltyReward.nao_usados.where(user_id: current_user.id)
                           .where("expires_at > ?", Time.current)
                           .includes(:car_wash, :appointment, :earned_appointment)
                           .order(created_at: :desc)
                           .group_by(&:car_wash_id)
      cards.flat_map do |c|
        vs = vales[c[:car_wash_id]] || []
        c[:card_key] = "cw-#{c[:car_wash_id]}"
        if c[:milestone] && vs.any?
          c[:reward] = vs.first.as_cliente
          vs = vs.drop(1)
        end
        completos = vs.map { |v| cartao_completo(c, v) }
        completos + [c]
      end
    end

    def cartao_completo(atual, vale)
      meta = atual[:visits_required]
      ganho = vale.earned_appointment
      visitas = current_user.appointments.where(car_wash_id: vale.car_wash_id, status: "attended")
                            .where("scheduled_at <= ?", ganho.scheduled_at).que_contam_carimbo
                            .includes(:service).order(scheduled_at: :desc).limit(meta)
      atual.merge(
        card_key:           "vale-#{vale.id}",
        completed:          true,
        reward_description: vale.description,
        filled:             meta,
        milestone:          true,
        reward:             vale.as_cliente,
        history:            visitas.map { |a| { at: (a.attended_at || a.scheduled_at)&.iso8601, service: a.service&.title } }
      )
    end

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
