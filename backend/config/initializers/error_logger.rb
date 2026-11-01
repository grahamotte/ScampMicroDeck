Rails.application.config.after_initialize do
  JournalFormatter.install(Rails.logger) if ENV["JOURNAL_STREAM"].present?
  Rails.error.subscribe(ErrorLogger.new)
end
