class AppointmentsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :set_appointment, only: [:show, :cancel, :help]
  before_action :set_car_wash, only: [:new, :create]

  def new
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
        current_time = Time.current.in_time_zone("America/Sao_Paulo")
        all          = current_user.appointments.includes(:service, :car_wash, :review)

        @upcoming_appointments = all
          .select { |a| active_status?(a) && end_time(a) >= current_time }
          .sort_by(&:scheduled_at)

        @past_appointments = all
          .reject { |a| %w[cancelled no_show].include?(a.status) }
          .select { |a| end_time(a) < current_time || a.status == 'attended' }
          .uniq(&:id)
          .sort_by(&:scheduled_at)
          .reverse

        @ongoing_appointments = @upcoming_appointments
          .select { |a| current_time.between?(a.scheduled_at, end_time(a)) }
          .map(&:id)

        phone = current_user.phone.to_s.gsub(/\D/, '')
        @client_code = phone.length >= 4 ? phone.last(4) : nil

        car_wash_ids = all.map(&:car_wash_id).uniq
        active_programs = LoyaltyProgram
          .where(car_wash_id: car_wash_ids, active: true)
          .index_by(&:car_wash_id)

        if active_programs.any?
          @loyalty_by_car_wash = {}
          active_programs.each do |car_wash_id, prog|
            visits = current_user.appointments
              .where(car_wash_id: car_wash_id, status: "attended")
              .where("scheduled_at >= ?", prog.created_at)
              .count

            goal           = prog.visits_required
            cycle          = visits % goal
            last_milestone = visits > 0 && cycle == 0

            @loyalty_by_car_wash[car_wash_id] = {
              visits:         visits,
              goal:           goal,
              filled:         last_milestone ? goal : cycle,
              milestone:      last_milestone,
              reward:         prog.reward_description,
              program_active: true
            }
          end
        else
          @loyalty_by_car_wash = {}
        end
      end

      format.json do
        all = current_user.appointments
          .includes(:service, :car_wash, :review)
          .order(scheduled_at: :desc)

        # Último 4 dígitos do próprio telefone do cliente — usado no card do
        # app pro cliente ver qual código dizer ao lava-rápido quando chegar.
        phone_digits = current_user.phone.to_s.gsub(/\D/, "")
        phone_last4  = phone_digits.length >= 4 ? phone_digits.last(4) : nil

        render json: all.map { |a|
          # show_code: de 15 min antes do horário agendado até 5 min depois
          # (buffer pequeno pra quando o cliente chega atrasado). Só em
          # confirmed — depois de attended/no_show/cancelled não faz sentido.
          show_code = a.status == "confirmed" &&
                      a.scheduled_at <= Time.current + 15.minutes &&
                      a.scheduled_at >= Time.current - 5.minutes

          {
            id:           a.id,
            status:       a.status,
            scheduled_at: a.scheduled_at,
            reviewed:     a.review.present?,
            review_id:    a.review&.id,
            phone_last4:  phone_last4,
            show_code:    show_code,
            car_wash: {
              id:   a.car_wash.id,
              name: a.car_wash.name
            },
            service: {
              id:       a.service.id,
              title:    a.service.title,
              price:    a.service.price,
              duration: a.service.duration
            }
          }
        }
      end
    end
  rescue StandardError => e
    Rails.logger.error("Erro em AppointmentsController#index: #{e.message}")
    render json: { error: "Erro interno: #{e.message}" }, status: :internal_server_error
  end

  def create
    @appointment        = Appointment.new(appointment_params.except(:date, :time))
    @appointment.user   = current_user
    @appointment.status = 'pending'

    scheduled_date = params[:appointment][:date]
    scheduled_time = params[:appointment][:time]

    unless scheduled_date.present? && scheduled_time.present?
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Data e horário são obrigatórios." }
        format.json { render json: { error: "Data e horário são obrigatórios." }, status: :unprocessable_entity }
      end
      return
    end

    begin
      date_parts = scheduled_date.split('-').map(&:to_i)
      time_parts = scheduled_time.split(':').map(&:to_i)
      @appointment.scheduled_at = DateTime.new(
        date_parts[0], date_parts[1], date_parts[2],
        time_parts[0], time_parts[1], 0, '-03:00'
      )
    rescue
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Data ou horário inválidos." }
        format.json { render json: { error: "Data ou horário inválidos." }, status: :unprocessable_entity }
      end
      return
    end

    unless params[:appointment][:service_id].present?
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Por favor, selecione um serviço." }
        format.json { render json: { error: "Selecione um serviço." }, status: :unprocessable_entity }
      end
      return
    end

    current_time_with_tolerance = DateTime.now.in_time_zone("America/Sao_Paulo") - 5.minutes
    if @appointment.scheduled_at < current_time_with_tolerance
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Não é possível agendar para um horário no passado." }
        format.json { render json: { error: "Não é possível agendar para um horário no passado." }, status: :unprocessable_entity }
      end
      return
    end

    minutes_until = ((@appointment.scheduled_at.in_time_zone("America/Sao_Paulo") - Time.current.in_time_zone("America/Sao_Paulo")) / 60).to_i
    if @appointment.regular? && minutes_until < 45 && minutes_until >= 0
      respond_to do |format|
        format.html { redirect_to disponivel_index_path, alert: "Este horário só pode ser reservado pelo Disponível." }
        format.json { render json: { error: "Este horário só pode ser reservado pelo Disponível." }, status: :unprocessable_entity }
      end
      return
    end

    service    = Service.find(params[:appointment][:service_id])
    start_time = @appointment.scheduled_at
    end_time   = start_time + service.duration.minutes

    operating_hours = @car_wash.operating_hours.where(day_of_week: start_time.wday)
    unless operating_hours.any?
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "O lava-rápido não está disponível no dia selecionado." }
        format.json { render json: { error: "O lava-rápido não está disponível no dia selecionado." }, status: :unprocessable_entity }
      end
      return
    end

    within_operating_hours = operating_hours.any? do |oh|
      start_min = start_time.hour * 60 + start_time.min
      end_min   = end_time.hour * 60   + end_time.min
      opens_at  = oh.opens_at.hour * 60  + oh.opens_at.min
      closes_at = oh.closes_at.hour * 60 + oh.closes_at.min
      start_min >= opens_at && end_min <= closes_at
    end

    unless within_operating_hours
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "O horário selecionado está fora do horário de funcionamento." }
        format.json { render json: { error: "Horário fora do funcionamento." }, status: :unprocessable_entity }
      end
      return
    end

    saved    = false
    conflict = false

    ActiveRecord::Base.transaction do
      @car_wash.lock!

      overlapping = Appointment
        .joins(:service)
        .where(car_wash_id: @car_wash.id)
        .where(status: %w[pending confirmed])
        .where(
          "appointments.scheduled_at < ? AND (appointments.scheduled_at + (services.duration * interval '1 minute')) > ?",
          end_time, start_time
        )
        .count

      if overlapping >= @car_wash.capacity_per_slot
        conflict = true
        raise ActiveRecord::Rollback
      end

      @appointment.status = 'confirmed'
      saved = @appointment.save
      raise ActiveRecord::Rollback unless saved
    end

    if conflict
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Horário indisponível. Por favor, escolha outro." }
        format.json { render json: { error: "Horário indisponível. Escolha outro." }, status: :conflict }
      end
      return
    end

    unless saved
      respond_to do |format|
        format.html { redirect_to car_wash_path(@car_wash, anchor: 'booking'), alert: "Erro ao criar o agendamento." }
        format.json { render json: { error: @appointment.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
      return
    end

    begin
      AppointmentMailer.confirmation(@appointment).deliver_now
    rescue => e
      Rails.logger.error("[Appointments#create] Email falhou: #{e.message}")
    end

    respond_to do |format|
      format.html { redirect_to appointments_path, notice: "Agendamento criado com sucesso!" }
      format.json { render json: { message: "Agendamento confirmado!", appointment_id: @appointment.id }, status: :created }
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
    if @appointment.disponivel?
      redirect_to appointments_path, alert: "Agendamentos Disponíveis não podem ser cancelados por aqui."
      return
    end
    minutes_until = ((@appointment.scheduled_at - current_time) / 60).to_i
    if minutes_until <= 120
      deadline = @appointment.scheduled_at.in_time_zone("America/Sao_Paulo") - 2.hours
      redirect_to appointments_path, alert: "O prazo de cancelamento (até #{deadline.strftime('%H:%M')} do dia #{deadline.strftime('%d/%m')}) já encerrou."
      return
    end
    @appointment.update_columns(status: 'cancelled')
    redirect_to appointments_path, notice: "Agendamento cancelado. O horário foi liberado."
  end

  def help
    flash[:notice] = "Entre em contato com o suporte para assistência com o agendamento ##{@appointment.id}."
    redirect_to appointments_path
  end

  private

  def end_time(a)
    a.scheduled_at + a.service.duration.minutes
  end

  def active_status?(a)
    %w[pending confirmed pending_acceptance].include?(a.status)
  end

  def set_appointment
    @appointment = Appointment.find(params[:id])
    unless @appointment.user_id == current_user.id
      redirect_to root_path, alert: 'Acesso não autorizado.'
    end
  end

  def set_car_wash
    car_wash_id = params[:car_wash_id] || params[:appointment]&.dig(:car_wash_id)
    @car_wash   = CarWash.find(car_wash_id) if car_wash_id.present?
  rescue ActiveRecord::RecordNotFound
    @car_wash = nil
  end

  def appointment_params
    params.require(:appointment).permit(:car_wash_id, :service_id)
  end
end
