# Busca lava-rápidos via Places API (New) e devolve dados prontos
# pra criar Outreach::Lead. Usa o endpoint :searchText que retorna até
# 20 places em UMA única chamada (incluindo telefone, reviews, address
# components — não precisa de Place Details separado como na legacy).
#
# Custo no free tier de $200/mês:
# - Text Search com FieldMask "Pro+Enterprise" (todos os campos):
#   $0.040 por chamada
# - Cada query ≈ $0.04 → $200/$0.04 = 5.000 buscas/mês
# - Na prática você nunca paga.
#
# Setup:
# 1. console.cloud.google.com → projeto
# 2. APIs & Services → Library → "Places API (New)" → Enable
#    (NÃO a "Places API" legacy — Google Cloud novo só libera a New)
# 3. Credentials → use a key que já existe (Maps Platform) ou cria nova
# 4. Em "API restrictions" da key, garante que "Places API (New)"
#    está liberada
# 5. No Render: GOOGLE_PLACES_API_KEY = a key
class GooglePlacesService
  ENDPOINT = 'https://places.googleapis.com/v1/places:searchText'.freeze

  # FieldMask define quais campos vêm de volta. Mais campos = preço maior
  # (basic, advanced, preferred). Os campos abaixo cobrem tudo que
  # precisamos pra criar lead com mensagem da IA personalizada.
  FIELD_MASK = [
    'places.id',
    'places.displayName',
    'places.formattedAddress',
    'places.addressComponents',
    'places.location',
    'places.nationalPhoneNumber',
    'places.internationalPhoneNumber',
    'places.websiteUri',
    'places.rating',
    'places.userRatingCount',
    'places.reviews',
    'places.businessStatus'
  ].join(',').freeze

  def search_with_details(query, max_details: 20)
    api_key = ENV['GOOGLE_PLACES_API_KEY']
    return { error: 'no_key' } if api_key.blank?

    require 'net/http'
    require 'json'

    uri  = URI(ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 30

    req                              = Net::HTTP::Post.new(uri)
    req['Content-Type']              = 'application/json'
    req['X-Goog-Api-Key']             = api_key
    req['X-Goog-FieldMask']           = FIELD_MASK
    req.body = {
      textQuery:    query,
      languageCode: 'pt-BR',
      regionCode:   'BR',
      maxResultCount: [max_details, 20].min
    }.to_json

    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      err_body = res.body.to_s
      Rails.logger.error("[GooglePlacesService] HTTP #{res.code}: #{err_body}")
      parsed = (JSON.parse(err_body) rescue nil)
      msg    = parsed&.dig('error', 'message') || "HTTP #{res.code}"
      return { error: msg }
    end

    data   = JSON.parse(res.body)
    places = data['places'] || []
    return { error: 'no_results', results: [] } if places.empty?

    results = places.first(max_details).map { |p| build_lead_attrs(p) }.compact
    { results: results }
  rescue => e
    Rails.logger.error("[GooglePlacesService] #{e.class}: #{e.message}")
    { error: e.message }
  end

  private

  def build_lead_attrs(place)
    name     = place.dig('displayName', 'text').to_s
    address  = place['formattedAddress'].to_s

    addr_components = place['addressComponents'] || []
    bairro = addr_components.find { |c|
      types = c['types'] || []
      types.include?('sublocality') ||
        types.include?('sublocality_level_1') ||
        types.include?('neighborhood')
    }&.dig('longText')

    cidade = addr_components.find { |c|
      (c['types'] || []).include?('administrative_area_level_2')
    }&.dig('longText')

    phone_raw = place['nationalPhoneNumber'].presence || place['internationalPhoneNumber'].to_s
    phone     = phone_raw.gsub(/\D/, '').presence  # nil se ficou vazio

    reviews_sample = (place['reviews'] || []).first(3).map { |r|
      txt = r.dig('text', 'text').to_s.gsub(/\s+/, ' ').strip
      txt = "#{txt[0..200]}..." if txt.length > 200
      stars = '★' * r['rating'].to_i
      "[#{stars} #{r['rating']}] #{txt}"
    }.join("\n\n")

    {
      name:           name,
      phone:          phone,
      address:        address,
      bairro:         bairro,
      cidade:         cidade.presence || 'Osasco',
      rating:         place['rating'],
      reviews_count:  place['userRatingCount'],
      reviews_sample: reviews_sample,
      place_id:       place['id'],
      website:        place['websiteUri']
    }
  end
end
