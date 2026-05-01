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

  # GET /push_tokens/diagnostic — lista tokens do usuário logado pra debug.
  def diagnostic
    tokens = current_user.push_tokens.order(created_at: :desc).map do |t|
      {
        id:           t.id,
        platform:     t.platform,
        last_seen_at: t.last_seen_at&.iso8601,
        created_at:   t.created_at.iso8601,
        token_prefix: t.token.to_s[0, 18] + "...",
      }
    end
    render json: {
      user_id: current_user.id,
      email:   current_user.email,
      role:    current_user.role,
      push_tokens_count: tokens.size,
      tokens: tokens,
    }
  end
end
