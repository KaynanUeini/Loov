class CarWashesController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_car_wash, only: %i[show manage update available_times]
  before_action :ensure_owner_or_attendant, only: [:manage]
  before_action :ensure_owner, only: [:update]
  # Mantém available_times e a listagem consistentes — se um pending_acceptance
  # venceu, não deve mais bloquear aquele slot nas próximas queries.
  before_action -> { Appointment.expire_stale_disponivel_acceptances! }, only: [:index, :show, :available_times]

  def index
    @car_washes = CarWash.all

    if params[:search].present?
      @car_washes = @car_washes.where("name ILIKE ? OR address ILIKE ?", "%#{params[:search]}%", "%#{params[:search]}%")
    end

    if params[:group].present? && Service::GROUPS[params[:group]]
      group_categories = Service::GROUPS[params[:group]]
      if params[:service_title].present?
        @car_washes = @car_washes.joins(:services).where(services: { title: params[:service_title] }).distinct
      elsif params[:category].present? && group_categories.include?(params[:category])
        @car_washes = @car_washes.joins(:services).where(services: { category: params[:category] }).distinct
      else
        @car_washes = @car_washes.joins(:services).where(services: { category: group_categories }).distinct
      end
    end

    if params[:latitude].present? && params[:longitude].present?
      begin
        latitude  = params[:latitude].to_f
        longitude = params[:longitude].to_f
        # Eager-load antes de converter em Array — caso contrário o bloco JSON
        # fica N+1 (ou, se chamar .includes no Array, quebra com NoMethodError).
        preloaded = @car_washes.includes(:services, :operating_hours)
        with_coords    = preloaded.select(&:has_valid_coordinates?).sort_by { |cw| cw.distance_to([latitude, longitude], :km) }
        without_coords = preloaded.reject(&:has_valid_coordinates?)
        @car_washes    = with_coords + without_coords
      rescue => e
        Rails.logger.error("Erro ao calcular distância: #{e.message}")
      end
    end

    @groups                 = Service::GROUPS
    @selected_group         = params[:group]
    @selected_category      = params[:category]
    @selected_service_title = params[:service_title]

    if @selected_group == "Lavagem"
      @subcategories = Service.where(category: "Lavagem").distinct.pluck(:title).compact.sort
    elsif @selected_group.present? && Service::GROUPS[@selected_group]
      @subcategories = Service::GROUPS[@selected_group]
    else
      @subcategories = []
    end

    respond_to do |format|
      # /car_washes (listagem HTML) foi descontinuada — a home logada já
      # mostra os lava-rápidos com filtros. Redireciona pra raiz mantendo
      # query params (latitude/longitude) pra contexto.
      format.html { redirect_to root_path(request.query_parameters) }
      format.json do
        lat_param = params[:latitude].presence&.to_f
        lng_param = params[:longitude].presence&.to_f

        now_br       = Time.current.in_time_zone("America/Sao_Paulo")
        today_dow    = now_br.wday
        now_seconds  = now_br.seconds_since_midnight.to_i

        # @car_washes pode ser Relation (sem coords) ou Array (ordenado por
        # distância acima). Só chama .includes se ainda é Relation.
        collection = @car_washes.respond_to?(:includes) ?
          @car_washes.includes(:services, :operating_hours) :
          @car_washes

        # Agrega rating em batch (evita N+1 ao somar/avg por lava-rápido).
        cw_ids = collection.map(&:id)
        rating_map = Review.where(car_wash_id: cw_ids)
                           .group(:car_wash_id)
                           .pluck(:car_wash_id, Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))
                           .each_with_object({}) { |(id, avg, count), h|
                             h[id] = { avg: avg.to_f.round(1), count: count.to_i }
                           }

        # Pré-carrega ids favoritados em UMA query (batch) — evita N+1
        # e permite o mobile mostrar heart preenchido no card sem
        # precisar chamar /client/favorites separadamente.
        favorited_ids = if user_signed_in? && current_user.client?
          current_user.favorite_car_washes.where(car_wash_id: cw_ids).pluck(:car_wash_id).to_set
        else
          Set.new
        end

        render json: collection.map { |cw|
          # Hora de hoje do lava-rápido (pode não existir se fechado no dia)
          today_oh = cw.operating_hours.find { |oh| oh.day_of_week.to_i == today_dow }

          open_now = false
          if today_oh && today_oh.opens_at && today_oh.closes_at
            opens_sec  = today_oh.opens_at.seconds_since_midnight.to_i  rescue 0
            closes_sec = today_oh.closes_at.seconds_since_midnight.to_i rescue 86400
            open_now   = now_seconds >= opens_sec && now_seconds <= closes_sec
          end
          # CarWashClosure ativo bate hoje? Marca como fechado.
          open_now = false if open_now && cw.closed_on?(Date.current)

          rating_info = rating_map[cw.id] || { avg: 0.0, count: 0 }

          data = {
            id:            cw.id,
            name:          cw.name,
            address:       cw.address,
            favorited:     favorited_ids.include?(cw.id),
            logradouro:    cw.logradouro,
            numero:        cw.numero,
            bairro:        cw.bairro,
            cidade:        cw.cidade,
            uf:            cw.uf,
            city:          cw.cidade,
            state:         cw.uf,
            lat:           cw.latitude,
            lng:           cw.longitude,
            latitude:      cw.latitude,
            longitude:     cw.longitude,
            open_now:      open_now,
            rating_avg:    rating_info[:avg],
            reviews_count: rating_info[:count],
            services: cw.services.sort_by { |s| s.title.to_s }.map { |s|
              {
                id:          s.id,
                title:       s.title,
                price:       s.price.to_f,
                duration:    s.duration,
                category:    s.category,
                description: s.description
              }
            },
            operating_hours: cw.operating_hours.sort_by { |oh| oh.day_of_week.to_i }.map { |oh|
              {
                day_of_week: oh.day_of_week.to_i,
                opens_at:    oh.opens_at&.strftime('%H:%M'),
                closes_at:   oh.closes_at&.strftime('%H:%M')
              }
            }
          }
          if lat_param && lng_param && cw.has_valid_coordinates?
            data[:distance_km] = cw.distance_to([lat_param, lng_param], :km).round(2)
          end
          data
        }
      end
    end
  end

  def show
    @services    = @car_wash.services
    @appointment = Appointment.new(car_wash_id: @car_wash.id)

    respond_to do |format|
      format.html do
        @closures = @car_wash.car_wash_closures.where("end_date >= ?", Date.current)
      end
      format.json do
        cw   = @car_wash
        dist = if params[:latitude].present? && params[:longitude].present? && cw.has_valid_coordinates?
          cw.distance_to([params[:latitude].to_f, params[:longitude].to_f], :km).round(1)
        end

        favorited = user_signed_in? && current_user.client? &&
          current_user.favorite_car_washes.exists?(car_wash_id: cw.id)

        # Rating real (média + contagem de Reviews)
        rating_stats = Review.where(car_wash_id: cw.id)
                             .pick(Arel.sql("COALESCE(AVG(rating), 0)"), Arel.sql("COUNT(*)"))
        rating_avg    = rating_stats[0].to_f.round(1)
        reviews_count = rating_stats[1].to_i

        # Aberto agora? (operating_hours + nenhum CarWashClosure ativo)
        now_sp     = Time.current.in_time_zone("America/Sao_Paulo")
        today_oh   = cw.operating_hours.find_by(day_of_week: now_sp.wday)
        open_now   = open_at_time?(today_oh, now_sp) && !cw.closed_on?(now_sp.to_date)

        # Próxima vaga (em minutos a partir de agora) — null se fechado o dia inteiro.
        next_slot_minutes = next_available_slot_minutes(cw, now_sp)

        render json: {
          id:                cw.id,
          name:              cw.name,
          address:           cw.address,
          favorited:         favorited,
          cep:               cw.cep,
          logradouro:        cw.logradouro,
          bairro:            cw.bairro,
          cidade:            cw.cidade,
          uf:                cw.uf,
          city:              cw.cidade,
          state:             cw.uf,
          lat:               cw.latitude,
          lng:               cw.longitude,
          latitude:          cw.latitude,
          longitude:         cw.longitude,
          distance_km:       dist,
          capacity_per_slot: cw.capacity_per_slot,
          rating_avg:         rating_avg,
          reviews_count:      reviews_count,
          open_now:           open_now,
          next_slot_minutes:  next_slot_minutes,
          # Elegível pro Last Minute: aberto agora + tem serviço com
          # duração curta (≤ 60min). Frontend usa pra liberar slots
          # disponivel_only como link pro fluxo Disponível.
          disponivel_eligible: open_now && cw.services.any? { |s|
            d = s.duration.to_i
            d > 0 && d <= 60
          },
          reviews:           Review.where(car_wash_id: cw.id)
                                   .order(created_at: :desc)
                                   .limit(20)
                                   .includes(:user)
                                   .map { |r|
                                     {
                                       id:         r.id,
                                       rating:     r.rating,
                                       comment:    r.comment.to_s,
                                       tags:       r.tags_list,
                                       author:     r.user&.display_name || "Cliente",
                                       created_at: r.created_at.iso8601,
                                     }
                                   },
          operating_hours: (cw.operating_hours || []).order(:day_of_week).map { |oh|
            {
              id:          oh.id,
              day_of_week: oh.day_of_week,
              opens_at:    oh.opens_at&.strftime('%H:%M'),
              closes_at:   oh.closes_at&.strftime('%H:%M')
            }
          },
          services: (cw.services || []).order(:title).map { |s|
            {
              id:          s.id,
              title:       s.title,
              category:    s.category,
              description: s.description,
              price:       s.price.to_f,
              duration:    s.duration
            }
          }
        }
      end
    end
  end

  def new
    @car_wash = CarWash.new
  end

  def edit
  end

  def create
    @car_wash      = CarWash.new(car_wash_params)
    @car_wash.user = current_user
    if @car_wash.save
      redirect_to @car_wash, notice: "Lava-rápido criado com sucesso!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if current_user.attendant?
      raw = params.require(:car_wash).permit(
        :name, :address, :cep, :logradouro, :bairro, :cidade, :uf,
        :latitude, :longitude, :capacity_per_slot,
        operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
        services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
        ).to_h

      PendingChange.create!(
        car_wash:    @car_wash,
        attendant:   current_user,
        change_type: "manage_car_wash",
        status:      "pending",
        description: "Alterações no gerenciamento do lava-rápido",
        payload:     { car_wash_params: raw }.to_json
        )

      redirect_to manage_car_wash_path(@car_wash),
      notice: "✅ Alterações enviadas para aprovação do proprietário."
      return
    end

    update_params = params.require(:car_wash).permit(
      :name, :address, :cep, :logradouro, :bairro, :cidade, :uf,
      :latitude, :longitude, :capacity_per_slot,
      operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
      services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
      )

    if update_params[:operating_hours_attributes].present?
      seen_days = []
      update_params[:operating_hours_attributes].each do |_, attrs|
        next if attrs[:_destroy] == "1"
        day = attrs[:day_of_week].to_i
        if seen_days.include?(day)
          @car_wash.errors.add(:base, "Dia da semana já adicionado: #{OperatingHour.new(day_of_week: day).day_of_week_name}")
          render :manage, status: :unprocessable_entity and return
        end
        seen_days << day
      end
    end

    if @car_wash.update(update_params)
      redirect_to manage_car_wash_path(@car_wash), notice: "Lava-rápido atualizado com sucesso!"
    else
      @car_wash.operating_hours.build if @car_wash.operating_hours.empty?
      @car_wash.services.build if @car_wash.services.empty?
      render :manage, status: :unprocessable_entity
    end
  end

  def destroy
    @car_wash.destroy
    redirect_to root_path, notice: "Lava-rápido excluído com sucesso!"
  end

  def manage
    @is_attendant    = current_user.attendant?
    @pending_changes = @car_wash.pending_changes.pending if current_user.owner?
    @car_wash.operating_hours.build if @car_wash.operating_hours.empty?
    @car_wash.services.build if @car_wash.services.empty?
  end

  def available_times
    lock_minutes = 45
    Timeout.timeout(5) do
      begin
        date = Date.parse(params[:date])
      rescue ArgumentError, TypeError
        render json: [], status: :bad_request and return
      end
      begin
        Service.find(params[:service_id])
      rescue ActiveRecord::RecordNotFound
        render json: [], status: :not_found and return
      end

      duration          = params[:duration].to_i
      capacity_per_slot = @car_wash.capacity_for(date)

      if duration <= 0
        render json: [] and return
      end

      operating_hour = @car_wash.operating_hours.find_by(day_of_week: date.wday)
      unless operating_hour
        render json: [] and return
      end

      opens_at_min  = (operating_hour.opens_at.hour  * 60) + operating_hour.opens_at.min
      closes_at_min = (operating_hour.closes_at.hour * 60) + operating_hour.closes_at.min

      now            = Time.current.in_time_zone("America/Sao_Paulo")
      now_minutes    = now.hour * 60 + now.min
      is_today       = date == Date.current
      lock_threshold = now_minutes + lock_minutes

      if is_today && now_minutes >= opens_at_min
        slots_passed = ((now_minutes - opens_at_min).to_f / duration).ceil
        opens_at_min = opens_at_min + (slots_passed * duration)
      end

      appointments = @car_wash.appointments
      .occupying_capacity
      .joins(:service)
      .where("DATE(scheduled_at) = ?", date)
      .select("appointments.scheduled_at, services.duration AS svc_duration")
      .to_a

      occupied = appointments.map do |appt|
        s = (appt.scheduled_at.in_time_zone("America/Sao_Paulo").hour * 60) +
        appt.scheduled_at.in_time_zone("America/Sao_Paulo").min
        d = appt.svc_duration.to_i
        next nil if d <= 0
        { begin: s, end: s + d }
        end.compact

        available = []
        current   = opens_at_min

        while current + duration <= closes_at_min
          time_end    = current + duration
          overlapping = occupied.count { |i| current < i[:end] && time_end > i[:begin] }

          if overlapping < capacity_per_slot
            disponivel_only = is_today && current < lock_threshold
            available << {
              time:            format("%02d:%02d", current / 60, current % 60),
              disponivel_only: disponivel_only
            }
          end

          current += duration
        end

        render json: available
      end
    rescue Timeout::Error
      render json: [], status: :request_timeout
    rescue => e
      Rails.logger.error("[available_times] Erro: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      render json: [], status: :internal_server_error
    end

    private

    def set_car_wash
      @car_wash = CarWash.find(params[:id] || params[:car_wash_id])
    end

    # ── Helpers de disponibilidade pro endpoint show ──────────────────────
    def open_at_time?(operating_hour, time)
      return false unless operating_hour&.opens_at && operating_hour&.closes_at
      mins = time.hour * 60 + time.min
      opens  = operating_hour.opens_at.hour  * 60 + operating_hour.opens_at.min
      closes = operating_hour.closes_at.hour * 60 + operating_hour.closes_at.min
      mins >= opens && mins <= closes
    end

    # Retorna minutos até a próxima vaga disponível.
    # 0   = vaga agora; nil = sem vaga em até 7 dias ou nunca abre.
    # Usa duração padrão de 30 min e checa capacity vs appointments
    # existentes — espelha a lógica de available_times.
    def next_available_slot_minutes(car_wash, now)
      duration = 30

      # Itera dia a dia (hoje, amanhã...) até 7 dias.
      (0..7).each do |days_ahead|
        date = (now + days_ahead.days).to_date
        oh   = car_wash.operating_hours.find_by(day_of_week: date.wday)
        next unless oh&.opens_at && oh&.closes_at

        # Dentro do loop: a varredura cruza dias e cada um tem a sua capacidade.
        capacity = car_wash.capacity_for(date)

        opens_min  = oh.opens_at.hour  * 60 + oh.opens_at.min
        closes_min = oh.closes_at.hour * 60 + oh.closes_at.min

        # No dia 0 começa do slot a partir de agora; nos seguintes,
        # da abertura.
        if days_ahead == 0
          now_min      = now.hour * 60 + now.min
          if now_min >= closes_min
            next  # já fechou hoje, próximo dia
          end
          slots_passed = ((now_min - opens_min).to_f / duration).ceil
          start_min    = [opens_min, opens_min + slots_passed * duration].max
        else
          start_min = opens_min
        end

        next if start_min + duration > closes_min

        appts = car_wash.appointments
                  .occupying_capacity
                  .joins(:service)
                  .where("DATE(scheduled_at) = ?", date)
                  .pluck("appointments.scheduled_at, services.duration")

        occupied = appts.map { |sa, d|
          s_local = sa.in_time_zone("America/Sao_Paulo")
          s = s_local.hour * 60 + s_local.min
          d.to_i > 0 ? { begin: s, end: s + d.to_i } : nil
        }.compact

        current = start_min
        while current + duration <= closes_min
          time_end    = current + duration
          overlapping = occupied.count { |i| current < i[:end] && time_end > i[:begin] }
          if overlapping < capacity
            slot_at = ActiveSupport::TimeZone["America/Sao_Paulo"].local(
              date.year, date.month, date.day, current / 60, current % 60, 0
            )
            return ((slot_at - now) / 60).to_i.clamp(0, 7 * 24 * 60)
          end
          current += duration
        end
      end

      nil
    rescue => e
      Rails.logger.warn("[next_available_slot] erro: #{e.message}")
      nil
    end

    def ensure_owner
      unless current_user.owner? && @car_wash.user == current_user
        redirect_to root_path, alert: "Acesso não autorizado." unless current_user.attendant?
      end
    end

    def ensure_owner_or_attendant
      if current_user.owner?
        redirect_to root_path, alert: "Acesso não autorizado." unless @car_wash.user == current_user
      elsif current_user.attendant?
        redirect_to root_path, alert: "Acesso não autorizado." unless current_car_wash&.id == @car_wash.id
      else
        redirect_to root_path, alert: "Acesso não autorizado."
      end
    end

    def car_wash_params
      params.require(:car_wash).permit(
        :name, :address, :cep, :logradouro, :bairro, :cidade, :uf,
        :latitude, :longitude, :capacity_per_slot,
        operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :_destroy],
        services_attributes: [:id, :title, :description, :price, :duration, :category, :_destroy]
        )
    end
  end
