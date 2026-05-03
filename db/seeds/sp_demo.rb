# db/seeds/sp_demo.rb
#
# Popula a base com lava-rápidos demo distribuídos pelos principais
# bairros de São Paulo. Idempotente — pode rodar várias vezes sem
# duplicar.
#
# Uso (em produção, no Render shell):
#   bundle exec rails runner db/seeds/sp_demo.rb
#
# Configuração: todos abrem 06:00–23:00 todos os dias, capacidade 2,
# com 4 serviços incluindo pelo menos um ≤60min (elegível pro Last
# Minute). Coords reais dos bairros.

puts "🌱 SP demo seed — populando lava-rápidos pelos bairros de SP..."

# Owner único compartilhado pra todos os car_washes demo. Não interfere
# com owners reais que tenham email diferente.
demo_owner = User.find_or_create_by!(email: "demo@loov.app") do |u|
  u.password   = SecureRandom.hex(8)
  u.role       = "owner"
  u.full_name  = "Loov Demo"
  u.phone      = "11999999999"
end

# Bairros de SP com coordenadas aproximadas do centroide. Cobertura
# zonal: Centro, Oeste, Sul, Leste, Norte, Sudeste.
SP_NEIGHBORHOODS = [
  # ── CENTRO ────────────────────────────────────────────
  { bairro: "Sé",                logradouro: "Praça da Sé",                 lat: -23.5505, lng: -46.6333, cep: "01001000" },
  { bairro: "República",         logradouro: "Praça da República",          lat: -23.5436, lng: -46.6432, cep: "01045000" },
  { bairro: "Bela Vista",        logradouro: "Avenida Paulista",            lat: -23.5614, lng: -46.6558, cep: "01310100" },
  { bairro: "Liberdade",         logradouro: "Rua Galvão Bueno",            lat: -23.5587, lng: -46.6357, cep: "01506000" },
  { bairro: "Cambuci",           logradouro: "Avenida do Estado",           lat: -23.5689, lng: -46.6210, cep: "01524000" },
  { bairro: "Aclimação",         logradouro: "Rua Muniz de Souza",          lat: -23.5719, lng: -46.6280, cep: "01533000" },
  { bairro: "Bom Retiro",        logradouro: "Rua José Paulino",            lat: -23.5320, lng: -46.6360, cep: "01125000" },
  { bairro: "Barra Funda",       logradouro: "Avenida Marquês de São Vicente", lat: -23.5269, lng: -46.6655, cep: "01139001" },

  # ── OESTE ─────────────────────────────────────────────
  { bairro: "Pinheiros",         logradouro: "Rua dos Pinheiros",           lat: -23.5640, lng: -46.7022, cep: "05422000" },
  { bairro: "Vila Madalena",     logradouro: "Rua Aspicuelta",              lat: -23.5489, lng: -46.6906, cep: "05433010" },
  { bairro: "Itaim Bibi",        logradouro: "Rua João Cachoeira",          lat: -23.5868, lng: -46.6788, cep: "04535001" },
  { bairro: "Jardim Paulista",   logradouro: "Rua Oscar Freire",            lat: -23.5645, lng: -46.6668, cep: "01426001" },
  { bairro: "Vila Olímpia",      logradouro: "Rua Funchal",                 lat: -23.5950, lng: -46.6841, cep: "04551060" },
  { bairro: "Moema",             logradouro: "Avenida Ibirapuera",          lat: -23.6005, lng: -46.6647, cep: "04029001" },
  { bairro: "Brooklin",          logradouro: "Rua Pensilvânia",             lat: -23.6150, lng: -46.6863, cep: "04564002" },
  { bairro: "Morumbi",           logradouro: "Avenida Giovanni Gronchi",    lat: -23.6011, lng: -46.7197, cep: "05699000" },
  { bairro: "Lapa",              logradouro: "Rua Clélia",                  lat: -23.5283, lng: -46.7060, cep: "05042000" },
  { bairro: "Perdizes",          logradouro: "Rua Cardoso de Almeida",      lat: -23.5380, lng: -46.6753, cep: "05013000" },
  { bairro: "Pompeia",           logradouro: "Rua Clélia",                  lat: -23.5325, lng: -46.6857, cep: "05042000" },
  { bairro: "Vila Sônia",        logradouro: "Avenida Eliseu de Almeida",   lat: -23.6025, lng: -46.7434, cep: "05553001" },
  { bairro: "Butantã",           logradouro: "Avenida Vital Brasil",        lat: -23.5712, lng: -46.7186, cep: "05503001" },
  { bairro: "Alto de Pinheiros", logradouro: "Avenida Pedroso de Morais",   lat: -23.5479, lng: -46.7093, cep: "05420001" },
  { bairro: "Vila Leopoldina",   logradouro: "Avenida Imperatriz Leopoldina", lat: -23.5426, lng: -46.7341, cep: "05305002" },

  # ── SUL ───────────────────────────────────────────────
  { bairro: "Vila Mariana",      logradouro: "Rua Vergueiro",               lat: -23.5879, lng: -46.6347, cep: "04101300" },
  { bairro: "Saúde",             logradouro: "Avenida Bosque da Saúde",     lat: -23.6205, lng: -46.6379, cep: "04132010" },
  { bairro: "Jabaquara",         logradouro: "Avenida Engenheiro Armando de Arruda Pereira", lat: -23.6494, lng: -46.6432, cep: "04340000" },
  { bairro: "Campo Belo",        logradouro: "Avenida Vereador José Diniz", lat: -23.6255, lng: -46.6687, cep: "04603001" },
  { bairro: "Santo Amaro",       logradouro: "Avenida Santo Amaro",         lat: -23.6594, lng: -46.6976, cep: "04701001" },
  { bairro: "Ipiranga",          logradouro: "Avenida Doutor Ricardo Jafet", lat: -23.5934, lng: -46.6017, cep: "04220001" },
  { bairro: "Sacomã",            logradouro: "Avenida Doutor Gentil de Moura", lat: -23.6047, lng: -46.6044, cep: "04212000" },
  { bairro: "Vila Prudente",     logradouro: "Avenida Salim Farah Maluf",   lat: -23.5860, lng: -46.5848, cep: "03145001" },
  { bairro: "Paraíso",           logradouro: "Rua Vergueiro",               lat: -23.5715, lng: -46.6435, cep: "04101300" },
  { bairro: "Cidade Ademar",     logradouro: "Avenida Cupecê",              lat: -23.6620, lng: -46.6707, cep: "04366001" },

  # ── LESTE ─────────────────────────────────────────────
  { bairro: "Tatuapé",           logradouro: "Rua Tuiuti",                  lat: -23.5394, lng: -46.5791, cep: "03307000" },
  { bairro: "Mooca",             logradouro: "Rua da Mooca",                lat: -23.5532, lng: -46.5940, cep: "03103000" },
  { bairro: "Belém",             logradouro: "Avenida Celso Garcia",        lat: -23.5470, lng: -46.6035, cep: "03014001" },
  { bairro: "Penha",             logradouro: "Avenida Penha de França",     lat: -23.5314, lng: -46.5404, cep: "03625001" },
  { bairro: "Itaquera",          logradouro: "Avenida Itaquera",            lat: -23.5377, lng: -46.4570, cep: "08210000" },
  { bairro: "Aricanduva",        logradouro: "Avenida Aricanduva",          lat: -23.5677, lng: -46.5085, cep: "03434001" },
  { bairro: "São Mateus",        logradouro: "Avenida Sapopemba",           lat: -23.6097, lng: -46.4748, cep: "08390001" },
  { bairro: "Cidade Tiradentes", logradouro: "Estrada do Iguatemi",         lat: -23.6040, lng: -46.4090, cep: "08470001" },
  { bairro: "Ermelino Matarazzo", logradouro: "Avenida São Miguel",         lat: -23.4945, lng: -46.4905, cep: "03807001" },
  { bairro: "Guaianases",        logradouro: "Avenida Salvador Gianetti",   lat: -23.5414, lng: -46.4108, cep: "08410001" },
  { bairro: "Vila Carrão",       logradouro: "Avenida Conselheiro Carrão",  lat: -23.5479, lng: -46.5292, cep: "03435001" },

  # ── NORTE ─────────────────────────────────────────────
  { bairro: "Santana",           logradouro: "Avenida Cruzeiro do Sul",     lat: -23.5006, lng: -46.6249, cep: "02030001" },
  { bairro: "Tucuruvi",          logradouro: "Avenida Tucuruvi",            lat: -23.4791, lng: -46.6068, cep: "02304001" },
  { bairro: "Vila Maria",        logradouro: "Avenida Guilherme Cotching",  lat: -23.5089, lng: -46.5928, cep: "02115001" },
  { bairro: "Cachoeirinha",      logradouro: "Avenida Antônio Munhoz Bonilha", lat: -23.4853, lng: -46.6588, cep: "02712001" },
  { bairro: "Tremembé",          logradouro: "Avenida Maria Amália Lopes Azevedo", lat: -23.4684, lng: -46.6195, cep: "02340001" },
  { bairro: "Casa Verde",        logradouro: "Rua Voluntários da Pátria",   lat: -23.5045, lng: -46.6644, cep: "02013001" },
  { bairro: "Freguesia do Ó",    logradouro: "Avenida Mutinga",             lat: -23.5108, lng: -46.7014, cep: "02914001" },
  { bairro: "Pirituba",          logradouro: "Avenida Mutinga",             lat: -23.4854, lng: -46.7384, cep: "02943002" },
  { bairro: "Brasilândia",       logradouro: "Avenida Itaberaba",           lat: -23.4626, lng: -46.6880, cep: "02844001" },
  { bairro: "Jaçanã",            logradouro: "Avenida Cipriano Barata",     lat: -23.4538, lng: -46.5912, cep: "02273000" },
  { bairro: "Vila Guilherme",    logradouro: "Avenida Engenheiro Caetano Álvares", lat: -23.5050, lng: -46.6087, cep: "02053001" },

  # ── EXTREMOS / BORDAS ─────────────────────────────────
  { bairro: "Capão Redondo",     logradouro: "Avenida Carlos Caldeira Filho", lat: -23.6790, lng: -46.7616, cep: "05874001" },
  { bairro: "M'Boi Mirim",       logradouro: "Estrada do M'Boi Mirim",      lat: -23.7075, lng: -46.7546, cep: "04937001" },
  { bairro: "Cidade Dutra",      logradouro: "Avenida Senador Teotônio Vilela", lat: -23.7297, lng: -46.7026, cep: "04827001" },
  { bairro: "Grajaú",            logradouro: "Avenida Dona Belmira Marin",  lat: -23.7641, lng: -46.6987, cep: "04821001" },
  { bairro: "Parelheiros",       logradouro: "Avenida Sadamu Inoue",        lat: -23.8266, lng: -46.7281, cep: "04944001" },
  { bairro: "Campo Limpo",       logradouro: "Estrada do Campo Limpo",      lat: -23.6451, lng: -46.7565, cep: "05777001" },
  { bairro: "Jaguaré",           logradouro: "Avenida Jaguaré",             lat: -23.5453, lng: -46.7484, cep: "05346001" },
].freeze

