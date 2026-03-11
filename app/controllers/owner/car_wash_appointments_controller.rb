module Owner
  class CarWashAppointmentsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner

    def index
      # Garante que apenas o dono do lava-rápido acesse seus próprios agendamentos
      car_wash = current_user.car_washes.first
      if car_wash.nil?
        redirect_to root_path, alert: "Você não tem um lava-rápido associado."
        return
      end

      # Filtra os agendamentos do lava-rápido
      @appointments = car_wash.appointments

      # Exclui agendamentos de datas passadas (apenas hoje e futuro)
      @appointments = @appointments.where("scheduled_at::date >= CURRENT_DATE")

      # Exibe apenas agendamentos com status "confirmed"
      @appointments = @appointments.where(status: "confirmed")

      # Aplica filtros
      if params[:period].present?
        case params[:period]
        when "last_7_days"
          @appointments = @appointments.where("scheduled_at >= ?", 7.days.ago)
        when "next_7_days"
          @appointments = @appointments.where("scheduled_at <= ?", 7.days.from_now)
        when "custom"
          if params[:start_date].present? && params[:end_date].present?
            start_date = Date.parse(params[:start_date]).beginning_of_day
            end_date = Date.parse(params[:end_date]).end_of_day
            @appointments = @appointments.where(scheduled_at: start_date..end_date)
          end
        end
      end

      if params[:search].present?
        search_term = "%#{params[:search].downcase}%"
        @appointments = @appointments.joins(:user).where(
          "LOWER(users.email) LIKE ?", # Ajustado para buscar por email, já que users.name não existe
          search_term
        ).or(
          @appointments.joins(:service).where("LOWER(services.title) LIKE ?", search_term)
        ).references(:user, :services)
      end

      # Agrupa os agendamentos por data para a visão de lista expansível
      # Ordena por scheduled_at em ordem crescente (datas mais próximas primeiro)
      @appointments = @appointments.order(scheduled_at: :asc)

      # Agrupa os agendamentos por data
      grouped_by_date = @appointments.group_by { |a| a.scheduled_at.to_date }

      # Reordena as chaves (datas) em ordem crescente (já que todas são futuras ou hoje)
      sorted_dates = grouped_by_date.keys.sort

      # Cria um novo hash ordenado com base nas datas ordenadas
      @appointments_by_date = {}
      sorted_dates.each do |date|
        @appointments_by_date[date] = grouped_by_date[date]
      end
    end

    def show
      car_wash = current_user.car_washes.first
      if car_wash.nil?
        redirect_to root_path, alert: "Você não tem um lava-rápido associado."
        return
      end

      @appointment = car_wash.appointments.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to owner_car_wash_appointments_path, alert: "Agendamento não encontrado."
    end

    private

    def ensure_owner
      unless current_user&.owner?
        redirect_to root_path, alert: "Acesso restrito a donos de lava-rápidos."
      end
    end
  end
end
