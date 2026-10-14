module Client
  # GET  /client/tour       — { home: true } se o tour da home ainda deve aparecer
  # POST /client/tour/seen  — marca como visto (app e site compartilham)
  class ToursController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    def show
      render json: { home: current_user.mostrar_tour_home? }
    end

    def seen
      current_user.concluir_tour_home!
      render json: { ok: true }
    end

    private

    def ensure_client
      return if current_user&.client?
      render json: { error: "Acesso negado." }, status: :forbidden
    end
  end
end
