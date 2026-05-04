# Gera mensagem de WhatsApp/email pra um lead da fase de testes da Loov.
# Usa Claude (Anthropic API) com prompt SDR-style. Sem chave configurada,
# cai num fallback estático mas customizado pelo nome do shop.
class OutreachAgentService
  ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages'.freeze
  MODEL             = 'claude-haiku-4-5-20251001'.freeze

  def generate(lead, channel: 'whatsapp')
    api_key = ENV['ANTHROPIC_API_KEY']
    if api_key.blank?
      Rails.logger.warn("[OutreachAgent] ANTHROPIC_API_KEY ausente — usando fallback")
      return fallback_message(lead, channel)
    end

    prompt = build_prompt(lead, channel)
    body   = call_claude(prompt, api_key)
    body.presence || fallback_message(lead, channel)
  rescue => e
    Rails.logger.error("[OutreachAgent] erro na geração: #{e.class} #{e.message}")
    fallback_message(lead, channel)
  end

  private

  def build_prompt(lead, channel)
    reviews_block = lead.reviews_sample.presence || 'Nenhum review fornecido.'
    rating_line   = lead.rating.present? ? "- Rating Google: #{lead.rating}/5\n" : ''
    style_note    = case channel
                    when 'email' then 'Formato: assunto curto + corpo de email com saudação e despedida.'
                    else              'Formato: WhatsApp casual mas profissional, 80–130 palavras, parágrafos curtos.'
                    end

    <<~PROMPT
      Você é um SDR (sales development rep) experiente, brasileiro, representando a Loov.

      LEAD (lava-rápido em prospecção):
      - Nome: #{lead.name}
      - Endereço: #{lead.address || 'não informado'}
      - Bairro: #{lead.bairro || '?'}, #{lead.cidade || 'Osasco'}
      #{rating_line}
      REVIEWS RECENTES DO SHOP:
      #{reviews_block}

      LOOV (pitch curto):
      - App de agendamento on-demand pra lava-rápidos
      - Cliente agenda horário antes de chegar (zero fila)
      - "Last Minute" libera vagas ociosas pra reservas instantâneas com 35%
        pago antecipado (compromisso real do cliente)
      - Sem mensalidade, sem taxa fixa, só comissão pequena por agendamento
      - Cliente paga online ou no local

      OBJETIVO: convidar pra reunião de 15 min apresentando a fase de
      testes — selecionando 10 lava-rápidos em Osasco pra usar gratuito
      por 60 dias com suporte direto do fundador.

      INSTRUÇÕES:
      #{style_note}
      - Tom direto, brasileiro, sem clichê de SDR gringo
      - Hook personalizado: cite UM detalhe específico das reviews
        (problema OU elogio); se reviews vazios, abre pelo nome do shop
      - Apresente Loov em 2 frases
      - CTA pedindo 15 min de conversa essa semana
      - Máximo 1 emoji
      - Assine apenas: "Kaynan, Loov"
      - Devolva APENAS o corpo da mensagem. Sem aspas, sem cabeçalho.
    PROMPT
  end

  def call_claude(prompt, api_key)
    require 'net/http'
    require 'json'

    uri  = URI(ANTHROPIC_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    http.read_timeout = 30

    req                       = Net::HTTP::Post.new(uri)
    req['x-api-key']          = api_key
    req['anthropic-version']  = '2023-06-01'
    req['content-type']       = 'application/json'
    req.body = {
      model:      MODEL,
      max_tokens: 700,
      messages:   [{ role: 'user', content: prompt }]
    }.to_json

    res = http.request(req)
    return nil unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).dig('content', 0, 'text')&.strip
  end

  def fallback_message(lead, channel)
    nome = lead.name.to_s.strip.split.first&.capitalize || 'pessoal'
    if channel == 'email'
      <<~MSG
        Assunto: Loov — convite pra fase de testes em Osasco

        Olá, #{nome}!

        Aqui é o Kaynan, da Loov. Estou contatando lava-rápidos
        selecionados em Osasco pra apresentar nossa plataforma de
        agendamento on-demand.

        A Loov é um app onde clientes agendam horário antes de chegar
        (zero fila) e tem o "Last Minute" que enche suas vagas ociosas
        com pagamento de 35% antecipado — compromisso real do cliente.

        Estou convidando 10 lava-rápidos da região pra fase de testes
        gratuita por 60 dias. Topa uma conversa de 15 min essa semana?

        Abraços,
        Kaynan, Loov
      MSG
    else
      <<~MSG.strip
        Oi, #{nome}! Aqui é o Kaynan, da Loov.

        Tô contatando lava-rápidos selecionados de Osasco pra apresentar nossa plataforma. A Loov é um app onde o cliente agenda horário antes de chegar (zero fila) e tem o "Last Minute" que enche vagas ociosas com 35% pago antecipado — compromisso real.

        Estou convidando 10 lava-rápidos da região pra fase de testes gratuita por 60 dias. Topa 15 min de conversa essa semana?

        Kaynan, Loov
      MSG
    end
  end
end
