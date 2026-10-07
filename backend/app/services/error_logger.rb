class ErrorLogger
  BACKTRACE_LINES = 30
  LEVELS = { error: :error, warning: :warn, info: :info }.freeze

  def report(error, handled:, severity:, context:, source: nil)
    Telemetry.with_attributes(attributes(error)) do
      Rails.logger.public_send(LEVELS.fetch(severity, :error), body(error))
    end
  end

  def attributes(error)
    {
      "exception.type" => error.class.name,
      "error.fingerprint" => fingerprint(error),
    }
  end

  def body(error)
    [ "#{error.class.name}: #{error.message}", *Array(error.backtrace).first(BACKTRACE_LINES) ].join("\n")
  end

  def fingerprint(error)
    Digest::SHA256.hexdigest([ error.class.name, location(error) ].join("\n")).first(16)
  end

  private

  def location(error)
    backtrace = Array(error.backtrace)
    line = Rails.backtrace_cleaner.clean(backtrace).first || backtrace.first
    line.to_s.sub(/:\d+:in /, ":in ")
  end
end
