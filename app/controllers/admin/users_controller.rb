module Admin
  class UsersController < Admin::BaseController
    def index
      users = User.all.order(created_at: :desc)
      users = users.where("email ILIKE ? OR name ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
      users = users.where(role: params[:role]) if params[:role].present?
      users = users.where.not(blocked_at: nil) if params[:blocked] == "1"

      render json: users.map { |u|
        {
          id:                 u.id,
          name:               u.display_name,
          email:              u.email,
          role:               u.role,
          phone:              u.phone,
          vehicle:            u.vehicle_model,
          blocked:            u.blocked_at.present?,
          blocked_at:         u.blocked_at&.strftime("%d/%m/%Y"),
          appointments_count: u.appointments.count,
          created_at:         u.created_at.strftime("%d/%m/%Y")
        }
      }
    end

    def show
      u = User.find(params[:id])
      appointments = u.appointments.order(scheduled_at: :desc).limit(10).includes(:service)

      render json: {
        id:         u.id,
        name:       u.display_name,
        email:      u.email,
        role:       u.role,
        phone:      u.phone,
        vehicle:    u.vehicle_model,
        blocked:    u.blocked_at.present?,
        blocked_at: u.blocked_at&.strftime("%d/%m/%Y %H:%M"),
        created_at: u.created_at.strftime("%d/%m/%Y"),
        appointments: appointments.map { |a|
          {
            id:           a.id,
            scheduled_at: a.scheduled_at&.strftime("%d/%m/%Y %H:%M"),
            service:      a.service&.title,
            status:       a.status
          }
        }
      }
    end

    def block
      user = User.find(params[:id])
      user.update!(blocked_at: Time.current)
      render json: { ok: true, message: "Usuário bloqueado." }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def unblock
      user = User.find(params[:id])
      user.update!(blocked_at: nil)
      render json: { ok: true, message: "Usuário desbloqueado." }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def change_role
      user = User.find(params[:id])
      user.update!(role: params[:role])
      render json: { ok: true, message: "Role alterado para #{params[:role]}." }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
