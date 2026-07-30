class VersionController < ApplicationController
  skip_before_action :verify_authenticity_token

  # Momento em que este processo subiu. Serve pra distinguir "o deploy rodou"
  # de "o serviço só reiniciou".
  BOOTED_AT = Time.current

  # O Render expõe o SHA do commit no ambiente do serviço. Fora dele (dev),
  # cai no git. Resolvido uma vez no carregamento da classe — não vale
  # shellar a cada request, e em produção não shella nunca.
  REVISION =
    ENV["RENDER_GIT_COMMIT"].presence ||
    (Rails.env.development? ? `git rev-parse HEAD 2>/dev/null`.strip.presence : nil)

  # GET /version
  #
  # Existe pra tornar "o deploy subiu?" verificável em uma requisição. Antes
  # isso era inferido por sinal indireto — procurar uma chave nova em alguma
  # resposta pública — e quando a mudança ficava atrás de login ou dependia
  # dos dados do momento, não havia como confirmar.
  def show
    render json: {
      commit:       REVISION,
      commit_short: REVISION&.slice(0, 7),
      branch:       ENV["RENDER_GIT_BRANCH"].presence,
      environment:  Rails.env,
      booted_at:    BOOTED_AT.iso8601
    }
  end
end
