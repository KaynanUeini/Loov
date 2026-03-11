class SessionsController < Devise::SessionsController
  # Sobrescreve o método after_sign_in_path_for para remover a mensagem flash
  def after_sign_in_path_for(resource)
    flash.clear # Limpa todas as mensagens flash, incluindo "Signed in successfully"
    root_path
  end
end
