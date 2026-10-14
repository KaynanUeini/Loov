# Trava de login por tentativas ERRADAS.
#
# Antes o Rack::Attack contava todo POST de login, inclusive os que davam
# certo: 3 por e-mail por hora bastavam pra travar quem só entrou e saiu
# algumas vezes. E 5 por IP travava gente diferente atrás do mesmo IP de
# operadora (CGNAT, comum no 4G). Aqui só senha errada conta, e um login
# certo zera a conta daquele e-mail.
module LoginGuard
  LIMITE_EMAIL = 5          # erros seguidos no mesmo e-mail
  LIMITE_IP    = 20         # erros vindos do mesmo IP (vários e-mails)
  JANELA       = 15.minutes

  MENSAGEM = "Muitas tentativas de login com senha errada. Aguarde 15 minutos " \
             "ou use \"Esqueci minha senha\".".freeze

  module_function

  def bloqueado?(ip, email)
    contagem(chave(:email, email)) >= LIMITE_EMAIL || contagem(chave(:ip, ip)) >= LIMITE_IP
  end

  def falhou!(ip, email)
    somar(chave(:email, email)) if email.present?
    somar(chave(:ip, ip)) if ip.present?
  end

  def sucesso!(email)
    Rails.cache.delete(chave(:email, email)) if email.present?
  end

  def chave(tipo, valor)
    "login_guard:#{tipo}:#{valor.to_s.strip.downcase}"
  end

  def contagem(k)
    Rails.cache.read(k).to_i
  end

  # read + write em vez de increment: nem todo cache store cria a chave no
  # increment. Corrida entre requests só faz a conta atrasar um erro.
  def somar(k)
    Rails.cache.write(k, contagem(k) + 1, expires_in: JANELA)
  end
end
