# Lembrete do vale de fidelidade perto de vencer: um push por vale, 7 dias
# antes (LoyaltyReward::AVISO_ANTES), só pra quem ainda não usou nem marcou
# horário com ele. Pega carona no gatilho diário do lembrete da véspera
# (POST /internal/reminders) — no Render free não há cron aqui dentro.
class LoyaltyRewardReminders
  BATCH = 50

  def self.run!(batch: BATCH)
    sent = 0
    due.includes(:user, :car_wash).limit(batch).each do |vale|
      # Marca antes: push repetido é pior que um lembrete a menos.
      vale.update_column(:reminder_sent_at, Time.current)
      dias = ((vale.expires_at - Time.current) / 1.day).ceil
      ExpoPushNotifier.new.notify_user(
        vale.user,
        title: dias <= 1 ? "Seu vale vence hoje" : "Seu vale vence em #{dias} dias",
        body:  "#{vale.resumo_curto} no #{vale.car_wash.name}. Agende pra usar antes de perder.",
        data:  { type: "loyalty_reward_expiring", car_wash_id: vale.car_wash_id, reward_id: vale.id }
      )
      sent += 1
    rescue => e
      Rails.logger.error("[LoyaltyRewardReminders] vale ##{vale.id}: #{e.class}: #{e.message}")
    end
    { vales_lembrados: sent, vales_restantes: due.count }
  end

  def self.due
    LoyaltyReward.livres.where(reminder_sent_at: nil)
                 .where("loyalty_rewards.expires_at <= ?", Time.current + LoyaltyReward::AVISO_ANTES)
  end
end
