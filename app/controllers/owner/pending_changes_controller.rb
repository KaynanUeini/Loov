module Owner
  class PendingChangesController < ApplicationController
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
        cost_params = data["cost_params"]
        year        = data["year"].to_i
        month       = data["month"].to_i
        cost        = MonthlyCost.for_month(change.car_wash, year, month)
        cost.update!(cost_params.merge("year" => year, "month" => month)) if cost_params.present?
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
