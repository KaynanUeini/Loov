module Admin
  class DashboardController < Admin::BaseController
    def index
    end

    def stats
      today_start = Time.current.beginning_of_day
      today_end   = Time.current.end_of_day
      month_start = Time.current.beginning_of_month
      month_end   = Time.current.end_of_month

      commission_month = Appointment
        .where(appointment_type: "disponivel", status: "attended")
        .where(scheduled_at: month_start..month_end)
        .sum(:commission_amount).to_f

      commission_total = Appointment
        .where(appointment_type: "disponivel", status: "attended")
        .sum(:commission_amount).to_f

      render json: {
        users: {
          total:     User.count,
          clients:   User.where(role: "client").count,
          owners:    User.where(role: "owner").count,
          attendants: User.where(role: "attendant").count,
          blocked:   User.where.not(blocked_at: nil).count,
          new_today: User.where(created_at: today_start..today_end).count
        },
        car_washes: {
          total:    CarWash.count,
          active:   CarWash.where(active: true).count,
          inactive: CarWash.where(active: false).count
        },
        appointments: {
          today:          Appointment.where(scheduled_at: today_start..today_end).where.not(status: "cancelled").count,
          attended_today: Appointment.where(scheduled_at: today_start..today_end).where(status: "attended").count,
          this_month:     Appointment.where(scheduled_at: month_start..month_end).where.not(status: "cancelled").count,
          pending:        Appointment.where(status: "pending_acceptance").count
        },
        financial: {
          commission_month: commission_month.round(2),
          commission_total: commission_total.round(2)
        },
        support: {
          open:        SupportTicket.where(status: "open").count,
          in_progress: SupportTicket.where(status: "in_progress").count,
          pending:     SupportTicket.where(status: %w[open in_progress]).count
        }
      }
    end

    def activity
      appointments = Appointment
        .order(created_at: :desc)
        .limit(50)
        .includes(:service, :user)

      users     = User.where(id: appointments.map(&:user_id).compact.uniq).index_by(&:id)
      car_washes = CarWash.where(id: appointments.map(&:car_wash_id).uniq).index_by(&:id)
      services  = Service.where(id: appointments.map(&:service_id).uniq).index_by(&:id)

      render json: appointments.map { |a|
        user      = users[a.user_id]
        car_wash  = car_washes[a.car_wash_id]
        service   = services[a.service_id]
        {
          id:           a.id,
          status:       a.status,
          type:         a.appointment_type,
          client:       a.walk_in? ? (a.walk_in_name || "Avulso") : (user&.display_name || user&.email&.split("@")&.first&.capitalize || "—"),
          service:      service&.title,
          car_wash:     car_wash&.name,
          scheduled_at: a.scheduled_at&.strftime("%d/%m %H:%M"),
          created_at:   a.created_at.strftime("%d/%m %H:%M"),
          commission:   a.commission_amount.to_f
        }
      }
    end
  end
end
