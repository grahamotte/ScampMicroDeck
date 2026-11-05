Rails.application.routes.draw do
  constraints(host: /\Ajobs\./) { mount GoodJob::Engine => "/" }

  post "graphql", to: "graphql#execute"

  namespace :api, path: "" do
    get "noop/ping", to: "noop#ping"
  end
end
