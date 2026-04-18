module Client
  class ReviewsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_client

    def create
      appointment = current_user.appointments.find_by(id: params[:appointment_id])

      if appointment.nil?
        return render_error("Agendamento não encontrado.", :not_found)
      end

      if appointment.review.present?
        return render_error("Este agendamento já foi avaliado.", :unprocessable_entity)
      end

      unless appointment.status == "attended"
        return render_error("Só é possível avaliar agendamentos concluídos.", :unprocessable_entity)
      end

      tags_value =
        case params[:tags]
        when Array  then params[:tags].reject(&:blank?).join(",")
        when String then params[:tags]
        else nil
        end

      @review = Review.new(
        appointment: appointment,
        car_wash:    appointment.car_wash,
        user:        current_user,
        rating:      params[:rating].to_i,
        tags:        tags_value,
        comment:     params[:comment].to_s.strip.presence
      )

      if @review.save
        respond_to do |format|
          format.html { redirect_to appointments_path, notice: "Avaliação enviada! Obrigado pelo feedback." }
          format.json do
            render json: {
              ok: true,
              review: {
                id:         @review.id,
                rating:     @review.rating,
                tags:       @review.tags_list,
                comment:    @review.comment,
                created_at: @review.created_at.iso8601
              }
            }
          end
        end
      else
        render_error(@review.errors.full_messages.join(", "), :unprocessable_entity)
      end
    end

    private

    def ensure_client
      return if current_user&.client?
      if request.format.json?
        render json: { error: "Acesso negado." }, status: :forbidden
      else
        redirect_to root_path
      end
    end

    def render_error(message, status)
      respond_to do |format|
        format.html { redirect_to appointments_path, alert: message }
        format.json { render json: { ok: false, error: message }, status: status }
      end
    end
  end
end
