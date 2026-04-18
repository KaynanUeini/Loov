module Owner
  class CarWashController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner
    before_action :set_car_wash

    def show
      render json: {
        id:                @car_wash.id,
        name:              @car_wash.name,
        cep:               @car_wash.cep,
        logradouro:        @car_wash.logradouro,
        bairro:            @car_wash.bairro,
        cidade:            @car_wash.cidade,
        uf:                @car_wash.uf,
        address:           @car_wash.address,
        capacity_per_slot: @car_wash.capacity_per_slot,
        latitude:          @car_wash.latitude,
        longitude:         @car_wash.longitude,
        operating_hours: @car_wash.operating_hours.order(:day_of_week).map { |oh|
          {
            id:          oh.id,
            day_of_week: oh.day_of_week,
            opens_at:    oh.opens_at&.strftime('%H:%M'),
            closes_at:   oh.closes_at&.strftime('%H:%M'),
          }
        },
        services: @car_wash.services.order(:title).map { |s|
          {
            id:          s.id,
            title:       s.title,
            category:    s.category,
            description: s.description,
            price:       s.price.to_f,
            duration:    s.duration,
          }
        }
      }
    end

    def update
      update_params = params.require(:car_wash).permit(
        :name, :cep, :logradouro, :bairro, :cidade, :uf, :address,
        :capacity_per_slot, :latitude, :longitude,
        operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
        services_attributes:        [:id, :title, :category, :description, :price, :duration, :_destroy]
      )

      if @car_wash.update(update_params)
        render json: { ok: true }
      else
        render json: { error: @car_wash.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    private

    def set_car_wash
      @car_wash = current_user.car_washes.first
      render json: { error: 'Lava-rápido não encontrado.' }, status: :not_found unless @car_wash
    end

    def ensure_owner
      render json: { error: 'Acesso negado.' }, status: :forbidden unless current_user&.owner?
    end
  end
end
