module Admin
  class UsersController < Admin::BaseController
    def index
      # Coluna `blocked_at` existe no schema.rb mas pode não ter sido
      # aplicada em produção (migration pendente). Evita NoMethodError
      # checando dinamicamente o que a tabela tem.
      has_blocked = User.column_names.include?('blocked_at')

      users = User.all.order(created_at: :desc)
      users = users.where("email ILIKE ? OR full_name ILIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
      users = users.where(role: params[:role]) if params[:role].present?
      users = users.where.not(blocked_at: nil) if params[:blocked] == "1" && has_blocked

      users_list = users.to_a
      ids        = users_list.map(&:id)

      appt_counts = if ids.any?
        Appointment.where(user_id: ids).group(:user_id).count
      else
        {}
      end

      payload = users_list.map do |u|
        blocked_at = has_blocked ? u.blocked_at : nil
        {
          id:                 u.id,
          name:               (u.display_name rescue (u.email.to_s.split("@").first || "—")),
          email:              u.email.to_s,
          role:               u.role.to_s,
          phone:              u.phone,
          vehicle:            u.vehicle_model,
          blocked:            blocked_at.present?,
          blocked_at:         blocked_at&.strftime("%d/%m/%Y"),
          appointments_count: appt_counts[u.id] || 0,
          created_at:         u.created_at&.strftime("%d/%m/%Y")
        }
      end

      render json: payload
    rescue => e
      Rails.logger.error("[Admin::Users#index] #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
      render json: { error: e.message, klass: e.class.name }, status: :internal_server_error
    end

    def block
      user = User.find(params[:id])
      if User.column_names.include?('blocked_at')
        user.update!(blocked_at: Time.current)
        render json: { ok: true, message: "Usuário bloqueado." }
      else
        render json: { error: "Coluna blocked_at ainda não aplicada no banco de produção. Rode db:migrate." }, status: :unprocessable_entity
      end
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def unblock
      user = User.find(params[:id])
      if User.column_names.include?('blocked_at')
        user.update!(blocked_at: nil)
        render json: { ok: true, message: "Usuário desbloqueado." }
      else
        render json: { error: "Coluna blocked_at ainda não aplicada no banco de produção." }, status: :unprocessable_entity
      end
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
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

    def change_role
      user = User.find(params[:id])
      user.update!(role: params[:role])
      render json: { ok: true, message: "Role alterado para #{params[:role]}." }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
