class CarWashesController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_car_wash, only: %i[show manage update available_times]
  before_action :ensure_owner_or_attendant, only: [:manage]
  before_action :ensure_owner, only: [:update]

  def index
    @car_washes = CarWash.all

    if params[:search].present?
      @car_washes = @car_washes.where("name ILIKE ? OR address ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
    end

    if params[:group].present? && Service::GROUPS[params[:group]]
      group_categories = Service::GROUPS[params[:group]]

      if params[:service_title].present?
        @car_washes = @car_washes.joins(:services).where(services: { title: params[:service_title] }).distinct
      elsif params[:category].present? && group_categories.include?(params[:category])
        @car_washes = @car_washes.joins(:services).where(services: { category: params[:category] }).distinct
      else
        @car_washes = @car_washes.joins(:services).where(services: { category: group_categories }).distinct
      end
    end

    if params[:latitude].present? && params[:longitude].present?
      begin
        latitude  = params[:latitude].to_f
        longitude = params[:longitude].to_f
        with_coords    = @car_washes.select(&:has_valid_coordinates?).sort_by { |cw| cw.distance_to([latitude, longitude], :km) }
        without_coords = @car_washes.reject(&:has_valid_coordinates?)
        @car_washes    = with_coords + without_coords
      rescue => e
        Rails.logger.error("Erro ao calcular distância: #{e.message}")
      end
    end

    @groups = Service::GROUPS
    @selected_group         = params[:group]
    @selected_category      = params[:category]
    @selected_service_title = params[:service_title]

    if @selected_group == "Lavagem"
      @subcategories = Service.where(category: "Lavagem").distinct.pluck(:title).compact.sort
    elsif @selected_group.present? && Service::GROUPS[@selected_group]
      @subcategories = Service::GROUPS[@selected_group]
    else
      @subcategories = []
    end
  end

  def show
    @services    = @car_wash.services
    @appointment = Appointment.new(car_wash_id: @car_wash.id)
  end

  def new
    @car_wash = CarWash.new
  end

  def edit
  end

  def create
    @car_wash      = CarWash.new(car_wash_params)
    @car_wash.user = current_user
    if @car_wash.save
      redirect_to @car_wash, notice: "Lava-rápido criado com sucesso!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    # Atendente: cria pending change em vez de salvar direto
    if current_user.attendant?
      raw = params.require(:car_wash).permit(
        :name, :address, :cep, :logradouro, :bairro, :cidade, :uf,
        :latitude, :longitude, :capacity_per_slot,
        operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
        services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
      ).to_h

      PendingChange.create!(
        car_wash:    @car_wash,
        attendant:   current_user,
        change_type: "manage_car_wash",
        status:      "pending",
        description: "Alterações no gerenciamento do lava-rápido",
        payload:     { car_wash_params: raw }.to_json
      )

      redirect_to manage_car_wash_path(@car_wash),
        notice: "✅ Alterações enviadas para aprovação do proprietário."
      return
    end

    # Owner: salva direto
    update_params = params.require(:car_wash).permit(
      :name, :address, :cep, :logradouro, :bairro, :cidade, :uf,
      :latitude, :longitude, :capacity_per_slot,
      operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
      services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
    )

    if update_params[:operating_hours_attributes].present?
      seen_days = []
      update_params[:operating_hours_attributes].each do |_, attrs|
        next if attrs[:_destroy] == "1"
        day = attrs[:day_of_week].to_i
        if seen_days.include?(day)
          @car_wash.errors.add(:base, "Dia da semana já adicionado: #{OperatingHour.new(day_of_week: day).day_of_week_name}")
          render :manage, status: :unprocessable_entity and return
        end
        seen_days << day
      end
    end

    if @car_wash.update(update_params)
      redirect_to manage_car_wash_path(@car_wash), notice: "Lava-rápido atualizado com sucesso!"
    else
      @car_wash.operating_hours.build if @car_wash.operating_hours.empty?
      @car_wash.services.build if @car_wash.services.empty?
      render :manage, status: :unprocessable_entity
    end
  end

  def destroy
    @car_wash.destroy
    redirect_to root_path, notice: "Lava-rápido excluído com sucesso!"
  end

  def manage
    @is_attendant    = current_user.attendant?
    @pending_changes = @car_wash.pending_changes.pending if current_user.owner?
    @car_wash.operating_hours.build if @car_wash.operating_hours.empty?
    @car_wash.services.build if @car_wash.services.empty?
  end

  def available_times
    Timeout.timeout(3) do
      begin
        date = Date.parse(params[:date])
      rescue ArgumentError, TypeError
        render json: [], status: :bad_request and return
      end

      begin
        Service.find(params[:service_id])
      rescue ActiveRecord::RecordNotFound
        render json: [], status: :not_found and return
      end

      duration        = params[:duration].to_i
      operating_hour  = @car_wash.operating_hours.find_by(day_of_week: date.wday)
      available_times = []

      if operating_hour
        opens_at_minutes  = (operating_hour.opens_at.hour * 60) + operating_hour.opens_at.min
        closes_at_minutes = (operating_hour.closes_at.hour * 60) + operating_hour.closes_at.min

        appointments = @car_wash.appointments.joins(:service)
          .where("DATE(scheduled_at) = ?", date)
          .select("appointments.scheduled_at, services.duration").to_a

        occupied_intervals = appointments.map do |appt|
          s = (appt.scheduled_at.hour * 60) + appt.scheduled_at.min
          e = s + appt.duration.to_i
          (s..e)
        end

        current = opens_at_minutes
        while current <= closes_at_minutes - duration
          time_end = current + duration
          if occupied_intervals.none? { |i| current < i.end && time_end > i.begin }
            available_times << format("%02d:%02d", current / 60, current % 60)
          end
          current += 10
        end
      end

      render json: available_times
    end
  rescue Timeout::Error
    render json: [], status: :request_timeout
  end

  private

  def set_car_wash
    @car_wash = CarWash.find(params[:id] || params[:car_wash_id])
  end

  def ensure_owner
    unless current_user.owner? && @car_wash.user == current_user
      redirect_to root_path, alert: "Acesso não autorizado." unless current_user.attendant?
    end
  end

  def ensure_owner_or_attendant
    if current_user.owner?
      redirect_to root_path, alert: "Acesso não autorizado." unless @car_wash.user == current_user
    elsif current_user.attendant?
      redirect_to root_path, alert: "Acesso não autorizado." unless current_car_wash&.id == @car_wash.id
    else
      redirect_to root_path, alert: "Acesso não autorizado."
    end
  end

  def car_wash_params
    params.require(:car_wash).permit(
      :name, :address, :cep, :logradouro, :bairro, :cidade, :uf,
      :latitude, :longitude, :capacity_per_slot,
      operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
      services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
    )
  end
end
