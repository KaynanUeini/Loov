class StripeService
  def capture(payment_intent_id)
    Stripe::PaymentIntent.capture(payment_intent_id)
  end

  def refund(payment_intent_id, reason: "requested_by_customer")
    # Busca o payment intent para obter o charge
    intent = Stripe::PaymentIntent.retrieve(payment_intent_id)

    # Se já capturado, cria refund pelo charge
    if intent.latest_charge.present?
      Stripe::Refund.create(
        charge: intent.latest_charge,
        reason: reason
      )
    else
      # Se ainda não capturado (apenas autorizado), cancela o intent
      Stripe::PaymentIntent.cancel(payment_intent_id)
    end
  end

  # Libera uma pré-autorização (o valor some da fatura do cliente sem virar
  # cobrança). reject!/expire! já chamavam este método, que não existia —
  # o NoMethodError era engolido pelo rescue e a recusa falhava calada.
  def cancel(payment_intent_id)
    Stripe::PaymentIntent.cancel(payment_intent_id)
  end

  # Pré-autoriza (capture_method manual): o valor fica reservado no cartão e
  # só vira cobrança no capture. payment_method_types fixo em cartão porque
  # o confirm imediato com métodos automáticos exigiria return_url.
  def create_payment_intent(amount_cents:, currency: "brl", customer_id:, payment_method_id:, metadata: {})
    Stripe::PaymentIntent.create(
      amount:               amount_cents,
      currency:             currency,
      customer:             customer_id,
      payment_method:       payment_method_id,
      payment_method_types: ["card"],
      capture_method:       "manual",
      confirm:              true,
      # Se o banco pedir 3DS, a próxima ação fica no formato que o Stripe.js
      # resolve no navegador (stripe.handleNextAction), sem return_url.
      use_stripe_sdk:       true,
      metadata:             metadata
    )
  end

  def retrieve(payment_intent_id)
    Stripe::PaymentIntent.retrieve(payment_intent_id)
  end
end
