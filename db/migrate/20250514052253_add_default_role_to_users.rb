class AddDefaultRoleToUsers < ActiveRecord::Migration[7.0]
  def change
    # Define um valor padrão para novos usuários
    change_column_default :users, :role, from: nil, to: "client"
    # Torna o campo role não nulo
    change_column_null :users, :role, false
    # Atualiza usuários existentes com role nulo
    User.where(role: nil).update_all(role: "client")
  end
end
