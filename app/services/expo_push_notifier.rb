require "net/http"
require "json"

# Envia push notifications via Expo Push API.
# https://docs.expo.dev/push-notifications/sending-notifications/
#
# Uso:
#   ExpoPushNotifier.new.notify_user(
#     user,
#     title: "Reserva cancelada",
#     body:  "O lava-rápido cancelou seu agendamento",
#     data:  { type: "appointment_cancelled", appointment_id: 42 }
#   )
#
# Limpa tokens que a Expo reportar como inválidos (DeviceNotRegistered).
class ExpoPushNotifier
  ENDPOINT = "https://exp.host/--/api/v2/push/send".freeze

  def notify_user(user, title:, body:, data: {}, sound: "default")
    return if user.blank?
    tokens = user.push_tokens.pluck(:token).uniq
    return if tokens.empty?

    messages = tokens.map do |token|
      {
        to:       token,
        title:    title,
        body:     body,
        data:     data,
        sound:    sound,
        priority: "high",
      }
    end

    response = post(messages)
    handle_response(response, tokens)
  rescue => e
    Rails.logger.error("[ExpoPushNotifier] #{e.class}: #{e.message}")
    nil
  end

  private

  def post(messages)
    uri = URI(ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri.path, {
      "Content-Type" => "application/json",
      "Accept"       => "application/json",
    })
    req.body = messages.to_json
    http.request(req)
  end

  def handle_response(response, tokens)
    return unless response.is_a?(Net::HTTPSuccess)
    payload = JSON.parse(response.body) rescue nil
    return unless payload.is_a?(Hash) && payload["data"].is_a?(Array)

    payload["data"].each_with_index do |ticket, idx|
      next unless ticket.is_a?(Hash) && ticket["status"] == "error"
      error_code = ticket.dig("details", "error") || ticket["message"]
      if error_code.to_s.include?("DeviceNotRegistered")
        PushToken.where(token: tokens[idx]).destroy_all
      else
        Rails.logger.warn("[ExpoPushNotifier] token=#{tokens[idx]} error=#{error_code}")
      end
    end
  end
end
