require "test_helper"

class TelemetryTest < ActiveSupport::TestCase
  ENDPOINT = "https://otlp.example.test/otlp/v1/logs"

  def setup
    super
    @exporter = OpenTelemetry::SDK::Logs::Export::InMemoryLogRecordExporter.new
    @provider = Telemetry.build_provider(@exporter)
    @logger = Telemetry.logger(@provider)
  end

  def teardown
    @provider.shutdown
    super
  end

  def test_disabled_in_test
    previous = Telemetry::KEYS.index_with { |key| ENV[key] }
    Telemetry::KEYS.each { |key| ENV[key] = "value" }

    refute Telemetry.enabled?
    assert_nil Telemetry.start
    assert_nil Telemetry.provider
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def test_severities
    @logger.level = Logger::DEBUG
    @logger.debug("debug")
    @logger.info("info")
    @logger.warn("warn")
    @logger.error("error")
    @logger.fatal("fatal")
    @logger.unknown("unknown")

    assert_equal(
      [ [ "DEBUG", 5 ], [ "INFO", 9 ], [ "WARN", 13 ], [ "ERROR", 17 ], [ "FATAL", 21 ], [ "ANY", 0 ] ],
      records.map { |x| [ x.severity_text, x.severity_number ] },
    )
  end

  def test_broadcast_keeps_tags_and_runs_blocks_once
    io = StringIO.new
    primary = ActiveSupport::TaggedLogging.logger(io)
    broadcast = ActiveSupport::BroadcastLogger.new(primary, Telemetry.logger(@provider, primary))
    runs = 0

    broadcast.tagged("request-1") do
      runs += 1
      broadcast.info("hello\n")
    end
    broadcast.info("worker") { "done" }

    assert_equal 1, runs
    assert_equal [ "[request-1] hello", "worker done" ], records.map(&:body)
    assert_equal [ "[request-1] hello", "done" ], io.string.lines.map(&:strip).compact_blank
  end

  def test_attributes
    Telemetry.with_attributes("a" => "1") do
      Telemetry.with_attributes("b" => "2") { @logger.info("nested") }
      @logger.info("outer")
    end
    @logger.info("none")

    assert_equal [ { "a" => "1", "b" => "2" }, { "a" => "1" }, nil ], records.map(&:attributes)
    assert_equal({}, Telemetry.attributes)
  end

  def test_context
    job = ApplicationJob.new
    controller = Api::NoopController.new
    controller.request = ActionDispatch::TestRequest.create("action_dispatch.request_id" => "request-1")
    ActiveSupport::ExecutionContext[:controller] = controller
    ActiveSupport::ExecutionContext[:job] = job

    Telemetry.with_attributes("request.id" => "override") { @logger.info("overridden") }
    @logger.info("context")
    ActiveSupport::ExecutionContext.clear
    @logger.info("cleared")

    assert_equal(
      [
        { "request.id" => "override", "job.class" => "ApplicationJob", "job.id" => job.job_id },
        { "request.id" => "request-1", "job.class" => "ApplicationJob", "job.id" => job.job_id },
        nil,
      ],
      records.map(&:attributes),
    )
  ensure
    ActiveSupport::ExecutionContext.clear
  end

  def test_resource
    attributes = Telemetry.resource.attribute_enumerator.to_h

    assert_equal "test", attributes.fetch("deployment.environment")
    assert_equal "rails", attributes.fetch("service.instance.id")
    assert_match(/\A\h{40}\z/, attributes.fetch("service.version"))
    assert_equal Telemetry.version, attributes.fetch("service.version")
    assert_equal Socket.gethostname, attributes.fetch("host.name")
    assert_equal "rails", Telemetry.role
  end

  def test_version
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      git = root.join(".git")
      git.join("refs/heads").mkpath

      assert_nil Telemetry.version(root)

      git.join("HEAD").write("#{"a" * 40}\n")
      assert_equal "a" * 40, Telemetry.version(root)

      git.join("HEAD").write("ref: refs/heads/master\n")
      git.join("packed-refs").write("# pack-refs\n#{"b" * 40} refs/heads/master\n")
      assert_equal "b" * 40, Telemetry.version(root)

      git.join("refs/heads/master").write("#{"c" * 40}\n")
      assert_equal "c" * 40, Telemetry.version(root)
    end
  end

  def test_version_in_worktree
    Dir.mktmpdir do |dir|
      root = Pathname(dir).join("worktree")
      common = Pathname(dir).join("main/.git")
      git = common.join("worktrees/worktree")
      git.mkpath
      common.join("refs/heads").mkpath
      root.mkpath
      root.join(".git").write("gitdir: #{git}\n")
      git.join("HEAD").write("ref: refs/heads/moto-117\n")
      git.join("commondir").write("../..\n")
      common.join("refs/heads/moto-117").write("#{"d" * 40}\n")

      assert_equal "d" * 40, Telemetry.version(root)
    end
  end

  def test_log_subscriber_event_name
    Rails.logger.broadcast_to(@logger)

    ActiveSupport::Notifications.instrument("sql.active_record", sql: "BEGIN", name: "TRANSACTION", binds: [], type_casted_binds: []) { nil }
    Rails.logger.info("plain")

    record = records.find { |x| x.body.include?("TRANSACTION") }
    assert_equal({ "event.name" => "sql.active_record" }, record.attributes)
    assert_nil records.find { |x| x.body == "plain" }.attributes
  ensure
    Rails.logger.stop_broadcasting_to(@logger)
  end

  def test_exporter_posts_protobuf_with_basic_auth
    stub_request(:post, ENDPOINT)
      .with(headers: { "Authorization" => "Basic abc", "Content-Type" => "application/x-protobuf" })
      .to_return(status: 200, body: "")
    exporter = Telemetry::Exporter.new(endpoint: ENDPOINT, headers: "Authorization=Basic abc")
    provider = Telemetry.build_provider(exporter)

    Telemetry.logger(provider).error("boom")

    assert_equal OpenTelemetry::SDK::Logs::Export::SUCCESS, provider.force_flush
    assert_requested :post, ENDPOINT, times: 1
  ensure
    provider&.shutdown
  end

  def test_exporter_failure_does_not_raise
    previous = OpenTelemetry.logger
    OpenTelemetry.logger = Logger.new(nil)
    stub_request(:post, ENDPOINT).to_return(status: 400, body: "")
    exporter = Telemetry::Exporter.new(endpoint: ENDPOINT, headers: "Authorization=Basic%20abc")
    provider = Telemetry.build_provider(exporter)

    Telemetry.logger(provider).error("boom")

    assert_equal OpenTelemetry::SDK::Logs::Export::FAILURE, provider.force_flush
  ensure
    provider&.shutdown
    OpenTelemetry.logger = previous
  end

  private

  def records
    @provider.force_flush
    @exporter.emitted_log_records
  end
end
