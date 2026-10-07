# Formatos usados nos e-mails — um lugar só, pra todo e-mail falar a data
# do mesmo jeito ("Sexta, 9 de outubro às 14:30"), sempre no fuso de SP.
module EmailHelper
  def email_day(time)
    t = time.in_time_zone("America/Sao_Paulo")
    I18n.l(t.to_date, format: "%A, %-d de %B", locale: :"pt-BR").sub("-feira", "").capitalize
  end

  def email_time(time)
    time.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
  end

  def email_when(time)
    "#{email_day(time)} às #{email_time(time)}"
  end

  def email_money(value)
    number_to_currency(value, locale: :"pt-BR")
  end

  # Link de mapa a partir do endereço — abre o app de mapas no celular.
  def email_map_url(address)
    "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode(address)}"
  end

  def email_greeting(user)
    name = user&.greeting_name
    name.present? ? "Oi, #{name}." : "Oi!"
  end
end
