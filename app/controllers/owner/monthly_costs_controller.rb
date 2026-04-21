module Owner
  class MonthlyCostsController < ApplicationController
    skip_before_action :verify_authenticity_token
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
          mes:            date.strftime("%b/%Y"),
          mes_label:      MonthlyCost::MONTH_NAMES[month - 1],
          ano:            year,
          mes_num:        month,
          faturamento:    revenue.round(2),
          receita_aberto: pending_revenue.round(2),
          custos:         total_cost.round(2),
          lucro:          profit.round(2),
          margem:         margin,
          tem_custo:      cost.present?
        }
      end.reverse

      @current_year  = Date.current.year
      @current_month = Date.current.month
      @current_cost  = MonthlyCost.for_month(@car_wash, @current_year, @current_month)

      respond_to do |format|
        format.html
        format.json { render json: { dre: @dre } }
      end
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

      respond_to do |format|
        format.html
        format.json do
          render json: {
            year:           @cost.year,
            month:          @cost.month,
            month_label:    MonthlyCost::MONTH_NAMES[@cost.month - 1],
            rent:           @cost.rent.to_f,
            salaries:       @cost.salaries.to_f,
            utilities:      @cost.utilities.to_f,
            water:          @cost.water.to_f,
            electricity:    @cost.electricity.to_f,
            products:       @cost.products.to_f,
            maintenance:    @cost.maintenance.to_f,
            other_fixed:    @cost.other_fixed.to_f,
            other_variable: @cost.other_variable.to_f,
            notes:          @cost.notes.to_s,
            custom_lines:   (@cost.persisted? ? @cost.custom_cost_lines.ordered : []).map { |l|
              { id: l.id, name: l.name, amount: l.amount.to_f, cost_type: l.cost_type, position: l.position }
            },
            pending_fields: @pending_fields,
            has_pending:    @has_pending,
            is_attendant:   current_user.attendant?
          }
        end
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

        pending = @car_wash.pending_changes
                    .where(change_type: "monthly_costs", status: "pending")
                    .select { |pc| pc.payload_data["year"].to_i == year && pc.payload_data["month"].to_i == month }
        locked_fields = pending.flat_map { |pc| pc.payload_data["cost_params"]&.keys || [] }.uniq
        raw = raw.reject { |k, _| locked_fields.include?(k) }

        existing = MonthlyCost.for_month(@car_wash, year, month)

        changed = raw.select do |k, v|
          if k == "notes"
            existing.send(k).to_s.strip != v.to_s.strip
          else
            existing.send(k).to_f.round(2) != v.to_f.round(2)
          end
        end

        if changed.empty?
          if request.format.json?
            return render json: { ok: false, message: "Nenhuma alteração detectada." }
          else
            redirect_to edit_owner_monthly_costs_path(year: year, month: month),
              notice: "Nenhuma alteração detectada."
            return
          end
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

        if request.format.json?
          render json: { ok: true, pending: true, message: "Alterações enviadas para aprovação do proprietário." }
        else
          redirect_to edit_owner_monthly_costs_path(year: year, month: month),
            notice: "✅ Alterações enviadas para aprovação do proprietário."
        end
        return
      end

      # Owner: salva direto
      @cost = MonthlyCost.for_month(@car_wash, year, month)

      # Rails `wrap_parameters` às vezes aninha o array em monthly_cost.
      # Aceita top-level OU aninhado — frontend pode mandar de qualquer jeito.
      custom_lines_payload = params[:custom_lines].presence ||
                             params.dig(:monthly_cost, :custom_lines) ||
                             []
      Rails.logger.info("[monthly_costs#upsert] custom_lines recebidas: #{Array(custom_lines_payload).size}")

      ok = ActiveRecord::Base.transaction do
        next false unless @cost.update(cost_params.merge(year: year, month: month))
        sync_custom_lines!(@cost, custom_lines_payload)
        true
      end

      if ok
        if request.format.json?
          render json: { ok: true, message: "Custos de #{MonthlyCost::MONTH_NAMES[month - 1]}/#{year} salvos." }
        else
          redirect_to edit_owner_monthly_costs_path,
            notice: "Custos de #{MonthlyCost::MONTH_NAMES[month - 1]}/#{year} salvos com sucesso."
        end
      else
        if request.format.json?
          render json: { error: @cost.errors.full_messages.join(', ') }, status: :unprocessable_entity
        else
          render :edit, status: :unprocessable_entity
        end
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
      return if current_user&.owner? || current_user&.attendant?
      if request.format.json?
        render json: { error: 'Acesso negado.' }, status: :forbidden
      else
        redirect_to root_path
      end
    end

    def ensure_owner_only
      return if current_user&.owner?
      if request.format.json?
        render json: { error: 'Acesso negado.' }, status: :forbidden
      else
        redirect_to edit_owner_monthly_costs_path, alert: "Acesso não autorizado."
      end
    end

    def cost_params
      params.require(:monthly_cost).permit(
        :rent, :salaries, :utilities, :water, :electricity, :products,
        :maintenance, :other_fixed, :other_variable, :notes
      )
    end

    # Sincroniza as linhas customizadas do mês. Estratégia:
    #   - Linhas com `id` → update (se pertencem ao mesmo monthly_cost)
    #   - Linhas sem `id` → create
    #   - Linhas existentes no banco cujo id NÃO veio no payload → destroy
    # Ignora linhas com nome vazio ou amount <= 0 (cleanup natural).
    def sync_custom_lines!(monthly_cost, payload)
      incoming = Array(payload).map do |h|
        h = h.respond_to?(:permit) ? h.permit(:id, :name, :amount, :cost_type, :position).to_h : h.to_h.stringify_keys
        h.slice("id", "name", "amount", "cost_type", "position")
      end

      # Filtra linhas vazias ou zeradas — dono limpou o campo, vira deleção.
      incoming = incoming.reject do |h|
        name   = h["name"].to_s.strip
        amount = h["amount"].to_f
        name.empty? || amount <= 0
      end

      keep_ids = incoming.map { |h| h["id"] }.compact.map(&:to_i)
      monthly_cost.custom_cost_lines.where.not(id: keep_ids).destroy_all if monthly_cost.persisted?

      incoming.each_with_index do |h, idx|
        cost_type = h["cost_type"].to_s
        next unless CustomCostLine::COST_TYPES.include?(cost_type)

        attrs = {
          name:      h["name"].to_s.strip[0, 80],
          amount:    h["amount"].to_f.round(2),
          cost_type: cost_type,
          position:  (h["position"] || idx).to_i,
        }

        if h["id"].present?
          line = monthly_cost.custom_cost_lines.find_by(id: h["id"])
          line&.update(attrs)
        else
          monthly_cost.custom_cost_lines.create(attrs)
        end
      end
    end
  end
end
