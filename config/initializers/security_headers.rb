# config/initializers/security_headers.rb
# Headers HTTP de segurança aplicados em todas as respostas

Rails.application.config.action_dispatch.default_headers = {
  # Previne clickjacking — página não pode ser carregada em iframe externo
  "X-Frame-Options"        => "SAMEORIGIN",

  # Previne MIME sniffing — browser respeita o Content-Type declarado
  "X-Content-Type-Options" => "nosniff",

  # Ativa proteção XSS do browser (legado, mas ainda útil)
  "X-XSS-Protection"       => "1; mode=block",

  # Não envia Referer para outros domínios — protege URLs internas
  "Referrer-Policy"        => "strict-origin-when-cross-origin",

  # Permissions-Policy — libera geolocation no próprio domínio (clientes
  # precisam pra encontrar lava-rápidos perto). Os outros sensores ficam
  # bloqueados por default.
  "Permissions-Policy"     => "geolocation=(self), camera=(), microphone=(), gyroscope=(), payment=()",

  # Remove header que revela que usamos Ruby on Rails
  "X-Powered-By"           => nil,
  "X-Runtime"              => nil,

  # Content Security Policy — define quais recursos podem ser carregados
  # Ajuste os domínios conforme necessário (CDNs, Stripe, etc.)
  "Content-Security-Policy" => [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline' https://js.stripe.com https://cdn.jsdelivr.net",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net",
    "font-src 'self' https://fonts.gstatic.com https://cdn.jsdelivr.net",
    "img-src 'self' data: https:",
    "connect-src 'self' https://api.stripe.com https://api.anthropic.com",
    "frame-src https://js.stripe.com",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'"
  ].join("; ")
}
