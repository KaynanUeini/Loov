require 'faker'

puts "🌱 Iniciando seed..."

def weighted_sample(weights_hash)
  total = weights_hash.values.sum
  r     = rand(total)
  acc   = 0
  weights_hash.each do |k, w|
    acc += w
    return k if r < acc
  end
  weights_hash.keys.last
end

DAY_WEIGHTS = {
  1 => 8, 2 => 7, 3 => 9, 4 => 10, 5 => 18, 6 => 14
}.freeze

HOUR_WEIGHTS = {
  8 => 5, 9 => 10, 10 => 14, 11 => 12, 12 => 6,
  13 => 8, 14 => 12, 15 => 13, 16 => 14, 17 => 6
}.freeze

def create_clients(count, prefix)
  clients = []
  count.times do |i|
    first = Faker::Name.first_name.downcase.gsub(/[^a-z]/, '')
    last  = Faker::Name.last_name.downcase.gsub(/[^a-z]/, '')
    email = "#{prefix}_#{first}#{i}@gmail.com"
    user  = User.find_or_create_by!(email: email) do |u|
      u.password = "123456"
      u.role     = "client"
    end
    clients << user
  end
  clients
end

def create_appointments(car_wash:, clients:, services:, count:, period_months: 12,
                        loyalty_clients: [], loyalty_visits: 2..5,
                        no_show_rate: 0.12, cancelled_rate: 0.08,
                        service_weights: nil)
  start_range = period_months.months.ago.to_date
  end_range   = 30.days.from_now.to_date
  valid_dates = (start_range..end_range).select { |d| DAY_WEIGHTS.key?(d.wday) }
  svc_weights = service_weights || services.each_with_index.map { |_, i| [i, [40, 25, 15, 8, 5, 4, 2, 1][i] || 2] }.to_h

  count.times do
    date    = valid_dates.sample
    hour    = weighted_sample(HOUR_WEIGHTS)
    minute  = [0, 30].sample
    next if date.wday == 6 && hour >= 14

    scheduled_at = Time.zone.local(date.year, date.month, date.day, hour, minute)
    client       = clients.sample
    svc_idx      = weighted_sample(svc_weights)
    service      = services[svc_idx] || services.first

    status = if scheduled_at > Time.current
      "confirmed"
    elsif rand < cancelled_rate
      "cancelled"
    elsif rand < no_show_rate
      "no_show"
    else
      "attended"
    end

    begin
      Appointment.create!(
        user: client, car_wash: car_wash,
        service: service, scheduled_at: scheduled_at, status: status
      )
    rescue ActiveRecord::RecordInvalid
    end
  end

  loyalty_clients.each do |client|
    rand(loyalty_visits).times do
      date    = valid_dates.sample
      hour    = weighted_sample(HOUR_WEIGHTS)
      minute  = [0, 30].sample
      next if date.wday == 6 && hour >= 14

      scheduled_at = Time.zone.local(date.year, date.month, date.day, hour, minute)
      service      = services.sample

      status = if scheduled_at > Time.current
        "confirmed"
      elsif rand < 0.06
        "no_show"
      else
        "attended"
      end

      begin
        Appointment.create!(
          user: client, car_wash: car_wash,
          service: service, scheduled_at: scheduled_at, status: status
        )
      rescue ActiveRecord::RecordInvalid
      end
    end
  end
end

def create_monthly_costs_12m(car_wash:, base_costs:, variation: 0.08, spikes: {})
  12.times do |i|
    date  = i.months.ago
    month = date.month

    seasonal = case month
    when 1, 2   then 1.12
    when 6, 7   then 0.90
    when 11, 12 then 1.08
    else 1.0
    end

    costs = base_costs.transform_values do |v|
      (v * seasonal * (1 + (rand - 0.5) * 2 * variation)).round(2)
    end

    spikes[i]&.each { |field, extra| costs[field] = (costs[field].to_f + extra).round(2) }

    car_wash.monthly_costs.find_or_create_by!(year: date.year, month: date.month) do |mc|
      mc.rent           = costs[:rent]           || 0
      mc.salaries       = costs[:salaries]       || 0
      mc.utilities      = costs[:utilities]      || 0
      mc.products       = costs[:products]       || 0
      mc.maintenance    = costs[:maintenance]    || 0
      mc.other_fixed    = costs[:other_fixed]    || 0
      mc.other_variable = costs[:other_variable] || 0
    end
  end
