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

      car_wash_ids = list.map { |f| f.car_wash_id }
      rating_map = Review.where(car_wash_id: car_wash_ids)
                         .group(:car_wash_id)
                         .pluck(:car_wash_id, Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))
                         .each_with_object({}) { |(id, avg, count), h|
                           h[id] = { avg: avg.to_f.round(1), count: count.to_i }
                         }

      now_sp     = Time.current.in_time_zone("America/Sao_Paulo")
      now_min    = now_sp.hour * 60 + now_sp.min
      today_dow  = now_sp.wday

      render json: list.map { |f| serialize(f.car_wash, rating_map, today_dow, now_min) }
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

    def serialize(cw, rating_map = {}, today_dow = nil, now_min = nil)
      today_oh = today_dow ? cw.operating_hours.find { |oh| oh.day_of_week.to_i == today_dow } : nil
      open_now = false
      if today_oh && today_oh.opens_at && today_oh.closes_at && now_min
        opens  = today_oh.opens_at.hour  * 60 + today_oh.opens_at.min
        closes = today_oh.closes_at.hour * 60 + today_oh.closes_at.min
        open_now = now_min >= opens && now_min <= closes
      end

      rating = rating_map[cw.id] || { avg: 0.0, count: 0 }

      {
        id:            cw.id,
        name:          cw.name,
        address:       cw.address,
        logradouro:    cw.logradouro,
        bairro:        cw.bairro,
        cidade:        cw.cidade,
        uf:            cw.uf,
        rating_avg:    rating[:avg],
        reviews_count: rating[:count],
        open_now:      open_now,
        operating_hours: cw.operating_hours.sort_by { |oh| oh.day_of_week.to_i }.map { |oh|
          {
            day_of_week: oh.day_of_week,
            opens_at:    oh.opens_at&.strftime('%H:%M'),
            closes_at:   oh.closes_at&.strftime('%H:%M'),
          }
        },
        services: cw.services.order(:title).map { |s|
          { id: s.id, title: s.title, price: s.price.to_f, category: s.category }
        }
      }
    end
  end
end
