require "test_helper"

class ErrorLoggerTestJob < ApplicationJob
  def perform
    raise ArgumentError, "job failed"
  end
end

class ErrorLoggerTest < ActiveSupport::TestCase
  def setup
    super
    @output = StringIO.new
    @logger = ActiveSupport::Logger.new(@output)
    @logger.formatter = ->(severity, _time, _progname, msg) { "#{severity} #{msg}\n" }
    Rails.logger.broadcast_to(@logger)
  end

  def teardown
    Rails.logger.stop_broadcasting_to(@logger)
    super
  end

  def test_body
    error = build_error("Boom", [ "#{Rails.root}/app/services/x.rb:10:in 'X.y'", "/gems/z.rb:1:in 'z'" ])
    reporter = ErrorLogger.new
    body = reporter.body(error, handled: true, severity: :warning, source: "test")

    assert body.start_with?("RAILS_ERROR {")
    refute_includes body, "\n"
    assert_equal(
      {
        "type" => "RuntimeError",
        "message" => "Boom",
        "fingerprint" => reporter.fingerprint(error),
        "severity" => "warning",
        "handled" => true,
        "source" => "test",
        "backtrace" => [ "#{Rails.root}/app/services/x.rb:10:in 'X.y'", "/gems/z.rb:1:in 'z'" ],
      },
      parse(body),
    )
    assert_equal 16, reporter.fingerprint(error).length
  end

  def test_body_truncates_backtrace_and_message
    error = build_error("a" * 5000, Array.new(50) { |i| "/gems/z.rb:#{i}:in 'z'" })
    payload = parse(ErrorLogger.new.body(error))

    assert_equal ErrorLogger::BACKTRACE_LINES, payload.fetch("backtrace").size
    assert_equal ErrorLogger::MESSAGE_LIMIT, payload.fetch("message").size
    assert_equal [], parse(ErrorLogger.new.body(build_error("Boom", nil))).fetch("backtrace")
  end

  def test_body_escapes_multiline_messages
    body = ErrorLogger.new.body(build_error("one\ntwo", [ "/gems/z.rb:1:in 'z'" ]))

    refute_includes body, "\n"
    assert_equal "one\ntwo", parse(body).fetch("message")
  end

  def test_fingerprint_ignores_message_and_line_numbers
    reporter = ErrorLogger.new
    first = build_error("one", [ "/gems/z.rb:1:in 'z'", "#{Rails.root}/app/services/x.rb:10:in 'X.y'" ])
    second = build_error("two", [ "/gems/z.rb:2:in 'z'", "#{Rails.root}/app/services/x.rb:12:in 'X.y'" ])
    other = build_error("one", [ "/gems/z.rb:1:in 'z'", "#{Rails.root}/app/services/x.rb:10:in 'X.z'" ])

    assert_equal reporter.fingerprint(first), reporter.fingerprint(second)
    refute_equal reporter.fingerprint(first), reporter.fingerprint(other)
    refute_equal reporter.fingerprint(first), reporter.fingerprint(ArgumentError.new("one").tap { |x| x.set_backtrace(first.backtrace) })
    assert_equal reporter.fingerprint(build_error("a", [ "/gems/z.rb:1:in 'z'" ])), reporter.fingerprint(build_error("b", [ "/gems/z.rb:9:in 'z'" ]))
  end

  def test_report_levels
    error = build_error("Boom", [ "/gems/z.rb:1:in 'z'" ])
    reporter = ErrorLogger.new

    reporter.report(error, handled: false, severity: :error, context: {})
    reporter.report(error, handled: true, severity: :warning, context: {})
    reporter.report(error, handled: true, severity: :info, context: {}, source: "test")

    assert_equal [ "ERROR", "WARN", "INFO" ], entries.map(&:first)
    assert_equal [ "error", "warning", "info" ], entries.map { |x| x.last.fetch("severity") }
    assert_equal "test", entries.last.last.fetch("source")
  end

  def test_rails_error_subscriber
    Rails.error.report(build_error("Reported", [ "/gems/z.rb:1:in 'z'" ]), handled: false)

    severity, payload = entries.find { |x| x.last.fetch("message") == "Reported" }
    assert_equal "ERROR", severity
    assert_equal "RuntimeError", payload.fetch("type")
    assert_equal false, payload.fetch("handled")
  end

  def test_failing_job
    job = ErrorLoggerTestJob.new
    assert_raises(ArgumentError) { ActiveJob::Base.execute(job.serialize) }

    errors = entries.select { |x| x.last.fetch("type") == "ArgumentError" }
    assert_equal 1, errors.size
    assert_equal "ERROR", errors.first.first
    assert_equal "ErrorLoggerTestJob", errors.first.last.fetch("job_class")
    assert_equal job.job_id, errors.first.last.fetch("job_id")
    assert_equal "job failed", errors.first.last.fetch("message")
  end

  def test_good_job_thread_error
    error = build_error("thread failed", [ "/gems/z.rb:1:in 'z'" ])

    GoodJob._on_thread_error(error)
    GoodJob._on_thread_error(error)

    errors = entries.select { |x| x.last.fetch("message") == "thread failed" }
    assert_equal 1, errors.size
    assert_equal "ERROR", errors.first.first
    assert_equal "good_job", errors.first.last.fetch("source")
  end

  private

  def build_error(message, backtrace)
    RuntimeError.new(message).tap { |x| x.set_backtrace(backtrace) if backtrace }
  end

  def parse(body)
    JSON.parse(body.delete_prefix("#{ErrorLogger::MARKER} "))
  end

  def entries
    @output.string.lines.filter_map do |line|
      severity, body = line.chomp.split(" ", 2)
      [ severity, parse(body) ] if body.start_with?(ErrorLogger::MARKER)
    end
  end
end
