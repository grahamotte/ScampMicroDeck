require "open3"
require "path"

class Agent
  class << self
    def call(model: "deepseek/deepseek-v4-flash", effort: "high", before_run: nil, after_run: nil, prompt:, env: {})
      Path.with_tmp_dir do |dir|
        before_run&.call(dir)
        result = new(model:, effort:, prompt:, dir:, env:).call
        after_run&.call(dir)
        result
      end
    end
  end

  def initialize(model:, effort:, prompt:, dir:, env: {})
    @model = model.start_with?("openrouter/") ? model : "openrouter/#{model}"
    @effort = effort
    @prompt = prompt
    @dir = dir
    @env = env
  end

  def call
    stdout, stderr, status = capture
    raise "Agent failed: #{error_messages(stdout).join("\n").presence || stderr.strip.presence || stdout.strip.presence || "unknown error"}" unless status.success?

    stdout.each_line.filter_map do |line|
      event = JSON.parse(line)
      event.dig("part", "text") if event["type"] == "text"
    end
  end

  private

  def error_messages(stdout)
    stdout.each_line.filter_map do |line|
      event = JSON.parse(line)
      event.dig("error", "message") if event.is_a?(Hash) && event["type"] == "error"
    rescue JSON::ParserError
      nil
    end
  end

  def capture
    Open3.capture3(environment, *command, **options)
  end

  def environment = { "OPENROUTER_API_KEY" => ENV.fetch("OPENROUTER_TOKEN"), "TMPDIR" => @dir, "PWD" => @dir }.merge(@env)

  def options = { stdin_data: @prompt, chdir: @dir }

  def command
    [
      "opencode",
      "run",
      "--standalone",
      "--format",
      "json",
      "--model",
      [ @model, @effort.presence ].compact.join("#"),
    ]
  end
end
