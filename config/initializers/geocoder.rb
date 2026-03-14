Geocoder.configure(
  lookup:     :nominatim,
  timeout:    10,
  units:      :km,
  http_headers: {
    "User-Agent"    => "Loov/1.0 (agendamento de lava-rapidos; contato@loov.com.br)",
    "Accept"        => "application/json",
    "Referer"       => "https://loov.com.br"
  }
)
