class DisponivelController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!, except: [:index]
  before_action :expire_stale_acceptances!

  # GET /disponivel
  def index
    @lat = params[:latitude].presence&.to_f
    @lon = params[:longitude].presence&.to_f

    window_start = Time.current
    today_dow    = Date.current.wday
    now_seconds  = Time.current.seconds_since_midnight.to_i

    open_car_wash_ids = OperatingHour
    .where(day_of_week: today_dow)
    .select { |oh|
      opens_sec  = oh.opens_at.seconds_since_midnight.to_i  rescue 0
      closes_sec = oh.closes_at.seconds_since_midnight.to_i rescue 86400
      now_seconds >= opens_sec && now_seconds <= closes_sec
    }
    .map(&:car_wash_id).uniq

    car_washes_scope = CarWash.where(id: open_car_wash_ids).distinct
    car_washes_scope = car_washes_scope.near([@lat, @lon], 5, units: :km) if @lat && @lon

    # Exclui lava-rápidos com fechamento ativo cobrindo HOJE (férias,
    # feriado, manutenção). Sub-query mais eficiente que ruby filter.
    today          = Date.current
    closed_ids_now = CarWashClosure
      .where("start_date <= ? AND end_date >= ?", today, today)
      .pluck(:car_wash_id)
    car_washes_scope = car_washes_scope.where.not(id: closed_ids_now) if closed_ids_now.any?

    # Filtro por car_wash específico — usado pelo BookingScreen quando o
    # cliente clica num slot disponivel_only e quer ir direto pro Last
    # Minute desse lava-rápido.
    if params[:car_wash_id].present?
      car_washes_scope = car_washes_scope.where(id: params[:car_wash_id])
    end

    # Dedup em Ruby como rede de segurança — geocoder .near pode adicionar
    # JOINs que fazem o mesmo car_wash aparecer mais de uma vez no .each.
    raw_car_washes    = car_washes_scope.to_a
    dedup_car_washes  = raw_car_washes.uniq(&:id)
    if raw_car_washes.size != dedup_car_washes.size
      Rails.logger.warn("[Disponivel#index] duplicata detectada: raw=#{raw_car_washes.size} dedup=#{dedup_car_washes.size} ids=#{raw_car_washes.map(&:id)}")
    end

    @available_slots = []

    # Tudo o que o laço abaixo consulta, carregado de uma vez pra todas as
    # lojas: horários de funcionamento, lavagens e ocupação. Antes eram ~120
    # consultas por carregamento (algumas por loja, uma de cada vez); agora
    # são poucas, e o Last Minute aparece bem mais rápido na home.
    ActiveRecord::Associations::Preloader.new(records: dedup_car_washes, associations: :operating_hours).call
    cw_ids = dedup_car_washes.map(&:id)
    services_by_cw = Service.last_minute.where(car_wash_id: cw_ids).order(:price).group_by(&:car_wash_id)
    max_duration = services_by_cw.values.flatten.map { |svc| svc.duration.to_i }.max.to_i
    occupancy_until = window_start + CarWash::JANELA_LAST_MINUTE + CarWash::PASSO_LAST_MINUTE.minutes +
                      [max_duration, CarWash::PASSO_LAST_MINUTE].max.minutes

    Appointment.with_preloaded_occupancy(cw_ids, from: window_start - 1.minute, to: occupancy_until) do
    dedup_car_washes.each do |cw|
      # Last Minute é um produto de LAVAGEM: oferece todas as lavagens do
      # estabelecimento e nenhum outro tipo de serviço (polimento, higienização
      # etc.). Antes o corte era por duração (<= 60 min), o que escondia a
      # "Lavagem Completa" e fazia o cliente ver uma opção só, sem entender por
      # quê — enquanto deixava passar serviços de outras categorias curtos.
      entry_services = services_by_cw[cw.id] || []
      next if entry_services.empty?

      slot = cw.last_minute_slot(window_start)
      next if slot.nil?

      # Não basta estar aberto e a marca existir: cada serviço precisa CABER
      # nela. Cabe antes do fechamento — fecha 23:30, são 23:18 e a lavagem
      # mais curta é de 60 min? não há o que oferecer — e tem capacidade pela
      # duração INTEIRA, que é o que o checkout cobra. Sem os dois, a lista
      # promete um horário que o backend nega no fim do fluxo.

      fitting = entry_services.select { |s| cw.last_minute_cabe?(slot, s) }
      next if fitting.empty?

      distance_km = (@lat && @lon && cw.has_valid_coordinates?) ?
        cw.distance_to([@lat, @lon], :km).round(2) : nil

      @available_slots << {
        car_wash:    cw,
        services:    fitting,
        slots:       [slot],
        min_price:   fitting.map { |s| s.price.to_f }.min,
        distance_km: distance_km
      }
    end
    end

    # Belt-and-suspenders: dedup final pelo id do car_wash
    @available_slots.uniq! { |s| s[:car_wash].id }
    @available_slots.sort_by! { |s| [s[:slots].first, s[:min_price]] }

    respond_to do |format|
      format.html
      format.json do
        # Batch de rating pra evitar N+1 quando renderizar cards do
        # Last Minute no mobile (que agora mostra ⭐ no canto superior).
        slot_cw_ids = @available_slots.map { |s| s[:car_wash].id }
        rating_map = Review.where(car_wash_id: slot_cw_ids)
                           .group(:car_wash_id)
                           .pluck(:car_wash_id, Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))
                           .each_with_object({}) { |(id, avg, count), h|
                             h[id] = { avg: avg.to_f.round(1), count: count.to_i }
                           }

        # Batch dos favoritos do cliente logado — index é opcional-auth
        # (skip authenticate_user!), então current_user pode ser nil.
        # O card do Last Minute mostra um marcador cinza pros favoritados.
        favorite_ids = current_user ?
          current_user.favorite_car_washes.where(car_wash_id: slot_cw_ids).pluck(:car_wash_id).to_set :
          Set.new

        render json: @available_slots.map { |s|
          cw = s[:car_wash]
          r  = rating_map[cw.id] || { avg: 0.0, count: 0 }
          {
            car_wash: {
              id:            cw.id,
              name:          cw.name,
              address:       cw.address,
              logradouro:    cw.logradouro,
              numero:        cw.numero,
              bairro:        cw.bairro,
              cidade:        cw.cidade,
              uf:            cw.uf,
              latitude:      cw.latitude,
              longitude:     cw.longitude,
              distance_km:   s[:distance_km],
              rating_avg:    r[:avg],
              reviews_count: r[:count],
              favorited:     favorite_ids.include?(cw.id)
            },
            services:  s[:services].map { |svc|
              {
                id:          svc.id,
                title:       svc.title,
                price:       svc.price.to_f,
                duration:    svc.duration,
                category:    svc.category,
                description: svc.description
              }
            },
            slots:     s[:slots].map(&:iso8601),
            min_price: s[:min_price].to_f
          }
        }
      end
    end
  end

  # GET /disponivel/checkout
  # Mostra o resumo da reserva.
  # A verificação de cartão acontece apenas no POST /disponivel (create).
  def checkout
    @car_wash = CarWash.find(params[:car_wash_id])
    @service  = @car_wash.services.find(params[:service_id])
    @slot     = Time.zone.parse(params[:slot])

    # Mesma definição que monta a lista — se divergir, o cliente escolhe algo
    # que aparecia e aqui leva um "indisponível" que não faz sentido pra ele.
    unless last_minute_services(@car_wash).exists?(id: @service.id)
      redirect_to disponivel_index_path, alert: "Serviço indisponível na aba Disponíveis."
      return
    end

    if @slot < Time.current.in_time_zone("America/Sao_Paulo")
      redirect_to disponivel_index_path, alert: "Este horário já passou."
      return
    end

    unless slot_available?(@car_wash, @slot, @service)
      redirect_to disponivel_index_path, alert: "Este horário acabou de ser ocupado."
      return
    end

    @total_price = @service.price.to_f
    @prepayment  = (@total_price * Appointment::PREPAYMENT_PCT).round(2)
    @remaining   = (@total_price - @prepayment).round(2)
    @has_card    = current_user.has_payment_method?
    @card_display = current_user.card_display

  rescue ActiveRecord::RecordNotFound
    redirect_to disponivel_index_path, alert: "Lava-rápido ou serviço não encontrado."
  end

  # POST /disponivel
  #
  # Site e app: a reserva exige cartão e pré-autoriza 35% do serviço (o
  # PREPAYMENT_PCT) no momento do pedido: o valor fica reservado no cartão,
  # vira cobrança quando o dono aceita (Appointment#accept!) e é liberado se
  # ele recusa, se o tempo de aceite acaba ou se o cliente desiste. Os 65%
  # restantes são pagos no lava-rápido.
  def create
    log_tag = "[Disponivel#create]"
    Rails.logger.info("#{log_tag} IN user_id=#{current_user&.id} params=#{params.permit(:car_wash_id, :service_id, :slot).to_h.inspect}")

    unless current_user.has_payment_method?
      render json: {
        error: "Cadastre um cartão para reservar no Last Minute. Você paga #{(Appointment::PREPAYMENT_PCT * 100).round}% agora pra garantir a vaga.",
        code:  "card_required"
      }, status: :payment_required
      return
    end

    car_wash = CarWash.find(params[:car_wash_id])
    service  = car_wash.services.find(params[:service_id])
    slot     = Time.zone.parse(params[:slot])

    Rails.logger.info("#{log_tag} resolved car_wash_id=#{car_wash.id} service_id=#{service.id} slot=#{slot.iso8601}")

    appointment   = nil
    slot_taken    = false
    save_error    = nil

    # Transação + row-level lock na car_wash serializa todas as tentativas
    # de reserva concorrentes para o mesmo lava-rápido. Sem isso, dois
    # clientes clicando "Reservar" ao mesmo tempo poderiam passar pelo
    # slot_available? simultaneamente e ambos criar agendamento no mesmo
    # slot → overbooking.
    ActiveRecord::Base.transaction do
      car_wash.lock!

      unless slot_available?(car_wash, slot, service)
        slot_taken = true
        raise ActiveRecord::Rollback
      end

      expires_at  = Time.current + Appointment::ACCEPTANCE_TTL
      appointment = Appointment.new(
        user:                  current_user,
        car_wash:              car_wash,
        service:               service,
        scheduled_at:          slot,
        status:                "pending_acceptance",
        appointment_type:      "disponivel",
        acceptance_expires_at: expires_at
      )
      # Valores informativos (pré-pagamento teórico, comissão) — úteis para DRE/relatórios
      appointment.calculate_disponivel_amounts!

      unless appointment.save
        save_error = appointment.errors.full_messages.join(", ")
        raise ActiveRecord::Rollback
      end
    end

    if slot_taken
      Rails.logger.warn("#{log_tag} slot_taken car_wash_id=#{car_wash.id} slot=#{slot.iso8601}")
      render json: { error: "Este horário acabou de ser ocupado. Escolha outro." }, status: :unprocessable_entity
      return
    end

    if save_error
      Rails.logger.warn("#{log_tag} save_error car_wash_id=#{car_wash.id} slot=#{slot.iso8601} errors=#{save_error.inspect}")
      render json: { error: save_error }, status: :unprocessable_entity
      return
    end

    outcome, detail = authorize_prepayment!(appointment, log_tag)
    if outcome == :declined
      render json: { error: detail, code: "card_declined" }, status: :payment_required
      return
    end
    if outcome == :action
      # Banco pediu 3DS: a vaga fica segura por PAYMENT_AUTH_TTL enquanto o
      # cliente confirma (navegador no site,
      # tela do Stripe no app). O dono só fica sabendo depois.
      Rails.logger.info("#{log_tag} requires_action appointment_id=#{appointment.id}")
      begin
        ExpireDisponivelAcceptanceJob.set(wait: Appointment::PAYMENT_AUTH_TTL).perform_later(appointment.id)
      rescue => job_err
        Rails.logger.warn("#{log_tag} falha ao enfileirar expiração do 3DS: #{job_err.message}")
      end
      render json: {
        ok:              true,
        requires_action: true,
        appointment_id:  appointment.id,
        client_secret:   detail,
        # O app inicializa o Stripe com esta chave pra abrir a confirmação.
        publishable_key: ENV["STRIPE_PUBLISHABLE_KEY"].presence || Rails.application.credentials.dig(:stripe, :publishable_key),
        prepayment:      appointment.prepayment_amount.to_f
      }
      return
    end

    Rails.logger.info("#{log_tag} OK appointment_id=#{appointment.id}")
    start_acceptance!(appointment, log_tag)
    render json: request_payload(appointment)

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn("#{log_tag} not_found user_id=#{current_user&.id} car_wash_id=#{params[:car_wash_id].inspect} service_id=#{params[:service_id].inspect} msg=#{e.message}")
    render json: { error: "Lava-rápido ou serviço não encontrado." }, status: :not_found
  rescue => e
    Rails.logger.error("#{log_tag} error #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
    render json: {
      error: e.message,
      trace: e.backtrace&.first(3)
    }, status: :internal_server_error
  end

  # POST /disponivel/:id/authorized
  #
  # O navegador chama depois que o cliente confirmou no banco (3DS). Não
  # confia no navegador: pergunta ao Stripe se o valor está mesmo reservado.
  # Só aí o pedido vira pending_acceptance, o dono é avisado e os 3 min de
  # aceite começam a contar — o tempo gasto no banco não sai do prazo dele.
  def authorized
    log_tag = "[Disponivel#authorized]"
    appointment = Appointment.find(params[:id])
    return render(json: { error: "Acesso negado." }, status: :forbidden) unless appointment.user_id == current_user.id

    # Segunda chamada (duplo clique, retry): devolve o estado já alcançado.
    return render(json: request_payload(appointment)) if appointment.status == "pending_acceptance"

    unless appointment.status == "awaiting_payment" && appointment.stripe_payment_intent_id.present?
      return render json: { error: "O tempo para confirmar no banco acabou e a vaga foi liberada.", code: "expired" },
                    status: :unprocessable_entity
    end

    intent = StripeService.new.retrieve(appointment.stripe_payment_intent_id)
    unless intent.status == "requires_capture"
      release_prepayment(appointment)
      appointment.update_columns(status: "cancelled", updated_at: Time.current)
      Rails.logger.warn("#{log_tag} intent #{intent.id} status=#{intent.status} appointment_id=#{appointment.id}")
      return render json: { error: "O banco não confirmou o pagamento. Nada foi cobrado; tente de novo ou use outro cartão.", code: "card_declined" },
                    status: :payment_required
    end

    promoted = false
    appointment.with_lock do
      if appointment.status == "awaiting_payment"
        appointment.update!(status: "pending_acceptance", acceptance_expires_at: Time.current + Appointment::ACCEPTANCE_TTL)
        promoted = true
      end
    end
    start_acceptance!(appointment, log_tag) if promoted
    Rails.logger.info("#{log_tag} OK appointment_id=#{appointment.id} promoted=#{promoted}")
    render json: request_payload(appointment.reload)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Reserva não encontrada." }, status: :not_found
  rescue Stripe::StripeError => e
    Rails.logger.error("#{log_tag} stripe_error #{e.class}: #{e.message}")
    render json: { error: "Não conseguimos confirmar com o banco agora. Tente de novo em instantes." }, status: :bad_gateway
  end

  # GET /disponivel/:id/confirmacao
  def confirmacao
    @appointment = Appointment.find(params[:id])
    redirect_to root_path, alert: "Acesso negado." unless @appointment.user == current_user
  end

  # PATCH /disponivel/:id/cancel
  # Cliente desiste da reserva antes do dono aceitar. Só permite enquanto o
  # status ainda é pending_acceptance — depois disso (confirmed/cancelled/
  # rejected) a transição não faz sentido e retorna 422.
  def cancel
    appointment = Appointment.find(params[:id])

    unless appointment.user_id == current_user.id
      render json: { error: "Acesso negado." }, status: :forbidden
      return
    end

    unless %w[pending_acceptance awaiting_payment].include?(appointment.status)
      render json: {
        error: "Esta reserva não pode mais ser cancelada.",
        status: appointment.status
      }, status: :unprocessable_entity
      return
    end

    appointment.update!(status: "cancelled")
    release_prepayment(appointment)
    render json: { ok: true, status: appointment.status }

  rescue ActiveRecord::RecordNotFound
    render json: { error: "Reserva não encontrada." }, status: :not_found
  rescue => e
    Rails.logger.error("Disponivel#cancel error: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end

  # GET /disponivel/:id (JSON polling)
  def show
    appointment = Appointment.find(params[:id])
    unless appointment.user == current_user
      render json: { error: "Acesso negado." }, status: :forbidden
      return
    end
    render json: {
      status:        appointment.status,
      seconds_left:  appointment.seconds_until_expiry,
      car_wash_name: appointment.car_wash.name,
      service_name:  appointment.service.title,
      scheduled_at:  appointment.scheduled_at.strftime("%d/%m/%Y às %H:%M"),
      prepayment:    appointment.prepayment_amount,
      total:         appointment.effective_price
    }
  end

  private

  # Reserva os 35% no cartão salvo. Devolve:
  #   [:ok]                     valor reservado, segue o fluxo normal
  #   [:action, client_secret]  banco pediu 3DS; o navegador conclui
  #   [:declined, mensagem]     não deu; pedido cancelado antes de o dono
  #                             saber, e a vaga volta pra lista
  def authorize_prepayment!(appointment, log_tag)
    amount_cents = (appointment.prepayment_amount.to_f * 100).round
    current_user.stripe_customer!
    intent = StripeService.new.create_payment_intent(
      amount_cents:      amount_cents,
      customer_id:       current_user.stripe_customer_id,
      payment_method_id: current_user.stripe_payment_method_id,
      metadata:          { appointment_id: appointment.id, kind: "last_minute_prepayment" }
    )

    case intent.status
    when "requires_capture"
      appointment.update_columns(stripe_payment_intent_id: intent.id, updated_at: Time.current)
      [:ok]
    when "requires_action"
      appointment.update_columns(
        stripe_payment_intent_id: intent.id,
        status:                   "awaiting_payment",
        acceptance_expires_at:    Time.current + Appointment::PAYMENT_AUTH_TTL,
        updated_at:               Time.current
      )
      [:action, intent.client_secret]
    else
      begin
        StripeService.new.cancel(intent.id)
      rescue => e
        Rails.logger.warn("#{log_tag} cancel do intent #{intent.id} falhou: #{e.message}")
      end
      appointment.update_columns(status: "cancelled", updated_at: Time.current)
      Rails.logger.warn("#{log_tag} intent #{intent.id} status=#{intent.status} appointment_id=#{appointment.id}")
      [:declined, "Não conseguimos reservar o valor nesse cartão. Tente outro cartão."]
    end
  rescue Stripe::CardError => e
    appointment.update_columns(status: "cancelled", updated_at: Time.current)
    Rails.logger.warn("#{log_tag} card_error appointment_id=#{appointment.id} code=#{e.code} msg=#{e.message}")
    [:declined, "O cartão recusou a reserva dos #{(Appointment::PREPAYMENT_PCT * 100).round}%. Tente outro cartão."]
  rescue Stripe::StripeError => e
    appointment.update_columns(status: "cancelled", updated_at: Time.current)
    Rails.logger.error("#{log_tag} stripe_error appointment_id=#{appointment.id} #{e.class}: #{e.message}")
    [:declined, "Não conseguimos falar com o processador do cartão agora. Tente de novo em instantes."]
  end

  # Pedido pronto pro dono: avisa e agenda a expiração do aceite. Job fora
  # da transação — se falhar, a lazy expiration ainda cobre.
  def start_acceptance!(appointment, log_tag)
    notify_owner_of_request(appointment, log_tag)
    ExpireDisponivelAcceptanceJob.set(wait: Appointment::ACCEPTANCE_TTL).perform_later(appointment.id)
  rescue => job_err
    Rails.logger.warn("#{log_tag} falha ao enfileirar ExpireDisponivelAcceptanceJob: #{job_err.message}")
  end

  def request_payload(appointment)
    {
      ok:             true,
      appointment_id: appointment.id,
      expires_at:     appointment.acceptance_expires_at.iso8601,
      seconds:        [(appointment.acceptance_expires_at - Time.current).round, 0].max,
      prepayment:     appointment.prepayment_amount.to_f,
      payment_status: appointment.stripe_payment_intent_id.present? ? "authorized" : "pending"
    }
  end

  def release_prepayment(appointment)
    return if appointment.stripe_payment_intent_id.blank?
    StripeService.new.cancel(appointment.stripe_payment_intent_id)
  rescue => e
    Rails.logger.warn("[Disponivel#cancel] falha ao liberar #{appointment.stripe_payment_intent_id}: #{e.message}")
  end

  # A regra de "o que o Last Minute vende" mora em Service.last_minute — o
  # mesmo scope que a validação do agendamento consulta, pra lista e backend
  # nunca mais discordarem.
  def last_minute_services(car_wash)
    car_wash.services.last_minute.order(:price)
  end

  # Avisa o dono que caiu um pedido de Last Minute.
  #
  # Sem isto o pedido só existia pra quem já estivesse com o painel aberto: o
  # app do dono descobre solicitação por polling de 10s, e o aceite morre em
  # ACCEPTANCE_TTL (3 min). Dono com o celular no bolso — que é o normal
  # durante o expediente — nunca ficava sabendo, e o cliente recebia uma recusa
  # por tempo esgotado que ninguém decidiu. É o pedido mais urgente do produto
  # e era o único evento do app que não notificava.
  #
  # Nunca deixa a criação falhar: o pedido já está salvo e válido: push é aviso,
  # não parte da transação.
  def notify_owner_of_request(appointment, log_tag)
    owner = appointment.car_wash&.user
    if owner.blank?
      Rails.logger.warn("#{log_tag} sem dono pra notificar car_wash_id=#{appointment.car_wash_id}")
      return
    end
    return if owner == appointment.user # dono testando no próprio lava-rápido

    horario = appointment.scheduled_at.in_time_zone("America/Sao_Paulo").strftime("%H:%M")
    minutos = (Appointment::ACCEPTANCE_TTL / 60).to_i

    ExpoPushNotifier.new.notify_user(
      owner,
      title: "Novo pedido Last Minute · #{horario}",
      body:  "#{appointment.display_client} quer #{appointment.service&.title}. " \
             "Você tem #{minutos} min pra aceitar.",
      data: {
        type:           "disponivel_request",
        appointment_id: appointment.id,
        car_wash_id:    appointment.car_wash_id,
        expires_at:     appointment.acceptance_expires_at&.iso8601
      }
    )
  rescue => e
    Rails.logger.error("#{log_tag} push pro dono falhou: #{e.class}: #{e.message}")
  end

  # Delega para Appointment.expire_stale_disponivel_acceptances! — método
  # throttled e centralizado (Render free tier pode não rodar o job async).
  def expire_stale_acceptances!
    Appointment.expire_stale_disponivel_acceptances!
  end

  # Esta era a QUARTA cópia da mesma regra: "cabe antes de fechar e tem
  # capacidade pela duração inteira do serviço". A listagem tinha a sua, o
  # available_times tinha a sua, o /disponivel tinha a sua, e o checkout tinha
  # esta. Toda vez que duas divergiam, um caminho oferecia o que o outro
  # negava — foi assim que a Lavagem Completa nunca aparecia no Last Minute e
  # que uma lavagem de 90 min podia ser anunciada numa vaga que o checkout
  # recusava. Agora todas perguntam ao model.
  def slot_available?(car_wash, slot, service = nil)
    car_wash.last_minute_cabe?(slot, service)
  end
end
