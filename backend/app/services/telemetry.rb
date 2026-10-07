class Telemetry
  KEYS = %w[OTEL_EXPORTER_OTLP_ENDPOINT OTEL_EXPORTER_OTLP_HEADERS OTEL_SERVICE_NAME].freeze
  SEVERITIES = {
    "DEBUG" => 5,
    "INFO" => 9,
    "WARN" => 13,
    "ERROR" => 17,
    "FATAL" => 21,
  }.freeze

  class Exporter < OpenTelemetry::Exporter::OTLP::Logs::LogsExporter
    private

    def log_partial_success(body)
      super if body.present?
    end
  end

  module LogSubscriber
    def call(event)
      Telemetry.with_attributes("event.name" => event.name) { super }
    end
  end

  class Device
    def initialize(logger)
      @logger = logger
    end

    def write(record)
      @logger.on_emit(**record)
    end

    def close; end
  end

  class Formatter < ::Logger::Formatter
    def initialize(tagged)
      super()
      @tagged = tagged
    end

    def call(severity, time, progname, msg)
      {
        timestamp: time,
        severity_text: severity,
        severity_number: SEVERITIES.fetch(severity, 0),
        body: [ *tags, progname, msg2str(msg) ].compact_blank.join(" ").strip,
        attributes: Telemetry.context.merge(Telemetry.attributes).presence,
      }
    end

    private

    def tags
      @tagged.respond_to?(:current_tags) ? @tagged.current_tags.map { |tag| "[#{tag}]" } : []
    end
  end

  class << self
    attr_reader :provider

    def enabled?
      (X.prod? || X.dev?) && KEYS.all? { |key| ENV[key].present? }
    end

    def start
      return if provider.present? || !enabled?

      @provider = build_provider(Exporter.new)
      Rails.logger.broadcast_to(logger)
      provider.tap { |x| at_exit { x.shutdown(timeout: 10) } }
    end

    def build_provider(exporter)
      OpenTelemetry::SDK::Logs::LoggerProvider.new(resource:).tap do |x|
        x.add_log_record_processor(OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter))
      end
    end

    def logger(logger_provider = provider, primary = Rails.logger)
      ActiveSupport::Logger.new(Device.new(logger_provider.logger(name: "rails"))).tap do |x|
        x.formatter = Formatter.new(primary.formatter)
        x.level = primary.level
      end
    end

    def resource
      OpenTelemetry::SDK::Resources::Resource.default.merge(
        OpenTelemetry::SDK::Resources::Resource.create(
          {
            "deployment.environment" => Rails.env.to_s,
            "service.instance.id" => role,
            "service.version" => version,
            "host.name" => Socket.gethostname,
          }.compact,
        ),
      )
    end

    def version(root = Rails.root.join(".."))
      git = root.join(".git")
      git = root.join(git.read.delete_prefix("gitdir:").strip) if git.file?
      head = git.join("HEAD").read.strip
      return head unless head.start_with?("ref: ")

      ref = head.delete_prefix("ref: ")
      common = git.join("commondir").file? ? git.join(git.join("commondir").read.strip) : git
      [ git, common ].map { |dir| dir.join(ref) }.find(&:file?)&.read&.strip ||
        common.join("packed-refs").read[/^(\h+) #{Regexp.escape(ref)}$/, 1]
    rescue SystemCallError
      nil
    end

    def role
      return "job" if GoodJob::CLI.within_exe?
      return "api" if defined?(Rails::Server)

      "rails"
    end

    def context
      context = ActiveSupport::ExecutionContext.to_h
      request = context[:controller].try(:request)
      job = context[:job]

      {
        "request.id" => request.try(:request_id),
        "job.class" => job&.class&.name,
        "job.id" => job.try(:job_id),
      }.compact
    end

    def attributes
      ActiveSupport::IsolatedExecutionState[:telemetry_attributes] || {}
    end

    def with_attributes(values)
      previous = ActiveSupport::IsolatedExecutionState[:telemetry_attributes]
      ActiveSupport::IsolatedExecutionState[:telemetry_attributes] = attributes.merge(values)
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[:telemetry_attributes] = previous
    end
  end
end
