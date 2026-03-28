module Admin
  class FinancialController < Admin::BaseController
    def index
      months     = (params[:months] || 3).to_i
      start_date = months.months.ago.beginning_of_month
      end_date   = Time.current.end_of_month

      base = Appointment
        .where(appointment_type: "disponivel", status: "attended")
        .where(scheduled_at: start_date..end_date)
        .includes(:service, :user)

      car_washes = CarWash.where(id: base.map(&:car_wash_id).uniq).index_by(&:id)
      users      = User.where(id: base.map(&:user_id).compact.uniq).index_by(&:id)

      by_month = base.group_by { |a| a.scheduled_at.strftime("%Y-%m") }
        .transform_values { |appts|
          {
            count:      appts.count,
            volume:     appts.sum { |a| a.effective_price.to_f }.round(2),
            commission: appts.sum { |a| a.commission_amount.to_f }.round(2)
          }
        }

      transactions = base.order(scheduled_at: :desc).map { |a|
        user     = users[a.user_id]
        car_wash = car_washes[a.car_wash_id]
        {
          id:           a.id,
          scheduled_at: a.scheduled_at.strftime("%d/%m/%Y %H:%M"),
          client:       user&.display_name || user&.email&.split("@")&.first&.capitalize || "—",
          service:      a.service&.title,
          car_wash:     car_wash&.name,
          price:        a.effective_price.to_f,
          prepayment:   a.prepayment_amount.to_f,
          commission:   a.commission_amount.to_f
        }
      }

      render json: {
        summary: {
          total_volume:     base.sum { |a| a.effective_price.to_f }.round(2),
          total_commission: base.sum { |a| a.commission_amount.to_f }.round(2),
          total_count:      base.count
        },
        by_month:     by_month,
        transactions: transactions
      }
    end

    def export
      months     = 3
      start_date = months.months.ago.beginning_of_month
      end_date   = Time.current.end_of_month

      appointments = Appointment
        .where(appointment_type: "disponivel", status: "attended")
        .where(scheduled_at: start_date..end_date)
        .includes(:service, :user)
        .order(scheduled_at: :desc)

      car_washes = CarWash.where(id: appointments.map(&:car_wash_id).uniq).index_by(&:id)

      require "csv"
      csv = CSV.generate(headers: true) do |row|
        row << ["Data", "Cliente", "Serviço", "Lava-rápido", "Valor", "Pré-pago", "Comissão Loov"]
        appointments.each do |a|
          row << [
            a.scheduled_at.strftime("%d/%m/%Y %H:%M"),
            a.user&.email || "—",
            a.service&.title,
            car_washes[a.car_wash_id]&.name,
            format("%.2f", a.effective_price.to_f),
            format("%.2f", a.prepayment_amount.to_f),
            format("%.2f", a.commission_amount.to_f)
          ]
        end
      end

      send_data csv,
        filename: "loov_financeiro_#{Date.current}.csv",
        type:     "text/csv"
    end
  end
end
