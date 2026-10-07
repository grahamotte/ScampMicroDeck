Rails.application.routes.draw do
  constraints(host: /\Ajobs\./) { mount GoodJob::Engine => "/" }

  namespace :api do
    resources :noop, only: [] do
      collection do
        get :ping
        get :lock
        get :hc
        post :error
      end
    end
  end
end
