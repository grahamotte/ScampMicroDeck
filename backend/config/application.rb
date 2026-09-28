require_relative "boot"

require "rails/all"
Bundler.require(*Rails.groups)
require_relative "settings"

module Backend
  class Application < Rails::Application
    config.load_defaults 8.0
    config.autoload_lib(ignore: %w[assets tasks])
    config.api_only = true
    config.generators { |x| x.orm :active_record, primary_key_type: :uuid }
    config.session_store :cookie_store, key: "session"
    config.middleware.use Rack::MethodOverride
    config.middleware.use ActionDispatch::Flash
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options
  end
end
