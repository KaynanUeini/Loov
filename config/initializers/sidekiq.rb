# Só ativa Sidekiq quando REDIS_URL está configurado. Em ambientes sem Redis
# (ex: Render free tier sem add-on), cai no :async padrão do Rails — os jobs
# rodam in-process e podem morrer entre requests, mas o código crítico (ex:
# expiração de aceites Disponíveis) tem lazy expiration como rede de segurança.
if ENV["REDIS_URL"].present?
  Sidekiq.configure_server do |config|
    config.redis = { url: ENV["REDIS_URL"] }
  end

  Sidekiq.configure_client do |config|
    config.redis = { url: ENV["REDIS_URL"] }
  end

  Rails.application.config.active_job.queue_adapter = :sidekiq
else
  Rails.application.config.active_job.queue_adapter = :async
  Rails.logger.warn("[Sidekiq] REDIS_URL não configurado — usando :async como queue_adapter") if defined?(Rails.logger)
end
