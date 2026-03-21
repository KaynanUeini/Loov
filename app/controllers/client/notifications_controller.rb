module Client
  class NotificationsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_client

    # GET /client/notifications
    def index
      appointments = current_user.appointments
        .where(appointment_type: "disponivel")
        .where("created_at >= ?", 7.days.ago)
        .includes(:service, :car_wash)
        .order(created_at: :desc)
        .limit(10)

      render json: appointments.map { |a|
        {
          id:            a.id,
          status:        a.status,
          service_name:  a.service.title,
          car_wash_name: a.car_wash.name,
          scheduled_at:  a.scheduled_at.strftime("%d/%m às %H:%M"),
          created_at:    a.created_at.iso8601  # necessário para o badge de "não lido"
        }
      }
    end

    private

    def ensure_client
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.client?
    end
  end
end