end

# ── 1. LAVA CAR PREMIUM ───────────────────────────────────────────────────────

owner = User.find_or_create_by!(email: "dono@lavacar.com") do |u|
  u.password = "123456"; u.role = "owner"
end
puts "✅ Owner Premium: #{owner.email}"

car_wash = owner.car_washes.find_or_create_by!(name: "Lava Car Premium") do |cw|
  cw.address = "Av. Paulista, 1000 - Bela Vista, São Paulo - SP"
  cw.capacity_per_slot = 3
  cw.cep = "01310100"; cw.logradouro = "Avenida Paulista"
  cw.bairro = "Bela Vista"; cw.cidade = "São Paulo"; cw.uf = "SP"
  cw.latitude = -23.5614; cw.longitude = -46.6558
end

[{day_of_week: 1, opens_at: "08:00", closes_at: "18:00"},
 {day_of_week: 2, opens_at: "08:00", closes_at: "18:00"},
 {day_of_week: 3, opens_at: "08:00", closes_at: "18:00"},
 {day_of_week: 4, opens_at: "08:00", closes_at: "18:00"},
 {day_of_week: 5, opens_at: "08:00", closes_at: "18:00"},
 {day_of_week: 6, opens_at: "08:00", closes_at: "14:00"}].each do |h|
  car_wash.operating_hours.find_or_create_by!(day_of_week: h[:day_of_week]) do |oh|
    oh.opens_at = h[:opens_at]; oh.closes_at = h[:closes_at]
  end
end

services_1 = [
  {title: "Lavagem Simples",      category: "Lavagem",       description: "Lavagem externa completa",         price: 35.00,  duration: 30 },
  {title: "Lavagem Completa",     category: "Lavagem",       description: "Lavagem externa e interna",        price: 65.00,  duration: 60 },
  {title: "Lavagem Premium",      category: "Lavagem",       description: "Lavagem completa com cera",        price: 95.00,  duration: 90 },
  {title: "Polimento Simples",    category: "Polimento",     description: "Polimento da pintura",             price: 150.00, duration: 120},
  {title: "Polimento Completo",   category: "Polimento",     description: "Polimento + cristalização",        price: 250.00, duration: 180},
  {title: "Higienização Interna", category: "Higienização",  description: "Limpeza profunda do interior",     price: 180.00, duration: 150},
  {title: "Cristalização",        category: "Cristalização", description: "Cristalização da pintura",         price: 300.00, duration: 180},
  {title: "Lavagem de Motor",     category: "Outros",        description: "Limpeza e desengraxante do motor", price: 80.00,  duration: 60 },
].map do |s|
  car_wash.services.find_or_create_by!(title: s[:title]) do |svc|
    svc.category = s[:category]; svc.description = s[:description]
    svc.price = s[:price]; svc.duration = s[:duration]
  end
end

clients_1 = create_clients(150, "premium")
create_appointments(
  car_wash: car_wash, clients: clients_1, services: services_1,
  count: 300, loyalty_clients: clients_1.first(20), loyalty_visits: 3..8,
  no_show_rate: 0.10, cancelled_rate: 0.08
)
puts "✅ #{Appointment.where(car_wash: car_wash).count} agendamentos Premium"

create_monthly_costs_12m(
  car_wash: car_wash,
  base_costs: {rent: 3500, salaries: 4200, utilities: 600, products: 800, maintenance: 400, other_fixed: 300, other_variable: 200},
  spikes: {3 => {maintenance: 800}, 9 => {maintenance: 600}}
)
puts "✅ 12 meses custos Premium"