# Templates de nomes pra dar variedade — mistura formal/casual.
NAME_TEMPLATES = [
  "Lava Car %{bairro}",
  "Auto Estética %{bairro}",
  "%{bairro} Car Wash",
  "Speed Lava %{bairro}",
  "Brilho Total %{bairro}",
  "Premium Wash %{bairro}",
  "Auto Spa %{bairro}",
  "Lava Rápido %{bairro}",
  "Eco Lava %{bairro}",
  "Estação Lava %{bairro}",
].freeze

# Pacote padrão de serviços. Inclui pelo menos um ≤60min pra ser
# elegível ao Last Minute (que requer service.duration ≤ 60).
DEFAULT_SERVICES = [
  { title: "Lavagem Simples",       category: "Lavagem",      description: "Lavagem externa completa com aspirado básico.", price: 35.00,  duration: 30 },
  { title: "Lavagem Completa",      category: "Lavagem",      description: "Lavagem externa, interna e aspirado.",          price: 65.00,  duration: 45 },
  { title: "Lavagem Premium",       category: "Lavagem",      description: "Lavagem completa com cera de proteção.",        price: 95.00,  duration: 60 },
  { title: "Higienização Interna",  category: "Higienização", description: "Limpeza profunda de bancos, teto e carpete.",   price: 180.00, duration: 90 },
  { title: "Polimento",             category: "Polimento",    description: "Polimento da pintura com máquina rotativa.",    price: 220.00, duration: 120 },
].freeze

