module Owner
  # Ficha do carro (ver VehicleCheck): o atendente registra o estado do veículo
  # na entrada, por fotos ou pontos no desenho. Só pelo app, por enquanto.
  class VehicleChecksController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :ensure_owner_or_attendant
    before_action :set_car_wash
    before_action :ensure_owner, only: [:settings_update]
    before_action :load_appointment, only: [:uploads, :create, :conferir]

    # GET /owner/vehicle_checks/settings
    def settings
      render json: settings_json
    end

    # PATCH /owner/vehicle_checks/settings
    # Só o dono: muda a regra do lava-rápido inteiro.
    def settings_update
      attrs = {}
      attrs[:vehicle_check_enabled]   = ActiveModel::Type::Boolean.new.cast(params[:enabled])    if params.key?(:enabled)
      attrs[:vehicle_check_skippable] = ActiveModel::Type::Boolean.new.cast(params[:skippable])  if params.key?(:skippable)
      if params.key?(:mode)
        return render json: { error: "Modo inválido." }, status: :unprocessable_entity unless %w[choose photos sketch].include?(params[:mode])
        attrs[:vehicle_check_mode] = params[:mode]
      end
      @car_wash.update_columns(attrs.merge(updated_at: Time.current)) if attrs.any?
      render json: settings_json
    end

    # POST /owner/checkins/:id/vehicle_check/conferir  { label, image }
    # A IA confere uma foto guiada (FichaConferencia). image: JPEG em base64,
    # já reduzido pelo app. Sem resposta da IA, { ok: true, conferida: false }:
    # a foto passa, a conferência nunca trava a ficha.
    def conferir
      label = params[:label].to_s
      img   = params[:image].to_s
      return render json: { error: "Foto inválida." }, status: :unprocessable_entity unless FichaConferencia::ESPERADO.key?(label)
      return render json: { error: "Foto grande demais." }, status: :unprocessable_entity if img.bytesize > 400_000 || img.blank?

      chave = "ficha_conferencia:#{@appointment.id}"
      usadas = Rails.cache.increment(chave, 1, expires_in: 6.hours) || (Rails.cache.write(chave, 1, expires_in: 6.hours) && 1)
      return render json: { ok: true, conferida: false } if usadas.to_i > FichaConferencia::LIMITE_POR_ATENDIMENTO

      r = FichaConferencia.conferir(label, img)
      render json: r ? r.merge(conferida: true) : { ok: true, conferida: false }
    end

    # POST /owner/checkins/:id/vehicle_check/uploads  { labels: ["front", …] }
    # Devolve uma URL de envio por foto; o app manda cada foto direto pro R2.
    def uploads
      return render json: { error: "Fotos indisponíveis. Use o desenho." }, status: :service_unavailable unless FichaStorage.configurado?
      return render json: { error: "Este carro já tem ficha." }, status: :conflict if @appointment.vehicle_check

      labels = Array(params[:labels]).map(&:to_s)
      validos = VehicleCheck::PHOTO_LABELS + ["detail"]
      if labels.empty? || labels.size > VehicleCheck::PHOTO_LABELS.size + VehicleCheck::MAX_DETAILS || (labels - validos).any?
        return render json: { error: "Fotos inválidas." }, status: :unprocessable_entity
      end

      storage = FichaStorage.new
      render json: {
        uploads: labels.map do |label|
          chave = FichaStorage.nova_chave(@appointment, label)
          { label: label, key: chave, url: storage.url_envio(chave) }
        end
      }
    end

    # POST /owner/checkins/:id/vehicle_check
    #   { mode: "photos"|"sketch"|"skipped", plate, vehicle_model, notes,
    #     photos: [{ label, key, kind? }], marks: [{ x, y, kind }] }
    def create
      return render json: { error: "Este carro já tem ficha." }, status: :conflict if @appointment.vehicle_check

      mode = params[:mode].to_s
      # Ficha obrigatória: ninguém pula, nem o dono. Pra liberar um carro sem
      # ficha, o dono desliga a obrigatoriedade na configuração da ficha.
      if mode == "skipped" && !@car_wash.vehicle_check_skippable
        return render json: { error: "A ficha é obrigatória neste lava-rápido." }, status: :forbidden
      end
      if mode.in?(%w[photos sketch]) && !modo_permitido?(mode)
        return render json: { error: "O lava-rápido usa outro modo de ficha." }, status: :unprocessable_entity
      end

      photos = mode == "photos" ? Array(params[:photos]).map { |p| p.permit(:label, :key, :kind, :flag).to_h } : []
      if photos.any?
        return render json: { error: "Fotos indisponíveis. Use o desenho." }, status: :service_unavailable unless FichaStorage.configurado?
        prefixo = FichaStorage.prefixo(@appointment)
        storage = FichaStorage.new
        if photos.any? { |p| !p["key"].to_s.start_with?(prefixo) || !storage.existe?(p["key"]) }
          return render json: { error: "Alguma foto não chegou. Tente de novo." }, status: :unprocessable_entity
        end
      end

      marks = mode == "sketch" ? Array(params[:marks]).map { |m| m.permit(:x, :y, :kind).to_h } : []

      check = @car_wash.vehicle_checks.new(
        appointment:   @appointment,
        recorded_by:   current_user,
        mode:          mode,
        plate:         params[:plate].presence || @appointment.user&.vehicle_plate,
        vehicle_model: params[:vehicle_model].presence || @appointment.user&.vehicle_model,
        notes:         params[:notes],
        photos:        photos,
        marks:         marks
      )

      if check.save
        render json: { ok: true, vehicle_check: serialize(check, detalhe: true) }, status: :created
      else
        render json: { error: check.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "Este carro já tem ficha." }, status: :conflict
    end

    # GET /owner/vehicle_checks/:id
    def show
      check = @car_wash.vehicle_checks.find(params[:id])
      render json: { vehicle_check: serialize(check, detalhe: true) }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Ficha não encontrada." }, status: :not_found
    end

    # GET /owner/vehicle_checks?plate=ABC1D23
    # O histórico da placa neste lava-rápido e as avarias que se repetem —
    # a mesma avaria em várias fichas é a prova de que ela já existia.
    def index
      plate = params[:plate].to_s.upcase.gsub(/[^A-Z0-9]/, "")
      return render json: { error: "Informe a placa." }, status: :unprocessable_entity if plate.blank?

      checks = @car_wash.vehicle_checks.registradas.where(plate: plate)
                        .includes(:recorded_by).order(recorded_at: :desc).to_a
      render json: {
        plate:         plate,
        vehicle_model: checks.find { |c| c.vehicle_model.present? }&.vehicle_model,
        count:         checks.size,
        since:         checks.last&.recorded_at&.iso8601,
        recurring:     recorrentes(checks),
        checks:        checks.map { |c| serialize(c) }
      }
    end

    private

    def set_car_wash
      @car_wash = current_car_wash
      render json: { error: "Lava-rápido não encontrado." }, status: :not_found unless @car_wash
    end

    def ensure_owner_or_attendant
      return if current_user&.owner? || current_user&.attendant?
      render json: { error: "Acesso negado." }, status: :forbidden
    end

    def ensure_owner
      render json: { error: "Só o dono muda a ficha do carro." }, status: :forbidden unless current_user&.owner?
    end

    def load_appointment
      @appointment = @car_wash.appointments.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Agendamento não encontrado." }, status: :not_found
    end

    # Sem o R2 configurado não tem foto, e o desenho vale mesmo pra quem
    # escolheu "sempre fotos" — melhor uma ficha mais fraca do que nenhuma.
    def modo_permitido?(mode)
      @car_wash.vehicle_check_mode.in?(["choose", mode]) ||
        (mode == "sketch" && !FichaStorage.configurado?)
    end

    def settings_json
      {
        enabled:          @car_wash.vehicle_check_enabled,
        mode:             @car_wash.vehicle_check_mode,
        skippable:        @car_wash.vehicle_check_skippable,
        photos_available: FichaStorage.configurado?
      }
    end

    # Mesma avaria (tipo + lugar) em 2 fichas ou mais.
    def recorrentes(checks)
      vistas = Hash.new { |h, k| h[k] = [] }
      checks.each do |c|
        c.marks.map { |m| [m["kind"], m["area"]] }.uniq.each { |chave| vistas[chave] << c.recorded_at }
      end
      vistas.select { |_, datas| datas.size >= 2 }.map do |(kind, area), datas|
        { kind: kind, area: area, count: datas.size, first_at: datas.min.iso8601 }
      end.sort_by { |r| -r[:count] }
    end

    def serialize(check, detalhe: false)
      data = {
        id:            check.id,
        appointment_id: check.appointment_id,
        mode:          check.mode,
        plate:         check.plate,
        vehicle_model: check.vehicle_model,
        recorded_at:   check.recorded_at.iso8601,
        recorded_by:   check.recorded_by&.display_name,
        photos_count:  check.photos.size,
        marks_count:   check.marks.size,
        damage_count:  check.marks.size + check.photos.count { |p| p["kind"].present? }
      }
      return data unless detalhe

      storage = FichaStorage.configurado? ? FichaStorage.new : nil
      data.merge(
        notes:      check.notes,
        expires_at: check.expires_at.iso8601,
        marks:      check.marks,
        photos:     check.photos.map do |p|
          { label: p["label"], kind: p["kind"], flag: p["flag"], url: storage&.url_leitura(p["key"]) }
        end
      )
    end
  end
end
