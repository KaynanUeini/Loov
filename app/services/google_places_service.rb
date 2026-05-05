# Busca lava-rápidos no Google Places API e devolve dados prontos
# pra criar Outreach::Lead. Usa Text Search (até 20 resultados) +
# Place Details (telefone, reviews) por place_id.
#
# Custo no free tier de $200/mês do Google Cloud:
# - Text Search: $0.032 por chamada
# - Place Details: $0.017 por chamada
# - Cada query do usuário: 1 Text Search + ~20 Place Details = $0.37
# - $200 / $0.37 ≈ 540 queries/mês (na prática nunca paga)
#
# Setup:
# 1. console.cloud.google.com → criar projeto
# 2. APIs & Services → Enable APIs → habilita "Places API" (legacy,
#    não a New)
# 3. Credentials → Create credentials → API key
# 4. Restringe a key (HTTP referrer ou IP do Render)
# 5. Cola no Render: settings → environment → GOOGLE_PLACES_API_KEY
class GooglePlacesService
  BASE_URL = 'https://maps.googleapis.com/maps/api/place'.freeze

  def search_with_details(query, max_details: 20)
    api_key = ENV['GOOGLE_PLACES_API_KEY']
    return { error: 'no_key' } if api_key.blank?

    search_results = text_search(query, api_key)
    return { error: 'no_results', results: [] } if search_results.empty?

    detailed = search_results.first(max_details).map do |r|
      details = place_details(r['place_id'], api_key)
      next nil if details.nil?
      build_lead_attrs(r, details)
    end.compact

    { results: detailed }
  rescue => e
    Rails.logger.error("[GooglePlacesService] #{e.class}: #{e.message}")
    { error: e.message }
  end

  private

  def text_search(query, key)
    require 'net/http'
    require 'json'
    uri = URI("#{BASE_URL}/textsearch/json")
    uri.query = URI.encode_www_form(
      query:    query,
      key:      key,
      language: 'pt-BR',
      region:   'br'
    )

    res = Net::HTTP.get_response(uri)
    return [] unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body)
    if data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS'
      Rails.logger.error("[GooglePlacesService] text_search status=#{data['status']} #{data['error_message']}")
      return []
    end
    data['results'] || []
  end

  def place_details(place_id, key)
    require 'net/http'
    require 'json'
    fields = %w[
      name formatted_address formatted_phone_number international_phone_number
      website rating user_ratings_total reviews geometry address_components
    ].join(',')

    uri = URI("#{BASE_URL}/details/json")
    uri.query = URI.encode_www_form(
      place_id: place_id,
      fields:   fields,
      key:      key,
      language: 'pt-BR'
    )

    res = Net::HTTP.get_response(uri)
    return nil unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body)
    return nil if data['status'] != 'OK'
    data['result']
  end

  def build_lead_attrs(search_result, details)
    addr_components = details['address_components'] || []

    bairro = addr_components.find { |c|
      types = c['types'] || []
      types.include?('sublocality') ||
        types.include?('sublocality_level_1') ||
        types.include?('neighborhood')
    }&.dig('long_name')

    cidade = addr_components.find { |c|
      (c['types'] || []).include?('administrative_area_level_2')
    }&.dig('long_name')

    phone_raw = details['formatted_phone_number'] || details['international_phone_number'] || ''
    phone = phone_raw.gsub(/\D/, '')

    reviews_sample = (details['reviews'] || []).first(3).map { |r|
      stars = '★' * r['rating'].to_i
      txt   = r['text'].to_s.gsub(/\s+/, ' ').strip
      txt   = "#{txt[0..200]}..." if txt.length > 200
      "[#{stars} #{r['rating']}] #{txt}"
    }.join("\n\n")

    {
      name:           details['name'].to_s,
      phone:          phone,
      address:        details['formatted_address'].to_s,
      bairro:         bairro,
      cidade:         cidade.presence || 'Osasco',
      rating:         details['rating'],
      reviews_count:  details['user_ratings_total'],
      reviews_sample: reviews_sample,
      place_id:       search_result['place_id'],
      website:        details['website'],
    }
  end
end
