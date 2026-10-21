module ApplicationHelper
  # Voltar das páginas do dono: quem veio pela Conta (?de=conta) volta pra
  # Conta; quem veio pelo menu de cima ou pelo painel volta pro início.
  def voltar_do_dono
    params[:de] == "conta" ? edit_user_registration_path : root_path
  end
end
