# Página de suporte do site (chat com a equipe Loov), pra cliente, dono e
# funcionário. A página só monta a tela; as conversas vêm dos mesmos
# endpoints JSON que o app usa (/client/support_tickets e
# /owner/support_tickets), então app e site enxergam as mesmas conversas.
class SuporteController < ApplicationController
  before_action :authenticate_user!

  def show
    return redirect_to(admin_dashboard_path) if current_user.admin?
    @papel = current_user.client? ? "client" : "owner"
  end
end
