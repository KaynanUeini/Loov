module Owner
  class DisponivelAcceptanceController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :set_car_wash
    before_action :expire_stale_acceptances!
    before_action :set_appointment, only: [:show, :accept, :reject, :seen]

    # GET /owner/disponivel_acceptance
    # Lista agendamentos disponíveis aguardando aceite (para polling do painel)
    def index
      @pending = Appointment
        .where(car_wash_id: visible_car_wash_ids)
        .disponivel
        .pending_acceptance
        .where("acceptance_expires_at > ?", Time.current)
        .includes(:user, :service, :car_wash)
        .order(:acceptance_expires_at)

      lista = @pending.map { |a| serialize(a) }

      # `include_state` de propósito, em vez de trocar a forma da resposta:
      # esta é a tela onde o dono aceita solicitações, e um app antigo lendo um
      # objeto onde esperava array mostraria a fila VAZIA. Perder um pedido de
      # verdade por causa de uma janela de deploy é inaceitável aqui, então a
      # forma antiga continua valendo pra quem não pede o estado.
      if params[:include_state].present?
        cws = CarWash.where(id: visible_car_wash_ids)
        render json: {
          requests: lista,
          # Pausado = TODOS os visíveis estão pausados. Com um só lava-rápido,
          # que é o caso comum, dá no mesmo; com vários, dizer "pausado" com um
          # deles ainda recebendo seria mentira.
          paused:       cws.any? && cws.all?(&:pausado?),
          paused_until: cws.filter_map(&:paused_until).max&.iso8601,
          open_now:     cws.any?(&:aberto_em?),
          # A tela "esperando" (o placar do app): a vaga que está na vitrine
          # agora, as duas meias horas seguintes e o que o Last Minute rendeu
          # hoje. Com vários lava-rápidos, a vitrine é a do primeiro aberto.
          vitrine: vitrine_de(cws),
        }
      else
        render json: lista
      end
    end

    # GET /owner/disponivel_acceptance/diagnostic
    #
    # Responde "por que não aparece nada pra mim?" com dado em vez de palpite.
    # O index legítimo esconde tudo que expirou ou mudou de status, então um
    # pedido que existiu e morreu é indistinguível de um pedido que nunca
    # chegou — e é justamente essa diferença que precisa ser vista.
    def diagnostic
      ids = visible_car_wash_ids

      recent = Appointment
        .where(car_wash_id: ids)
        .disponivel
        .includes(:user, :service, :car_wash)
        .order(created_at: :desc)
        .limit(10)

      render json: {
        server_time:      Time.current.iso8601,
        acceptance_ttl_s: Appointment::ACCEPTANCE_TTL.to_i,
        user: {
          id:    current_user.id,
          email: current_user.email,
          role:  current_user.role
        },
        car_washes: current_user.car_washes.map { |cw| { id: cw.id, name: cw.name } },
        visible_car_wash_ids: ids,
        # Homônimos de outro dono. O cliente vê "Italy Wash" na lista e reserva;
        # o dono abre o painel do SEU "Italy Wash" e não encontra nada — os dois
        # estão certos, são registros diferentes. Sem isto, o sintoma é
        # indistinguível de pedido perdido.
        homonimos_de_outro_dono: CarWash
          .where(name: current_user.car_washes.pluck(:name))
          .where.not(user_id: current_user.id)
          .map { |cw|
            {
              id:            cw.id,
              name:          cw.name,
              owner_user_id: cw.user_id,
              pedidos_1h:    cw.appointments.disponivel
                               .where("appointments.created_at > ?", 1.hour.ago).count
            }
          },
        pending_now: Appointment.where(car_wash_id: ids).disponivel.pending_acceptance
                                .where("acceptance_expires_at > ?", Time.current).count,
        recent_disponivel: recent.map { |a|
          {
            id:           a.id,
            car_wash:     a.car_wash&.name,
            client:       a.display_client,
            service:      a.service&.title,
            status:       a.status,
            created_at:   a.created_at.iso8601,
            scheduled_at: a.scheduled_at&.iso8601,
            expires_at:   a.acceptance_expires_at&.iso8601,
            seconds_left: a.acceptance_expires_at ? (a.acceptance_expires_at - Time.current).to_i : nil
          }
        }
      }
    end

    # GET /owner/disponivel_acceptance/:id (JSON)
    # Detalhes de um pedido específico — para o countdown individual
    def show
      render json: serialize(@appointment)
    end

    # PATCH /owner/disponivel_acceptance/:id/accept
    def accept
      if @appointment.acceptance_expired?
        render json: { error: "O tempo de aceite expirou." }, status: :unprocessable_entity
        return
      end

      stripe_service = StripeService.new

      if @appointment.accept!(stripe_service)
        render json: {
          ok:      true,
          message: "Agendamento aceito e pagamento capturado.",
          appointment: serialize(@appointment.reload)
        }
      else
        render json: { error: "Não foi possível aceitar o agendamento." }, status: :unprocessable_entity
      end
    end

    # POST /owner/disponivel_acceptance/:id/seen
    # O painel chama quando o pedido aparece na tela de alguém, com a aba ou o
    # app em primeiro plano. Só a primeira vez conta: o cliente vê "Visto às
    # 12:58", e esse horário não pode andar a cada polling.
    def seen
      if @appointment.status == "pending_acceptance" && @appointment.acceptance_seen_at.nil?
        @appointment.update_column(:acceptance_seen_at, Time.current)
      end
      head :no_content
    end

    # PATCH /owner/disponivel_acceptance/:id/reject
    def reject
      stripe_service = StripeService.new

      if @appointment.reject!(stripe_service)
        render json: {
          ok:      true,
          message: "Agendamento recusado. Pagamento não realizado."
        }
      else
        render json: { error: "Não foi possível recusar o agendamento." }, status: :unprocessable_entity
      end
    end

    private

    def set_car_wash
      @car_wash = current_car_wash
    end

    # Todos os lava-rápidos que este usuário opera. O dono pode ter mais de um
    # (o cadastro nunca impediu), mas current_car_wash resolve pra
    # car_washes.first — então uma reserva feita no segundo ficava invisível no
    # painel, sem erro nenhum, como se o cliente nunca tivesse pedido.
    def visible_car_wash_ids
      return current_user.car_washes.pluck(:id) if current_user.owner?
      [current_car_wash&.id].compact
    end

    def set_appointment
      @appointment = Appointment
        .where(car_wash_id: visible_car_wash_ids)
        .disponivel
        .find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Agendamento não encontrado." }, status: :not_found
    end

    # Delega para o método centralizado (throttled) no Appointment.
    def expire_stale_acceptances!
      Appointment.expire_stale_disponivel_acceptances!
    end

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { error: "Acesso negado." }, status: :forbidden
      end
    end

    # A vitrine responde o mesmo que o Last Minute do cliente: uma vaga só
    # conta se ALGUM serviço do Last Minute cabe nela (espaço no pátio pela
    # duração inteira e terminar antes de fechar). Olhar só o espaço anunciava
    # 23:30 num lava-rápido que fecha 23:59, onde nenhuma lavagem cabe.
    def vitrine_de(cws)
      agora = Time.current
      cw = cws.find { |c| c.aberto_em?(agora) } || cws.first
      return nil unless cw
      servicos = cw.services.last_minute.to_a
      # Igual ao /disponivel do cliente: só lava-rápido aberto AGORA e sem
      # fechamento cadastrado hoje entra no Last Minute. last_minute_slot só
      # olha o fechamento, então de madrugada ele achava 00:30, 01:00… num
      # lava-rápido que abre às 8h.
      aberto = cw.aberto_em?(agora) && !cw.closed_on?(agora.to_date)
      vaga = aberto ? servicos.filter_map { |sv| cw.last_minute_slot(agora, sv) }.min : nil
      fecha = cw.closing_at(agora)
      # Sem vaga: porque o dia acabou (nenhuma lavagem termina antes de fechar
      # na próxima marca) ou porque o pátio está cheio. A tela diz qual.
      sem_vaga = aberto ? nil : "fora"
      if vaga.nil? && aberto && !cw.pausado?(agora)
        passo = CarWash::PASSO_LAST_MINUTE * 60
        marca = agora.beginning_of_day + ((agora.seconds_since_midnight / passo.to_f).ceil * passo).seconds
        sem_vaga = servicos.any? { |sv| cw.fits_before_closing?(marca, sv) } ? "cheio" : "fechando"
      end
      seguintes = []
      if vaga
        t = vaga + CarWash::PASSO_LAST_MINUTE.minutes
        2.times do
          # Marca em que nenhum serviço termina antes do fechamento DE HOJE já
          # não é horário. closing_at(t) olha o dia de t: às 23:30, a marca
          # 00:00 caía no dia seguinte e passava como "próxima na vitrine"
          # num lava-rápido que só reabre às 8h.
          break if fecha.nil? || t.to_date != vaga.to_date
          break unless servicos.any? { |sv| t + cw.duracao_efetiva(sv).minutes <= fecha }
          seguintes << { hora: t.strftime("%H:%M"), livre: servicos.any? { |sv| cw.last_minute_cabe?(t, sv) } }
          t += CarWash::PASSO_LAST_MINUTE.minutes
        end
      end
      hoje = Appointment.where(car_wash_id: cws.map(&:id)).disponivel
        .where(status: %w[confirmed attended])
        .where(scheduled_at: agora.beginning_of_day..agora.end_of_day)
        .includes(:service).to_a
      {
        car_wash:   cw.name,
        vaga:       vaga&.strftime("%H:%M"),
        sem_vaga:   sem_vaga,
        fecha:      fecha&.strftime("%H:%M"),
        abre:       aberto ? nil : proxima_abertura(cw, agora),
        seguintes:  seguintes,
        hoje_qtd:   hoje.size,
        hoje_total: hoje.sum { |a| a.effective_price.to_f }.round(2),
      }
    end

    # Quando o lava-rápido volta a abrir: { hora: "08:00", dia: "hoje" |
    # "amanhã" | "segunda"… }. Pula os dias sem horário e os fechamentos
    # cadastrados (férias, feriado).
    DIAS = %w[domingo segunda terça quarta quinta sexta sábado].freeze
    def proxima_abertura(cw, agora)
      (0..7).each do |n|
        dia = agora.to_date + n
        oh = cw.operating_hours.detect { |h| h.day_of_week == dia.wday }
        next unless oh&.opens_at && oh&.closes_at
        next if cw.closed_on?(dia)
        abre = agora.beginning_of_day + n.days + oh.opens_at.seconds_since_midnight.seconds
        next if abre <= agora
        return { hora: abre.strftime("%H:%M"), dia: n.zero? ? "hoje" : n == 1 ? "amanhã" : DIAS[dia.wday] }
      end
      nil
    end

    def serialize(appointment)
      {
        id:             appointment.id,
        status:         appointment.status,
        seconds_left:   appointment.seconds_until_expiry,
        expires_at:     appointment.acceptance_expires_at&.iso8601,
        client_name:    appointment.display_client,
        # O dono não recebe um nome, recebe um carro. Modelo e placa são como
        # ele confere que quem encostou é quem pediu — e a placa é o único
        # dado do pedido que não depende do cliente se identificar.
        vehicle_model:  appointment.user&.vehicle_model.presence,
        vehicle_plate:  appointment.user&.vehicle_plate.presence,
        # Qual unidade recebeu o pedido: sem isso, o dono com mais de um
        # lava-rápido não sabe pra onde o cliente está indo.
        car_wash_id:    appointment.car_wash_id,
        car_wash_name:  appointment.car_wash&.name,
        service_id:     appointment.service_id,
        service_name:   appointment.service.title,
        service_price:  appointment.effective_price,
        prepayment:     appointment.prepayment_amount,
        commission:     appointment.commission_amount,
        owner_net:      appointment.owner_prepayment_net,
        # O que o dono recebe no balcão quando o cliente chega: o serviço menos
        # o que já ficou garantido no cartão. É o "Você recebe" do aceite.
        on_arrival:     (appointment.effective_price - appointment.prepayment_amount.to_f).clamp(0, Float::INFINITY).round(2),
        scheduled_at:   appointment.scheduled_at.strftime("%H:%M"),
        scheduled_date: appointment.scheduled_at.strftime("%d/%m/%Y")
      }
    end
  end
end
