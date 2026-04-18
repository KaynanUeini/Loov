module Owner
  class NotificationsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant

    # GET /owner/notifications
    def index
      render json: build_notifications
    end

    # PATCH /owner/notifications/:id/read
    def read
      key = params[:id].to_s
      nr  = NotificationRead.find_or_initialize_by(user: current_user, key: key)
      nr.read_at = Time.current
      nr.save!
      render json: { ok: true }
    end

    # POST /owner/notifications/read_all
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

    def ensure_owner_or_attendant
      return if current_user&.owner? || current_user&.attendant?
      render json: { error: "Acesso negado." }, status: :forbidden
    end

    def build_notifications
      car_wash = current_user.car_washes.first
      reads    = current_user.notification_reads.pluck(:key, :read_at).to_h

      notifications = []

      # ── 1. Disponíveis aguardando aceite ────────────────────────────────────
      if car_wash
        car_wash.appointments
                .where(appointment_type: "disponivel", status: "pending_acceptance")
                .where("acceptance_expires_at > ?", Time.current)
                .includes(:user, :service)
                .each do |a|
          key = "disponivel-#{a.id}"
          notifications << {
            id:         key,
            type:       "disponivel",
            title:      "Pedido disponível aguardando aceite",
            desc:       "#{a.display_client} · #{a.service&.title} · #{a.scheduled_at.in_time_zone('America/Sao_Paulo').strftime('%H:%M')}",
            route:      "OwnerDisponivel",
            params:     { appointment_id: a.id },
            created_at: a.created_at.iso8601,
            read:       reads.key?(key)
          }
        end
      end

      # ── 2. Aprovações pendentes (apenas owner) ──────────────────────────────
      if current_user.owner? && car_wash
        car_wash.pending_changes.where(status: "pending").order(created_at: :desc).each do |pc|
          key = "pending_change-#{pc.id}"
          notifications << {
            id:         key,
            type:       "pending_change",
            title:      "Aprovação pendente",
            desc:       pc.description.to_s.truncate(120),
            route:      "OwnerMudancasPendentes",
            params:     {},
            created_at: pc.created_at.iso8601,
            read:       reads.key?(key)
          }
        end
      end

      # ── 3. Tickets de suporte com resposta nova ─────────────────────────────
      current_user.support_tickets
                  .where(status: %w[open in_progress])
                  .includes(:messages)
                  .each do |t|
        last = t.messages.order(:created_at).last
        next unless last && last.from_admin?
        key = "support_reply-#{t.id}-#{last.id}"
        notifications << {
          id:         key,
          type:       "support_reply",
          title:      "Nova resposta do suporte",
          desc:       last.body.to_s.truncate(120),
          route:      "OwnerSupport",
          params:     { ticket_id: t.id },
          created_at: last.created_at.iso8601,
          read:       reads.key?(key)
        }
      end

      # ── 4. AI Insights pronta ───────────────────────────────────────────────
      if car_wash
        insight = AiInsight.current_for(car_wash)
        if insight && insight.respond_to?(:ready?) && insight.ready? && !insight.expired?
          key = "ai_insight-#{insight.id}"
          notifications << {
            id:         key,
            type:       "ai_insight",
            title:      "Análise AI Insights pronta",
            desc:       "Sua análise do ciclo está disponível para revisão.",
            route:      "OwnerAiInsights",
            params:     {},
            created_at: insight.generated_at.iso8601,
            read:       reads.key?(key)
          }
        end
      end

      notifications.sort_by! { |n| -Time.iso8601(n[:created_at]).to_i }
      notifications
    end
  end
end
