# Conta senha errada no login do SITE (HTML) pro LoginGuard. No site a
# falha acontece dentro do Warden (Devise FailureApp), não no controller;
# o login do app (JSON) é contado no SessionsController#create. Na falha o
# Warden já trocou o PATH_INFO por /unauthenticated — o caminho original
# vem em opts[:attempted_path].
Warden::Manager.before_failure do |env, opts|
  next unless opts[:attempted_path] == "/users/sign_in"

  req = ActionDispatch::Request.new(env)
  next unless req.post? && !req.format.json?

  email = req.params.dig("user", "email").to_s.strip.downcase
  LoginGuard.falhou!(req.remote_ip, email)
end
