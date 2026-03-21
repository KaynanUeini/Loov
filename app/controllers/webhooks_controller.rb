class WebhooksController < ApplicationController
  # Stripe envia webhooks sem CSRF token — necessário pular a verificação
  skip_before_action :verify_authenticity_token

  # POST /webhooks/stripe
  def stripe
    payload    = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = ENV["STRIPE_WEBHOOK_SECRET"]

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError => e
      Rails.logger.error("Stripe webhook JSON error: #{e.message}")
      render json: { error: "Invalid payload" }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("Stripe webhook signature error: #{e.message}")
      render json: { error: "Invalid signature" }, status: :bad_request
      return
    end

    case event.type

    # PaymentIntent autorizado com sucesso pelo cliente
    # (cliente pagou no checkout, aguardando aceite do dono)
    when "payment_intent.amount_capturable_updated"
      handle_intent_authorized(event.data.object)

    # PaymentIntent capturado (dono aceitou)
    when "payment_intent.succeeded"
      handle_intent_captured(event.data.object)

    # PaymentIntent cancelado (dono recusou ou timeout)
    when "payment_intent.canceled"
      handle_intent_cancelled(event.data.object)

    else
      Rails.logger.info("Stripe webhook: evento não tratado #{event.type}")
    end

    render json: { received: true }
  end

  private

  def handle_intent_authorized(intent)
    appointment = Appointment.find_by(stripe_payment_intent_id: intent.id)
    return unless appointment

    Rails.logger.info("Stripe: PaymentIntent #{intent.id} autorizado para appointment ##{appointment.id}")
    # O status do agendamento já é pending_acceptance — nada a fazer aqui
    # O aceite acontece via painel do dono
  end

  def handle_intent_captured(intent)
    appointment = Appointment.find_by(stripe_payment_intent_id: intent.id)
    return unless appointment

    Rails.logger.info("Stripe: PaymentIntent #{intent.id} capturado — appointment ##{appointment.id} confirmado")
    # Já foi tratado no accept! do model — apenas log
  end

  def handle_intent_cancelled(intent)
    appointment = Appointment.find_by(stripe_payment_intent_id: intent.id)
    return unless appointment

    Rails.logger.info("Stripe: PaymentIntent #{intent.id} cancelado — appointment ##{appointment.id}")

    # Se ainda está pending, marca como cancelado
    if appointment.pending_acceptance?
      appointment.update!(status: "cancelled")
    end
  end
end
