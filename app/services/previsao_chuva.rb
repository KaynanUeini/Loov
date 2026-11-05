require "net/http"

# "Vai chover neste dia, no bairro do lava-rápido?" — pro extra de desconto da
# Hora Off. Vem da previsão da Open-Meteo (gratuita, sem chave), pela
# coordenada do lava-rápido.
#
# Falha fechada: sem coordenada, sem rede ou com resposta estranha, a resposta
# é não. O pior caso de errar pra menos é o desconto normal da Hora Off; o de
# errar pra mais seria dar desconto que o dono não queria.
class PrevisaoChuva
  URL       = "https://api.open-meteo.com/v1/forecast".freeze
  LIMITE    = 70 # % de chance de chuva no dia a partir da qual conta
  VALIDADE  = 3.hours
  TIMEOUT   = 3

  def self.provavel?(car_wash, dia)
    return false unless car_wash.has_valid_coordinates?

    # skip_nil: consulta que falhou não fica guardada, a próxima tenta de novo.
    chances = Rails.cache.fetch(chave(car_wash), expires_in: VALIDADE, skip_nil: true) { buscar(car_wash) }
    chances.is_a?(Hash) && chances[dia.iso8601].to_i >= LIMITE
  rescue => e
    Rails.logger.warn("[PrevisaoChuva] #{car_wash.id}: #{e.class}: #{e.message}")
    false
  end

  # Coordenada arredondada (~1 km): lava-rápidos vizinhos dividem a consulta.
  def self.chave(car_wash)
    "previsao_chuva:#{car_wash.latitude.to_f.round(2)}:#{car_wash.longitude.to_f.round(2)}:#{Date.current.iso8601}"
  end

  # { "2026-11-05" => 80, ... } — chance máxima de chuva em cada dia.
  def self.buscar(car_wash)
    uri = URI(URL)
    uri.query = URI.encode_www_form(
      latitude:      car_wash.latitude.to_f.round(4),
      longitude:     car_wash.longitude.to_f.round(4),
      daily:         "precipitation_probability_max",
      timezone:      "America/Sao_Paulo",
      forecast_days: 3
    )
    resposta = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.get(uri.request_uri)
    end
    return nil unless resposta.is_a?(Net::HTTPSuccess)

    diario = JSON.parse(resposta.body).fetch("daily", {})
    Array(diario["time"]).zip(Array(diario["precipitation_probability_max"])).to_h
  end
end
