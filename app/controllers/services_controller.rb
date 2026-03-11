class ServicesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_car_wash
  before_action :authorize_user
  before_action :set_service, only: [:edit, :update]

  def new
    @service = @car_wash.services.new
  end

  def create
    @service = @car_wash.services.new(service_params)
    if @service.save
      redirect_to @car_wash, notice: "Serviço criado com sucesso!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to @car_wash, notice: "Serviço atualizado com sucesso!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_car_wash
    @car_wash = CarWash.find(params[:car_wash_id])
  end

  def set_service
    @service = @car_wash.services.find(params[:id])
  end

  def service_params
    params.require(:service).permit(:title, :description, :price, :duration)
  end

  def authorize_user
    unless current_user.car_wash == @car_wash
      redirect_to root_path, alert: 'Ação não autorizada.'
    end
  end
end
