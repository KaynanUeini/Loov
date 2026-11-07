require "net/http"

# Conferência das 4 fotos guiadas da ficha do carro pela IA (Claude Haiku):
# tem carro na foto, a parte do carro bate com o pedido (frente, traseira ou
# lateral) e dá pra ver a lataria. É a segunda camada: o app já recusou, de
# graça, a foto escura, estourada ou tremida (public/ficha/qualidade.html).
#
# Custo no mínimo: a foto chega reduzida a 512 px (~260 tokens de imagem), a
# instrução é curta e em inglês (menos tokens), o raciocínio fica desligado
# (no Haiku 5.5 ele vem ligado e conta como saída) e a resposta é um JSON de
# três campos garantido por esquema (structured outputs). Fica perto de
# US$ 0,00005 por foto. Sem a chave, com erro ou demora, devolve nil e a foto
# passa: a conferência nunca trava a ficha.
#
# O Haiku 5.5 recusa (400) temperature e resposta pré-escrita do assistente;
# a primeira versão mandava os dois e toda conferência falhava em silêncio.
class FichaConferencia
  MODEL      = "claude-haiku-5-5".freeze
  MAX_TOKENS = 60
  TIMEOUT    = 12 # s
  # Teto de conferências por atendimento (4 guiadas e as refeitas): passa
  # disso, a foto segue sem conferir, pra uma falha em loop não virar custo.
  LIMITE_POR_ATENDIMENTO = 16

  ESPERADO = { "front" => "front", "rear" => "rear", "left" => "side", "right" => "side" }.freeze

  PROMPT = "Car wash check-in photo. car: a car or other road vehicle fills most of the photo " \
           "(false for doors, walls, people, animals or anything else). view: the part of the vehicle shown. " \
           "clear: sharp and lit enough to see scratches on the body.".freeze

  SCHEMA = {
    type: "object",
    properties: {
      car:   { type: "boolean" },
      view:  { type: "string", enum: %w[front rear side other] },
      clear: { type: "boolean" }
    },
    required: %w[car view clear],
    additionalProperties: false
  }.freeze

  def self.configurada?
    ENV["ANTHROPIC_API_KEY"].present?
  end

  # => { ok: true } | { ok: false, motivo: "sem_carro"|"outro_lado"|"sem_nitidez", visto: "front"|... }
  #    | { falha: "motivo técnico" } quando não deu pra conferir (a foto passa)
  def self.conferir(label, imagem_b64)
    esperado = ESPERADO[label]
    return { falha: "foto sem conferência" } unless esperado
    return { falha: "ANTHROPIC_API_KEY ausente" } unless configurada?

    r = chamar(imagem_b64)
    return r if r.key?("falha")

    if r["car"] == false
      { ok: false, motivo: "sem_carro" }
    elsif r["view"].present? && r["view"] != esperado && r["view"] != "other"
      { ok: false, motivo: "outro_lado", visto: r["view"] }
    elsif r["clear"] == false
      { ok: false, motivo: "sem_nitidez" }
    else
      { ok: true }
    end
  end

  def self.chamar(imagem_b64)
    uri  = URI("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = TIMEOUT

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]      = "application/json"
    req["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    req["anthropic-version"] = "2023-06-01"
    req.body = {
      model:      MODEL,
      max_tokens: MAX_TOKENS,
      thinking:   { type: "disabled" },
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: SCHEMA }
      },
      messages: [
        { role: "user", content: [
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: imagem_b64 } },
          { type: "text", text: PROMPT }
        ] }
      ]
    }.to_json

    res  = http.request(req)
    body = JSON.parse(res.body) rescue nil
    unless res.is_a?(Net::HTTPSuccess) && body
      erro = "HTTP #{res.code}: #{body&.dig('error', 'message') || res.body.to_s[0, 200]}"
      Rails.logger.warn("[FichaConferencia] #{erro}")
      return { "falha" => erro }
    end

    uso = body["usage"] || {}
    Rails.logger.info("[FichaConferencia] tokens entrada=#{uso['input_tokens']} saída=#{uso['output_tokens']} stop=#{body['stop_reason']}")
    return { "falha" => "stop_reason #{body['stop_reason']}" } unless body["stop_reason"] == "end_turn"
    texto = Array(body["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s
    JSON.parse(texto)
  rescue StandardError => e
    Rails.logger.warn("[FichaConferencia] #{e.class}: #{e.message}")
    { "falha" => "#{e.class}: #{e.message}"[0, 200] }
  end
end
