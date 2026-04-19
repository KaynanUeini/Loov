module Client
  class FavoritesController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    # GET /client/favorites
    def index
      list = current_user.favorite_car_washes
        .includes(car_wash: [:services, :operating_hours])
        .order(created_at: :desc)

      render json: list.map { |f| serialize(f.car_wash) }
    end

    # POST /client/favorites { car_wash_id }
    def create
      car_wash = CarWash.find(params[:car_wash_id])
      current_user.favorite_car_washes.find_or_create_by!(car_wash_id: car_wash.id)
      render json: { ok: true, favorited: true }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Lava-rápido não encontrado." }, status: :not_found
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # DELETE /client/favorites/:id  (id = car_wash_id for simplicity)
    def destroy
      fav = current_user.favorite_car_washes.find_by(car_wash_id: params[:id])
      fav&.destroy
      render json: { ok: true, favorited: false }
    end

    private

    def ensure_client
      return if current_user&.client?
      render json: { error: "Acesso negado." }, status: :forbidden
    end

    def serialize(cw)
      {
        id:         cw.id,
        name:       cw.name,
        address:    cw.address,
        logradouro: cw.logradouro,
        bairro:     cw.bairro,
        cidade:     cw.cidade,
        uf:         cw.uf,
        services: cw.services.order(:title).map { |s|
          { id: s.id, title: s.title, price: s.price.to_f, category: s.category }
        }
      }
    end
  end
end
