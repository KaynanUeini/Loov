module Owner
  class MonthlyCostsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner

    def index
      @car_wash = current_user.car_washes.first
      @costs    = @car_wash.monthly_costs.order(year: :desc, month: :desc)

      @dre = (0..11).map do |i|
        date  = i.months.ago
        year  = date.year
        month = date.month
        cost  = @car_wash.monthly_costs.find_by(year: year, month: month)

        # Faturamento REAL = apenas clientes que compareceram (attended)
        revenue = @car_wash.appointments
                    .where(status: "attended")
                    .joins(:service)
                    .where(scheduled_at: date.beginning_of_month..date.end_of_month)
                    .sum("services.price").to_f

        # Receita em aberto = confirmed ainda não realizados (só mês atual/futuro)
        pending_revenue = @car_wash.appointments
                            .where(status: "confirmed")
                            .joins(:service)
                            .where(scheduled_at: Date.today..date.end_of_month)
                            .sum("services.price").to_f

        total_cost = cost&.total.to_f
        profit     = revenue - total_cost
        margin     = revenue > 0 ? ((profit / revenue) * 100).round(1) : nil

        {
          mes:             date.strftime("%b/%Y"),
          mes_label:       MonthlyCost::MONTH_NAMES[month - 1],
          ano:             year,
          mes_num:         month,
          faturamento:     revenue.round(2),
          receita_aberto:  pending_revenue.round(2),
          custos:          total_cost.round(2),
          lucro:           profit.round(2),
          margem:          margin,
          tem_custo:       cost.present?
        }
      end.reverse

      @current_year  = Date.current.year
      @current_month = Date.current.month
      @current_cost  = MonthlyCost.for_month(@car_wash, @current_year, @current_month)
    end

    def edit
      @car_wash = current_user.car_washes.first
      year      = params[:year]&.to_i  || Date.current.year
      month     = params[:month]&.to_i || Date.current.month
      @cost     = MonthlyCost.for_month(@car_wash, year, month)

      @revenue = @car_wash.appointments
                   .where(status: "attended")
                   .joins(:service)
                   .where(scheduled_at: Date.new(year, month).beginning_of_month..Date.new(year, month).end_of_month)
                   .sum("services.price").to_f
    end

    def upsert
      @car_wash = current_user.car_washes.first
      year      = params[:year]&.to_i  || Date.current.year
      month     = params[:month]&.to_i || Date.current.month
      @cost     = MonthlyCost.for_month(@car_wash, year, month)

      if @cost.update(cost_params.merge(year: year, month: month))
        redirect_to owner_monthly_costs_path, notice: "Custos de #{MonthlyCost::MONTH_NAMES[month-1]}/#{year} salvos com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @car_wash = current_user.car_washes.first
      cost      = @car_wash.monthly_costs.find(params[:id])
      cost.destroy
      redirect_to owner_monthly_costs_path, notice: "Custos removidos."
    end

    private

    def ensure_owner
      redirect_to root_path unless current_user&.owner?
    end

    def cost_params
      params.require(:monthly_cost).permit(
        :rent, :salaries, :utilities, :products,
        :maintenance, :other_fixed, :other_variable, :notes
      )
    end
  end
end
