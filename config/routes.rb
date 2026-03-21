Rails.application.routes.draw do
  root "home#index"
  devise_for :users, controllers: { sessions: 'sessions' }

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
      get :confirmacao
    end
    collection do
      get :checkout
    end
  end

  # ── STRIPE WEBHOOK ────────────────────────────────────────────────────────
  post 'webhooks/stripe', to: 'webhooks#stripe', as: :stripe_webhook

  namespace :client do
    resource :profile, only: [:show, :edit, :update] do
      collection do
        post   :attach_payment_method
        delete :remove_payment_method
      end
    end
    resources :reviews,       only: [:create]
    resources :notifications, only: [:index]
  end

  namespace :owner do
    get  'onboarding',          to: 'onboarding#show',          as: :onboarding
    post 'onboarding/car_wash', to: 'onboarding#save_car_wash', as: :onboarding_car_wash
    post 'onboarding/hours',    to: 'onboarding#save_hours',    as: :onboarding_hours
    post 'onboarding/services', to: 'onboarding#save_services', as: :onboarding_services

    resources :attendant_invitations, only: [:index, :create, :destroy] do
      collection do
        get  ':token/accept', to: 'attendant_invitations#accept',    as: :accept
        post ':token/accept', to: 'attendant_invitations#do_accept', as: :do_accept
      end
    end

    resources :pending_changes, only: [:index] do
      member do
        patch :approve
        patch :reject
      end
    end

    resources :car_wash_appointments, only: [:index, :show]
    get  'financial_tracking', to: 'financial_tracking#index'
    get  'ai_insights',        to: 'ai_insights#show'
    post 'ai_insights',        to: 'ai_insights#analyze'
    post 'ai_insights/input',  to: 'ai_insights#owner_input'

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
      member do
        patch :accept
        patch :reject
      end
    end
  end
end
