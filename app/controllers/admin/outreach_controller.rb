module Admin
  class OutreachController < BaseController
    skip_before_action :verify_authenticity_token, only: [:generate_message, :update_status, :destroy, :search_google, :import_google]

    def index
      @stats          = compute_stats
      @leads_by_status = Outreach::Lead::STATUSES.index_with do |s|
        Outreach::Lead.by_status(s).order(updated_at: :desc).to_a
      end
      @upcoming_meetings = Outreach::Meeting.upcoming.includes(:lead).limit(10)
    end

    def show
      @lead     = Outreach::Lead.find(params[:id])
      @messages = @lead.messages.order(created_at: :desc)
      @meetings = @lead.meetings.order(scheduled_at: :desc)
    end

    # POST /admin/outreach/import
    def import
      raw     = params[:raw_text].to_s
      created = []
      skipped = 0

      parse_blocks(raw).each do |attrs|
        next if attrs[:name].blank?
        existing = attrs[:phone].present? ? Outreach::Lead.find_by(phone: attrs[:phone]) : nil
        if existing
          skipped += 1
          next
        end
        lead = Outreach::Lead.new(attrs.merge(status: 'novo'))
        created << lead if lead.save
      end

      flash[:notice] = "#{created.size} lead(s) importado(s)#{skipped.positive? ? " (#{skipped} duplicado(s) pulado(s))" : ''}."
      redirect_to admin_outreach_index_path
    end

    # POST /admin/outreach/:id/generate_message
    def generate_message
      @lead    = Outreach::Lead.find(params[:id])
      channel  = params[:channel].presence || 'whatsapp'
      message  = OutreachAgentService.new.generate(@lead, channel: channel)
      render json: { message: message, whatsapp_link: @lead.whatsapp_link(message) }
    end

    # POST /admin/outreach/:id/mark_sent
    # GET cai aqui também e redireciona pro detalhe (evita 404 se alguém
    # acessa a URL diretamente sem submeter o form).
    def mark_sent
      @lead = Outreach::Lead.find(params[:id])
      if request.get?
        redirect_to admin_outreach_lead_path(@lead) and return
      end

      body = params[:body].to_s.strip
      body = '[Mensagem enviada manualmente — corpo não capturado]' if body.blank?

      @lead.messages.create!(
        body:    body,
        channel: params[:channel].presence || 'whatsapp',
        sent_at: Time.current
      )
      @lead.update!(status: 'enviado', last_contact_at: Time.current)
      redirect_to admin_outreach_lead_path(@lead), notice: 'Mensagem registrada como enviada.'
    end

    # PATCH /admin/outreach/:id/update_status
    def update_status
      @lead = Outreach::Lead.find(params[:id])
      if Outreach::Lead::STATUSES.include?(params[:status])
        @lead.update!(status: params[:status])
        render json: { ok: true, status: @lead.status }
      else
        render json: { ok: false, error: 'Status inválido.' }, status: :unprocessable_entity
      end
    end

    # POST /admin/outreach/:id/schedule_meeting
    def schedule_meeting
      @lead = Outreach::Lead.find(params[:id])
      @lead.meetings.create!(
        scheduled_at: params[:scheduled_at],
        kind:         params[:kind].presence || 'video',
        notes:        params[:notes]
      )
      @lead.update!(status: 'agendado', last_contact_at: Time.current)
      redirect_to admin_outreach_lead_path(@lead), notice: 'Reunião agendada.'
    end

    # PATCH /admin/outreach/:id (notas + dados básicos editáveis)
    def update
      @lead = Outreach::Lead.find(params[:id])
      @lead.update!(lead_params)
      redirect_to admin_outreach_lead_path(@lead), notice: 'Lead atualizado.'
    end

    # POST /admin/outreach/search_google
    # Busca lava-rápidos no Google Places via GooglePlacesService.
    # Devolve JSON com array de candidatos pra o frontend mostrar com
    # checkbox e o usuário escolher quais importar.
    def search_google
      query = params[:query].to_s.strip
      return render(json: { error: "Digite uma busca." }, status: :unprocessable_entity) if query.blank?

      if ENV['GOOGLE_PLACES_API_KEY'].blank?
        return render json: {
          error:        "Google Places API key não configurada.",
          setup_needed: true,
          setup:        "Configure GOOGLE_PLACES_API_KEY no Render (Settings → Environment). Crie projeto em console.cloud.google.com, ative a Places API, gere uma key e cole na env. Free tier do Google cobre milhares de buscas por mês."
        }, status: :service_unavailable
      end

      response = GooglePlacesService.new.search_with_details(query)
      if response[:error] && response[:error] != 'no_results'
        return render json: { error: response[:error] }, status: :unprocessable_entity
      end

      results = (response[:results] || []).map do |r|
        existing = r[:phone].present? ? Outreach::Lead.find_by(phone: r[:phone]) : nil
        r.merge(already_imported: existing.present?)
      end

      render json: { results: results, count: results.size }
    rescue => e
      Rails.logger.error("[Admin::Outreach#search_google] #{e.class}: #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # POST /admin/outreach/import_google — recebe array de leads
    # selecionados pelo usuário a partir do resultado do search_google.
    def import_google
      list = params[:leads] || []
      created = 0
      skipped = 0

      list.each do |raw|
        attrs = raw.respond_to?(:permit) ? raw.permit(:name, :phone, :address, :bairro, :cidade, :rating, :reviews_sample, :website).to_h : raw.to_h.symbolize_keys
        next if attrs[:name].blank?
        if attrs[:phone].present? && Outreach::Lead.exists?(phone: attrs[:phone])
          skipped += 1
          next
        end
        Outreach::Lead.create!(
          name:           attrs[:name],
          phone:          attrs[:phone],
          address:        attrs[:address],
          bairro:         attrs[:bairro],
          cidade:         attrs[:cidade].presence || 'Osasco',
          rating:         attrs[:rating],
          reviews_sample: attrs[:reviews_sample],
          status:         'novo'
        )
        created += 1
      end

      render json: { ok: true, created: created, skipped: skipped }
    rescue => e
      Rails.logger.error("[Admin::Outreach#import_google] #{e.class}: #{e.message}")
      render json: { error: e.message }, status: :internal_server_error
    end

    # DELETE /admin/outreach/:id
    def destroy
      Outreach::Lead.find(params[:id]).destroy
      respond_to do |format|
        format.html { redirect_to admin_outreach_index_path, notice: 'Lead removido.' }
        format.json { render json: { ok: true } }
      end
    end

    private

    def lead_params
      params.require(:lead).permit(:name, :phone, :email, :address, :bairro, :cidade, :rating, :reviews_sample, :notes)
    end

    def compute_stats
      total      = Outreach::Lead.count
      sent       = Outreach::Lead.where.not(status: 'novo').count
      replied    = Outreach::Lead.where(status: %w[respondeu agendado convertido]).count
      scheduled  = Outreach::Lead.where(status: %w[agendado convertido]).count
      converted  = Outreach::Lead.where(status: 'convertido').count

      pct = ->(num, denom) { denom.positive? ? (num.to_f / denom * 100).round : 0 }

      {
        total:        total,
        sent:         sent,
        replied:      replied,
        scheduled:    scheduled,
        converted:    converted,
        sent_pct:     pct.call(sent, total),
        reply_pct:    pct.call(replied, sent),
        meeting_pct:  pct.call(scheduled, replied),
        convert_pct:  pct.call(converted, scheduled),
      }
    end

    # Parser tolerante pra texto bruto colado do Google Maps. Espera blocos
    # separados por linhas em branco; cada bloco tenta achar nome (1ª linha
    # não-vazia), telefone (regex BR), endereço, bairro e rating.
    def parse_blocks(raw)
      raw.split(/\n\s*\n/).map { |b| parse_one_block(b) }
    end

    def parse_one_block(block)
      lines = block.lines.map(&:strip).reject(&:blank?)
      return {} if lines.empty?

      name = lines.first
      # Remove rating se vier coladinho no nome (ex "Lava Car X 4.2")
      name = name.sub(/\s+\d[,.]\d\s*\(\d+\)?\s*$/, '').strip

      phone_match = block.scan(/\(?\d{2}\)?\s*9?\d{4}-?\s?\d{4}/).first
      phone       = phone_match&.gsub(/\D/, '')

      rating_match = block.match(/(\d[,.]\d)\s*\(?\d*\)?/)
      rating       = rating_match ? rating_match[1].sub(',', '.').to_f : nil

      address_line = lines.find { |l| l.match?(/\b(R\.|Rua|Av\.|Avenida|Alameda|Estrada|Rodovia|Praça|Travessa)\b/i) }
      bairro       = block.match(/-\s*([^,\n]+?)\s*,\s*Osasco/i)&.[](1)&.strip
      cidade       = block.match?(/Osasco/i) ? 'Osasco' : (block.match?(/São Paulo/i) ? 'São Paulo' : 'Osasco')

      {
        name:    name,
        phone:   phone,
        address: address_line,
        bairro:  bairro,
        cidade:  cidade,
        rating:  rating,
      }
    end
  end
end
