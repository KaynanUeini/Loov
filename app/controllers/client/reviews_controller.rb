module Client
  class ReviewsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_client

    def create
      appointment = current_user.appointments.find(params[:appointment_id])

      if appointment.review.present?
        redirect_to appointments_path, alert: "Este agendamento já foi avaliado."
        return
      end

      unless appointment.status == "confirmed" && appointment.scheduled_at < Time.current
        redirect_to appointments_path, alert: "Só é possível avaliar agendamentos concluídos."
        return
      end

      @review = Review.new(
        appointment: appointment,
        car_wash:    appointment.car_wash,
        user:        current_user,
        rating:      params[:rating],
        tags:        params[:tags],
        comment:     params[:comment]
      )

      if @review.save
        redirect_to appointments_path, notice: "Avaliação enviada! Obrigado pelo feedback."
      else
        redirect_to appointments_path, alert: "Erro ao enviar avaliação."
      end
    end

    private

    def ensure_client
      redirect_to root_path unless current_user&.client?
    end
  end
end
