class StripeService
  # ── CRIAR PAYMENT INTENT ──────────────────────────────────────────────────
  # Cria um PaymentIntent com capture_method: :manual
  # O dinheiro é autorizado mas NÃO capturado até o aceite do dono.
  # Se o dono recusar ou timeout → cancel → sem cobrança ao cliente.
  # Se o dono aceitar → capture → cliente é cobrado.
  #
  # amount_cents: valor em centavos (ex: 1575 para R$ 15,75)
  # metadata: hash com informações do agendamento para referência
  def create_disponivel_intent(amount_cents:, metadata: {})
    Stripe::PaymentIntent.create({
      amount:         amount_cents,
      currency:       "brl",
      capture_method: :manual,          # autoriza mas não captura
      confirm:        false,             # cliente confirma no frontend via Elements
      metadata:       metadata.merge(source: "loov_disponivel")
    })
  rescue Stripe::StripeError => e
    Rails.logger.error("StripeService#create_disponivel_intent: #{e.message}")
    raise
  end

  # ── CAPTURAR (aceite do dono) ─────────────────────────────────────────────
  # Captura o valor autorizado — cliente é efetivamente cobrado
  def capture(payment_intent_id)
    Stripe::PaymentIntent.capture(payment_intent_id)
  rescue Stripe::StripeError => e
    Rails.logger.error("StripeService#capture #{payment_intent_id}: #{e.message}")
    raise
  end

  # ── CANCELAR (rejeição ou timeout) ───────────────────────────────────────
  # Cancela o PaymentIntent antes da captura — cliente NÃO é cobrado
  def cancel(payment_intent_id)
    intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
    # Só cancela se ainda está em estado cancelável
    return if %w[canceled succeeded].include?(intent.status)
    Stripe::PaymentIntent.cancel(payment_intent_id)
  rescue Stripe::StripeError => e
    Rails.logger.error("StripeService#cancel #{payment_intent_id}: #{e.message}")
    raise
  end

  # ── BUSCAR ────────────────────────────────────────────────────────────────
  def retrieve(payment_intent_id)
    Stripe::PaymentIntent.retrieve(payment_intent_id)
  rescue Stripe::StripeError => e
    Rails.logger.error("StripeService#retrieve #{payment_intent_id}: #{e.message}")
    raise
  end
end
