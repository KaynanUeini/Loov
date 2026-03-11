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

  namespace :client do
    resource  :profile, only: [:show, :edit, :update]
    resources :reviews,  only: [:create]
  end

  namespace :owner do
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
  end
end