# ── 2. LAVA RÁPIDO ESTRELA ────────────────────────────────────────────────────

owner_top = User.find_or_create_by!(email: "dono@lavaestrela.com") do |u|
  u.password = "123456"; u.role = "owner"
end
puts "\n✅ Owner Estrela: #{owner_top.email}"

cw_top = owner_top.car_washes.find_or_create_by!(name: "Lava Rápido Estrela") do |cw|
  cw.address = "Rua Oscar Freire, 500 - Jardins, São Paulo - SP"
  cw.capacity_per_slot = 4
  cw.cep = "01426001"; cw.logradouro = "Rua Oscar Freire"
  cw.bairro = "Jardins"; cw.cidade = "São Paulo"; cw.uf = "SP"
  cw.latitude = -23.5631; cw.longitude = -46.6703
end

[{day_of_week: 1, opens_at: "07:00", closes_at: "19:00"},
 {day_of_week: 2, opens_at: "07:00", closes_at: "19:00"},
 {day_of_week: 3, opens_at: "07:00", closes_at: "19:00"},
 {day_of_week: 4, opens_at: "07:00", closes_at: "19:00"},
 {day_of_week: 5, opens_at: "07:00", closes_at: "19:00"},
 {day_of_week: 6, opens_at: "08:00", closes_at: "16:00"}].each do |h|
  cw_top.operating_hours.find_or_create_by!(day_of_week: h[:day_of_week]) do |oh|
    oh.opens_at = h[:opens_at]; oh.closes_at = h[:closes_at]
  end
end

services_top = [
  {title: "Lavagem Expressa",          category: "Lavagem",       description: "Lavagem externa rápida",                  price: 45.00,   duration: 25 },
  {title: "Lavagem Completa",          category: "Lavagem",       description: "Lavagem externa e interna detalhada",     price: 85.00,   duration: 60 },
  {title: "Lavagem com Cera Carnaúba", category: "Lavagem",       description: "Lavagem + cera de carnaúba",              price: 130.00,  duration: 90 },
  {title: "Polimento Técnico",         category: "Polimento",     description: "Polimento profissional 3 etapas",         price: 350.00,  duration: 240},
  {title: "Higienização Completa",     category: "Higienização",  description: "Higienização interna com ozônio",         price: 250.00,  duration: 180},
  {title: "Vitrificação",              category: "Cristalização", description: "Proteção cerâmica da pintura",            price: 800.00,  duration: 360},
  {title: "Estética Completa",         category: "Polimento",     description: "Polimento + vitrificação + higienização", price: 1200.00, duration: 480},
  {title: "Limpeza de Motor",          category: "Outros",        description: "Limpeza e proteção do compartimento",    price: 120.00,  duration: 90 },
].map do |s|
  cw_top.services.find_or_create_by!(title: s[:title]) do |svc|
    svc.category = s[:category]; svc.description = s[:description]
    svc.price = s[:price]; svc.duration = s[:duration]
  end
end

clients_top = create_clients(200, "estrela")
create_appointments(
  car_wash: cw_top, clients: clients_top, services: services_top,
  count: 450, loyalty_clients: clients_top.first(50), loyalty_visits: 4..10,
  no_show_rate: 0.07, cancelled_rate: 0.05,
  service_weights: {0 => 20, 1 => 25, 2 => 20, 3 => 10, 4 => 12, 5 => 5, 6 => 3, 7 => 5}
)
puts "✅ #{Appointment.where(car_wash: cw_top).count} agendamentos Estrela"

create_monthly_costs_12m(
  car_wash: cw_top,
  base_costs: {rent: 4500, salaries: 5500, utilities: 700, products: 1200, maintenance: 300, other_fixed: 400, other_variable: 300},
  spikes: {5 => {maintenance: 1200}, 11 => {other_variable: 800}}
)
puts "✅ 12 meses custos Estrela"

# ── 3. AUTO CENTER BEIRA RIO ──────────────────────────────────────────────────

