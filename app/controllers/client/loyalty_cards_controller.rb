module Client
  # GET /client/loyalty_cards
  # Retorna os programas de fidelidade dos lava-rápidos que o cliente já
  # visitou ao menos 1 vez (depois do programa ter sido criado). Cards sem
  # visitas ainda não aparecem — o cliente só começa a ter um carimbo
  # quando faz a primeira lavagem no local com programa ativo.
  class LoyaltyCardsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    def index
      programs = LoyaltyProgram.where(active: true).includes(:car_wash)

      cards = programs.map { |lp|
        visit_count = current_user.appointments
          .where(car_wash_id: lp.car_wash_id, status: "attended")
          .where("scheduled_at >= ?", lp.created_at)
          .count

        next nil if visit_count.zero?  # só mostra quando tem ao menos 1 visita

        goal       = lp.visits_required
        proj_cycle = visit_count % goal
        milestone  = proj_cycle == 0
        filled     = milestone ? goal : proj_cycle

        {
          car_wash_id:        lp.car_wash_id,
          car_wash_name:      lp.car_wash.name,
          reward_description: lp.reward_description,
          visits_required:    goal,
          visits_total:       visit_count,
          filled:             filled,
          milestone:          milestone
        }
      }.compact

      render json: cards
    end

    private

    def ensure_client
      return if current_user&.client?
      render json: { error: "Acesso negado." }, status: :forbidden
    end
  end
end
