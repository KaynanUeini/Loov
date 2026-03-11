class AppointmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_appointment, only: [:show, :cancel, :help]
  before_action :set_car_wash, only: [:new, :create]

  def new
    Rails.logger.info("AppointmentsController#new: car_wash_id=#{params[:car_wash_id]}")
    if @car_wash.nil?
      redirect_to car_washes_path, alert: "Lava-rápido não encontrado."
      return
    end
    if @car_wash.services.empty?
      redirect_to car_washes_path, alert: "O lava-rápido selecionado não tem serviços disponíveis."
      return
    end
    @appointment = Appointment.new(car_wash: @car_wash)
  end

  def index
    respond_to do |format|
      format.html do
        all_appointments = current_user&.appointments || Appointment.none
        current_time = DateTime.now.in_time_zone("America/Sao_Paulo")

        @upcoming_appointments = all_appointments
          .where(status: ['pending', 'confirmed'])
          .select { |a| (a.scheduled_at + a.service.duration.minutes) >= current_time }
          .sort_by(&:scheduled_at)

        @past_appointments = all_appointments
          .select { |a| (a.scheduled_at + a.service.duration.minutes) < current_time || a.status == 'cancelled' }
          .sort_by(&:scheduled_at).reverse

        @ongoing_appointments = @upcoming_appointments.select do |a|
          current_time.between?(a.scheduled_at, a.scheduled_at + a.service.duration.minutes)
        end.map(&:id)
      end

      format.json do
        car_wash_id = params[:car_wash_id]
        unless car_wash_id.present?
          render json: { error: "CarWash ID não fornecido." }, status: :bad_request
          return
        end

        begin
          car_wash = CarWash.find(car_wash_id)
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Lava-rápido não encontrado." }, status: :not_found
          return
        end

        unless params[:date].present?
          render json: { error: "Data não fornecida." }, status: :bad_request
          return
        end

        begin
          start_date = Date.parse(params[:date]).beginning_of_day
          end_date   = start_date.end_of_day
          appointments = car_wash.appointments
            .where(scheduled_at: start_date..end_date)
            .where(status: ['pending', 'confirmed'])
            .includes(:service)
          render json: { appointments: appointments.as_json(include: :service) }
        rescue ArgumentError, TypeError => e
          render json: { error: "Formato de data inválido." }, status: :bad_request
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error("Erro em AppointmentsController#index: #{e.message}")
    render json: { error: "Erro interno: #{e.message}" }, status: :internal_server_error
  end

  def create
    @appointment = Appointment.new(appointment_params.except(:date, :time))
    @appointment.user   = current_user
    @appointment.status = 'pending'

    scheduled_date = params[:appointment][:date]
    scheduled_time = params[:appointment][:time]

    unless scheduled_date.present? && scheduled_time.present?
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "Data e horário são obrigatórios."
      return
    end

    begin
      date_parts = scheduled_date.split('-').map(&:to_i)
      time_parts = scheduled_time.split(':').map(&:to_i)
      @appointment.scheduled_at = DateTime.new(
        date_parts[0], date_parts[1], date_parts[2],
        time_parts[0], time_parts[1], 0, '-03:00'
      )
    rescue => e
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "Data ou horário inválidos."
      return
    end

    unless params[:appointment][:service_id].present?
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "Por favor, selecione um serviço."
      return
    end

    current_time_with_tolerance = DateTime.now.in_time_zone("America/Sao_Paulo") - 5.minutes
    if @appointment.scheduled_at < current_time_with_tolerance
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "Não é possível agendar para um horário no passado."
      return
    end

    service = Service.find(params[:appointment][:service_id])
    start_time = @appointment.scheduled_at
    end_time   = start_time + service.duration.minutes

    operating_hours = @car_wash.operating_hours.where(day_of_week: start_time.wday)
    unless operating_hours.any?
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "O lava-rápido não está disponível no dia selecionado."
      return
    end

    within_operating_hours = operating_hours.any? do |oh|
      start_min  = start_time.hour * 60 + start_time.min
      end_min    = end_time.hour * 60 + end_time.min
      opens_at   = oh.opens_at.hour * 60 + oh.opens_at.min
      closes_at  = oh.closes_at.hour * 60 + oh.closes_at.min
      start_min >= opens_at && end_min <= closes_at
    end

    unless within_operating_hours
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "O horário selecionado está fora do horário de funcionamento."
      return
    end

    overlapping = Appointment
      .where(car_wash_id: @car_wash.id)
      .where(status: ['pending', 'confirmed'])
      .where("scheduled_at < ? AND scheduled_at >= ?", end_time, start_time - service.duration.minutes)
      .count

    if overlapping >= @car_wash.capacity_per_slot
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "Horário indisponível. Por favor, escolha outro."
      return
    end

    @appointment.status = 'confirmed'

    if @appointment.save
      Rails.logger.info("Agendamento ##{@appointment.id} criado com sucesso")
      redirect_to appointments_path, notice: "Agendamento criado com sucesso!"
    else
      Rails.logger.error("Erro ao salvar: #{@appointment.errors.full_messages.join(', ')}")
      redirect_to new_appointment_path(car_wash_id: @car_wash&.id), alert: "Erro ao criar o agendamento: #{@appointment.errors.full_messages.join(', ')}"
    end
  end

  def show
  end

  def cancel
    current_time = DateTime.now.in_time_zone("America/Sao_Paulo")

    unless @appointment.status != 'cancelled' && @appointment.scheduled_at > current_time
      redirect_to appointments_path, alert: "Não é possível cancelar este agendamento."
      return
    end

    # Cancelamento permitido apenas com mais de 30 minutos de antecedência
    # e somente se o serviço ainda não começou
    minutes_until = ((@appointment.scheduled_at - current_time) / 60).to_i

    if minutes_until <= 30
      redirect_to appointments_path, alert: "Não é possível cancelar com menos de 30 minutos de antecedência."
      return
    end

    @appointment.update_columns(status: 'cancelled')
    redirect_to appointments_path, notice: "Agendamento cancelado com sucesso."
  end

  def help
    flash[:notice] = "Entre em contato com o suporte para assistência com o agendamento ##{@appointment.id}."
    redirect_to appointments_path
  end

  private

  def set_appointment
    @appointment = Appointment.find(params[:id])
    unless @appointment.user_id == current_user.id
      redirect_to root_path, alert: 'Acesso não autorizado.'
    end
  end

  def set_car_wash
    car_wash_id = params[:car_wash_id] || params[:appointment]&.dig(:car_wash_id)
    @car_wash = CarWash.find(car_wash_id) if car_wash_id.present?
  rescue ActiveRecord::RecordNotFound
    @car_wash = nil
  end

  def appointment_params
    params.require(:appointment).permit(:car_wash_id, :service_id, :date, :time)
  end
end
