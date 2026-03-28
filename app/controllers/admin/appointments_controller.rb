module Admin
  class AppointmentsController < Admin::BaseController
    def index
      appointments = Appointment.all.order(scheduled_at: :desc).includes(:service, :user)
      appointments = appointments.where(status: params[:status])               if params[:status].present?
      appointments = appointments.where(appointment_type: params[:type])        if params[:type].present?
      appointments = appointments.where(scheduled_at: Date.parse(params[:date]).all_day) if params[:date].present?

      car_washes = CarWash.where(id: appointments.map(&:car_wash_id).uniq).index_by(&:id)

      render json: appointments.map { |a|
        user     = a.user
        car_wash = car_washes[a.car_wash_id]
        {
          id:           a.id,
          status:       a.status,
          type:         a.appointment_type,
          client:       a.walk_in? ? (a.walk_in_name || "Avulso") : (user&.display_name || user&.email&.split("@")&.first&.capitalize || "—"),
          client_email: user&.email,
          service:      a.service&.title,
          car_wash:     car_wash&.name,
          scheduled_at: a.scheduled_at&.strftime("%d/%m/%Y %H:%M"),
          price:        a.effective_price.to_f,
          prepayment:   a.prepayment_amount.to_f,
          commission:   a.commission_amount.to_f
        }
      }
    end

    def show
      a        = Appointment.find(params[:id])
      user     = a.user
      car_wash = a.car_wash

      render json: {
        id:           a.id,
        status:       a.status,
        type:         a.appointment_type,
        client:       a.walk_in? ? (a.walk_in_name || "Avulso") : (user&.display_name || user&.email&.split("@")&.first&.capitalize || "—"),
        client_email: user&.email,
        service:      a.service&.title,
        car_wash:     car_wash&.name,
        scheduled_at: a.scheduled_at&.strftime("%d/%m/%Y %H:%M"),
        price:        a.effective_price.to_f,
        prepayment:   a.prepayment_amount.to_f,
        commission:   a.commission_amount.to_f
      }
    end

    def cancel
      appointment = Appointment.find(params[:id])
      appointment.update!(status: "cancelled")
      render json: { ok: true, message: "Agendamento ##{appointment.id} cancelado." }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
