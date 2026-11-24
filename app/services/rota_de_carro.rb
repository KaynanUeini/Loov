require "net/http"

# Rota de carro de onde o cliente está até o lava-rápido, pro Agendado: o
# caminho desenhado no mapa (computador) e o tempo ("14 min de carro").
#
# Primeiro a TomTom (TOMTOM_API_KEY): calcula com o trânsito do momento e diz
# quanto dele é atraso. Plano gratuito: 20 mil rotas por mês. Se ela falhar
# ou a cota acabar, o OpenRouteService (OPENROUTESERVICE_API_KEY, 2.000 por
# dia) faz a rota sem trânsito, e a tela mostra o tempo com "≈".
#
# As chaves ficam aqui no servidor; o site e o app pedem a rota pra Loov. A
# mesma origem (arredondada em ~100 m) e o mesmo lava-rápido reaproveitam a
# consulta por 10 min (o trânsito muda; mais que isso o tempo envelhece).
#
# Sem rota nenhuma, devolve nil e a tela fica com o pino, como antes. Cada
# falha vai pro log com o motivo, pra não passar despercebida.
class RotaDeCarro
  TOMTOM_URL = "https://api.tomtom.com/routing/1/calculateRoute/%s/json".freeze
  ORS_URL    = "https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson".freeze
  VALIDADE   = 10.minutes
  TIMEOUT    = 5

  def self.para(car_wash, lat, lng)
    return nil unless car_wash.has_valid_coordinates?
    chave = "rota:#{car_wash.id}:#{lat.round(3)}:#{lng.round(3)}"
    Rails.cache.fetch(chave, expires_in: VALIDADE, skip_nil: true) { buscar(car_wash, lat, lng) }
  rescue => e
    Rails.logger.error("[RotaDeCarro] #{car_wash.id}: #{e.class}: #{e.message}")
    nil
  end

  # { pontos: [[lat, lng], ...], distancia_m:, duracao_s:, atraso_s:, transito: true|false }
  def self.buscar(car_wash, lat, lng)
    tomtom(car_wash, lat, lng) || ors(car_wash, lat, lng)
  end

  def self.tomtom(car_wash, lat, lng)
    key = ENV["TOMTOM_API_KEY"].to_s
    if key.empty?
      Rails.logger.error("[RotaDeCarro] TOMTOM_API_KEY ausente, indo pro OpenRouteService")
      return nil
    end
    locais = "#{lat},#{lng}:#{car_wash.latitude.to_f},#{car_wash.longitude.to_f}"
    uri = URI(format(TOMTOM_URL, locais))
    # traffic=true é o padrão; fica explícito porque é o motivo de usar a TomTom.
    uri.query = URI.encode_www_form(key: key, traffic: true, travelMode: "car", routeType: "fastest")
    res = http(uri).request(Net::HTTP::Get.new(uri, "Accept" => "application/json"))
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[RotaDeCarro] TomTom #{car_wash.id}: HTTP #{res.code} #{res.body.to_s[0, 200]}")
      return nil
    end

    rota   = JSON.parse(res.body).dig("routes", 0) || {}
    resumo = rota["summary"] || {}
    pontos = (rota["legs"] || []).flat_map { |l| l["points"] || [] }
                                 .map { |p| [p["latitude"].to_f.round(5), p["longitude"].to_f.round(5)] }
    return nil if pontos.size < 2 || resumo["travelTimeInSeconds"].nil?

    {
      pontos:      pontos,
      distancia_m: resumo["lengthInMeters"].to_i,
      duracao_s:   resumo["travelTimeInSeconds"].to_i,
      atraso_s:    resumo["trafficDelayInSeconds"].to_i,
      transito:    true
    }
  rescue => e
    Rails.logger.error("[RotaDeCarro] TomTom #{car_wash.id}: #{e.class}: #{e.message}")
    nil
  end

  def self.ors(car_wash, lat, lng)
    key = ENV["OPENROUTESERVICE_API_KEY"].to_s
    if key.empty?
      Rails.logger.error("[RotaDeCarro] OPENROUTESERVICE_API_KEY ausente")
      return nil
    end

    uri = URI(ORS_URL)
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => key)
    # O serviço recebe [longitude, latitude].
    req.body = { coordinates: [[lng, lat], [car_wash.longitude.to_f, car_wash.latitude.to_f]] }.to_json
    res = http(uri).request(req)
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[RotaDeCarro] ORS #{car_wash.id}: HTTP #{res.code} #{res.body.to_s[0, 200]}")
      return nil
    end

    f = JSON.parse(res.body).dig("features", 0)
    coords = f&.dig("geometry", "coordinates")
    resumo = f&.dig("properties", "summary") || {}
    return nil unless coords.is_a?(Array) && coords.size >= 2

    {
      pontos:      coords.map { |c| [c[1].round(5), c[0].round(5)] },
      distancia_m: resumo["distance"].to_f.round,
      duracao_s:   resumo["duration"].to_f.round,
      atraso_s:    0,
      transito:    false
    }
  rescue => e
    Rails.logger.error("[RotaDeCarro] ORS #{car_wash.id}: #{e.class}: #{e.message}")
    nil
  end

  def self.http(uri)
    h = Net::HTTP.new(uri.host, uri.port)
    h.use_ssl = true
    h.open_timeout = TIMEOUT
    h.read_timeout = TIMEOUT
    h
  end
end
