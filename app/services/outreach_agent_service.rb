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
                    when 'email' then 'Formato: assunto curto + corpo de email com saudação e despedida. 180–250 palavras.'
                    else              'Formato: WhatsApp profissional mas humano, 140–200 palavras, parágrafos curtos.'
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
      - Programa de fidelidade configurável (a cada N visitas, recompensa)
      - Cadastro de atendentes com permissões (atendente pode confirmar
        agendamentos sem ver dados financeiros)
      - Avaliações estruturadas dos clientes — sabe exatamente o que
        elogiam e o que reclamam, com tags
      - Suporte com agente IA 24/7 pra dúvidas operacionais

      ANÁLISE DE IA (DIFERENCIAL PRINCIPAL — ENFATIZAR NA MENSAGEM):
      A cada ciclo a Loov gera automaticamente uma análise completa do
      negócio com inteligência artificial, olhando para todos os dados
      do lava-rápido (faturamento, ticket médio, mix de serviços,
      horários mais e menos cheios, retenção de clientes, crescimento
      mês a mês, etc) e devolvendo:
      - Diagnóstico claro de como o negócio está
      - Decisão prioritária que vale a pena tomar agora
      - Sugestões concretas de onde mexer (preço, novos serviços,
        promoção em horário ocioso, foco em retenção, etc)
      - Comparativo do mês com o histórico
      O dono também pode pedir para a IA focar em alguma pergunta
      específica (ex: "por que caí no faturamento de sábado?") e a
      próxima análise responde isso. É como ter um consultor de negócio
      olhando para o lava-rápido todo mês — algo que normalmente custaria
      milhares de reais por mês com um consultor humano.

      LAST MINUTE (funcionalidade que traz volume novo, FACILITADOR DO CLIENTE):
      - Quando o cliente quer lavar o carro agora mas não tem agendamento,
        normalmente ele teria que abrir o app e procurar lava-rápido por
        lava-rápido tentando achar algum com horário disponível nos
        próximos 30 minutos
      - O Last Minute resolve isso: mostra numa única tela TODOS os
        lava-rápidos próximos com vaga aberta nos próximos 30 min
      - Cliente paga 35% antecipado pra garantir a vaga (anti no-show)
      - O lava-rápido recebe esses agendamentos automaticamente

      ESTÁGIO DO PRODUTO:
      - A Loov está em fase de implementação e testes
      - Estamos selecionando lava-rápidos da região pra participar dessa
        fase, conhecer o produto e dar feedback
      - Durante a fase de testes não há cobrança
      - NÃO mencionar mensalidade futura — não precisa antecipar isso agora

      OBJETIVO DA MENSAGEM: convidar pra conversa de 15 min sobre o
      produto — não pra fechar nada, só apresentar e ver se faz sentido
      participar dessa fase.

      INSTRUÇÕES:
      #{style_note}
      - Português formal mas humano. NUNCA use "tamo", "tô", "vc", "pra
        gente" no lugar de "para nós", "rolar". Use "estou", "para",
        "podemos", "gostaria", "verifique".
      - Hook personalizado: cite UM detalhe específico das reviews
        (problema OU elogio); se reviews vazios, abre pelo nome do shop
        e fato observável (bairro, há quanto tempo no Maps, etc)
      - Apresente brevemente o que é a Loov, depois cite algumas
        funcionalidades operacionais (agendamento, dashboard, financeiro)
      - DEDIQUE UM PARÁGRAFO INTEIRO falando da Análise de IA — esse é
        o maior diferencial do produto, descreva o que ela entrega
        (diagnóstico, decisão prioritária, sugestões concretas) e
        compare com o custo de um consultor humano. Não enterre essa
        feature no meio da lista.
      - Mencione que a Loov está em fase de implementação/testes e que
        está selecionando lava-rápidos da região pra participar
      - Mencione que durante essa fase não há cobrança
      - NÃO fale sobre mensalidade futura, valores futuros, ou prazo da
        fase de testes
      - NÃO use "revolucionando", "transformando o mercado", clichês de
        startup
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
    if channel == 'email'
      <<~MSG
        Assunto: Loov — convite para a fase de testes em Osasco

        Olá!

        Aqui é o Kaynan, fundador da Loov. A Loov está em fase de
        implementação e estamos selecionando lava-rápidos da região
        para participar dessa fase de testes — gostaria de convidar
        o #{lead.name} para conhecer o produto.

        A Loov é um app que tira o atendimento manual do dia a dia
        do lava-rápido: o cliente agenda horário direto pelo app
        (sem ligação, sem caderno), o senhor acompanha tudo num
        dashboard com agenda, faturamento e KPIs em tempo real, e
        ainda tem gestão financeira completa com DRE mensal, custos
        fixos e variáveis e lucro do mês.

        O grande diferencial é a Análise de IA: a Loov olha
        automaticamente para todos os dados do lava-rápido
        (faturamento, ticket médio, mix de serviços, horários cheios
        e ociosos, retenção, crescimento) e devolve um diagnóstico
        completo do negócio, com a decisão prioritária do momento
        e sugestões concretas de onde mexer. O senhor pode até pedir
        para a IA focar numa pergunta específica e a próxima análise
        responde. É como ter um consultor de negócio olhando para o
        lava-rápido todo mês, sem o custo de um consultor humano.

        Tem também o "Last Minute": quando o cliente quer lavar o
        carro agora mas não agendou antes, em vez de procurar
        lava-rápido por lava-rápido no app tentando achar um com
        vaga, ele vê numa única tela todos os próximos com horário
        disponível nos próximos 30 min. Ele paga 35% antecipado
        para garantir a vaga, evitando ausências.

        Durante a fase de testes não há cobrança e o suporte é
        direto comigo.

        O senhor teria 15 min essa semana para uma conversa rápida
        sobre o produto?

        Atenciosamente,
        Kaynan, Loov
      MSG
    else
      <<~MSG.strip
        Olá! Aqui é o Kaynan, fundador da Loov.

        A Loov está em fase de implementação e estamos selecionando lava-rápidos da região para participar dessa fase de testes. Gostaria de convidar o #{lead.name} para conhecer o produto.

        A Loov é um app que tira o atendimento manual do dia a dia: o cliente agenda horário direto pelo app, o senhor acompanha tudo num dashboard com agenda e faturamento em tempo real, e tem gestão financeira completa com DRE mensal e custos.

        O grande diferencial é a Análise de IA: a Loov olha automaticamente para todos os dados do seu lava-rápido (faturamento, ticket médio, mix de serviços, horários cheios e ociosos, retenção, crescimento) e devolve um diagnóstico completo, com a decisão prioritária do momento e sugestões concretas de onde mexer. O senhor pode até pedir para a IA focar em uma pergunta específica. É como ter um consultor de negócio olhando para o lava-rápido todo mês, sem o custo de um.

        Tem também o "Last Minute": quando o cliente quer lavar agora mas não agendou antes, em vez de procurar lava-rápido por lava-rápido tentando achar um com vaga, ele vê numa única tela todos com horário disponível nos próximos 30 min. Ele paga 35% antecipado para garantir a vaga.

        Durante a fase de testes não há cobrança.

        Teria 15 min essa semana para conversarmos?

        Kaynan, Loov
      MSG
    end
  end
end
