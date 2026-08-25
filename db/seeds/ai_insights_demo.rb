# db/seeds/ai_insights_demo.rb
#
# Cria 3 lava-rápidos demo com 6 meses de histórico pra testar a análise
# AI Insights de ponta a ponta: um BOM (margem saudável, crescendo), um
# MEDIANO (margem apertada, estagnado) e um RUIM (modo de crise, em queda).
#
# Idempotente: roda de novo e recria cada um do zero (destrói e reconstrói
# só os 3 lava-rápidos com os e-mails abaixo — não toca em outro dado).
#
# Uso:
#   bin/rails runner db/seeds/ai_insights_demo.rb
#
# Login (mesma senha nos 3):
#   bom@loovdemo.com       senha 12345678
#   mediano@loovdemo.com   senha 12345678
#   ruim@loovdemo.com      senha 12345678

DEMO_PASSWORD = "12345678"
HOJE          = Date.current
ZONA          = "-03:00"

srand(2026) # dataset determinístico entre execuções

puts "🌱 Gerando lava-rápidos demo pra AI Insights (hoje: #{HOJE})..."

# ── Helpers ──────────────────────────────────────────────────────────────────

# Remove só os 3 lava-rápidos demo (e o que pende deles) antes de recriar.
# AiInsight/AiInsightRun não têm dependent: :destroy a partir de CarWash —
# apagar o car_wash com uma análise já gerada estourava FK sem isso.
def limpa_demo!(email_owner, prefixo_clientes)
  owner = User.find_by(email: email_owner)
  if owner
    cw = CarWash.find_by(user: owner)
    if cw
      AiInsightRun.where(car_wash: cw).delete_all
      AiInsight.where(car_wash: cw).delete_all
      cw.destroy
    end
    owner.destroy
  end
  User.where("email LIKE ?", "#{prefixo_clientes}%").destroy_all
end

def cria_owner!(email)
  User.create!(email: email, password: DEMO_PASSWORD, password_confirmation: DEMO_PASSWORD, role: "owner")
end

def cria_car_wash!(owner, nome:, bairro:, cidade:, uf:, lat:, lng:)
  cw = CarWash.create!(
    user: owner, name: nome,
    address: "Rua Demonstração, 100 - #{bairro}, #{cidade} - #{uf}",
    logradouro: "Rua Demonstração", bairro: bairro, cidade: cidade, uf: uf,
    latitude: lat, longitude: lng,
    capacity_per_slot: 8, num_employees: 3
  )
  (0..6).each { |dow| cw.operating_hours.create!(day_of_week: dow, opens_at: "08:00", closes_at: "19:00", capacity: 8) }
  cw
end

def cria_servicos!(cw, defs)
  defs.map do |title, categoria, price, duration|
    cw.services.create!(title: title, category: categoria, price: price, duration: duration,
                         description: "Serviço demo — #{title}")
  end
end

def cria_cliente!(email, nome, telefone)
  User.create!(email: email, password: DEMO_PASSWORD, password_confirmation: DEMO_PASSWORD,
               role: "client", full_name: nome, phone: telefone)
end

def cria_custo!(cw, ano, mes, rent:, salaries:, utilities:, products:, maintenance:, other_fixed: 0, other_variable: 0)
  MonthlyCost.create!(
    car_wash: cw, year: ano, month: mes,
    rent: rent, salaries: salaries, utilities: utilities,
    products: products, maintenance: maintenance,
    other_fixed: other_fixed, other_variable: other_variable
  )
end

# Receita REAL (attended) do mês i.months.ago, na mesma janela que
# fetch_margin_context usa (beginning_of_month..end_of_month). Calcular os
# custos como % dessa receita real — em vez de adivinhar um valor fixo antes
# de gerar as visitas — é o que evita custo descolado do faturamento que a
# geração aleatória de fato produziu.
def receita_do_mes(cw, i)
  d = i.months.ago
  cw.appointments.where(status: "attended").joins(:service)
    .where(scheduled_at: d.beginning_of_month..d.end_of_month)
    .sum("services.price - COALESCE(appointments.commission_amount, 0)").to_f
end

# Gera 6 meses de custo como fração da receita real de cada mês, pra pousar
# na faixa de margem alvo (ex.: 0.62 de custo ≈ 38% de margem). Distribui o
# custo entre as linhas em proporção fixa; pequena variação mês a mês pra não
# ficar artificialmente idêntico.
def cria_custos_por_margem!(cw, fracao_custo:, variacao: 0.06, custo_minimo: 300)
  (0..5).each do |i|
    d       = i.months.ago
    receita = receita_do_mes(cw, i)
    fator   = fracao_custo * (1 + (rand - 0.5) * 2 * variacao)
    total   = [receita * fator, custo_minimo].max

    cria_custo!(cw, d.year, d.month,
      rent:        (total * 0.34).round(2),
      salaries:    (total * 0.34).round(2),
      utilities:   (total * 0.08).round(2),
      products:    (total * 0.16).round(2),
      maintenance: (total * 0.08).round(2))
  end
