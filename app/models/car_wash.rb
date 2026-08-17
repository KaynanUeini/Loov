class CarWash < ApplicationRecord
  belongs_to :user
  has_many :services,              dependent: :destroy
  has_many :appointments,          dependent: :destroy
  has_many :operating_hours,       dependent: :destroy
  has_many :monthly_costs,         dependent: :destroy
  has_many :reviews,               through: :appointments
  has_many :attendant_invitations, dependent: :destroy
  has_many :pending_changes,       dependent: :destroy
  has_many :car_wash_closures,     dependent: :destroy
  has_one :loyalty_program, dependent: :destroy

  accepts_nested_attributes_for :operating_hours, allow_destroy: true, reject_if: :all_blank
  accepts_nested_attributes_for :services,        allow_destroy: true, reject_if: :all_blank

  validates :name,              presence: true
  validates :address,           presence: true
  validates :capacity_per_slot, presence: true, numericality: { greater_than: 0 }

  geocoded_by :geocoding_address
  after_validation :geocode, if: :should_geocode?

  # Só chama a API do Geocoder quando o endereço mudou E ainda não temos
  # coordenadas válidas. Evita bater no rate limit do Nominatim durante
  # seeds/imports que já trazem lat/lng prontos.
  def should_geocode?
    address_changed? && !has_valid_coordinates?
  end

  def geocoding_address
    parts = []
    parts << logradouro if logradouro.present?
    parts << cidade     if cidade.present?
    parts << uf         if uf.present?
    parts << "Brasil"
    parts.join(", ")
  end

  def has_valid_coordinates?
    latitude.present? && longitude.present? && latitude != 0.0 && longitude != 0.0
  end

  # Capacidade de atendimento simultâneo no dia da data/hora informada.
  #
  # A equipe varia ao longo da semana (menor no meio, maior no fim de semana),
  # então cada operating_hour pode ter a sua capacidade; sem valor definido,
  # vale o default do lava-rápido. Sempre >= 1 — capacidade zero deixaria a
  # agenda inteira indisponível sem o dono entender o porquê.
  #
  # Recebe Date, Time ou DateTime. Sem argumento com wday (nil), devolve o
  # default. Usa `detect` em vez de `find_by` de propósito: carrega a
  # associação uma vez e as chamadas seguintes do mesmo request batem em
  # memória, o que importa em available_times (dezenas de slots por dia).
  # A que horas este lava-rápido fecha, no dia do slot informado. nil quando não
  # há horário cadastrado pro dia.
  #
  # Mora aqui, e não nos controllers, porque a regra "o serviço tem que TERMINAR
  # dentro do expediente" precisa valer igual em todo caminho que oferece
  # horário. Estava escrita à mão só no DisponivelController: a home web não
  # checava e anunciava slot que o agendamento recusaria — Italy Wash fechando
  # 23:59 aparecia com vaga às 23:00 pra uma lavagem de 60 min, que termina
  # 00:00 e estoura o expediente por um minuto.
  def closing_at(slot)
    oh = operating_hours.detect { |h| h.day_of_week == slot.wday }
    return nil unless oh&.closes_at
    slot.beginning_of_day + oh.closes_at.seconds_since_midnight.seconds
  end

  # O serviço cabe inteiro antes de fechar, começando neste slot?
  def fits_before_closing?(slot, service)
    closes = closing_at(slot)
    return true if closes.nil?
    minutos = service&.duration.to_i
    minutos = 30 if minutos <= 0
    slot + minutos.minutes <= closes
  end

  # ── Last Minute: a vaga, no singular ──────────────────────────────────────
  #
  # Last Minute vende UMA vaga de última hora: a próxima marca de 30 minutos
  # com espaço. Às 20:21 o horário é 20:30; às 20:32 é 21:00. Nunca vários.
  #
  # Esta regra estava escrita em dois lugares e de formas diferentes. O
  # /disponivel devolvia um slot só, e o available_times do detalhe do
  # lava-rápido etiquetava como Last Minute TUDO que caísse dentro da trava de
  # 45 minutos — então a mesma vaga aparecia como três ou quatro na hora de
  # escolher horário, enquanto a home mostrava uma. É a terceira vez nesta base
  # que um caminho oferece o que o outro não reconhece; por isso a regra passa
  # a morar aqui e os dois controllers perguntam.
  JANELA_LAST_MINUTE = 30.minutes
  PASSO_LAST_MINUTE  = 30

  # A marca que o Last Minute vende agora, ou nil. Com `service`, só devolve a
  # marca se AQUELE serviço couber nela — cabe antes de fechar e tem capacidade
  # pela duração inteira dele.
  def last_minute_slot(agora = Time.current, service = nil)
    # A pausa é honrada AQUI e não em cada listagem de propósito. Todo caminho
    # que oferece Last Minute passa por este método, então a regra não tem como
    # ser esquecida em um deles — que é exatamente o que aconteceu cinco vezes
    # nesta base com a regra de capacidade.
    return nil if pausado?(agora)

    fecha = closing_at(agora)
    return nil if fecha.nil?

    # A janela para no fechamento: não adianta oferecer 23:30 quando fecha
    # 23:00.
    limite = [agora + JANELA_LAST_MINUTE, fecha].min
    # Arredonda pelos SEGUNDOS, não pelos minutos: às 20:30:30, contar só hora
    # e minuto devolve 1230 e o arredondamento pra cima cai em 20:30 — meio
    # minuto no passado. O checkout recusa horário que já passou, então seria
    # mais uma vaga anunciada que o backend nega no fim do fluxo.
    passo = PASSO_LAST_MINUTE * 60
    atual = agora.beginning_of_day +
            ((agora.seconds_since_midnight / passo.to_f).ceil * passo).seconds

    while atual <= limite
      return atual if service ? last_minute_cabe?(atual, service) : vaga_por?(atual, PASSO_LAST_MINUTE)
      atual += PASSO_LAST_MINUTE.minutes
    end
    nil
  end

  # Este serviço pode ser vendido nesta vaga?
  #
  # A capacidade é medida pela duração INTEIRA do serviço, não pelos 30 minutos
  # do passo. O checkout sempre cobrou a duração inteira, então conferir só o
  # primeiro meia-hora fazia a lista prometer uma lavagem de 90 minutos numa
  # vaga que o checkout recusaria — o mesmo defeito de um caminho oferecer o
  # que o outro nega, agora pela duração.
  def last_minute_cabe?(slot, service)
    fits_before_closing?(slot, service) && vaga_por?(slot, duracao_efetiva(service))
  end

  # Serviço sem duração cai no passo padrão, que é a granularidade do slot.
  def duracao_efetiva(service)
    d = service&.duration.to_i
    d > 0 ? d : PASSO_LAST_MINUTE
  end

  def vaga_por?(slot, minutos)
    ocupacao = Appointment.peak_concurrency_during(
      car_wash: self,
      start_at: slot,
      end_at:   slot + minutos.minutes
    )
    # Capacidade consultada por slot: a janela pode virar o dia, e cada dia da
    # semana tem a sua.
    ocupacao < capacity_for(slot)
  end

  # ── Pausa: o dono dizendo "não me mande nada agora" ───────────────────────
  #
  # Não é fechar. O que já está marcado continua valendo; a pausa só tira o
  # lava-rápido do Last Minute, que é o canal que chega sem aviso e exige
  # capacidade imediata.
  #
  # Nunca passa do fim do expediente: pausa que atravessa a noite viraria loja
  # fechada no dia seguinte sem ninguém lembrar de religar, e um controle que
  # trai assim é pior que controle nenhum — o dono para de confiar nele.
  # Aberto NESTE instante — não "abre neste dia da semana", que é o que
  # closing_at responde. A pausa só faz sentido com a loja aberta: fora do
  # horário não chega Last Minute nenhum, e um botão que não muda nada lê como
  # quebrado.
  def aberto_em?(agora = Time.current)
    oh = operating_hours.detect { |h| h.day_of_week == agora.wday }
    return false unless oh&.opens_at && oh&.closes_at
    seg = agora.seconds_since_midnight
    seg >= oh.opens_at.seconds_since_midnight && seg <= oh.closes_at.seconds_since_midnight
  end

  def pausado?(agora = Time.current)
    paused_until.present? && paused_until > agora
  end

  # Este HORÁRIO está dentro da janela pausada?
  #
  # A pausa nasceu bloqueando só o Last Minute, e isso estava errado ao
  # contrário: no Last Minute o dono ainda é a autoridade final — oferta ruim
  # ele recusa. No agendamento comum NÃO HÁ aceite, então o cliente marca e
  # pronto. Sem isto, um lava-rápido sem condição de atender continuava
  # recebendo agendamento pra daqui uma ou duas horas e o dono não tinha como
  # impedir. CarWashClosure não resolve: é por data inteira.
  #
  # O alcance é a própria janela da pausa, não "o resto do dia": pausar 30
  # minutos fecha 30 minutos de agenda; "até fechar" fecha o resto do dia. O
  # controle de duração que o dono já usa passa a ser também o de alcance, sem
  # inventar outro.
  def pausado_para?(slot, agora = Time.current)
    pausado?(agora) && slot < paused_until
  end

  def pausar!(minutos = nil, agora = Time.current)
    fecha = closing_at(agora)
    fim   = minutos.to_i > 0 ? agora + minutos.to_i.minutes : (fecha || agora.end_of_day)
    fim   = [fim, fecha].min if fecha
    # paused_at existe pra barra de tempo ter denominador. Sem ele dá pra
    # desenhar uma barra, mas ela não mede nada.
    update!(paused_until: fim, paused_at: agora)
    fim
  end

  def retomar!
    update!(paused_until: nil, paused_at: nil)
  end

  def capacity_for(date_or_time)
    wday = date_or_time.try(:wday)
    hour = wday && operating_hours.detect { |oh| oh.day_of_week == wday }
    return hour.effective_capacity if hour
    [capacity_per_slot.to_i, 1].max
  end

  # Verifica se há um CarWashClosure ativo cobrindo a data informada
  # (default: hoje). Usado pelos endpoints client-facing pra filtrar/marcar
  # como fechado lavas-rápidos com fechamento programado.
  def closed_on?(date = Date.current)
    car_wash_closures.where("start_date <= ? AND end_date >= ?", date, date).exists?
  end

  def full_address
    [logradouro, bairro, cidade, uf].select(&:present?).join(", ")
  end

  def location_context
    parts = []
    parts << "Bairro: #{bairro}" if bairro.present?
    parts << "Cidade: #{cidade}" if cidade.present?
    parts << "UF: #{uf}"        if uf.present?
    parts << "CEP: #{cep}"      if cep.present?
    parts.join(" | ")
  end
end
