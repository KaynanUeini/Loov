module Owner
  class CarWashController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    # Atendente pode ler info do car_wash que está vinculado (nome aparece
    # no header do dashboard). Tudo que muda dados (update etc) segue
    # restrito ao dono via ensure_owner.
    before_action :ensure_owner_or_attendant, only: [:show, :update]
    before_action :ensure_owner,               except: [:show, :update]
    before_action :set_car_wash

    def show
      render json: {
        id:                @car_wash.id,
        name:              @car_wash.name,
        cep:               @car_wash.cep,
        logradouro:        @car_wash.logradouro,
        numero:            @car_wash.numero,
        bairro:            @car_wash.bairro,
        cidade:            @car_wash.cidade,
        uf:                @car_wash.uf,
        address:           @car_wash.address,
        capacity_per_slot: @car_wash.capacity_per_slot,
        latitude:          @car_wash.latitude,
        longitude:         @car_wash.longitude,
        operating_hours: @car_wash.operating_hours.order(:day_of_week).map { |oh|
          {
            id:          oh.id,
            day_of_week: oh.day_of_week,
            opens_at:    oh.opens_at&.strftime('%H:%M'),
            closes_at:   oh.closes_at&.strftime('%H:%M'),
            # capacity nil = herda o default do lava-rápido; effective_capacity
            # é o número que a agenda realmente aplica naquele dia.
            capacity:           oh.capacity,
            effective_capacity: oh.effective_capacity,
          }
        },
        services: @car_wash.services.order(:title).map { |s|
          {
            id:          s.id,
            title:       s.title,
            category:    s.category,
            description: s.description,
            price:       s.price.to_f,
            duration:    s.duration,
          }
        }
      }
    end

    def update
      update_params = params.require(:car_wash).permit(
        :name, :cep, :logradouro, :numero, :bairro, :cidade, :uf, :address,
        :capacity_per_slot, :latitude, :longitude,
        operating_hours_attributes: [:id, :day_of_week, :opens_at, :closes_at, :capacity, :_destroy],
        services_attributes:        [:id, :title, :category, :description, :price, :duration, :_destroy]
      )

      attendant_change = current_user.attendant?

      # Captura snapshot ANTES do update pra calcular diff preciso depois.
      before_snapshot = attendant_change ? car_wash_snapshot(@car_wash) : nil

      if @car_wash.update(update_params)
        if attendant_change
          notify_owner_of_attendant_change!(@car_wash, current_user, before_snapshot)
        end
        render json: { ok: true }
      else
        render json: { error: @car_wash.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # GET /owner/car_wash/slot_diagnostics?date=YYYY-MM-DD&duration=30
    #
    # Retorna, para cada slot do dia, a contagem e a lista completa de
    # agendamentos que bloqueiam aquele horário. Espelha exatamente a lógica
    # do `available_times` — mas com transparência total. Útil pro dono
    # entender "por que o cliente não consegue marcar nesse horário?".
    def slot_diagnostics
      Appointment.expire_stale_disponivel_acceptances!

      tz = "America/Sao_Paulo"
      begin
        date = Date.parse(params[:date].to_s)
      rescue ArgumentError, TypeError
        date = Date.current
      end
      duration = params[:duration].to_i
      duration = 30 if duration <= 0

      capacity = @car_wash.capacity_for(date)
      operating_hour = @car_wash.operating_hours.find_by(day_of_week: date.wday)

      unless operating_hour
        render json: {
          date:               date.iso8601,
          capacity_per_slot:  capacity,
          duration:           duration,
          closed:             true,
          slots:              []
        } and return
      end

      opens_at_min  = (operating_hour.opens_at.hour  * 60) + operating_hour.opens_at.min
      closes_at_min = (operating_hour.closes_at.hour * 60) + operating_hour.closes_at.min

      now_sp    = Time.current.in_time_zone(tz)
      is_today  = date == Date.current
      now_min   = is_today ? now_sp.hour * 60 + now_sp.min : 0
      lock_threshold = now_min + 45

      grid_opens = if is_today && now_min >= opens_at_min
        slots_passed = ((now_min - opens_at_min).to_f / duration).ceil
        opens_at_min + (slots_passed * duration)
      else
        opens_at_min
      end

      appts = @car_wash.appointments
        .occupying_capacity
        .where("DATE(scheduled_at) = ?", date)
        .includes(:service, :user)
        .to_a

      slots = []
      current = grid_opens
      while current + duration <= closes_at_min
        time_end = current + duration

        blocking = appts.select do |a|
          s = (a.scheduled_at.in_time_zone(tz).hour * 60) + a.scheduled_at.in_time_zone(tz).min
          d = a.service&.duration.to_i
          next false if d <= 0
          current < (s + d) && time_end > s
        end

        disp_only = is_today && current < lock_threshold
        slots << {
          time:              format("%02d:%02d", current / 60, current % 60),
          count:             blocking.size,
          capacity:          capacity,
          regular_available: blocking.size < capacity && !disp_only,
          disponivel_only:   disp_only,
          blocking:          blocking.map { |a| diagnostics_appt_json(a, tz) }
        }
        current += duration
      end

      render json: {
        date:              date.iso8601,
        now:               is_today ? now_sp.strftime("%H:%M") : nil,
        capacity_per_slot: capacity,
        duration:          duration,
        lock_minutes:      45,
        operating_hours: {
          opens_at:  operating_hour.opens_at.strftime("%H:%M"),
          closes_at: operating_hour.closes_at.strftime("%H:%M")
        },
        slots: slots
      }
    end

    private

    def diagnostics_appt_json(a, tz)
      {
        id:           a.id,
        time:         a.scheduled_at.in_time_zone(tz).strftime("%H:%M"),
        duration:     a.service&.duration,
        service:      a.service&.title,
        client:       a.walk_in? ? (a.walk_in_name.presence || "Avulso") : (a.user&.display_name || "—"),
        status:       a.status,
        walk_in:      a.walk_in,
        acceptance_expires_at: a.acceptance_expires_at&.iso8601
      }
    end

    def set_car_wash
      # Usa linked_car_wash pra resolver tanto pro dono (car_washes.first)
      # quanto pro atendente (attendant_invitations.accepted.first.car_wash).
      @car_wash = current_user&.linked_car_wash
      render json: { error: 'Lava-rápido não encontrado.' }, status: :not_found unless @car_wash
    end

    def ensure_owner
      render json: { error: 'Acesso negado.' }, status: :forbidden unless current_user&.owner?
    end

    def ensure_owner_or_attendant
      unless current_user&.owner? || current_user&.attendant?
        render json: { error: 'Acesso negado.' }, status: :forbidden
      end
    end

    # Push pro dono quando atendente altera o Gerenciar lava-rápido.
    # Não bloqueia a request — falha silenciosamente.
    def notify_owner_of_attendant_change!(car_wash, attendant, before_snapshot)
      owner = car_wash.user
      Rails.logger.info("[CarWash#notify] car_wash=#{car_wash.id} attendant=#{attendant&.id} owner=#{owner&.id}")
      return unless owner && owner != attendant

      diff = car_wash_diff(before_snapshot, car_wash_snapshot(car_wash.reload))
      Rails.logger.info("[CarWash#notify] diff=#{diff.inspect.to_s.truncate(300)}")
      return if diff.empty?  # nada mudou de fato

      items   = diff.map { |c| diff_item_text(c) }
      summary = format_diff(diff)
      title   = "Atendente alterou o lava-rápido"
      body    = "#{attendant.display_name} #{summary}"

      # Persiste pra aparecer em /owner/notifications. Falha de persistência
      # NÃO pode bloquear o push — então cada um tem seu próprio rescue.
      begin
        AttendantActivity.create!(
          car_wash:  car_wash,
          attendant: attendant,
          action:    "manage_car_wash",
          title:     title,
          body:      body,
          items:     items,
        )
        Rails.logger.info("[CarWash#notify] AttendantActivity persistida (items=#{items.size})")
      rescue => e
        Rails.logger.error("[CarWash#notify] persistência falhou: #{e.class}: #{e.message}")
      end

      begin
        ExpoPushNotifier.new.notify_user(
          owner,
          title: title,
          body:  body,
          data:  { type: "attendant_car_wash_change", car_wash_id: car_wash.id }
        )
        Rails.logger.info("[CarWash#notify] push disparado pra owner=#{owner.id}")
      rescue => e
        Rails.logger.error("[CarWash#notify] push falhou: #{e.class}: #{e.message}")
      end
    end

    # Snapshot estruturado do car_wash pra comparar antes/depois do update.
    def car_wash_snapshot(car_wash)
      {
        scalars: {
          "name"              => car_wash.name.to_s,
          "cep"               => car_wash.cep.to_s,
          "logradouro"        => car_wash.logradouro.to_s,
          "numero"            => car_wash.numero.to_s,
          "bairro"            => car_wash.bairro.to_s,
          "cidade"            => car_wash.cidade.to_s,
          "uf"                => car_wash.uf.to_s,
          "address"           => car_wash.address.to_s,
          "capacity_per_slot" => car_wash.capacity_per_slot.to_i,
          "latitude"          => car_wash.latitude.to_f,
          "longitude"         => car_wash.longitude.to_f,
        },
        hours: car_wash.operating_hours.order(:day_of_week).map { |h|
          { id: h.id, day_of_week: h.day_of_week,
            opens_at: h.opens_at&.strftime("%H:%M"),
            closes_at: h.closes_at&.strftime("%H:%M"),
            capacity: h.capacity }
        },
        services: car_wash.services.order(:id).map { |s|
          { id: s.id, title: s.title.to_s, category: s.category.to_s,
            description: s.description.to_s,
            price: s.price.to_f.round(2), duration: s.duration.to_i }
        },
      }
    end

    # Compara dois snapshots e retorna lista de mudanças textuais.
    # Cada item: { field, old, new, label } — para formatação posterior.
    def car_wash_diff(before, after)
      return [] unless before && after
      changes = []

      labels = {
        "name" => "o nome", "cep" => "o CEP", "logradouro" => "o logradouro",
        "numero" => "o número", "bairro" => "o bairro", "cidade" => "a cidade",
        "uf" => "a UF", "address" => "o endereço",
        "capacity_per_slot" => "a capacidade",
        "latitude" => "a latitude", "longitude" => "a longitude",
      }

      before[:scalars].each do |k, v_old|
        v_new = after[:scalars][k]
        next if v_old == v_new
        changes << { kind: :scalar, field: k, label: labels[k] || k,
                     old: format_scalar(k, v_old), new: format_scalar(k, v_new) }
      end

      hours_changes = diff_hours(before[:hours], after[:hours])
      changes.concat(hours_changes)

      services_changes = diff_services(before[:services], after[:services])
      changes.concat(services_changes)

      changes
    end

    DAY_NAMES = %w[domingo segunda terça quarta quinta sexta sábado].freeze

    def diff_hours(before, after)
      changes = []
      before_by_id = before.index_by { |h| h[:id] }
      after_by_id  = after.index_by  { |h| h[:id] }

      added   = after.reject  { |h| before_by_id.key?(h[:id]) }
      removed = before.reject { |h| after_by_id.key?(h[:id]) }
      common  = after.select  { |h| before_by_id.key?(h[:id]) }

      added.each do |h|
        changes << { kind: :hour_added,   day: DAY_NAMES[h[:day_of_week]],
                     opens: h[:opens_at], closes: h[:closes_at] }
      end
      removed.each do |h|
        changes << { kind: :hour_removed, day: DAY_NAMES[h[:day_of_week]] }
      end
      common.each do |h|
        old_h = before_by_id[h[:id]]
        if old_h[:opens_at] != h[:opens_at] || old_h[:closes_at] != h[:closes_at]
          changes << { kind: :hour_changed, day: DAY_NAMES[h[:day_of_week]],
                       old: "#{old_h[:opens_at]}–#{old_h[:closes_at]}",
                       new: "#{h[:opens_at]}–#{h[:closes_at]}" }
        end
        if old_h[:capacity] != h[:capacity]
          changes << { kind: :hour_capacity_changed, day: DAY_NAMES[h[:day_of_week]],
                       old: capacity_text(old_h[:capacity]),
                       new: capacity_text(h[:capacity]) }
        end
      end
      changes
    end

    def diff_services(before, after)
      changes = []
      before_by_id = before.index_by { |s| s[:id] }
      after_by_id  = after.index_by  { |s| s[:id] }

      added   = after.reject  { |s| before_by_id.key?(s[:id]) }
      removed = before.reject { |s| after_by_id.key?(s[:id]) }
      common  = after.select  { |s| before_by_id.key?(s[:id]) }

      added.each   { |s| changes << { kind: :service_added,   title: s[:title] } }
      removed.each { |s| changes << { kind: :service_removed, title: s[:title] } }
      common.each do |s|
        old_s = before_by_id[s[:id]]
        field_changes = []
        field_changes << "preço de #{format_money(old_s[:price])} para #{format_money(s[:price])}"  if old_s[:price]    != s[:price]
        field_changes << "duração de #{old_s[:duration]}min para #{s[:duration]}min"                if old_s[:duration] != s[:duration]
        field_changes << "título de \"#{old_s[:title]}\" para \"#{s[:title]}\""                     if old_s[:title]    != s[:title]
        field_changes << "categoria de \"#{old_s[:category]}\" para \"#{s[:category]}\""            if old_s[:category] != s[:category]
        field_changes << "descrição"                                                                 if old_s[:description] != s[:description]
        next if field_changes.empty?
        changes << { kind: :service_changed, title: s[:title], details: field_changes }
      end
      changes
    end

    def format_scalar(field, value)
      case field
      when "capacity_per_slot" then value.to_s
      when "latitude", "longitude" then format("%.4f", value)
      else value.to_s
      end
    end

    # nil de capacidade não é "vazio", é "herda o default do lava-rápido" —
    # dizer isso evita o dono ler "3 → " e achar que zerou.
    def capacity_text(value)
      value.present? ? value.to_s : "padrão do lava-rápido"
    end

    def format_money(v)
      "R$ #{format('%.2f', v).tr('.', ',')}"
    end

    # Texto de uma única mudança — começa com letra maiúscula, fica
    # bom isolado como item de lista.
    def diff_item_text(c)
      case c[:kind]
      when :scalar
        # capitaliza primeira letra do label ("a capacidade" → "A capacidade")
        label = c[:label].sub(/\A./) { |m| m.upcase }
        "#{label}: #{c[:old]} → #{c[:new]}"
      when :hour_added
        "Horário de #{c[:day]} adicionado (#{c[:opens]}–#{c[:closes]})"
      when :hour_removed
        "Horário de #{c[:day]} removido"
      when :hour_changed
        "Horário de #{c[:day]}: #{c[:old]} → #{c[:new]}"
      when :hour_capacity_changed
        "Capacidade de #{c[:day]}: #{c[:old]} → #{c[:new]}"
      when :service_added
        "Serviço \"#{c[:title]}\" adicionado"
      when :service_removed
        "Serviço \"#{c[:title]}\" removido"
      when :service_changed
        "Serviço \"#{c[:title]}\": #{c[:details].join(', ')}"
      end
    end

    # Resumo single-line para body do push e card colapsado.
    # Ex: "alterou a capacidade de 1 para 3 e o preço de Lavagem Simples"
    def format_diff(changes)
      parts = changes.map do |c|
        case c[:kind]
        when :scalar
          "#{c[:label]} de #{c[:old]} para #{c[:new]}"
        when :hour_added
          "horário de #{c[:day]} (#{c[:opens]}–#{c[:closes]}) adicionado"
        when :hour_removed
          "horário de #{c[:day]} removido"
        when :hour_changed
          "horário de #{c[:day]} de #{c[:old]} para #{c[:new]}"
        when :hour_capacity_changed
          "capacidade de #{c[:day]} de #{c[:old]} para #{c[:new]}"
        when :service_added
          "serviço \"#{c[:title]}\" adicionado"
        when :service_removed
          "serviço \"#{c[:title]}\" removido"
        when :service_changed
          "serviço \"#{c[:title]}\" — #{c[:details].join(', ')}"
        end
      end

      if parts.size == 1
        "alterou #{parts.first}"
      elsif parts.size <= 3
        "alterou #{parts[0..-2].join(', ')} e #{parts.last}"
      else
        first_two = parts.first(2).join(', ')
        rest      = parts.size - 2
        "alterou #{first_two} e mais #{rest} #{rest == 1 ? 'mudança' : 'mudanças'}"
      end
    end
  end
end