end

# dias_atras negativo = agendamento no FUTURO (pra confirmados/projeção).
def cria_visita!(cw, cliente, servico, dias_atras, status: "attended", max_tentativas: 15)
  dia = HOJE - dias_atras
  max_tentativas.times do
    hora   = rand(9..16)
    minuto = [0, 15, 30, 45].sample
    ap = Appointment.new(
      car_wash: cw, user: cliente, service: servico,
      scheduled_at: Time.new(dia.year, dia.month, dia.day, hora, minuto, 0, ZONA),
      duration: servico.duration, status: status, appointment_type: "regular"
    )
    ap.attended_at = ap.scheduled_at if status == "attended"
    begin
      ap.save!
      return ap
    rescue ActiveRecord::RecordInvalid
      next # slot cheio ou horário inválido — tenta outro
    end
  end
  warn "  ⚠️  não consegui agendar #{cliente.email} há #{dias_atras}d (capacidade/horário)"
  nil
end

# n dias distintos entre min..max, do mais ANTIGO pro mais RECENTE.
def datas_desc(n, min, max)
  (min..max).to_a.sample(n).sort.reverse
end

# Cliente recorrente. primeira_entry: força a 1ª visita (mais antiga) a ser o
# serviço de entrada — é o que faz o cliente contar como "iniciante do funil".
# garante_premium: força pelo menos uma visita (nunca a 1ª) a ser o premium —
# é o que conta como conversão.
def gera_recorrente!(cw, cliente, entry:, mid:, premium: nil, n_visitas:,
                      primeira_entry: false, garante_premium: false,
                      min_dias: 1, max_dias: 174)
  dias = datas_desc(n_visitas, min_dias, max_dias)
  idx_premium = (garante_premium && n_visitas >= 2) ? rand(1...n_visitas) : nil
  dias.each_with_index do |d, i|
    servico =
      if i.zero? && primeira_entry then entry
      elsif i == idx_premium       then premium
      else                              [entry, mid].sample
      end
    cria_visita!(cw, cliente, servico, d)
  end
end

def gera_no_shows!(cw, clientes, servico, quantidade, dia_semana_alvo: nil, min_dias: 1, max_dias: 90, peso_alvo: 0.75)
  quantidade.times do
    cliente = clientes.sample
    dia_atras =
      if dia_semana_alvo && rand < peso_alvo
        candidatos = (min_dias..max_dias).select { |d| (HOJE - d).wday == dia_semana_alvo }
        candidatos.sample || rand(min_dias..max_dias)
      else
        rand(min_dias..max_dias)
      end
    cria_visita!(cw, cliente, servico, dia_atras, status: "no_show")
  end
end

def gera_confirmados_futuros!(cw, clientes, servicos, quantidade)
  quantidade.times { cria_visita!(cw, clientes.sample, servicos.sample, -rand(1..9), status: "confirmed") }
end

def resumo_rapido(cw)
  ctx = AiInsightsService.new(cw).send(:build_context)
  sf  = ctx[:saude_financeira]
  fc  = ctx[:funil_conversao]
  {
    faturamento_mes:   ctx[:faturamento_mes_atual],
    margem_atual:      sf&.dig(:margem_atual),
    lucro_atual:       sf&.dig(:lucro_atual),
    perfil_financeiro: sf&.dig(:perfil_financeiro),
    crise:             sf&.dig(:is_critical_state),
    taxa_no_show:      ctx[:taxa_no_show],
    funil_starters:    fc&.dig(:funil)&.values&.sum { |d| d[:clientes_iniciaram_aqui] },
    total_clientes:    ctx[:total_clientes],
    retencao:          ctx[:percentual_clientes_que_voltam],
  }
end

# ── 1. BOM — "Água Viva Lava Rápido" ──────────────────────────────────────────