owner_mid = User.find_or_create_by!(email: "dono@beirario.com") do |u|
  u.password = "123456"; u.role = "owner"
end
puts "\n✅ Owner Beira Rio: #{owner_mid.email}"

cw_mid = owner_mid.car_washes.find_or_create_by!(name: "Auto Center Beira Rio") do |cw|
  cw.address = "Rua das Figueiras, 350 - Centro, Santo André - SP"
  cw.capacity_per_slot = 2
  cw.cep = "09010160"; cw.logradouro = "Rua das Figueiras"
  cw.bairro = "Centro"; cw.cidade = "Santo André"; cw.uf = "SP"
  cw.latitude = -23.6636; cw.longitude = -46.5278
end

[{day_of_week: 1, opens_at: "08:00", closes_at: "17:00"},
 {day_of_week: 2, opens_at: "08:00", closes_at: "17:00"},
 {day_of_week: 3, opens_at: "08:00", closes_at: "17:00"},
 {day_of_week: 4, opens_at: "08:00", closes_at: "17:00"},
 {day_of_week: 5, opens_at: "08:00", closes_at: "17:00"},
 {day_of_week: 6, opens_at: "08:00", closes_at: "13:00"}].each do |h|
  cw_mid.operating_hours.find_or_create_by!(day_of_week: h[:day_of_week]) do |oh|
    oh.opens_at = h[:opens_at]; oh.closes_at = h[:closes_at]
  end
end

services_mid = [
  {title: "Lavagem Simples",      category: "Lavagem",      description: "Lavagem externa",           price: 30.00,  duration: 30 },
  {title: "Lavagem Completa",     category: "Lavagem",      description: "Lavagem externa e interna", price: 55.00,  duration: 60 },
  {title: "Lavagem com Cera",     category: "Lavagem",      description: "Lavagem + cera simples",    price: 75.00,  duration: 75 },
  {title: "Polimento Simples",    category: "Polimento",    description: "Polimento básico",          price: 120.00, duration: 120},
  {title: "Higienização Interna", category: "Higienização", description: "Limpeza interna",           price: 150.00, duration: 120},
  {title: "Lavagem de Motor",     category: "Outros",       description: "Lavagem do motor",          price: 60.00,  duration: 60 },
].map do |s|
  cw_mid.services.find_or_create_by!(title: s[:title]) do |svc|
    svc.category = s[:category]; svc.description = s[:description]
    svc.price = s[:price]; svc.duration = s[:duration]
  end
end

clients_mid = create_clients(100, "beirario")
create_appointments(
  car_wash: cw_mid, clients: clients_mid, services: services_mid,
  count: 200, loyalty_clients: clients_mid.first(15), loyalty_visits: 2..5,
  no_show_rate: 0.15, cancelled_rate: 0.10,
  service_weights: {0 => 45, 1 => 30, 2 => 12, 3 => 5, 4 => 5, 5 => 3}
)
puts "✅ #{Appointment.where(car_wash: cw_mid).count} agendamentos Beira Rio"

create_monthly_costs_12m(
  car_wash: cw_mid,
  base_costs: {rent: 2200, salaries: 2800, utilities: 450, products: 500, maintenance: 250, other_fixed: 200, other_variable: 150},
  variation: 0.10,
  spikes: {2 => {maintenance: 700}, 8 => {salaries: 500}}
)
puts "✅ 12 meses custos Beira Rio"

# ── 4. LAVA RÁPIDO DO ZEZINHO ─────────────────────────────────────────────────

owner_bad = User.find_or_create_by!(email: "dono@zezinhocar.com") do |u|
  u.password = "123456"; u.role = "owner"
end
puts "\n✅ Owner Zezinho: #{owner_bad.email}"

cw_bad = owner_bad.car_washes.find_or_create_by!(name: "Lava Rápido do Zezinho") do |cw|
  cw.address = "Rua Vergueiro, 2200 - Vila Mariana, São Paulo - SP"
  cw.capacity_per_slot = 2
  cw.cep = "04102000"; cw.logradouro = "Rua Vergueiro"
  cw.bairro = "Vila Mariana"; cw.cidade = "São Paulo"; cw.uf = "SP"
  cw.latitude = -23.5925; cw.longitude = -46.6382
