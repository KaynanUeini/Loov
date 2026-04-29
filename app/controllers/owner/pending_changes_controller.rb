module Owner
  class PendingChangesController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner

    def index
      @car_wash        = current_user.car_washes.first
      @pending_changes = @car_wash.pending_changes.pending.order(created_at: :desc)
      render json: @pending_changes.map { |pc| serialize(pc) }
    end

    def approve
      change = find_change
      return unless change

      apply_change(change)
      change.update!(status: "approved")
      render json: { ok: true, message: "Alteração aprovada e aplicada." }
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def reject
      change = find_change
      return unless change

      change.update!(status: "rejected")
      render json: { ok: true, message: "Alteração rejeitada." }
    end

    private

    def ensure_owner
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.owner?
    end

    def find_change
      @car_wash = current_user.car_washes.first
      change    = @car_wash.pending_changes.find_by(id: params[:id])
      render json: { error: "Não encontrado." }, status: :not_found unless change
      change
    end

    def apply_change(change)
      data = change.payload_data

      case change.change_type
      when "manage_car_wash"
        car_wash_params = data["car_wash_params"]
        if car_wash_params.present?
          change.car_wash.update!(car_wash_params.except("operating_hours_attributes", "services_attributes"))

          if car_wash_params["operating_hours_attributes"].present?
            car_wash_params["operating_hours_attributes"].each_value do |attrs|
              if attrs["_destroy"] == "1"
                change.car_wash.operating_hours.find_by(id: attrs["id"])&.destroy
              elsif attrs["id"].present?
                change.car_wash.operating_hours.find_by(id: attrs["id"])&.update(
                  opens_at: attrs["opens_at"], closes_at: attrs["closes_at"]
                  )
              else
                change.car_wash.operating_hours.create(
                  day_of_week: attrs["day_of_week"],
                  opens_at:    attrs["opens_at"],
                  closes_at:   attrs["closes_at"]
                  )
              end
            end
          end

          if car_wash_params["services_attributes"].present?
            car_wash_params["services_attributes"].each_value do |attrs|
              if attrs["_destroy"] == "1"
                change.car_wash.services.find_by(id: attrs["id"])&.destroy
              elsif attrs["id"].present?
                change.car_wash.services.find_by(id: attrs["id"])&.update(
                  title: attrs["title"], category: attrs["category"],
                  price: attrs["price"], duration: attrs["duration"],
                  description: attrs["description"]
                  )
              else
                change.car_wash.services.create(
                  title: attrs["title"], category: attrs["category"],
                  price: attrs["price"].to_f, duration: attrs["duration"].to_i,
                  description: attrs["description"]
                  )
              end
            end
          end
        end

      when "monthly_costs"
        cost_params       = data["cost_params"]
        custom_lines_diff = data["custom_lines_diff"]
        custom_lines_full = data["custom_lines"]   # legado: payload antigo
        year              = data["year"].to_i
        month             = data["month"].to_i
        cost              = MonthlyCost.for_month(change.car_wash, year, month)

        ActiveRecord::Base.transaction do
          allowed = %w[rent salaries utilities water electricity products
                       maintenance other_fixed other_variable notes]
          if cost_params.present?
            attrs = cost_params.slice(*allowed).merge("year" => year, "month" => month)
            cost.update!(attrs)
          end

          if custom_lines_diff.is_a?(Hash)
            apply_custom_lines_diff!(cost, custom_lines_diff)
          elsif custom_lines_full.is_a?(Array)
            sync_custom_lines!(cost, custom_lines_full)
          end
        end
      end
    end

    # Aplica diff parcial nas linhas customizadas — não toca em linhas que
    # não estão no diff (preserva o que já foi aprovado).
    def apply_custom_lines_diff!(cost, diff)
      Array(diff["deleted"]).each do |id|
        cost.custom_cost_lines.find_by(id: id)&.destroy
      end
      Array(diff["updated"]).each do |upd|
        line = cost.custom_cost_lines.find_by(id: upd["id"])
        next unless line
        line.update(
          name:      upd["name"].to_s.strip[0, 80],
          amount:    upd["amount"].to_f.round(2),
          cost_type: upd["cost_type"]
        )
      end
      base_position = cost.custom_cost_lines.maximum(:position).to_i
      Array(diff["added"]).each_with_index do |add, idx|
        cost_type = add["cost_type"].to_s
        next unless CustomCostLine::COST_TYPES.include?(cost_type)
        cost.custom_cost_lines.create(
          name:      add["name"].to_s.strip[0, 80],
          amount:    add["amount"].to_f.round(2),
          cost_type: cost_type,
          position:  base_position + 1 + idx,
        )
      end
    end

    # Espelha a sincronização do MonthlyCostsController — mantém em sync as
    # linhas customizadas quando o dono aprova uma mudança que veio do atendente.
    def sync_custom_lines!(monthly_cost, payload)
      incoming = Array(payload).map do |h|
        h = h.respond_to?(:permit) ? h.permit(:id, :name, :amount, :cost_type, :position).to_h : h.to_h.stringify_keys
        h.slice("id", "name", "amount", "cost_type", "position")
      end

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
          line ? line.update(attrs) : monthly_cost.custom_cost_lines.create(attrs)
        else
          monthly_cost.custom_cost_lines.create(attrs)
        end
      end
    end

    def serialize(pc)
      {
        id:          pc.id,
        change_type: pc.change_type,
        description: pc.description,
        attendant:   pc.attendant.display_name,
        created_at:  pc.created_at.strftime("%d/%m %H:%M"),
        status:      pc.status,
        payload:     pc.payload_data
      }
    end
  end
end
