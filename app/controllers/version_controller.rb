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
      booted_at:    BOOTED_AT.iso8601,
      assets:       assets_diagnostic
    }
  end

  private

  # Diagnóstico do CSS montado no build (assets:precompile): se ele existe no
  # disco do servidor que atende o site. Só nomes e contagens — nada sensível.
  def assets_diagnostic
    dir = Rails.root.join("public", "assets")
    manifest = Dir.glob(dir.join(".sprockets-manifest-*.json")).first || Dir.glob(dir.join("manifest-*.json")).first
    {
      root:            Rails.root.to_s,
      dir_exists:      Dir.exist?(dir),
      files:           Dir.exist?(dir) ? Dir.children(dir).size : 0,
      tailwind_files:  Dir.glob(dir.join("tailwind-*.css")).map { |f| File.basename(f) },
      manifest:        manifest && File.basename(manifest),
      compile:         Rails.application.config.assets.compile,
      static_server:   Rails.application.config.public_file_server.enabled
    }
  rescue => e
    { error: e.class.name }
  end
end
