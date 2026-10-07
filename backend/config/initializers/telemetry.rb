Rails.application.config.after_initialize do
  ActiveSupport::LogSubscriber.prepend(Telemetry::LogSubscriber)
  Telemetry.start
  Rails.error.subscribe(ErrorLogger.new)
end