end

[{day_of_week: 1, opens_at: "09:00", closes_at: "17:00"},
 {day_of_week: 2, opens_at: "09:00", closes_at: "17:00"},
 {day_of_week: 3, opens_at: "09:00", closes_at: "17:00"},
 {day_of_week: 4, opens_at: "09:00", closes_at: "17:00"},
 {day_of_week: 5, opens_at: "09:00", closes_at: "17:00"},
 {day_of_week: 6, opens_at: "09:00", closes_at: "13:00"}].each do |h|
  cw_bad.operating_hours.find_or_create_by!(day_of_week: h[:day_of_week]) do |oh|
    oh.opens_at = h[:opens_at]; oh.closes_at = h[:closes_at]
  end
end

services_bad = [
  {title: "Lavagem Simples",  category: "Lavagem",   description: "Lavagem básica",            price: 25.00,  duration: 40 },
  {title: "Lavagem Completa", category: "Lavagem",   description: "Lavagem interna e externa", price: 45.00,  duration: 70 },
  {title: "Cera Simples",     category: "Polimento", description: "Aplicação de cera básica",  price: 70.00,  duration: 90 },
  {title: "Polimento",        category: "Polimento", description: "Polimento básico",          price: 100.00, duration: 120},
].map do |s|
  cw_bad.services.find_or_create_by!(title: s[:title]) do |svc|
    svc.category = s[:category]; svc.description = s[:description]
    svc.price = s[:price]; svc.duration = s[:duration]
  end
end

clients_bad = create_clients(60, "zezinho")
create_appointments(
  car_wash: cw_bad, clients: clients_bad, services: services_bad,
  count: 100, loyalty_clients: clients_bad.first(5), loyalty_visits: 1..3,
  no_show_rate: 0.22, cancelled_rate: 0.15,
  service_weights: {0 => 65, 1 => 25, 2 => 7, 3 => 3}
)
puts "✅ #{Appointment.where(car_wash: cw_bad).count} agendamentos Zezinho"

create_monthly_costs_12m(
  car_wash: cw_bad,
  base_costs: {rent: 2800, salaries: 2200, utilities: 400, products: 400, maintenance: 200, other_fixed: 150, other_variable: 0},
  variation: 0.05,
  spikes: {1 => {maintenance: 900}, 4 => {maintenance: 600}, 7 => {salaries: 400}, 10 => {maintenance: 500}}
)
puts "✅ 12 meses custos Zezinho"

# ── RESUMO ────────────────────────────────────────────────────────────────────

puts ""
puts "🎉 Seed concluído!"
puts ""
puts "  ┌──────────────────────────────────────────────────────────────────┐"
puts "  │  PERFIL           │ LOGIN                     │ SENHA           │"
puts "  ├──────────────────────────────────────────────────────────────────┤"
puts "  │  ⭐ Premium        │ dono@lavacar.com          │ 123456          │"
puts "  │  🏆 Muito Bom     │ dono@lavaestrela.com      │ 123456          │"
puts "  │  📊 Mediano       │ dono@beirario.com         │ 123456          │"
puts "  │  🔴 Ruim          │ dono@zezinhocar.com       │ 123456          │"
puts "  └──────────────────────────────────────────────────────────────────┘"
puts ""
puts "  • Lava Car Premium:       #{Appointment.where(car_wash: car_wash).count}"
puts "  • Lava Rápido Estrela:    #{Appointment.where(car_wash: cw_top).count}"
puts "  • Auto Center Beira Rio:  #{Appointment.where(car_wash: cw_mid).count}"
puts "  • Lava Rápido do Zezinho: #{Appointment.where(car_wash: cw_bad).count}"
puts "  Total: #{Appointment.count} agendamentos | #{User.count} usuários"
