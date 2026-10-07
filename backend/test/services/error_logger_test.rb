require "test_helper"

class ErrorLoggerTestJob < ApplicationJob
  def perform
    raise ArgumentError, "job failed"
  end
end

class ErrorLoggerTest < ActiveSupport::TestCase
  def setup
    super
    @exporter = OpenTelemetry::SDK::Logs::Export::InMemoryLogRecordExporter.new
    @provider = Telemetry.build_provider(@exporter)
    @logger = Telemetry.logger(@provider)
    Rails.logger.broadcast_to(@logger)
  end

  def teardown
    Rails.logger.stop_broadcasting_to(@logger)
    @provider.shutdown
    super
  end

  def test_body_and_attributes
    error = build_error("Boom", [ "#{Rails.root}/app/services/x.rb:10:in 'X.y'", "/gems/z.rb:1:in 'z'" ])
    reporter = ErrorLogger.new

    assert_equal "RuntimeError: Boom\n#{Rails.root}/app/services/x.rb:10:in 'X.y'\n/gems/z.rb:1:in 'z'", reporter.body(error)
    assert_equal({ "exception.type" => "RuntimeError", "error.fingerprint" => reporter.fingerprint(error) }, reporter.attributes(error))
    assert_equal 16, reporter.fingerprint(error).length
  end

  def test_body_truncates_backtrace
    error = build_error("Boom", Array.new(50) { |i| "/gems/z.rb:#{i}:in 'z'" })

    assert_equal ErrorLogger::BACKTRACE_LINES + 1, ErrorLogger.new.body(error).lines.size
    assert_equal "RuntimeError: Boom", ErrorLogger.new.body(build_error("Boom", nil))
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

    assert_equal [ "ERROR", "WARN", "INFO" ], records.map(&:severity_text)
    assert_equal reporter.attributes(error), records.first.attributes
  end

  def test_rails_error_subscriber
    Rails.error.report(build_error("Reported", [ "/gems/z.rb:1:in 'z'" ]), handled: false)

    record = records.find { |x| x.body.start_with?("RuntimeError: Reported") }
    assert_equal "ERROR", record.severity_text
    assert_equal "RuntimeError", record.attributes.fetch("exception.type")
  end

  def test_failing_job
    assert_raises(ArgumentError) { ActiveJob::Base.execute(ErrorLoggerTestJob.new.serialize) }

    errors = records.select { |x| x.attributes&.fetch("exception.type", nil) == "ArgumentError" }
    assert_equal 1, errors.size
    assert_equal "ERROR", errors.first.severity_text
    assert_equal "ErrorLoggerTestJob", errors.first.attributes.fetch("job.class")
    assert errors.first.body.start_with?("ArgumentError: job failed\n")
  end

  def test_good_job_thread_error
    error = build_error("thread failed", [ "/gems/z.rb:1:in 'z'" ])

    GoodJob._on_thread_error(error)
    GoodJob._on_thread_error(error)

    errors = records.select { |x| x.body.start_with?("RuntimeError: thread failed") }
    assert_equal 1, errors.size
    assert_equal "ERROR", errors.first.severity_text
  end

  private

  def build_error(message, backtrace)
    RuntimeError.new(message).tap { |x| x.set_backtrace(backtrace) if backtrace }
  end

  def records
    @provider.force_flush
    @exporter.emitted_log_records
  end
end
