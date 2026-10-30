Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*(Rails.env.development? ? Settings.development_origins : Settings.origins))

    resource "*",
      headers: :any,
      expose: [ "refresh-token" ],
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
