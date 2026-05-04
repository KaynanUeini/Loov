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
                    else              'Formato: WhatsApp profissional mas humano, 100–160 palavras, parágrafos curtos.'
                    end

    <<~PROMPT
      Você é o Kaynan, fundador da Loov, contatando lava-rápidos pra
      apresentar o produto e convidá-los pra fase de testes. Não é SDR
      gringo nem startup-bro — é um fundador brasileiro fazendo prospecção
      direta. Honesto sobre o estágio: a Loov ainda está em fase de
      captação de lava-rápidos pra testar.

      LEAD (lava-rápido em prospecção):
      - Nome: #{lead.name}
      - Endereço: #{lead.address || 'não informado'}
      - Bairro: #{lead.bairro || '?'}, #{lead.cidade || 'Osasco'}
      #{rating_line}
      REVIEWS RECENTES DO SHOP:
      #{reviews_block}

      O QUE A LOOV FAZ PRO DONO DO LAVA-RÁPIDO:
      - Cliente agenda pelo app — zero ligação, zero caderno de horários,
        zero fila no balcão
      - Dashboard mostra agenda do dia, faturamento em tempo real,
        atendidos/pendentes/ausentes, ticket médio, KPIs
      - Gestão financeira completa: DRE mensal, custos fixos e variáveis,
        lucro do mês, comparativo histórico
      - IA Insights: análise mensal automática do negócio com sugestões
        de onde mexer (preço, mix de serviços, horários ociosos, etc)
      - Programa de fidelidade configurável (a cada N visitas, recompensa)
      - Cadastro de atendentes com permissões (atendente pode confirmar
        agendamentos sem ver dados financeiros)
      - Avaliações estruturadas dos clientes — sabe exatamente o que
        elogiam e o que reclamam, com tags
      - Suporte com agente IA 24/7 pra dúvidas operacionais

      LAST MINUTE (funcionalidade-chave do cliente, traz volume novo):
      - Cliente abre o app procurando lavar agora — vê todos os
        lava-rápidos abertos perto dele com vaga nos próximos 30 min
      - Sem precisar ligar pra cada um perguntando "tem horário?"
      - Cliente paga 35% antecipado pra garantir a vaga (anti no-show)
      - O lava-rápido recebe esses agendamentos automaticamente

      MODELO DE COBRANÇA:
      - No futuro: mensalidade (valor ainda em definição)
      - DURANTE A FASE DE TESTES: 100% gratuito, sem cobrança nenhuma,
        suporte direto do fundador. Período da fase ainda não definido.

      OBJETIVO DA MENSAGEM: convidar pra conversa de 15 min sobre o
      produto — não pra fechar nada, só apresentar e ver se faz sentido
      participar dos testes.

      INSTRUÇÕES:
      #{style_note}
      - Português formal mas humano. NUNCA use "tamo", "tô", "vc", "pra
        gente" no lugar de "para nós", "rolar". Use "estou", "para",
        "podemos", "gostaria", "verifique".
      - Hook personalizado: cite UM detalhe específico das reviews
        (problema OU elogio); se reviews vazios, abre pelo nome do shop
        e fato observável (bairro, há quanto tempo no Maps, etc)
      - Apresente brevemente o que é a Loov + 2-3 funcionalidades
        concretas pro dono (dashboard, financeiro, IA insights, etc)
      - Mencione que está em fase de captação de lava-rápidos pra testar
        (não diga "revolucionando" nem "transformando o mercado")
      - Mencione que durante a fase de testes é gratuito, sem prazo fixo
      - CTA pedindo 15 min de conversa essa semana
      - Máximo 1 emoji
      - Assine apenas: "Kaynan, Loov"
      - Devolva APENAS o corpo da mensagem. Sem aspas, sem cabeçalho,
        sem assunto se for WhatsApp.
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
        Assunto: Loov — convite para a fase de testes em Osasco

        Olá!

        Aqui é o Kaynan, fundador da Loov. Estou em fase de captação
        de lava-rápidos para testar a plataforma e gostaria de convidar
        o #{lead.name} para conhecer o produto.

        A Loov é um app que tira o atendimento manual do dia a dia do
        lava-rápido: o cliente agenda horário direto pelo app (sem
        ligação, sem caderno), o senhor acompanha tudo num dashboard
        com agenda, faturamento e KPIs em tempo real, e ainda tem
        gestão financeira completa (DRE mensal, custos, lucro) e
        análise mensal de IA com sugestões para o negócio.

        Tem também o "Last Minute" — funcionalidade onde o cliente
        encontra lavagens disponíveis perto dele nos próximos 30 min,
        sem precisar ligar para cada lava-rápido perguntando se tem
        horário. O cliente paga 35% antecipado para garantir a vaga,
        evitando ausências.

        No futuro a Loov terá mensalidade, mas durante a fase de
        testes é totalmente gratuita, com suporte direto do fundador.
        O período ainda não está definido.

        O senhor teria 15 min essa semana para uma conversa rápida
        sobre o produto?

        Atenciosamente,
        Kaynan, Loov
      MSG
    else
      <<~MSG.strip
        Olá! Aqui é o Kaynan, fundador da Loov.

        Estou em fase de captação de lava-rápidos em Osasco para testar nossa plataforma e gostaria de convidar o #{lead.name} para conhecer.

        A Loov é um app que tira o atendimento manual do dia a dia: o cliente agenda horário direto pelo app (sem ligação, sem caderno), o senhor acompanha tudo num dashboard com agenda, faturamento e KPIs em tempo real, e ainda tem gestão financeira completa e análise mensal de IA com sugestões para o negócio.

        Tem também o "Last Minute", onde o cliente encontra lavagens disponíveis perto dele nos próximos 30 min — ele paga 35% antecipado para garantir a vaga, evitando ausências.

        No futuro a Loov terá mensalidade, mas durante a fase de testes é totalmente gratuita, com suporte direto. O período ainda não está definido.

        Teria 15 min essa semana para conversarmos?

        Kaynan, Loov
      MSG
    end
  end
end
