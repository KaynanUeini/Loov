class CarWashesController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_car_wash, only: %i[show manage update available_times]
  before_action :ensure_owner, only: %i[manage update]

  def index
    @car_washes = CarWash.all
    if params[:search].present?
      @car_washes = @car_washes.where("name ILIKE ? OR address ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
    end
    if params[:category].present?
      @car_washes = @car_washes.joins(:services).where(services: { category: params[:category] }).distinct
    end
    Rails.logger.debug "Car washes loaded: #{@car_washes.inspect}"
  end

  def show
    @services = @car_wash.services
    @appointment = Appointment.new(car_wash_id: @car_wash.id)
    Rails.logger.debug "Rendering car_washes/show.html.erb with car_wash: #{@car_wash.inspect}, services: #{@services.inspect}"
  end

  def new
    @car_wash = CarWash.new
  end

  def edit
  end

  def create
    @car_wash = CarWash.new(car_wash_params)
    @car_wash.user = current_user
    if @car_wash.save
      redirect_to @car_wash, notice: "Lava-rápido criado com sucesso!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    Rails.logger.debug "Received params: #{params.inspect}"
    Rails.logger.debug "Services attributes: #{params[:car_wash][:services_attributes].inspect if params[:car_wash][:services_attributes].present?}"
    Rails.logger.debug "Operating hours attributes: #{params[:car_wash][:operating_hours_attributes].inspect if params[:car_wash][:operating_hours_attributes].present?}"

    update_params = params.require(:car_wash).permit(
      :name,
      :address,
      :cep,
      :logradouro,
      :bairro,
      :cidade,
      :uf,
      :latitude,
      :longitude,
      :capacity_per_slot,
      operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
      services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
    )

    if update_params[:operating_hours_attributes].present?
      active_days = []
      update_params[:operating_hours_attributes].each do |index, attrs|
        next if attrs[:_destroy] == "1"
        active_days << attrs[:day_of_week].to_i
      end

      seen_days = []
      active_days.each do |day|
        if seen_days.include?(day)
          @car_wash.errors.add(:base, "Dia da semana já adicionado: #{OperatingHour.new(day_of_week: day).day_of_week_name}")
          Rails.logger.error "Validation failed: Duplicate day_of_week #{day}"
          render :manage, status: :unprocessable_entity
          return
        end
        seen_days << day
      end
    end

    if @car_wash.update(update_params)
      Rails.logger.info "Car wash updated successfully: #{@car_wash.inspect}"
      redirect_to manage_car_wash_path(@car_wash), notice: "Lava-rápido atualizado com sucesso!"
    else
      Rails.logger.error "Failed to update car wash: #{@car_wash.errors.full_messages.join(', ')}"
      @car_wash.operating_hours.build if @car_wash.operating_hours.empty?
      @car_wash.services.build if @car_wash.services.empty?
      render :manage, status: :unprocessable_entity
    end
  end

  def destroy
    @car_wash.destroy
    redirect_to car_washes_url, notice: "Lava-rápido excluído com sucesso!"
  end

  def manage
    @car_wash.operating_hours.build if @car_wash.operating_hours.empty?
    @car_wash.services.build if @car_wash.services.empty?
    Rails.logger.info "Rendering CarWashes#manage for car_wash_id=#{@car_wash.id}, user_id=#{current_user.id}"
  end

  def available_times
    Timeout.timeout(3) do
      begin
        date = Date.parse(params[:date])
      rescue ArgumentError, TypeError
        Rails.logger.error "Invalid date format: #{params[:date]}"
        render json: [], status: :bad_request
        return
      end

      begin
        service = Service.find(params[:service_id])
      rescue ActiveRecord::RecordNotFound
        Rails.logger.error "Service not found for ID: #{params[:service_id]}"
        render json: [], status: :not_found
        return
      end

      duration = params[:duration].to_i
      day_of_week = date.wday
      operating_hour = @car_wash.operating_hours.find_by(day_of_week: day_of_week)

      available_times = []
      if operating_hour
        opens_at = operating_hour.opens_at
        closes_at = operating_hour.closes_at
        opens_at_minutes  = (opens_at.hour * 60) + opens_at.min
        closes_at_minutes = (closes_at.hour * 60) + closes_at.min

        appointments = @car_wash.appointments.joins(:service).where(
          "DATE(scheduled_at) = ?", date
        ).select("appointments.scheduled_at, services.duration").to_a

        occupied_intervals = []
        appointments.each do |appt|
          appt_start = appt.scheduled_at.to_time
          appt_end   = appt_start + appt.duration.minutes
          appt_start_minutes = (appt_start.hour * 60) + appt_start.min
          appt_end_minutes   = (appt_end.hour * 60) + appt_end.min
          occupied_intervals << (appt_start_minutes..appt_end_minutes)
        end

        current_minutes = opens_at_minutes
        while current_minutes <= closes_at_minutes - duration
          time_end_minutes = current_minutes + duration
          available = occupied_intervals.none? { |i| current_minutes < i.end && time_end_minutes > i.begin }
          available_times << format("%02d:%02d", current_minutes / 60, current_minutes % 60) if available
          current_minutes += 10
        end
      end

      render json: available_times
    end
  rescue Timeout::Error
    Rails.logger.error "Timeout while generating available times"
    render json: [], status: :request_timeout
  end

  private

  def set_car_wash
    @car_wash = CarWash.find(params[:id] || params[:car_wash_id])
  end

  def ensure_owner
    unless current_user.owner? && @car_wash.user == current_user
      redirect_to car_washes_path, alert: "Acesso não autorizado."
    end
  end

  def car_wash_params
    params.require(:car_wash).permit(
      :name,
      :address,
      :cep,
      :logradouro,
      :bairro,
      :cidade,
      :uf,
      :latitude,
      :longitude,
      :capacity_per_slot,
      operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
      services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
    )
  end
end
