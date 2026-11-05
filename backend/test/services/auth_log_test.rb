require "test_helper"

class AuthLogTest < ActiveSupport::TestCase
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
    body = AuthLog.body("bad_credentials", ip: "10.0.0.1", email: "a\nb@example.com")

    assert body.start_with?("AUTH_FAILURE {")
    refute_includes body, "\n"
    assert_equal(
      { "event" => "bad_credentials", "ip" => "10.0.0.1", "email" => "a\nb@example.com" },
      JSON.parse(body.delete_prefix("AUTH_FAILURE ")),
    )
  end

  def test_warn_logs_one_warning
    AuthLog.warn("rate_limited", limit: "test", key: "10.0.0.1")

    assert_equal "WARN #{AuthLog.body("rate_limited", limit: "test", key: "10.0.0.1")}\n", @output.string
  end
end
