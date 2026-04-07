# config/initializers/rack_attack.rb
# Proteção contra brute force, DDoS e abuso de API
# Requer: gem 'rack-attack' no Gemfile

class Rack::Attack

  # ── THROTTLE — Login brute force ────────────────────────────────────────
  # Máximo 5 tentativas de login por IP a cada 20 minutos
  throttle("logins/ip", limit: 5, period: 20.minutes) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Máximo 3 tentativas por email por hora (evita enumeração de contas)
  throttle("logins/email", limit: 3, period: 1.hour) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  # ── THROTTLE — Criação de tickets de suporte ────────────────────────────
  # Máximo 5 tickets por hora por IP
  throttle("support_tickets/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path.include?("/owner/support_tickets") && req.post?
  end

  # ── THROTTLE — Agendamentos ─────────────────────────────────────────────
  # Máximo 10 agendamentos por hora por IP
  throttle("appointments/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path == "/appointments" && req.post?
  end

  # ── THROTTLE — API de horários disponíveis ──────────────────────────────
  # Máximo 60 requisições por minuto por IP (proteção contra scraping)
  throttle("available_times/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.include?("/available_times")
  end

  # ── BLOCKLIST — IPs maliciosos ──────────────────────────────────────────
  # Bloqueia após 10 requisições suspeitas em 1 minuto
  blocklist("block_suspicious_ips") do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 10, findtime: 1.minute, bantime: 1.hour) do
      # Detecta tentativas de path traversal, SQL injection e scanner automático
      req.path.include?("../") ||
      req.path.include?("etc/passwd") ||
      req.query_string.include?("UNION SELECT") ||
      req.query_string.include?("--") ||
      req.path.include?(".php") ||
      req.path.include?(".env") ||
      req.path.include?("wp-admin")
    end
  end

  # ── RESPOSTA PARA REQUESTS BLOQUEADAS ───────────────────────────────────
  self.throttled_responder = lambda do |env|
    [
      429,
      { "Content-Type" => "application/json" },
      [{ error: "Muitas tentativas. Aguarde antes de tentar novamente." }.to_json]
    ]
  end

  self.blocklisted_responder = lambda do |env|
    [
      403,
      { "Content-Type" => "application/json" },
      [{ error: "Acesso negado." }.to_json]
    ]
  end
end
