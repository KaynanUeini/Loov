module Owner
  # Clientes de Last Minute que disseram não ter sido atendidos (NaoAtendido),
  # e a situação da loja (alerta no 2º caso, suspensão no 3º). O dono e o
  # funcionário respondem: quem estava no balcão sabe o que houve.
  class NaoAtendidosController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :authenticate_user!
    before_action :exigir_loja

    # GET /owner/nao_atendidos
    def index
      render json: payload
    end

    # POST /owner/nao_atendidos/:id/confirmar
    def confirmar
      caso = achar
      return render(json: { error: "Este caso já foi respondido." }, status: :unprocessable_entity) unless caso.confirmar!(por: current_user)
      render json: payload
    end

    # POST /owner/nao_atendidos/:id/contestar  { resposta }
    def contestar
      caso = achar
      resposta = params[:resposta].to_s.strip
      return render(json: { error: "Conte o que aconteceu, pra equipe da Loov analisar." }, status: :unprocessable_entity) if resposta.length < 5
      return render(json: { error: "Este caso já foi respondido." }, status: :unprocessable_entity) unless caso.contestar!(por: current_user, resposta: resposta)
      render json: payload
    end

    private

    def exigir_loja
      return if (current_user.owner? || current_user.attendant?) && current_car_wash
      render json: { error: "Acesso negado." }, status: :forbidden
    end

    def achar
      current_car_wash.nao_atendidos.find(params[:id])
    end

    def payload
      situacao = NaoAtendido.situacao(current_car_wash)
      pendentes = current_car_wash.nao_atendidos.aguardando.includes(appointment: :service).order(:prazo_em)
      situacao.merge(pendentes: pendentes.map(&:resumo_dono))
    end
  end
end
