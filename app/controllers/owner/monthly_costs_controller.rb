module Owner
  class MonthlyCostsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :ensure_owner_only, only: [:index, :destroy]

    def index
      @car_wash = current_car_wash
      @costs    = @car_wash.monthly_costs.order(year: :desc, month: :desc)

      @dre = (0..11).map do |i|
        date  = i.months.ago
        year  = date.year
        month = date.month
        cost  = @car_wash.monthly_costs.find_by(year: year, month: month)

        revenue = @car_wash.appointments
                    .where(status: "attended")
                    .joins(:service)
                    .where(scheduled_at: date.beginning_of_month..date.end_of_month)
                    .sum("services.price").to_f

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
      @car_wash     = current_car_wash
      @is_attendant = current_user.attendant?
      year          = params[:year]&.to_i  || Date.current.year
      month         = params[:month]&.to_i || Date.current.month
      @cost         = MonthlyCost.for_month(@car_wash, year, month)

      @pending_fields = []
      @has_pending    = false
      if current_user.attendant?
        pending = @car_wash.pending_changes
                    .where(change_type: "monthly_costs", status: "pending")
                    .select { |pc| pc.payload_data["year"].to_i == year && pc.payload_data["month"].to_i == month }
        @pending_fields = pending.flat_map { |pc| pc.payload_data["cost_params"]&.keys || [] }.uniq
        @has_pending    = @pending_fields.any?
      end
    end

    def upsert
      @car_wash = current_car_wash
      year      = params[:year]&.to_i  || Date.current.year
      month     = params[:month]&.to_i || Date.current.month

      if current_user.attendant?
        raw = params.require(:monthly_cost).permit(
          :rent, :salaries, :utilities, :products,
          :maintenance, :other_fixed, :other_variable, :notes
        ).to_h

        # Remove campos já bloqueados por pendência
        pending = @car_wash.pending_changes
                    .where(change_type: "monthly_costs", status: "pending")
                    .select { |pc| pc.payload_data["year"].to_i == year && pc.payload_data["month"].to_i == month }
        locked_fields = pending.flat_map { |pc| pc.payload_data["cost_params"]&.keys || [] }.uniq
        raw = raw.reject { |k, _| locked_fields.include?(k) }

        existing = MonthlyCost.for_month(@car_wash, year, month)

        # ── FIX: comparação float para numéricos evita falso positivo ──
        # "5000.0".to_s != "5000" mas 5000.0.round(2) == 5000.0.round(2)
        changed = raw.select do |k, v|
          if k == "notes"
            existing.send(k).to_s.strip != v.to_s.strip
          else
            existing.send(k).to_f.round(2) != v.to_f.round(2)
          end
        end

        if changed.empty?
          redirect_to edit_owner_monthly_costs_path(year: year, month: month),
            notice: "Nenhuma alteração detectada."
          return
        end

        field_names = {
          "rent"           => "Aluguel",
          "salaries"       => "Salários",
          "utilities"      => "Energia/Água",
          "products"       => "Produtos",
          "maintenance"    => "Manutenção",
          "other_fixed"    => "Outros fixos",
          "other_variable" => "Outros variáveis",
          "notes"          => "Observações"
        }
        changed_labels = changed.keys.map { |k| field_names[k] || k }.join(", ")

        PendingChange.create!(
          car_wash:    @car_wash,
          attendant:   current_user,
          change_type: "monthly_costs",
          status:      "pending",
          description: "Custos #{MonthlyCost::MONTH_NAMES[month - 1]}/#{year} — alterou: #{changed_labels}",
          payload:     { cost_params: changed, year: year, month: month }.to_json
        )

        redirect_to edit_owner_monthly_costs_path(year: year, month: month),
          notice: "✅ Alterações enviadas para aprovação do proprietário."
        return
      end

      # Owner: salva direto
      @cost = MonthlyCost.for_month(@car_wash, year, month)
      if @cost.update(cost_params.merge(year: year, month: month))
        redirect_to edit_owner_monthly_costs_path, notice: "Custos de #{MonthlyCost::MONTH_NAMES[month - 1]}/#{year} salvos com sucesso."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @car_wash = current_car_wash
      cost      = @car_wash.monthly_costs.find(params[:id])
      cost.destroy
      redirect_to owner_monthly_costs_path, notice: "Custos removidos."
    end

    private

    def ensure_owner_or_attendant
      redirect_to root_path unless current_user&.owner? || current_user&.attendant?
    end

    def ensure_owner_only
      redirect_to edit_owner_monthly_costs_path, alert: "Acesso não autorizado." unless current_user&.owner?
    end

    def cost_params
      params.require(:monthly_cost).permit(
        :rent, :salaries, :utilities, :products,
        :maintenance, :other_fixed, :other_variable, :notes
      )
    end
  end
end