ActiveRecord::Base.transaction do
  limpa_demo!("bom@loovdemo.com", "bom-cliente-")
  owner = cria_owner!("bom@loovdemo.com")
  cw    = cria_car_wash!(owner, nome: "Água Viva Lava Rápido", bairro: "Moema", cidade: "São Paulo", uf: "SP",
                          lat: -23.5990, lng: -46.6650)

  entry, mid, premium = cria_servicos!(cw, [
    ["Lavagem Simples",     "Lavagem",     35,  30],
    ["Lavagem Completa",    "Lavagem",     70,  50],
    ["Vitrificação Premium","Vitrificação",220, 110],
  ])

  clientes = ->(n, pref) { Array.new(n) { |i| cria_cliente!("bom-cliente-#{pref}#{i}@loovdemo.com", "Cliente Bom #{pref}#{i}", "119#{rand(10_000_000..99_999_999)}") } }

  convertidos   = clientes.(16, "conv")
  entry_apenas  = clientes.(20, "entry")
  mid_direto    = clientes.(12, "mid")
  unica_recente = clientes.(8,  "urec")
  unica_antiga  = clientes.(5,  "uant")
  em_risco      = clientes.(6,  "risco")
  premium_dir   = clientes.(4,  "prem")

  convertidos.each  { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, premium: premium, n_visitas: rand(3..6), primeira_entry: true, garante_premium: true) }
  entry_apenas.each { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, n_visitas: rand(2..5), primeira_entry: true) }
  mid_direto.each   { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, n_visitas: rand(2..4)) }
  unica_recente.each { |c| cria_visita!(cw, c, entry, rand(3..25)) }
  unica_antiga.each  { |c| cria_visita!(cw, c, entry, rand(100..170)) }
  em_risco.each do |c|
    ultimo = rand(35..80)
    outros = datas_desc(rand(1..3), ultimo + 15, 174)
    (outros + [ultimo]).sort.reverse.each { |d| cria_visita!(cw, c, [entry, mid].sample, d) }
  end
  premium_dir.each { |c| cria_visita!(cw, c, premium, rand(5..170)) }

  # Custo ≈ 62% da receita real de cada mês → margem ≈ 38% (saudável).
  cria_custos_por_margem!(cw, fracao_custo: 0.62)

  gera_no_shows!(cw, convertidos + entry_apenas + mid_direto, entry, 5, min_dias: 1, max_dias: 90)
  gera_confirmados_futuros!(cw, convertidos + entry_apenas, [entry, mid, premium], 6)

  puts "✅ BOM — Água Viva: #{cw.appointments.count} agendamentos, #{cw.services.count} serviços"
  pp resumo_rapido(cw)
end

# ── 2. MEDIANO — "Lava Rápido Bom Preço" ──────────────────────────────────────

ActiveRecord::Base.transaction do
  limpa_demo!("mediano@loovdemo.com", "mediano-cliente-")
  owner = cria_owner!("mediano@loovdemo.com")
  cw    = cria_car_wash!(owner, nome: "Lava Rápido Bom Preço", bairro: "Vila Prudente", cidade: "São Paulo", uf: "SP",
                          lat: -23.5860, lng: -46.5848)

  entry, mid, premium = cria_servicos!(cw, [
    ["Lavagem Express",  "Lavagem",     25, 25],
    ["Lavagem Completa", "Lavagem",     50, 45],
    ["Enceramento",      "Enceramento", 90, 70],
  ])

  clientes = ->(n, pref) { Array.new(n) { |i| cria_cliente!("mediano-cliente-#{pref}#{i}@loovdemo.com", "Cliente Mediano #{pref}#{i}", "119#{rand(10_000_000..99_999_999)}") } }

  convertidos   = clientes.(6,  "conv")
  entry_apenas  = clientes.(8,  "entry")
  mid_direto    = clientes.(8,  "mid")
  unica_recente = clientes.(10, "urec")
  unica_antiga  = clientes.(8,  "uant")
  em_risco      = clientes.(7,  "risco")
  premium_dir   = clientes.(2,  "prem")

  convertidos.each  { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, premium: premium, n_visitas: rand(2..5), primeira_entry: true, garante_premium: true) }
  entry_apenas.each { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, n_visitas: rand(2..4), primeira_entry: true) }
  mid_direto.each   { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, n_visitas: rand(2..3)) }
  unica_recente.each { |c| cria_visita!(cw, c, entry, rand(3..28)) }
  unica_antiga.each  { |c| cria_visita!(cw, c, entry, rand(100..170)) }
  em_risco.each do |c|
    ultimo = rand(35..80)
    outros = datas_desc(rand(1..2), ultimo + 15, 174)
    (outros + [ultimo]).sort.reverse.each { |d| cria_visita!(cw, c, [entry, mid].sample, d) }
  end
  premium_dir.each { |c| cria_visita!(cw, c, premium, rand(5..170)) }

  # Custo ≈ 85% da receita real de cada mês → margem ≈ 15% (apertada).
  cria_custos_por_margem!(cw, fracao_custo: 0.85)

  gera_no_shows!(cw, convertidos + entry_apenas + mid_direto + unica_recente, entry, 14, min_dias: 1, max_dias: 90)
  gera_confirmados_futuros!(cw, convertidos + entry_apenas, [entry, mid], 4)

  puts "✅ MEDIANO — Bom Preço: #{cw.appointments.count} agendamentos, #{cw.services.count} serviços"
  pp resumo_rapido(cw)
