# Conta de login de qualquer papel (cliente, dono, funcionário), pelo app.
# O site faz o mesmo pelo Devise (registrations#update e #destroy), que passa
# pela mesma regra de exclusão em User#excluir_conta!.
class AccountsController < ApplicationController
  before_action :authenticate_user!
  # Só o app chega aqui (login no cabeçalho, sem token de formulário); um site
  # de terceiros não consegue mandar esse cabeçalho, então o CSRF segue valendo
  # pra qualquer outra origem.
  skip_before_action :verify_authenticity_token, if: -> { request.authorization.to_s.start_with?("Bearer ") }
  skip_before_action :redirect_owner_without_car_wash, raise: false

  # GET /account — o que a tela de Privacidade e segurança mostra.
  def show
    render json: { email: current_user.email, role: current_user.role }
  end

  # PATCH /account/email  { email, current_password }
  def update_email
    novo = params[:email].to_s.strip.downcase
    return erro("Informe o novo e-mail.") if novo.blank?
    return erro("Esse já é o seu e-mail.") if novo == current_user.email

    if current_user.update_with_password(email: novo, current_password: params[:current_password].to_s)
      render json: { ok: true, email: current_user.email }
    else
      render json: { ok: false, error: mensagem(current_user) }, status: :unprocessable_entity
    end
  end

  # DELETE /account  { current_password }
  def destroy
    unless current_user.valid_password?(params[:current_password].to_s)
      return erro("A senha não confere. Confira e tente de novo.")
    end

    case current_user.excluir_conta!
    when :solicitada
      render json: { ok: true, requested: true,
                     message: "Pedido enviado. A equipe Loov confere os agendamentos e pagamentos e conclui a exclusão; a conversa fica em Suporte." }
    else
      render json: { ok: true, deleted: true }
    end
  end

  private

  def erro(msg)
    render json: { ok: false, error: msg }, status: :unprocessable_entity
  end

  def mensagem(user)
    e = user.errors
    return "A senha não confere. Confira e tente de novo." if e[:current_password].any?
    return "Esse e-mail já está em uso em outra conta." if e.details[:email].any? { |d| d[:error] == :taken }
    return "E-mail inválido." if e[:email].any?
    e.full_messages.first || "Não foi possível salvar."
  end
end
