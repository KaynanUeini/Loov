class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
  :recoverable, :rememberable, :validatable,
  :jwt_authenticatable, jwt_revocation_strategy: Devise::JWT::RevocationStrategies::Null

  has_many :appointments,          dependent: :destroy
  has_many :car_washes,            dependent: :destroy
  has_many :support_tickets,       dependent: :destroy
  has_many :notification_reads,    dependent: :destroy
  has_many :push_tokens,           dependent: :destroy
  has_many :favorite_car_washes,   dependent: :destroy
  has_many :favorite_shops,        through: :favorite_car_washes, source: :car_wash
  has_many :sent_invitations,      class_name: "AttendantInvitation", foreign_key: :inviter_id,   dependent: :destroy
  has_many :attendant_invitations, class_name: "AttendantInvitation", foreign_key: :attendant_id, dependent: :nullify

  validates :role, presence: true, inclusion: { in: %w(client owner attendant admin), message: "deve ser 'client', 'owner', 'attendant' ou 'admin'" }
  validates :full_name, presence: { message: "é obrigatório" }, if: :client?
  validates :phone,     presence: { message: "é obrigatório" }, if: :client?
  validates :cpf, format: { with: /\A\d{3}\.\d{3}\.\d{3}-\d{2}\z/, message: "formato inválido (ex: 000.000.000-00)" }, allow_blank: true
  # Um regex cobre os dois padrões brasileiros: antigo ABC1234 e Mercosul
  # ABC1D23 (a 5ª posição aceita letra ou dígito).
  validates :vehicle_plate, format: { with: /\A[A-Z]{3}[0-9][A-Z0-9][0-9]{2}\z/, message: "placa inválida (ex: ABC1D23 ou ABC1234)" }, allow_blank: true

  # before_validation, não before_save: a normalização precisa acontecer ANTES
  # do regex acima, senão "abc-1234" seria rejeitado sem nunca ser normalizado.
  before_validation :normalize_vehicle_plate

  def client?;    role == "client";    end
  def owner?;     role == "owner";     end
  def attendant?; role == "attendant"; end
  def admin?;     role == "admin";     end

  def display_name
    full_name.presence || email.split("@").first.capitalize
  end

  # Primeiro nome pra saudação ("Oi, Kaynan."). Nil quando o nome não parece
  # nome de gente (vazio, ou com _ e dígitos de username): melhor um "Oi!"
  # do que "Oi, Premium_maria4."
  def greeting_name
    first = full_name.to_s.strip.split(/\s+/).first
    return nil if first.blank? || first.match?(/[_\d@]/)
    first.capitalize
  end

  def normalize_vehicle_plate
    return if vehicle_plate.nil?
    self.vehicle_plate = vehicle_plate.to_s.upcase.gsub(/[^A-Z0-9]/, "").presence
  end

  def initials
    if full_name.present?
      full_name.split(" ").first(2).map { |n| n[0] }.join.upcase
    else
      email[0].upcase
    end
  end

  def profile_complete?
    full_name.present? && phone.present?
  end

  # "ABC1234" → "ABC-1234". Mercosul (ABC1D23) não usa hífen, sai como está.
  def vehicle_plate_display
    plate = vehicle_plate.to_s
    return nil if plate.blank?
    plate.match?(/\A[A-Z]{3}[0-9]{4}\z/) ? "#{plate[0, 3]}-#{plate[3, 4]}" : plate
  end

  # Como o carro aparece pro dono: placa primeiro, que é o que identifica no
  # pátio; modelo como complemento.
  def vehicle_label
    [vehicle_plate_display, vehicle_model.presence].compact.join(" · ").presence
  end

  def linked_car_wash
    if owner?
      car_washes.first
    elsif attendant?
      accepted = attendant_invitations.accepted.includes(:car_wash).first
      accepted&.car_wash
    end
  end

  # ── STRIPE ────────────────────────────────────────────────────────────────

  def has_payment_method?
    stripe_payment_method_id.present?
  end

  # Garante que o cliente tem um Customer no Stripe, criando se necessário
  def stripe_customer!
    if stripe_customer_id.present?
      Stripe::Customer.retrieve(stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email:    email,
        name:     display_name,
        metadata: { loov_user_id: id }
        )
      update_column(:stripe_customer_id, customer.id)
      customer
    end
  rescue Stripe::StripeError => e
    Rails.logger.error("User#stripe_customer! error: #{e.message}")
    raise
  end

  # Salva um PaymentMethod no cliente e o define como padrão
  def attach_payment_method!(payment_method_id)
    previous = stripe_payment_method_id
    customer = stripe_customer!
    pm = Stripe::PaymentMethod.attach(payment_method_id, { customer: customer.id })
    Stripe::Customer.update(customer.id, { invoice_settings: { default_payment_method: pm.id } })
    update!(
      stripe_payment_method_id: pm.id,
      stripe_card_last4:        pm.card&.last4,
      stripe_card_brand:        pm.card&.brand&.capitalize,
      stripe_card_holder:       pm.billing_details&.name.presence,
      stripe_card_exp_month:    pm.card&.exp_month,
      stripe_card_exp_year:     pm.card&.exp_year
      )
    # Trocou de cartão: o antigo sai do Stripe também. Cartão que a Loov não
    # usa mais não deve continuar disponível pra cobrança.
    if previous.present? && previous != pm.id
      Stripe::PaymentMethod.detach(previous) rescue nil
    end
    pm
  rescue Stripe::StripeError => e
    Rails.logger.error("User#attach_payment_method! error: #{e.message}")
    raise
  end

  # Remove o cartão salvo
  def detach_payment_method!
    return unless stripe_payment_method_id.present?
    Stripe::PaymentMethod.detach(stripe_payment_method_id) rescue nil
    update!(stripe_payment_method_id: nil, stripe_card_last4: nil, stripe_card_brand: nil,
            stripe_card_holder: nil, stripe_card_exp_month: nil, stripe_card_exp_year: nil)
  end

  # ── Exclusão de conta ─────────────────────────────────────────────────────
  # Domínio .invalid nunca recebe e-mail (RFC 2606): marca a conta excluída
  # sem coluna nova e sem colidir com o e-mail de ninguém.
  DOMINIO_EXCLUIDA = "conta-excluida.invalid".freeze

  def conta_excluida?
    email.to_s.end_with?("@#{DOMINIO_EXCLUIDA}")
  end

  # Devise consulta isto a cada login E a cada requisição com token do app:
  # conta excluída ou bloqueada pelo admin deixa de entrar na hora, inclusive
  # com um token antigo que ainda não venceu.
  def active_for_authentication?
    super && !conta_excluida? && !(has_attribute?(:blocked_at) && blocked_at.present?)
  end

  def inactive_message
    conta_excluida? ? :conta_excluida : (has_attribute?(:blocked_at) && blocked_at.present? ? :conta_bloqueada : super)
  end

  # Cliente e funcionário: a conta vira anônima na hora. Não é um destroy:
  # apagar a linha levaria junto os atendimentos do caixa e do financeiro do
  # lava-rápido (e as avaliações), que são registro do negócio, não dado da
  # pessoa. Sai tudo o que identifica alguém; fica o histórico sem dono.
  #
  # Dono: não exclui sozinho (há clientes com horário marcado, Last Minute
  # pago e financeiro a fechar). Vira um chamado pra equipe concluir.
  #
  # Devolve :excluida ou :solicitada.
  def excluir_conta!
    return solicitar_exclusao! if owner?

    agora = Time.current
    transaction do
      # Agendamentos futuros: o horário volta pro lava-rápido. Pedido de Last
      # Minute ainda em aceite tem a reserva no cartão desfeita; o já aceito
      # segue a regra de sempre (o cliente desistiu, não há reembolso).
      appointments.where(status: %w[confirmed pending_acceptance awaiting_payment])
                  .where("scheduled_at > ?", agora).find_each do |a|
        if %w[pending_acceptance awaiting_payment].include?(a.status) && a.stripe_payment_intent_id.present?
          StripeService.new.cancel(a.stripe_payment_intent_id) rescue nil
        end
        a.update_columns(status: "cancelled", cancelled_by_id: id, cancelled_by_role: role,
                         cancellation_reason: "Conta do cliente excluída", updated_at: agora)
      end

      # Funcionário sai da equipe do lava-rápido.
      AttendantInvitation.where(attendant_id: id).destroy_all if attendant?

      push_tokens.destroy_all
      favorite_car_washes.destroy_all
      notification_reads.destroy_all

      update_columns(
        email:                 "excluida-#{id}-#{SecureRandom.hex(4)}@#{DOMINIO_EXCLUIDA}",
        encrypted_password:    Devise::Encryptor.digest(self.class, SecureRandom.hex(32)),
        full_name:             "Conta excluída",
        phone: nil, cpf: nil, vehicle_model: nil, vehicle_plate: nil,
        reset_password_token: nil, reset_password_sent_at: nil, remember_created_at: nil,
        stripe_payment_method_id: nil, stripe_card_last4: nil, stripe_card_brand: nil,
        stripe_card_holder: nil, stripe_card_exp_month: nil, stripe_card_exp_year: nil,
        updated_at: agora
      )
    end

    # Fora da transação: o cartão e o cadastro no Stripe saem por último e,
    # se o Stripe falhar, a conta já está anônima do lado da Loov.
    if stripe_customer_id.present?
      Stripe::Customer.delete(stripe_customer_id) rescue Rails.logger.warn("[User##{id}] Stripe customer não removido")
      update_column(:stripe_customer_id, nil)
    end
    :excluida
  end

  def solicitar_exclusao!
    aberto = support_tickets.pending.where(category: "cadastro")
                            .where("description LIKE ?", "Exclusão de conta%").first
    return :solicitada if aberto

    ticket = support_tickets.create!(
      category: "cadastro", status: "open", car_wash: car_washes.first,
      description: "Exclusão de conta solicitada pelo dono"
    )
    ticket.messages.create!(user: self, from_admin: false,
                            body: "Quero excluir minha conta e o meu lava-rápido da Loov.")
    ticket.messages.create!(
      user:       User.find_by(role: "admin") || self,
      from_admin: true,
      body:       "Recebemos seu pedido de exclusão. Antes de concluir, a equipe Loov confere os " \
                  "agendamentos marcados, os pagamentos do Last Minute e o financeiro, e te avisa por " \
                  "aqui. Se mudar de ideia, é só responder nesta conversa."
    )
    :solicitada
  end

  # Card display string ex: "Visa •••• 4242"
  def card_display
    return nil unless has_payment_method?
    "#{stripe_card_brand} •••• #{stripe_card_last4}"
  end
end
