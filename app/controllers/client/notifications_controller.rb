module Client
  # GET  /client/notifications              — lista agregada
  # PATCH /client/notifications/:id/read   — marca uma como lida
  # POST /client/notifications/read_all    — marca todas lidas
  #
  # Agrega pra o cliente:
  #   * Reservas Disponível confirmadas pelo dono
  #   * Reservas recusadas / canceladas / expiradas
  #   * Atendimentos concluídos (liberam avaliação)
  #   * Mensagens (OwnerMessage) direcionadas ao cliente ou broadcast
  #     dos lava-rápidos onde ele tem histórico recente
  class NotificationsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    def index
      render json: build_notifications
    end

    # PATCH /client/notifications/:id/read
    def read
      key = params[:id].to_s
      nr  = NotificationRead.find_or_initialize_by(user: current_user, key: key)
      nr.read_at = Time.current
      nr.save!
      render json: { ok: true }
    end

    # POST /client/notifications/read_all
    def read_all
      current = build_notifications
      now     = Time.current
      current.each do |n|
        nr = NotificationRead.find_or_initialize_by(user: current_user, key: n[:id])
        nr.read_at = now
        nr.save!
      end
      render json: { ok: true, marked: current.size }
    end

    private

    def ensure_client
      return if current_user&.client?
      render json: { error: "Acesso negado." }, status: :forbidden
    end

    def build_notifications
      reads = current_user.notification_reads.pluck(:key, :read_at).to_h
      list  = []

      # ── Appointments com mudanças recentes ────────────────────────────
      current_user.appointments
        .where("appointments.updated_at > ?", 7.days.ago)
        .includes(:car_wash, :service, :review)
        .each do |a|
          shop     = a.car_wash&.name || "Lava-rápido"
          svc      = a.service&.title || "Serviço"
          when_str = a.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m · %H:%M")

          case a.status
          when "confirmed"
            next unless a.appointment_type == "disponivel"
            key = "appt_confirmed-#{a.id}"
            list << {
              id: key, type: "appointment_confirmed",
              title: "Reserva confirmada",
              desc:  "#{shop} · #{svc} · #{when_str}",
              created_at: a.updated_at.iso8601,
              read: reads.key?(key)
            }
          when "rejected"
            key = "appt_rejected-#{a.id}"
            list << {
              id: key, type: "appointment_rejected",
              title: "Reserva recusada",
              desc:  "#{shop} não aceitou · #{svc} · #{when_str}",
              created_at: a.updated_at.iso8601,
              read: reads.key?(key)
            }
          when "cancelled"
            key = "appt_cancelled-#{a.id}"
            # owner/agent/closure → mesma mensagem clara ("X cancelou sua
            # reserva"). closure inclui o motivo do fechamento na desc.
            role     = a.cancelled_by_role.to_s
            by_owner = %w[owner agent closure].include?(role)
            reason   = a.cancellation_reason.to_s.strip

            if role == "closure"
              title = "#{shop} cancelou sua reserva — fechamento"
              desc  = "#{svc} em #{when_str}."
              desc << " #{reason}." if reason.present?
              desc << " Reagende quando quiser."
            elsif by_owner
              title = "#{shop} cancelou sua reserva"
              desc  = "#{svc} em #{when_str}."
              desc << " #{reason}." if reason.present?
              desc << " Reagende quando quiser."
            else
              title = "Reserva cancelada"
              desc  = "#{svc} em #{when_str} · #{shop}"
            end

            list << {
              id: key, type: "appointment_cancelled",
              title: title,
              desc:  desc,
              created_at: a.updated_at.iso8601,
              read: reads.key?(key)
            }
          when "attended"
            next if a.review.present?  # já avaliou, não precisa de aviso
            key = "appt_attended-#{a.id}"
            list << {
              id: key, type: "review_available",
              title: "Avalie seu atendimento",
              desc:  "#{shop} · #{svc}",
              created_at: a.updated_at.iso8601,
              read: reads.key?(key)
            }
          end
        end

      # ── Mensagens do dono ─────────────────────────────────────────────
      visited_car_wash_ids = current_user.appointments
        .where("scheduled_at > ?", 30.days.ago)
        .pluck(:car_wash_id).uniq

      OwnerMessage
        .where("owner_messages.created_at > ?", 7.days.ago)
        .where(
          "target = 'user' AND recipient_id = ? OR target = 'all' AND car_wash_id IN (?)",
          current_user.id, visited_car_wash_ids
        )
        .includes(:car_wash)
        .each do |m|
          key  = "owner_message-#{m.id}"
          shop = m.car_wash&.name || "Lava-rápido"
          list << {
            id: key, type: "owner_message",
            title: "Mensagem de #{shop}",
            desc:  m.body.to_s.truncate(120),
            created_at: m.created_at.iso8601,
            read: reads.key?(key)
          }
        end

      list.sort_by! { |n| -Time.iso8601(n[:created_at]).to_i }
      list
    end
  end
end
