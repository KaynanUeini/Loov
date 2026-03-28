class SupportAgentService
  KB_PATH = Rails.root.join("config", "support_agent_kb.txt")

  def initialize(ticket)
    @ticket = ticket
  end

  def generate_draft
    return nil if already_replied_by_admin?

    thread_context = build_thread_context
    kb             = load_knowledge_base
    prompt         = build_prompt(thread_context, kb)

    response = call_claude(prompt)
    return nil if response.nil?

    parsed = parse_response(response)
    return nil if parsed.nil?

    if parsed[:should_escalate]
      Rails.logger.info("[SupportAgent] Ticket ##{@ticket.id} marcado para escalação: #{parsed[:reason]}")
      return { escalate: true, reason: parsed[:reason] }
    end

    @ticket.update_columns(
      agent_draft:      parsed[:draft],
      agent_drafted_at: Time.current,
      agent_sent:       false
    )

    { draft: parsed[:draft], escalate: false }
  rescue => e
    Rails.logger.error("[SupportAgent] Erro ao gerar rascunho para ticket ##{@ticket.id}: #{e.message}")
    nil
  end

  # Envia o rascunho como mensagem real do admin
  def approve_and_send!(admin_user, custom_body = nil)
    body = custom_body.presence || @ticket.agent_draft
    return false if body.blank?

    ActiveRecord::Base.transaction do
      @ticket.messages.create!(
        user:       admin_user,
        body:       body,
        from_admin: true
      )
      @ticket.update_columns(
        status:     "in_progress",
        agent_sent: true,
        updated_at: Time.current
      )
    end
    true
  rescue => e
    Rails.logger.error("[SupportAgent] Erro ao aprovar rascunho ticket ##{@ticket.id}: #{e.message}")
    false
  end

  private

  # Verifica se o admin já respondeu APÓS a última mensagem do dono.
  # Permite gerar novo rascunho quando o dono faz uma nova pergunta
  # mesmo que já haja respostas anteriores do admin na thread.
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
      car_wash:    @ticket.user.car_washes.first&.name || "não identificado",
      owner_email: @ticket.user.email,
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
    last_owner_question = @ticket.messages
      .where(from_admin: false)
      .order(:created_at)
      .last&.body || ""

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
      - Proprietário: #{ctx[:owner_email]}
      - Aberto em: #{ctx[:opened_at]}

      HISTÓRICO COMPLETO DA CONVERSA:
      #{ctx[:messages]}

      ÚLTIMA PERGUNTA DO PROPRIETÁRIO (foco principal da sua resposta):
      "#{last_owner_question}"

      INSTRUÇÕES OBRIGATÓRIAS:
      1. Responda APENAS à última pergunta do proprietário.
      2. Se a resposta estiver na base de conhecimento: explique passo a passo onde clicar.
      3. Se NÃO estiver na base de conhecimento, ou envolver pagamento Stripe, disputa,
         bug crítico, exclusão de conta, ou situação incomum: indique escalação.
      4. Máximo 4 parágrafos curtos. Sem markdown com asteriscos — texto limpo.
      5. Termine sempre oferecendo ajuda adicional se necessário.
      6. NUNCA invente funcionalidades que não existem na base de conhecimento.

      RESPONDA APENAS EM JSON VÁLIDO, sem texto antes ou depois:
      {
        "should_escalate": false,
        "reason": null,
        "draft": "texto da resposta aqui"
      }

      Se não souber responder com base no conhecimento disponível:
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
    {
      should_escalate: data["should_escalate"] == true,
      reason:          data["reason"],
      draft:           data["draft"]
    }
  rescue => e
    Rails.logger.error("[SupportAgent] Erro ao parsear: #{e.message} — raw: #{raw[0..200]}")
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
