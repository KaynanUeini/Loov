# Páginas públicas, sem login: Central de Ajuda, Termos de Uso e Política de
# Privacidade. O app abre estas mesmas páginas dentro dele (?app=1, sem a
# barra do site), então o texto é um só e corrigir um artigo não depende de
# atualizar o app.
class PaginasController < ApplicationController
  skip_before_action :redirect_owner_without_car_wash
  before_action :modo_app

  # Artigos em config/ajuda.yml. Relido a cada pedido em desenvolvimento, pra
  # editar o texto sem reiniciar o servidor.
  def self.ajuda
    return carregar_ajuda if Rails.env.development?
    @ajuda ||= carregar_ajuda
  end

  def self.carregar_ajuda
    YAML.load_file(Rails.root.join("config/ajuda.yml")).deep_symbolize_keys
  end

  # GET /ajuda
  def ajuda
    @ajuda = self.class.ajuda
    @publico = params[:p] == "lava" ? "lava" : "clientes"
  end

  # GET /ajuda/:id
  def artigo
    @ajuda = self.class.ajuda
    @artigo = @ajuda[:artigos].find { |a| a[:id] == params[:id] }
    raise ActionController::RoutingError, "Artigo não encontrado" unless @artigo
    @tema = @ajuda[:temas][@artigo[:publico].to_sym].find { |t| t[:id] == @artigo[:tema] }
    @relacionados = @ajuda[:artigos].select { |a| a[:tema] == @artigo[:tema] && a[:id] != @artigo[:id] }
  end

  # GET /termos
  def termos; end

  # GET /privacidade
  def privacidade; end

  private

  # Dentro do app: sem a barra e o rodapé do site, e os links internos
  # continuam no modo app.
  def modo_app
    @embed = params[:app] == "1"
  end

  helper_method :pagina_path
  def pagina_path(caminho)
    @embed ? "#{caminho}#{caminho.include?('?') ? '&' : '?'}app=1" : caminho
  end
end
