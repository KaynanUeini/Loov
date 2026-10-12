# Aviso pro dono nos dias em que um ciclo da análise de IA abre (dia 15 e
# último dia do mês — AiInsight.dia_de_ciclo?). Pede duas coisas, nessa
# ordem: lançar os custos do mês no Financeiro (sem eles a IA lê um lucro
# maior do que é) e gerar a análise.
#
# Roda junto do lembrete da véspera, no mesmo gatilho diário
# (Internal::RemindersController, chamado pelo GitHub Actions às 18h). Nos
# outros dias não faz nada. Um envio por dono por dia: o gatilho tem retry.
class AiInsightReminders
  MESES = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze

  def self.run!(hoje = Date.current) = new(hoje).run!

  def initialize(hoje)
    @hoje = hoje
  end

  def run!
    return { ai_reminders: 0, motivo: "não é dia de ciclo" } unless AiInsight.dia_de_ciclo?(@hoje)

    enviados = 0
    CarWash.includes(:user).find_each do |cw|
      dono = cw.user
      next unless dono&.owner? && dono.active_for_authentication?
      next if ja_gerou?(cw)

      chave = "ai_reminder:#{@hoje}:#{dono.id}"
      next if Rails.cache.read(chave)

      ExpoPushNotifier.new.notify_user(dono, title: titulo, body: corpo(cw), data: { type: "ai_insights_cycle" })
      Rails.cache.write(chave, true, expires_in: 2.days)
      enviados += 1
    rescue => e
      Rails.logger.error("[AiInsightReminders] car_wash ##{cw.id}: #{e.message}")
    end
    { ai_reminders: enviados }
  end

  # Mesmo texto da central de notificações do dono.
  def self.texto(car_wash, hoje = Date.current)
    r = new(hoje)
    { title: r.titulo, body: r.corpo(car_wash) }
  end

  def titulo
    @hoje == @hoje.end_of_month ? "Fechamento do mês: hora da análise de IA" : "Meio do mês: hora da análise de IA"
  end

  def corpo(car_wash)
    mes = MESES[@hoje.month - 1]
    custos = MonthlyCost.exists?(car_wash_id: car_wash.id, year: @hoje.year, month: @hoje.month)
    pedido = custos ? "Confira se os custos de #{mes} no Financeiro estão em dia" : "Lance os custos de #{mes} no Financeiro"
    "#{pedido} e gere a nova análise: com os custos certos, ela fica mais completa."
  end

  private

  def ja_gerou?(car_wash)
    ultima = AiInsight.current_for(car_wash)
    ultima&.ready? && ultima.generated_at.to_date >= AiInsight.inicio_do_ciclo(@hoje)
  end
end
