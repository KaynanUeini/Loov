class SupportAgentService
  KB_PATH = Rails.root.join("config", "support_agent_kb.txt")

  def initialize(ticket)
    @ticket   = ticket
    @car_wash = ticket.user.car_washes.first
  end

  def run
    result = try_autonomous_action
    return result if result[:autonomous]
    draft_result = generate_draft
    { autonomous: false }.merge(draft_result || { error: true })
  end

  def generate_draft
    return nil if already_replied_by_admin?
    thread_context = build_thread_context
    kb             = load_knowledge_base
    prompt         = build_prompt(thread_context, kb)
    response       = call_claude(prompt)
    return nil if response.nil?
    parsed = parse_response(response)
    return nil if parsed.nil?

    if parsed[:should_escalate]
      Rails.logger.info("[SupportAgent] Ticket ##{@ticket.id} escalação: #{parsed[:reason]}")
      # Mantém rascunho pra admin revisar depois (não auto-posta).
      if parsed[:draft].present?
        @ticket.update_columns(agent_draft: parsed[:draft], agent_drafted_at: Time.current, agent_sent: false)
      else
        @ticket.update_columns(agent_draft: "[Escalado: #{parsed[:reason]}]", agent_drafted_at: Time.current, agent_sent: false)
      end
      # Posta uma mensagem informando que um humano vai revisar.
      post_agent_message(
        "Recebi sua mensagem e estou direcionando para um especialista da equipe Loov. " \
        "Você receberá uma resposta em breve por aqui mesmo."
      )
      return { escalate: true, reason: parsed[:reason] }
    end

    # AUTO-RESPOSTA: agente confiante → posta direto como mensagem do suporte.
    @ticket.update_columns(
      status:           "in_progress",
      agent_draft:      parsed[:draft],
      agent_drafted_at: Time.current,
    )
    post_agent_message(parsed[:draft])
    { draft: parsed[:draft], escalate: false, auto_replied: true }
  rescue => e
    Rails.logger.error("[SupportAgent] Erro draft ticket ##{@ticket.id}: #{e.message}")
    nil
  end

  def approve_and_send!(admin_user, custom_body = nil)
    body = custom_body.presence || @ticket.agent_draft
    return false if body.blank?
    ActiveRecord::Base.transaction do
      @ticket.messages.create!(user: admin_user, body: body, from_admin: true)
      @ticket.update_columns(status: "in_progress", agent_sent: true, updated_at: Time.current)
    end
    true
  rescue => e
    Rails.logger.error("[SupportAgent] Erro approve ticket ##{@ticket.id}: #{e.message}")
    false
  end

  private

  # ── AÇÕES AUTÔNOMAS ────────────────────────────────────────────────────────
  def try_autonomous_action
    # Owner confirmou cancelamento pendente → executa
    if awaiting_confirmation? && owner_confirmed?
      pending = load_pending_appointments
      return autonomous_execute_cancel(pending) if pending.any?
    end

    # Owner negou → aborta
    if awaiting_confirmation? && owner_denied?
      post_agent_message("Entendido, nenhum agendamento foi cancelado. Posso ajudar com mais alguma coisa?")
      resolve_ticket!
      return { autonomous: true, action: "aborted_by_owner" }
    end

    # Nova solicitação de cancelamento
    return autonomous_cancel_disponivel if cancelamento_disponivel?

    { autonomous: false }
  end

  def cancelamento_disponivel?
    cat = @ticket.category.to_s.downcase
    return false unless %w[cancelamento disponivel].include?(cat)
    all_text = @ticket.messages.map(&:body).join(" ").downcase
    keywords = %w[cancelar cancela cancelamento estorno reembolso devolver devolução]
    keywords.any? { |k| all_text.include?(k) } || cat == "cancelamento"
  end

  def autonomous_cancel_disponivel
    return { autonomous: false } unless @car_wash

    appointments = @car_wash.appointments
      .where(appointment_type: "disponivel", status: %w[confirmed pending_acceptance])
      .where("scheduled_at >= ?", 12.hours.ago)
      .includes(:user, :service)
      .order(:scheduled_at)

    if appointments.empty?
      post_agent_message(
        "Olá! Verifiquei seus agendamentos ativos do tipo Disponível e não encontrei nenhum " \
        "pendente no momento. Se o agendamento já foi atendido ou cancelado anteriormente, " \
        "o estorno não é mais aplicável. Caso acredite que há um erro, responda com o " \
        "horário e data do agendamento para que possamos verificar manualmente."
      )
      resolve_ticket!
      return { autonomous: true, action: "no_appointments_found" }
    end

    if appointments.count == 1
      # Sempre pede confirmação antes de agir
      return request_confirmation(appointments.to_a)
    end

    # Múltiplos — tenta interpretar quais o owner quer cancelar
    selected = interpret_selection(appointments)

    if selected.nil?
      # Não conseguiu interpretar — lista e pede que especifique
      list = appointments.map { |a|
        "• #{a.scheduled_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M')} — #{a.service.title} (#{a.user&.email || 'cliente'})"
      }.join("\n")
      post_agent_message(
        "Encontrei #{appointments.count} agendamentos Disponível ativos:\n\n#{list}\n\n" \
        "Por favor, informe quais deseja cancelar (pode dizer \"todos\", \"ambos\" ou especificar pelo horário/e-mail)."
      )
      @ticket.update_columns(status: "in_progress", updated_at: Time.current)
      return { autonomous: true, action: "awaiting_selection" }
    end

    # Tem seleção — pede confirmação
    request_confirmation(selected)
  end

  # ── CONFIRMAÇÃO ────────────────────────────────────────────────────────────
  def request_confirmation(appointments)
    list = appointments.map { |a|
      "• #{a.scheduled_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M')} — #{a.service.title} (#{a.user&.email || 'cliente'})"
    }.join("\n")

    msg = appointments.count == 1 ?
      "Encontrei o seguinte agendamento Disponível ativo:\n\n#{list}\n\nDeseja confirmar o cancelamento e processar o estorno ao cliente? Responda sim ou não." :
      "Encontrei #{appointments.count} agendamentos para cancelar:\n\n#{list}\n\nDeseja confirmar o cancelamento de todos e processar os estornos? Responda sim ou não."

    post_agent_message(msg)

    # Guarda IDs pendentes no agent_draft
    @ticket.update_columns(
      status:      "in_progress",
      agent_draft: "pending_cancel:#{appointments.map(&:id).join(',')}",
      updated_at:  Time.current
    )
    { autonomous: true, action: "awaiting_confirmation" }
  end

  def awaiting_confirmation?
    @ticket.reload.agent_draft.to_s.start_with?("pending_cancel:")
  end

  def owner_confirmed?
    last_msg = @ticket.messages.where(from_admin: false).order(:created_at).last&.body.to_s.downcase
    %w[sim yes confirmo pode ok isso].any? { |k| last_msg.include?(k) }
  end

  def owner_denied?
    last_msg = @ticket.messages.where(from_admin: false).order(:created_at).last&.body.to_s.downcase
    %w[nao não nope].any? { |k| last_msg.include?(k) }
  end

  def load_pending_appointments
    ids = @ticket.reload.agent_draft.to_s.sub("pending_cancel:", "").split(",").map(&:to_i)
    Appointment.where(id: ids, status: %w[confirmed pending_acceptance])
  end

  # ── SELEÇÃO ────────────────────────────────────────────────────────────────
  def interpret_selection(appointments)
    all_owner_msgs = @ticket.messages
      .where(from_admin: false)
      .order(:created_at)
      .pluck(:body)
      .join(" ")
      .downcase

    # Palavras que significam todos
    all_keywords = %w[ambos todos todas dois duas tudo qualquer]
    return appointments.to_a if all_keywords.any? { |k| all_owner_msgs.include?(k) }

    # Poucas mensagens + cancelar → todos
    owner_msg_count = @ticket.messages.where(from_admin: false).count
    return appointments.to_a if owner_msg_count <= 2 && all_owner_msgs.include?("cancelar")

    # Identifica por email ou horário
    last_msg = @ticket.messages.where(from_admin: false).order(:created_at).last&.body.to_s.downcase
    matched = appointments.select do |a|
      email = a.user&.email.to_s.downcase
      time  = a.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
      date  = a.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m")
      last_msg.include?(email) || last_msg.include?(time) || last_msg.include?(date)
    end
    return matched unless matched.empty?

    # Número digitado
    indices = last_msg.scan(/\d+/).map { |n| n.to_i - 1 }.select { |i| i >= 0 && i < appointments.size }
    return indices.map { |i| appointments.to_a[i] } unless indices.empty?

    nil
  end

  # ── EXECUÇÃO ───────────────────────────────────────────────────────────────
  def autonomous_execute_cancel(appointments_arr)
    appointments = Array(appointments_arr)
    ActiveRecord::Base.transaction do
      cancelled_summaries = []
      refund_issues       = []
      stripe_service      = StripeService.new

      appointments.each do |appt|
        appt.update_columns(
          status:              "cancelled",
          cancelled_by_id:     nil,
          cancelled_by_role:   "agent",
          cancellation_reason: "Cancelamento solicitado pelo proprietário via suporte Loov",
          updated_at:          Time.current
        )

        refund_note = ""
        if appt.stripe_payment_intent_id.present?
          begin
            # SEGURANÇA: verifica que o payment_intent pertence ao appointment
            # antes de processar o estorno — previne estornos arbitrários via IDOR
            intent = Stripe::PaymentIntent.retrieve(appt.stripe_payment_intent_id)
            expected_appt_id = intent.metadata&.dig("appointment_id").to_s
            if expected_appt_id.present? && expected_appt_id != appt.id.to_s
              raise "Payment intent não pertence a este agendamento"
            end
            stripe_service.refund(appt.stripe_payment_intent_id)
            refund_note = " (estorno processado)"
            Rails.logger.info("[SupportAgent] Estorno ok — ##{appt.id}")
          rescue => e
            Rails.logger.error("[SupportAgent] Erro estorno ##{appt.id}: #{e.message}")
            refund_note = " (estorno manual necessário)"
            refund_issues << appt.id
          end
        else
          refund_note = " (sem pagamento registrado)"
        end

        if appt.user.present?
          begin
            AppointmentMailer.owner_cancellation(appt).deliver_now
          rescue => e
            Rails.logger.error("[SupportAgent] Email falhou ##{appt.id}: #{e.message}")
          end
        end

        scheduled = appt.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m às %H:%M")
        cancelled_summaries << "• #{scheduled} — #{appt.service.title} (#{appt.user&.email || 'avulso'})#{refund_note}"
      end

      refund_msg = refund_issues.any? ?
        " Atenção: os agendamentos #{refund_issues.map { |id| "##{id}" }.join(", ")} precisam de estorno manual." :
        " Todos os valores foram estornados e serão creditados em até 5 dias úteis."

      client_word = appointments.count == 1 ? "O cliente foi notificado" : "Os clientes foram notificados"
      post_agent_message(
        "Cancelamento realizado com sucesso:\n\n" \
        "#{cancelled_summaries.join("\n")}\n\n" \
        "#{client_word} por e-mail.#{refund_msg}"
      )
      resolve_ticket!
    end

    { autonomous: true, action: "cancelled_and_refunded" }
  rescue => e
    Rails.logger.error("[SupportAgent] Erro ao cancelar: #{e.message}")
    { autonomous: false, error: e.message }
  end

  # ── HELPERS ────────────────────────────────────────────────────────────────
  def post_agent_message(body)
    @ticket.messages.create!(
      user:       User.find_by(role: "admin") || @ticket.user,
      body:       body,
      from_admin: true
    )
    @ticket.update_columns(agent_sent: true, updated_at: Time.current)
  end

  def resolve_ticket!
    @ticket.update_columns(status: "resolved", resolved_at: Time.current, updated_at: Time.current)
  end

  def already_replied_by_admin?
    last_owner_msg_at = @ticket.messages.where(from_admin: false).maximum(:created_at)
    return false if last_owner_msg_at.nil?
    @ticket.messages.where(from_admin: true).where("created_at > ?", last_owner_msg_at).exists?
  end

  def build_thread_context
    messages = @ticket.messages.chronological.map do |m|
      role = m.from_admin? ? "Suporte Loov" : "Proprietário"
      "[#{role} — #{m.created_at.strftime('%d/%m %H:%M')}]: #{m.body}"
    end
    {
      ticket_id:   @ticket.id,
      category:    @ticket.category,
      status:      @ticket.status,
      opened_at:   @ticket.created_at.strftime("%d/%m/%Y %H:%M"),
      car_wash:    @car_wash&.name || "não identificado",
      owner_ref:   "USR_#{@ticket.user_id}",  # anonimizado — não envia PII à API externa
      messages:    messages.join("\n\n")
    }
  end

  def load_knowledge_base
    File.read(KB_PATH)
  rescue => e
    Rails.logger.warn("[SupportAgent] KB não encontrada: #{e.message}")
    "Base de conhecimento não disponível."
  end

  def build_prompt(ctx, kb)
    last_owner_question = @ticket.messages.where(from_admin: false).order(:created_at).last&.body || ""
    <<~PROMPT
      Você é o suporte da Loov, um marketplace de agendamento de lava-rápidos no Brasil.
      Responda sempre em português, com tom profissional e cordial.
      Você representa a Loov — não o lava-rápido específico.
      Seja direto: explique exatamente onde clicar e como fazer, passo a passo.

      BASE DE CONHECIMENTO COMPLETA DA LOOV:
      #{kb}

      TICKET ##{ctx[:ticket_id]}:
      - Categoria: #{ctx[:category]}
      - Lava-rápido: #{ctx[:car_wash]}
      - Referência interna: #{ctx[:owner_ref]}
      - Aberto em: #{ctx[:opened_at]}

      HISTÓRICO COMPLETO DA CONVERSA:
      #{ctx[:messages]}

      ÚLTIMA PERGUNTA DO PROPRIETÁRIO:
      "#{last_owner_question}"

      INSTRUÇÕES OBRIGATÓRIAS:
      1. Responda APENAS à última pergunta do proprietário.
      2. Se a resposta estiver na base de conhecimento: explique passo a passo.
      3. Se NÃO estiver na base, ou envolver Stripe, disputa, bug crítico ou exclusão: indique escalação.
      4. Máximo 4 parágrafos curtos. Sem markdown com asteriscos — texto limpo.
      5. Termine sempre oferecendo ajuda adicional.
      6. NUNCA invente funcionalidades que não existem na base de conhecimento.

      RESPONDA APENAS EM JSON VÁLIDO, sem texto antes ou depois:
      {
        "should_escalate": false,
        "reason": null,
        "draft": "texto da resposta aqui"
      }

      Se não souber responder:
      {
        "should_escalate": true,
        "reason": "motivo em 1 frase",
        "draft": null
      }
    PROMPT
  end

  def parse_response(raw)
    clean = raw.gsub(/```json|```/, "").strip
    data  = JSON.parse(clean)
    { should_escalate: data["should_escalate"] == true, reason: data["reason"], draft: data["draft"] }
  rescue => e
    Rails.logger.error("[SupportAgent] Erro ao parsear: #{e.message}")
    nil
  end

  def call_claude(prompt)
    require "net/http"
    require "json"
    uri  = URI("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 30
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]      = "application/json"
    request["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    request["anthropic-version"] = "2023-06-01"
    request.body = {
      model:      "claude-haiku-4-5",
      max_tokens: 1024,
      messages:   [{ role: "user", content: prompt }]
    }.to_json
    response = http.request(request)
    body     = JSON.parse(response.body)
    raise "API error: #{body['error']&.dig('message')}" if body["error"]
    body.dig("content", 0, "text")
  end
end
