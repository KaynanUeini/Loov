require "net/http"

# Rota de carro de onde o cliente está até o lava-rápido, pro mapa do
# Agendado: o caminho desenhado e o tempo ("12 min de carro"). Vem do
# OpenRouteService (HeiGIT, plano gratuito: 2.000 rotas por dia, 40 por
# minuto), com a chave em OPENROUTESERVICE_API_KEY.
#
# A chave fica aqui no servidor; o site e o app pedem a rota pra Loov. A
# mesma origem (arredondada em ~100 m) e o mesmo lava-rápido reaproveitam a
# consulta por um tempo, pra reabrir a tela não gastar cota.
#
# Sem rota (sem chave, cota estourada, serviço fora), devolve nil e o mapa
# fica com o pino, como antes. A falha vai pro log com o motivo, pra não
# passar despercebida.
class RotaDeCarro
  URL      = "https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson".freeze
  VALIDADE = 30.minutes
  TIMEOUT  = 5

  def self.para(car_wash, lat, lng)
    return nil unless car_wash.has_valid_coordinates?
    chave = "rota:#{car_wash.id}:#{lat.round(3)}:#{lng.round(3)}"
    Rails.cache.fetch(chave, expires_in: VALIDADE, skip_nil: true) { buscar(car_wash, lat, lng) }
  rescue => e
    Rails.logger.error("[RotaDeCarro] #{car_wash.id}: #{e.class}: #{e.message}")
    nil
  end

  # { pontos: [[lat, lng], ...], distancia_m:, duracao_s: }
  def self.buscar(car_wash, lat, lng)
    key = ENV["OPENROUTESERVICE_API_KEY"].to_s
    if key.empty?
      Rails.logger.error("[RotaDeCarro] OPENROUTESERVICE_API_KEY ausente")
      return nil
    end

    uri  = URI(URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => key)
    # O serviço recebe [longitude, latitude].
    req.body = { coordinates: [[lng, lat], [car_wash.longitude.to_f, car_wash.latitude.to_f]] }.to_json
    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[RotaDeCarro] #{car_wash.id}: HTTP #{res.code} #{res.body.to_s[0, 200]}")
      return nil
    end

    f = JSON.parse(res.body).dig("features", 0)
    coords = f&.dig("geometry", "coordinates")
    resumo = f&.dig("properties", "summary") || {}
    return nil unless coords.is_a?(Array) && coords.size >= 2

    {
      pontos:      coords.map { |c| [c[1].round(5), c[0].round(5)] },
      distancia_m: resumo["distance"].to_f.round,
      duracao_s:   resumo["duration"].to_f.round
    }
  end
end
