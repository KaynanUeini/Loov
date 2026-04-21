class PushTokensController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!

  # POST /push_tokens { token, platform }
  def create
    token    = params[:token].to_s.strip
    platform = params[:platform].to_s.strip.presence

    if token.blank?
      render json: { error: "Token ausente." }, status: :unprocessable_entity
      return
    end

    record = PushToken.find_or_initialize_by(token: token)
    record.user         = current_user
    record.platform     = platform if platform
    record.last_seen_at = Time.current
    record.save!

    render json: { ok: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /push_tokens/:token
  def destroy
    PushToken.where(user: current_user, token: params[:token]).destroy_all
    render json: { ok: true }
  end
end