OPERATING_HOURS = (0..6).map { |dow|
  { day_of_week: dow, opens_at: "06:00", closes_at: "23:00" }
}.freeze

created  = 0
existing = 0

SP_NEIGHBORHOODS.each_with_index do |hood, idx|
  name = format(NAME_TEMPLATES[idx % NAME_TEMPLATES.size], bairro: hood[:bairro])

  cw = demo_owner.car_washes.find_by(name: name)
  if cw
    existing += 1
  else
    numero = (rand(50..2000)).to_s
    cw = demo_owner.car_washes.create!(
      name:              name,
      address:           "#{hood[:logradouro]}, #{numero} - #{hood[:bairro]}, São Paulo - SP",
      capacity_per_slot: 2,
      cep:               hood[:cep],
      logradouro:        hood[:logradouro],
      numero:            numero,
      bairro:            hood[:bairro],
      cidade:            "São Paulo",
      uf:                "SP",
      latitude:          hood[:lat],
      longitude:         hood[:lng],
      active:            true
    )
    created += 1
  end

  OPERATING_HOURS.each do |h|
    cw.operating_hours.find_or_create_by!(day_of_week: h[:day_of_week]) do |oh|
      oh.opens_at  = h[:opens_at]
      oh.closes_at = h[:closes_at]
    end
  end

  DEFAULT_SERVICES.each do |s|
    cw.services.find_or_create_by!(title: s[:title]) do |svc|
      svc.category    = s[:category]
      svc.description = s[:description]
      svc.price       = s[:price]
      svc.duration    = s[:duration]
    end
  end
end

puts "✅ SP demo seed concluído: #{created} criados, #{existing} já existiam."
puts "   Total de car_washes do owner demo: #{demo_owner.car_washes.count}"
puts "   Owner demo: #{demo_owner.email}"
puts "   Horário de todos: 06:00–23:00 todos os dias"
puts "   Last Minute funciona quando estiver dentro desse horário e o cliente"
puts "   tiver geolocalização ativa (raio de 5km)."
