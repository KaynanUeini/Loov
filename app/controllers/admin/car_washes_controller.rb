module Admin
  class CarWashesController < Admin::BaseController
    def index
      car_washes = CarWash.all.order(created_at: :desc)
      car_washes = car_washes.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?

      owners = User.where(id: car_washes.map(&:user_id).uniq).index_by(&:id)

      render json: car_washes.map { |cw|
        owner = owners[cw.user_id]
        {
          id:           cw.id,
          name:         cw.name,
          owner:        owner&.display_name || owner&.email&.split("@")&.first&.capitalize,
          owner_email:  owner&.email,
          active:       cw.active,
          services:     cw.services.count,
          appointments: cw.appointments.count,
          revenue:      cw.appointments.where(status: "attended").joins(:service).sum("services.price").to_f
        }
      }
    end

    def show
      cw    = CarWash.find(params[:id])
      owner = cw.user
      reviews = cw.reviews

      render json: {
        id:                 cw.id,
        name:               cw.name,
        address:            cw.address,
        active:             cw.active,
        owner:              owner&.display_name || owner&.email&.split("@")&.first&.capitalize,
        owner_email:        owner&.email,
        avg_rating:         reviews.any? ? reviews.average(:rating).to_f.round(1) : nil,
        review_count:       reviews.count,
        total_appointments: cw.appointments.count,
        total_revenue:      cw.appointments.where(status: "attended").joins(:service).sum("services.price").to_f
      }
    end

    def activate
      cw = CarWash.find(params[:id])
      cw.update!(active: true)
      render json: { ok: true, message: "#{cw.name} ativado." }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def deactivate
      cw = CarWash.find(params[:id])
      cw.update!(active: false)
      render json: { ok: true, message: "#{cw.name} desativado." }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
