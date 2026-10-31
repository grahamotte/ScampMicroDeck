Rails.application.routes.draw do
  constraints(host: /\Ajobs\./) { mount GoodJob::Engine => "/" }

  namespace :api, path: "" do
    resources :noop, only: [] do
      collection do
        get :ping
        get :lock
        get :hc
        post :error
      end
    end

    resources :users, only: [] do
      collection do
        post :jwt
      end
    end
  end
end
