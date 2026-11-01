class ErrorLogger
  BACKTRACE_LINES = 30
  MESSAGE_LIMIT = 4000
  MARKER = "RAILS_ERROR".freeze
  LEVELS = { error: :error, warning: :warn, info: :info }.freeze

  def report(error, handled:, severity:, context:, source: nil)
    Rails.logger.public_send(LEVELS.fetch(severity, :error), body(error, handled:, severity:, source:))
  end

  def body(error, handled: false, severity: :error, source: nil)
    "#{MARKER} #{JSON.generate(payload(error, handled:, severity:, source:))}"
  end

  def payload(error, handled: false, severity: :error, source: nil)
    {
      type: error.class.name,
      message: error.message.to_s.truncate(MESSAGE_LIMIT),
      fingerprint: fingerprint(error),
      severity: severity.to_s,
      handled:,
      source:,
      **execution,
      backtrace: Array(error.backtrace).first(BACKTRACE_LINES),
    }
  end

  def fingerprint(error)
    Digest::SHA256.hexdigest([ error.class.name, location(error) ].join("\n")).first(16)
  end

  private

  def execution
    context = ActiveSupport::ExecutionContext.to_h
    job = context[:job]

    {
      request_id: context[:controller].try(:request).try(:request_id),
      job_class: job&.class&.name,
      job_id: job.try(:job_id),
    }.compact
  end

  def location(error)
    backtrace = Array(error.backtrace)
    line = Rails.backtrace_cleaner.clean(backtrace).first || backtrace.first
    line.to_s.sub(/:\d+:in /, ":in ")
  end
end
