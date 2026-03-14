class Owner::OnboardingController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_owner!

  def show
    redirect_to root_path if current_user.car_washes.any?
  end

  def save_car_wash
    address = [
      params.dig(:car_wash, :logradouro),
      params.dig(:car_wash, :numero),
      params.dig(:car_wash, :bairro),
      params.dig(:car_wash, :cidade),
      params.dig(:car_wash, :uf)
    ].select(&:present?).join(", ")

    @car_wash = current_user.car_washes.build(car_wash_params)
    @car_wash.address = address

    if @car_wash.save
      # Geocoding em background para não travar o wizard
      begin
        @car_wash.geocode
        @car_wash.save if @car_wash.latitude.present?
      rescue => e
        Rails.logger.warn("Geocoding falhou para #{@car_wash.name}: #{e.message}")
      end

      render json: { success: true, car_wash_id: @car_wash.id }
    else
      render json: { success: false, errors: @car_wash.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def save_hours
    @car_wash = current_user.car_washes.find(params[:car_wash_id])
    params[:hours].each do |day, times|
      next unless times[:enabled] == "1"
      hour = @car_wash.operating_hours.find_or_initialize_by(day_of_week: day.to_i)
      hour.update(
        opens_at: "#{times[:opens_at]}:00",
        closes_at: "#{times[:closes_at]}:00"
      )
    end
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, errors: ["Lava-rápido não encontrado"] }, status: :not_found
  end

  def save_services
    @car_wash = current_user.car_washes.find(params[:car_wash_id])
    params[:services].each do |_, service|
      next if service[:title].blank?
      @car_wash.services.create(
        title: service[:title].to_s.split.map(&:capitalize).join(" "),
        category: service[:category],
        price: service[:price].to_f,
        duration: service[:duration].to_i
      )
    end
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, errors: ["Lava-rápido não encontrado"] }, status: :not_found
  end

  private

  def ensure_owner!
    redirect_to root_path unless current_user.owner?
  end

  def car_wash_params
    params.require(:car_wash).permit(:name, :cep, :logradouro, :numero, :bairro, :cidade, :uf, :capacity_per_slot, :num_employees)
  end
end
