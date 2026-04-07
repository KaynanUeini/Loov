module Client
  class NotificationsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_client

    def index
      # ── Disponível (últimos 7 dias)
      disponivel_notifs = current_user.appointments
        .where(appointment_type: "disponivel")
        .where("created_at >= ?", 7.days.ago)
        .includes(:service, :car_wash)
        .order(updated_at: :desc)
        .limit(20)
        .map do |a|
          {
            id:            "d#{a.id}",
            type:          "disponivel",
            status:        a.status,
            service_name:  a.service.title,
            car_wash_name: a.car_wash.name,
            scheduled_at:  a.scheduled_at.strftime("%d/%m às %H:%M"),
            notif_at:      a.updated_at.iso8601
          }
        end

      # ── Regular confirmado (últimos 7 dias)
      regular_confirmed = current_user.appointments
        .where(appointment_type: "regular")
        .where(status: %w[confirmed attended])
        .where("appointments.created_at >= ?", 7.days.ago)
        .includes(:service, :car_wash)
        .order(created_at: :desc)
        .limit(20)
        .map do |a|
          {
            id:            "r#{a.id}",
            type:          "regular_confirmed",
            status:        a.status,
            service_name:  a.service.title,
            car_wash_name: a.car_wash.name,
            scheduled_at:  a.scheduled_at.strftime("%d/%m às %H:%M"),
            notif_at:      a.created_at.iso8601
          }
        end

      # ── Cancelados pelo estabelecimento (últimos 30 dias)
      regular_cancelled = current_user.appointments
        .where(appointment_type: "regular", status: "cancelled")
        .where("appointments.updated_at >= ?", 30.days.ago)
        .includes(:service, :car_wash)
        .order(updated_at: :desc)
        .limit(20)
        .map do |a|
          {
            id:            "c#{a.id}",
            type:          "cancelled_by_establishment",
            status:        "cancelled",
            service_name:  a.service.title,
            car_wash_name: a.car_wash.name,
            scheduled_at:  a.scheduled_at.strftime("%d/%m às %H:%M"),
            notif_at:      a.updated_at.iso8601
          }
        end

      # ── Mensagens do estabelecimento (últimos 14 dias)
      car_wash_ids = current_user.appointments
        .where("appointments.created_at >= ?", 90.days.ago)
        .pluck(:car_wash_id)
        .uniq

      owner_msgs = OwnerMessage
        .where(car_wash_id: car_wash_ids)
        .where("created_at >= ?", 14.days.ago)
        .where("target = 'all' OR recipient_id = ?", current_user.id)
        .includes(:car_wash)
        .order(created_at: :desc)
        .limit(20)
        .map do |m|
          {
            id:            "m#{m.id}",
            type:          "owner_message",
            status:        "message",
            service_name:  m.body,
            car_wash_name: m.car_wash.name,
            scheduled_at:  m.created_at.strftime("%d/%m às %H:%M"),
            notif_at:      m.created_at.iso8601
          }
        end

      all_notifs = (disponivel_notifs + regular_confirmed + regular_cancelled + owner_msgs)
        .sort_by { |n| n[:notif_at] }
        .reverse

      render json: all_notifs
    end

    private

    def ensure_client
      render json: { error: "Acesso negado." }, status: :forbidden unless current_user&.client?
    end
  end
end
