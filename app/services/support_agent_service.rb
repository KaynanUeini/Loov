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
    Rails.logger.info("[SupportAgent] generate_draft start ticket=##{@ticket.id} cat=#{@ticket.category}")

    if already_replied_by_admin?
      Rails.logger.info("[SupportAgent] já respondido pelo admin — pulando")
      return nil
    end

    if ENV["ANTHROPIC_API_KEY"].to_s.strip.empty?
      Rails.logger.error("[SupportAgent] ANTHROPIC_API_KEY ausente — postando fallback")
      post_agent_message(fallback_no_api_message)
      return { fallback: true, escalate: false }
    end

    thread_context = build_thread_context
    kb             = load_knowledge_base
    prompt         = build_prompt(thread_context, kb)
    Rails.logger.info("[SupportAgent] prompt size=#{prompt.size} kb_size=#{kb.size}")

    response = call_claude(prompt)
    if response.nil?
      Rails.logger.error("[SupportAgent] Claude retornou nil — postando fallback")
      post_agent_message(fallback_claude_failed_message)
      return { fallback: true, escalate: false }
    end

    parsed = parse_response(response)
    if parsed.nil?
      Rails.logger.error("[SupportAgent] parse falhou — raw=#{response.to_s.slice(0, 200)}")
      post_agent_message(fallback_claude_failed_message)
      return { fallback: true, escalate: false }
    end

    Rails.logger.info("[SupportAgent] parsed escalate=#{parsed[:should_escalate]} draft_size=#{parsed[:draft].to_s.size}")

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

    # Owner refinou seleção (ex: "só o 1", "apenas o João") em vez de sim/não.
    # Re-interpreta sobre a lista pendente e re-pergunta confirmação se for
    # um subconjunto válido.
    if awaiting_confirmation?
      pending = load_pending_appointments.to_a
      if pending.size > 1
        refined = interpret_selection(pending)
        if refined && refined.any? && refined.size < pending.size
          return request_confirmation(refined)
        end
      end
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
      # Não conseguiu interpretar — lista NUMERADA e pede que especifique.
      list = appointments.each_with_index.map { |a, i|
        "#{i + 1}. #{a.scheduled_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M')} — #{a.service.title} (#{a.user&.display_name || 'cliente'})"
      }.join("\n")
      post_agent_message(
        "Encontrei #{appointments.count} agendamentos Disponível ativos. Qual(is) deseja cancelar?\n\n" \
        "#{list}\n\n" \
        "Responda com o número (ex: \"1\" ou \"1 e 3\"), o nome do cliente ou \"todos\" se forem todos."
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
      "• #{a.scheduled_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M')} — #{a.service.title} (#{a.user&.display_name || 'cliente'})"
    }.join("\n")

    msg = if appointments.count == 1
      "Vou cancelar o seguinte agendamento e processar o estorno:\n\n#{list}\n\n" \
      "Confirma? Responda sim ou não."
    else
      "Vou cancelar #{appointments.count} agendamentos e processar os estornos:\n\n#{list}\n\n" \
      "Confirma TODOS esses? Responda sim ou não — se quiser cancelar apenas alguns, " \
      "diga quais (pode usar o número da lista ou o nome do cliente)."
    end

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
    last_msg = @ticket.messages.where(from_admin: false).order(:created_at).last&.body.to_s.downcase

    # "Todos" só é aceito quando o dono diz EXPLICITAMENTE na ÚLTIMA
    # mensagem — não basta ter aparecido em algum momento. Isso evita
    # falso positivo do tipo "quero cancelar todos" interpretado a partir
    # da primeira mensagem genérica "quero cancelar".
    all_keywords = %w[ambos todos todas tudo qualquer]
    if all_keywords.any? { |k| last_msg.include?(k) }
      return appointments.to_a
    end

    # Identifica por nome do cliente, email ou horário.
    # O dono vê NOME no card e na mensagem do agente, então prioriza match
    # por display_name e first_name; email fica como fallback.
    matched = appointments.select do |a|
      email      = a.user&.email.to_s.downcase
      display    = a.user&.display_name.to_s.downcase
      first_name = display.split(" ").first.to_s
      time       = a.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
      date       = a.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m")
      (display.present?      && last_msg.include?(display))    ||
      (first_name.length > 2 && last_msg.include?(first_name)) ||
      (email.present?        && last_msg.include?(email))      ||
      last_msg.include?(time) ||
      last_msg.include?(date)
    end
    return matched unless matched.empty?

    # Número digitado (1, 2, 3...) referente à lista numerada
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
          # 1) E-mail — best-effort
          begin
            AppointmentMailer.owner_cancellation(appt).deliver_now
          rescue => e
            Rails.logger.error("[SupportAgent] Email falhou ##{appt.id}: #{e.message}")
          end

          # 2) Push pro celular do cliente — best-effort. Notificação in-app
          # é gerada automaticamente pelo Client::NotificationsController via
          # status=cancelled + cancelled_by_role=agent (sem necessidade de
          # criar registro extra).
          begin
            shop_name = appt.car_wash&.name || "Lava-rápido"
            svc_title = appt.service&.title || "Serviço"
            when_str  = appt.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m às %H:%M")
            ExpoPushNotifier.new.notify_user(
              appt.user,
              title: "#{shop_name} cancelou sua reserva",
              body:  "#{svc_title} em #{when_str}. O estorno está sendo processado.",
              data:  {
                type:           "appointment_cancelled",
                appointment_id: appt.id,
                car_wash_id:    appt.car_wash_id,
              }
            )
          rescue => e
            Rails.logger.error("[SupportAgent] Push falhou ##{appt.id}: #{e.message}")
          end
        end

        scheduled = appt.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m às %H:%M")
        cancelled_summaries << "• #{scheduled} — #{appt.service.title} (#{appt.user&.display_name || 'avulso'})#{refund_note}"
      end

      refund_msg = refund_issues.any? ?
        " Atenção: os agendamentos #{refund_issues.map { |id| "##{id}" }.join(", ")} precisam de estorno manual." :
        " Todos os valores foram estornados e serão creditados em até 5 dias úteis."

      client_word = appointments.count == 1 ? "O cliente foi notificado" : "Os clientes foram notificados"
      post_agent_message(
        "Cancelamento realizado com sucesso:\n\n" \
        "#{cancelled_summaries.join("\n")}\n\n" \
        "#{client_word} no app (notificação push e tela de notificações).#{refund_msg}"
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

      DECISÃO — qual caminho tomar:

      A) RESPONDA DIRETAMENTE (should_escalate=false, draft preenchido) quando:
         - A pergunta é sobre o app Loov / lava-rápidos / agendamentos / financeiro /
           atendentes / fidelidade / disponíveis / qualquer feature do produto.
           Use a base de conhecimento e responda passo a passo.
         - A pergunta é COMPLETAMENTE fora do escopo Loov (ex: receitas, futebol,
           clima, vida pessoal, programação, etc). NÃO escale — responda
           gentilmente que você é o suporte da Loov e só pode ajudar com o
           produto, sugerindo perguntas relacionadas. Exemplo de tom:
           "Olá! Sou o assistente de suporte da Loov e só posso ajudar com
           dúvidas relacionadas ao seu lava-rápido — agendamentos, financeiro,
           atendentes, etc. Se tiver alguma dúvida sobre o app, é só perguntar!"

      B) ESCALE PARA HUMANO (should_escalate=true) APENAS quando:
         - Envolve disputa de pagamento Stripe que não conseguimos resolver pela KB
         - Bug crítico / dado corrompido / problema técnico não resolvível por instrução
         - Pedido de exclusão de conta ou dados sensíveis
         - Pergunta legítima sobre o produto cuja resposta NÃO está na KB

      INSTRUÇÕES DE FORMATO:
      1. Responda APENAS à última pergunta do proprietário.
      2. Máximo 4 parágrafos curtos. Sem markdown com asteriscos — texto limpo.
      3. Termine sempre oferecendo ajuda adicional ("Se precisar de mais alguma
         coisa, é só chamar.").
      4. NUNCA invente funcionalidades que não existem na base de conhecimento.

      RESPONDA APENAS EM JSON VÁLIDO, sem texto antes ou depois:
      {
        "should_escalate": false,
        "reason": null,
        "draft": "texto da resposta aqui"
      }

      Apenas se for caso (B) genuíno:
      {
        "should_escalate": true,
        "reason": "motivo curto",
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

    Rails.logger.info("[SupportAgent] Claude POST anthropic.com/v1/messages model=claude-haiku-4-5")
    response = http.request(request)
    Rails.logger.info("[SupportAgent] Claude resp status=#{response.code} size=#{response.body.to_s.size}")
    body     = JSON.parse(response.body)
    if body["error"]
      Rails.logger.error("[SupportAgent] Claude erro: #{body['error'].inspect}")
      raise "API error: #{body['error']&.dig('message')}"
    end
    body.dig("content", 0, "text")
  rescue => e
    Rails.logger.error("[SupportAgent] call_claude exceção: #{e.class}: #{e.message}")
    nil
  end

  def fallback_no_api_message
    "Olá! Recebemos seu chamado e a equipe Loov vai responder por aqui em breve. " \
    "Obrigado pela paciência."
  end

  def fallback_claude_failed_message
    "Olá! Recebi seu chamado. No momento o atendimento automático está indisponível, " \
    "mas a equipe Loov vai te responder em breve por aqui mesmo."
  end
end
