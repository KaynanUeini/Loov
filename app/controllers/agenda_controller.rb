class AgendaController < ApplicationController
  # GET /agenda/:token.ics
  #
  # "Adicionar à agenda" da confirmação do agendamento (app e site). Sem login
  # de propósito: o calendário do celular abre o link fora da sessão (o Safari
  # do iPhone mostra "Adicionar ao Calendário" direto pra text/calendar). O
  # token é o signed_id do agendamento, então não dá pra montar um evento
  # qualquer no nosso domínio nem chegar no agendamento de outra pessoa.
  def show
    a = Appointment.find_signed(params[:token], purpose: :agenda)
    return head(:not_found) unless a

    send_data ics_de(a),
              type: "text/calendar; charset=utf-8",
              disposition: %(inline; filename="loov-#{a.id}.ics")
  end

  private

  def ics_de(a)
    cw     = a.car_wash
    inicio = a.scheduled_at
    fim    = inicio + (a.service&.duration.to_i.positive? ? a.service.duration : 30).minutes
    local  = cw.endereco_rota.presence || cw.address.to_s
    utc    = ->(t) { t.utc.strftime("%Y%m%dT%H%M%SZ") }

    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Loov//Agendamento//PT-BR",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:agendamento-#{a.id}@loov",
      "DTSTAMP:#{utc.(Time.current)}",
      "DTSTART:#{utc.(inicio)}",
      "DTEND:#{utc.(fim)}",
      "SUMMARY:#{txt("#{a.service&.title || 'Lavagem'} · #{cw.name}")}",
      ("LOCATION:#{txt(local)}" if local.present?),
      "DESCRIPTION:#{txt('Agendado pelo Loov. Se não puder ir, cancele pelo app pra liberar o horário.')}",
      # Lembrete 1 h antes: o mesmo motivo do botão, chegar no horário.
      "BEGIN:VALARM",
      "TRIGGER:-PT1H",
      "ACTION:DISPLAY",
      "DESCRIPTION:#{txt("Lavagem no #{cw.name} em 1 hora")}",
      "END:VALARM",
      "END:VEVENT",
      "END:VCALENDAR"
    ].compact.join("\r\n") + "\r\n"
  end

  # Escape de texto do iCalendar (RFC 5545, 3.3.11).
  def txt(s)
    s.to_s.gsub("\\", "\\\\\\").gsub(";", "\;").gsub(",", "\\,").gsub(/\r?\n/, "\\n")
  end
end
