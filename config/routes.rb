Rails.application.routes.draw do
  root "home#index"

  # Qual commit está em produção. Público e sem auth de propósito: o objetivo é
  # confirmar deploy sem depender de login.
  get 'version', to: 'version#show'
  devise_for :users, controllers: {
    sessions:      'sessions',
    registrations: 'users/registrations'
  }

  # ── Password reset (custom API + página HTML pra setar nova senha) ────────
  post 'password/forgot',     to: 'passwords#forgot'   # JSON pro app: dispara email
  get  'password/edit',       to: 'passwords#edit'     # HTML: form pra digitar nova senha
  post 'password/update',     to: 'passwords#update'   # HTML form submit

  # /car_washes — mantido pois o app mobile chama aqui em JSON pra listar
  # lava-rápidos. Web HTML redireciona pra home dentro do controller
  # (ver CarWashesController#index).
  resources :car_washes do
    resources :appointments, only: [:create]
    member do
      get 'manage'
      get 'available_times'
    end
  end

  resources :appointments, only: [:new, :create, :index, :show] do
    member do
      delete :cancel
      get    :help
    end
  end

  # ── ABA DISPONÍVEIS ───────────────────────────────────────────────────────
  resources :disponivel, only: [:index, :create, :show] do
    member do
      get   :confirmacao
      patch :cancel
    end
    collection { get :checkout }
  end

  # ── STRIPE WEBHOOK ────────────────────────────────────────────────────────
  post 'webhooks/stripe', to: 'webhooks#stripe', as: :stripe_webhook

  # ── PUSH TOKENS (mobile) ──────────────────────────────────────────────────
  post   'push_tokens',            to: 'push_tokens#create'
  get    'push_tokens/diagnostic', to: 'push_tokens#diagnostic'
  delete 'push_tokens/:token',     to: 'push_tokens#destroy', constraints: { token: /[^\/]+/ }

  namespace :client do
    resource :profile, only: [:show, :edit, :update] do
      collection do
        post   :attach_payment_method
        delete :remove_payment_method
      end
    end
    resources :reviews,    only: [:create]
    resources :favorites,  only: [:index, :create, :destroy]
    get 'loyalty_cards', to: 'loyalty_cards#index'

    resources :notifications, only: [:index] do
      member do
        patch :read
      end
      collection do
        post :read_all
      end
    end
  end

  namespace :owner do
    get   'car_wash',                  to: 'car_wash#show'
    patch 'car_wash',                  to: 'car_wash#update'
    get   'car_wash/slot_diagnostics', to: 'car_wash#slot_diagnostics'

    get  'onboarding',          to: 'onboarding#show',          as: :onboarding
    get  'onboarding/status',   to: 'onboarding#status',        as: :onboarding_status
    post 'onboarding/car_wash', to: 'onboarding#save_car_wash', as: :onboarding_car_wash
    post 'onboarding/hours',    to: 'onboarding#save_hours',    as: :onboarding_hours
    post 'onboarding/services', to: 'onboarding#save_services', as: :onboarding_services
    get  'loyalty_program', to: 'loyalty_programs#show'
    post 'loyalty_program', to: 'loyalty_programs#upsert'
    patch 'checkins/:id/cancel', to: 'checkins#cancel', as: :checkin_cancel

    resources :attendant_invitations, only: [:index, :create, :destroy] do
      collection do
        get  ':token/accept', to: 'attendant_invitations#accept',    as: :accept
        post ':token/accept', to: 'attendant_invitations#do_accept', as: :do_accept
      end
    end

    # JSON API — gestão de funcionários pelo app do dono
    resources :attendants, only: [:index, :create, :destroy] do
      collection do
        post :direct,     action: :create_direct
        get  :diagnostic, action: :diagnostic
      end
    end
    delete 'attendants/invitations/:id', to: 'attendants#destroy_invitation', as: :destroy_attendant_invitation
    delete 'attendants/car_wash/:id',    to: 'attendants#destroy_car_wash',  as: :destroy_owner_car_wash

    resources :messages, only: [:create] do
      collection do
        get :clients_today
      end
    end

    resources :pending_changes, only: [:index] do
      member do
        patch :approve
        patch :reject
      end
    end

    resources :closures, only: [:index, :create, :destroy]
    resources :car_wash_appointments, only: [:index, :show]

    get  'financial_tracking', to: 'financial_tracking#index'
    get  'ai_insights',        to: 'ai_insights#show'
    get  'ai_insights/status', to: 'ai_insights#status'
    post 'ai_insights',        to: 'ai_insights#create'
    post 'ai_insights/input',  to: 'ai_insights#input'

    resources :monthly_costs, only: [:index, :destroy] do
      collection do
        get  :edit
        post :upsert
      end
    end

    get   'checkins/today',              to: 'checkins#today',          as: :checkins_today
    post  'checkins/walk_in',            to: 'checkins#walk_in',        as: :checkin_walk_in
    patch 'checkins/:id/attend',         to: 'checkins#attend',         as: :checkin_attend
    patch 'checkins/:id/no_show',        to: 'checkins#no_show',        as: :checkin_no_show
    patch 'checkins/:id/revert',         to: 'checkins#revert',         as: :checkin_revert
    patch 'checkins/:id/update_service', to: 'checkins#update_service', as: :checkin_update_service

    resources :disponivel_acceptance, only: [:index, :show] do
      collection do
        get :diagnostic
      end
      member do
        patch :accept
        patch :reject
      end
    end

    resources :support_tickets, only: [:index, :create] do
      member do
        post  :message
        patch :close
      end
    end

    resources :notifications, only: [:index] do
      member do
        patch :read
      end
      collection do
        post :read_all
      end
    end
  end

  namespace :admin do
    get 'dashboard',          to: 'dashboard#index',    as: :dashboard
    get 'dashboard/stats',    to: 'dashboard#stats',    as: :dashboard_stats
    get 'dashboard/activity', to: 'dashboard#activity', as: :dashboard_activity
    post 'ceo_assistant/analyze', to: 'ceo_assistant#analyze', as: :ceo_assistant_analyze

    # ── Outreach (prospecção semiautomatizada) ─────────────────────
    get    'outreach',                to: 'outreach#index',         as: :outreach_index
    post   'outreach/import',         to: 'outreach#import',        as: :outreach_import
    post   'outreach/search_google',  to: 'outreach#search_google', as: :outreach_search_google
    post   'outreach/import_google',  to: 'outreach#import_google', as: :outreach_import_google
    get    'outreach/:id',          to: 'outreach#show',   as: :outreach_lead
    patch  'outreach/:id',          to: 'outreach#update'
    delete 'outreach/:id',          to: 'outreach#destroy'
    post   'outreach/:id/generate_message', to: 'outreach#generate_message', as: :outreach_generate
    # match GET+POST: GET cai no controller que redireciona pro detalhe
    match  'outreach/:id/mark_sent',        to: 'outreach#mark_sent',        via: [:get, :post], as: :outreach_mark_sent
    patch  'outreach/:id/status',           to: 'outreach#update_status',    as: :outreach_status
    post   'outreach/:id/meeting',          to: 'outreach#schedule_meeting', as: :outreach_meeting

    resources :users, only: [:index, :show] do
      member do
        patch :block
        patch :unblock
        patch :change_role
      end
    end

    resources :car_washes, only: [:index, :show] do
      member do
        patch :deactivate
        patch :activate
      end
    end

    resources :appointments, only: [:index, :show] do
      member { patch :cancel }
    end

    get  'financial',        to: 'financial#index',  as: :financial
    get  'financial/export', to: 'financial#export', as: :financial_export

    resources :support_tickets, only: [:index] do
      member do
        post   :message
        patch  :resolve
        patch  :reopen
        post   :approve_draft
        delete :discard_draft
        post   :run_agent
      end
    end
  end
end