end

# ── 3. RUIM — "Lava Rápido do Zé" (modo de crise) ─────────────────────────────

ActiveRecord::Base.transaction do
  limpa_demo!("ruim@loovdemo.com", "ruim-cliente-")
  owner = cria_owner!("ruim@loovdemo.com")
  cw    = cria_car_wash!(owner, nome: "Lava Rápido do Zé", bairro: "Capão Redondo", cidade: "São Paulo", uf: "SP",
                          lat: -23.6660, lng: -46.7770)

  entry, mid, premium = cria_servicos!(cw, [
    ["Lavagem Básica",   "Lavagem",   20, 25],
    ["Lavagem Completa", "Lavagem",   40, 45],
    ["Polimento",        "Polimento", 70, 60],
  ])

  # Custos fixos NÃO acompanharam a queda de faturamento — é a própria história
  # da crise: aluguel e salários continuam do tamanho de um movimento que já
  # não existe mais.
  custos = [
    { rent: 700, salaries: 600, utilities: 80, products: 40,  maintenance: 30 }, # mês atual (parcial) — faturamento quase zero
    { rent: 700, salaries: 600, utilities: 85, products: 60,  maintenance: 35 },
    { rent: 700, salaries: 600, utilities: 85, products: 80,  maintenance: 35 },
    { rent: 700, salaries: 650, utilities: 90, products: 100, maintenance: 40 },
    { rent: 700, salaries: 650, utilities: 90, products: 110, maintenance: 40 },
    { rent: 700, salaries: 650, utilities: 90, products: 120, maintenance: 40 },
  ]
  custos.each_with_index { |c, i| d = i.months.ago; cria_custo!(cw, d.year, d.month, **c) }

  clientes = ->(n, pref) { Array.new(n) { |i| cria_cliente!("ruim-cliente-#{pref}#{i}@loovdemo.com", "Cliente Ruim #{pref}#{i}", "119#{rand(10_000_000..99_999_999)}") } }

  convertidos   = clientes.(3,  "conv")
  entry_apenas  = clientes.(4,  "entry")
  mid_direto    = clientes.(5,  "mid")
  unica_recente = clientes.(12, "urec")
  unica_antiga  = clientes.(10, "uant")
  em_risco      = clientes.(4,  "risco")

  # Volume caindo mês a mês: convertidos/entry/mid concentram as visitas cada
  # vez mais no passado (max_dias mais baixo simula menos gente vindo agora).
  convertidos.each  { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, premium: premium, n_visitas: rand(2..4), primeira_entry: true, garante_premium: true, min_dias: 20, max_dias: 174) }
  entry_apenas.each { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, n_visitas: rand(1..3), primeira_entry: true, min_dias: 20, max_dias: 174) }
  mid_direto.each   { |c| gera_recorrente!(cw, c, entry: entry, mid: mid, n_visitas: rand(1..2), min_dias: 20, max_dias: 174) }
  # Muita gente experimenta e não volta — parte ainda recente (não conta como
  # abandono ainda, só não teve tempo de voltar), parte já claramente foi embora.
  unica_recente.each { |c| cria_visita!(cw, c, entry, rand(1..80)) }
  unica_antiga.each  { |c| cria_visita!(cw, c, entry, rand(95..174)) }
  em_risco.each do |c|
    ultimo = rand(35..80)
    cria_visita!(cw, c, [entry, mid].sample, ultimo)
    cria_visita!(cw, c, entry, ultimo + rand(20..60))
  end

  # No-show concentrado numa segunda-feira (wday 1) — sinal que
  # calc_no_show_breakdown deveria pegar.
  todos = convertidos + entry_apenas + mid_direto + unica_recente + unica_antiga + em_risco
  gera_no_shows!(cw, todos, entry, 16, dia_semana_alvo: 1, min_dias: 1, max_dias: 90, peso_alvo: 0.8)
  gera_confirmados_futuros!(cw, entry_apenas + unica_recente, [entry, mid], 2)

  puts "✅ RUIM — do Zé: #{cw.appointments.count} agendamentos, #{cw.services.count} serviços"
  pp resumo_rapido(cw)
end

puts "\n🌱 Pronto. Login (senha igual pros 3): #{DEMO_PASSWORD}"
puts "   bom@loovdemo.com"
puts "   mediano@loovdemo.com"
puts "   ruim@loovdemo.com"
