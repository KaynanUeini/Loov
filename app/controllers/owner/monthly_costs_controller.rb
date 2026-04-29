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
                    .sum("services.price - COALESCE(appointments.commission_amount, 0)").to_f

        pending_revenue = @car_wash.appointments
                            .where(status: "confirmed")
                            .joins(:service)
                            .where(scheduled_at: Date.today..date.end_of_month)
                            .sum("services.price - COALESCE(appointments.commission_amount, 0)").to_f

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

      @pending_fields        = []
      @pending_values        = {}
      @pending_custom_lines  = nil
      @has_pending           = false
      if current_user.attendant?
        pending = @car_wash.pending_changes
                    .where(change_type: "monthly_costs", status: "pending")
                    .select { |pc| pc.payload_data["year"].to_i == year && pc.payload_data["month"].to_i == month }
                    .sort_by(&:created_at)

        # O mais recente sobrescreve os anteriores — atendente vê o último
        # valor que ele submeteu pra cada campo.
        pending.each do |pc|
          (pc.payload_data["cost_params"] || {}).each { |k, v| @pending_values[k] = v }
          if pc.payload_data["custom_lines"].is_a?(Array)
            @pending_custom_lines = pc.payload_data["custom_lines"]
          end
        end
        @pending_fields = @pending_values.keys
        @has_pending    = @pending_fields.any? || !@pending_custom_lines.nil?
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
            pending_fields:       @pending_fields,
            pending_values:       @pending_values,
            pending_custom_lines: @pending_custom_lines,
            has_pending:          @has_pending,
            is_attendant:         current_user.attendant?
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
          :rent, :salaries, :utilities, :water, :electricity, :products,
          :maintenance, :other_fixed, :other_variable, :notes
        ).to_h

        incoming_lines = (params[:custom_lines].presence ||
                          params.dig(:monthly_cost, :custom_lines) ||
                          []).map do |h|
          h = h.respond_to?(:permit) ? h.permit(:id, :name, :amount, :cost_type, :position).to_h : h.to_h.stringify_keys
          {
            "id"        => h["id"].presence&.to_i,
            "name"      => h["name"].to_s.strip,
            "amount"    => h["amount"].to_f.round(2),
            "cost_type" => h["cost_type"].to_s,
            "position"  => (h["position"] || 0).to_i,
          }
        end.reject { |h| h["name"].empty? || h["amount"] <= 0 }

        existing = MonthlyCost.for_month(@car_wash, year, month)

        # Pending changes do mês, ordenadas por criação (mais antiga primeiro).
        pending = @car_wash.pending_changes
                    .where(change_type: "monthly_costs", status: "pending")
                    .select { |pc| pc.payload_data["year"].to_i == year && pc.payload_data["month"].to_i == month }
                    .sort_by(&:created_at)

        # Estado mais recente "intencionado" pra cada campo padrão:
        # último pending sobrescreve DB. Diff é contra esse estado, não só DB.
        allowed_keys = %w[rent salaries utilities water electricity products
                          maintenance other_fixed other_variable notes]
        current_values = {}
        allowed_keys.each { |k| current_values[k] = existing.send(k) }
        pending.each do |pc|
          (pc.payload_data["cost_params"] || {}).each { |k, v| current_values[k] = v }
        end

        changed = raw.select do |k, v|
          if k == "notes"
            current_values[k].to_s.strip != v.to_s.strip
          else
            current_values[k].to_f.round(2) != v.to_f.round(2)
          end
        end

        # Estado mais recente das linhas customizadas: último pending com
        # custom_lines OU as linhas salvas no DB.
        latest_pending_lines = pending.reverse.find { |pc| pc.payload_data["custom_lines"].is_a?(Array) }
                                       &.payload_data&.dig("custom_lines")
        current_lines =
          if latest_pending_lines
            latest_pending_lines.map { |h|
              { "id" => h["id"].presence&.to_i, "name" => h["name"].to_s.strip,
                "amount" => h["amount"].to_f.round(2), "cost_type" => h["cost_type"].to_s }
            }
          elsif existing.persisted?
            existing.custom_cost_lines.ordered.map { |l|
              { "id" => l.id, "name" => l.name.to_s.strip,
                "amount" => l.amount.to_f.round(2), "cost_type" => l.cost_type.to_s }
            }
          else
            []
          end

        normalize_lines = ->(arr) { arr.map { |h| h.slice("id", "name", "amount", "cost_type") }
                                       .sort_by { |h| [h["id"].to_i, h["name"]] } }
        custom_changed = normalize_lines.call(current_lines) != normalize_lines.call(incoming_lines)

        if changed.empty? && !custom_changed
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
          "water"          => "Água",
          "electricity"    => "Luz",
          "products"       => "Produtos",
          "maintenance"    => "Manutenção",
          "other_fixed"    => "Outros fixos",
          "other_variable" => "Outros variáveis",
          "notes"          => "Observações"
        }
        labels = changed.keys.map { |k| field_names[k] || k }
        labels << "Linhas customizadas" if custom_changed
        changed_labels = labels.join(", ")

        payload = { cost_params: changed, year: year, month: month }
        # Pra custom_lines mandamos a lista COMPLETA — apply_change usa sync
        # (cria/atualiza/destrói) baseado em quem está no payload.
        payload[:custom_lines] = incoming_lines if custom_changed

        PendingChange.create!(
          car_wash:    @car_wash,
          attendant:   current_user,
          change_type: "monthly_costs",
          status:      "pending",
          description: "Custos #{MonthlyCost::MONTH_NAMES[month - 1]}/#{year} — alterou: #{changed_labels}",
          payload:     payload.to_json
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
