# GET /rota?car_wash_id=..&lat=..&lng=.. (JSON)
# Rota de carro até o lava-rápido pro mapa do Agendado (RotaDeCarro). Só
# com login: é quem acabou de agendar, e cada chamada gasta cota.
class RotasController < ApplicationController
  before_action :authenticate_user!

  def show
    car_wash = CarWash.find(params[:car_wash_id])
    lat = Float(params[:lat], exception: false)
    lng = Float(params[:lng], exception: false)
    return head(:bad_request) unless lat && lng && lat.abs <= 90 && lng.abs <= 180

    rota = RotaDeCarro.para(car_wash, lat, lng)
    return head(:no_content) unless rota
    render json: rota
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
