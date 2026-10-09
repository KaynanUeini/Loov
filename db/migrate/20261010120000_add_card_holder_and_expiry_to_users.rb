# Dados de EXIBIÇÃO do cartão salvo (o Stripe guarda o cartão; aqui só o que
# aparece na tela de Pagamentos): nome impresso e validade. Sem eles a tela
# mostrava o nome da conta, que nem sempre é o do cartão.
class AddCardHolderAndExpiryToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :stripe_card_holder,    :string
    add_column :users, :stripe_card_exp_month, :integer
    add_column :users, :stripe_card_exp_year,  :integer
  end
end
