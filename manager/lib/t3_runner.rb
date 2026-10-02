require "open3"
require "securerandom"
require "time"
require "timeout"

class T3Runner
  PROVIDERS = {
    "openai" => "codex",
    "anthropic" => "claudeAgent",
    "xai" => "grok",
    "google" => "antigravity",
  }.freeze
  APP = "/Applications/T3 Code (Alpha).app"

  class << self
    def start(prompt, directory:, model: nil, variant: nil)
      defaults = AgentSelection.resolve(runner: "t3", model:, variant:)
      model, variant = defaults.values_at(:model, :variant)
      selection = model_selection(model, variant)
      directory = File.realpath(directory)
      workspace = workspace(directory)
      issued = JSON.parse(auth("issue", "--ttl", "5m", "--label", "Code Moto manager", "--json"), symbolize_names: true)
      headers = { "Authorization" => "Bearer #{issued.fetch(:token)}" }
      thread_id = SecureRandom.uuid
      created = false
      begin
        project_id = project(workspace.fetch(:root), headers)
        dispatch(
          {
            type: "thread.create",
            threadId: thread_id,
            projectId: project_id,
            title: File.basename(directory),
            modelSelection: selection,
            runtimeMode: "full-access",
            interactionMode: "default",
            branch: workspace[:branch],
            worktreePath: directory == workspace[:root] ? nil : directory,
          },
          headers,
        )
        created = true
        dispatch(
          {
            type: "thread.turn.start",
            threadId: thread_id,
            message: {
              messageId: SecureRandom.uuid,
              role: "user",
              text: prompt,
              attachments: [],
            },
            modelSelection: selection,
            runtimeMode: "full-access",
            interactionMode: "default",
          },
          headers,
        )
        { threadId: thread_id }
      rescue StandardError
        if created
          begin
            dispatch({ type: "thread.delete", threadId: thread_id }, headers)
          rescue StandardError
            warn "Could not remove the failed T3 thread #{thread_id}"
          end
        end
        raise
      ensure
        begin
          auth("revoke", issued.fetch(:sessionId))
        rescue StandardError
          warn "Could not revoke the temporary T3 session; it expires after five minutes"
        end
      end
    end

    def selection(model:, variant: nil)
      model_selection(model, variant)
    end

    def refresh_provider(instance)
      issued = JSON.parse(auth("issue", "--ttl", "5m", "--label", "Code Moto quota refresh", "--json"), symbolize_names: true)
      socket = nil
      responses = Queue.new
      begin
        Timeout.timeout(30) do
          socket = WebSocket::Client::Simple.connect(
            "#{origin.sub(/\Ahttp/, "ws")}/ws",
            headers: { "Authorization" => "Bearer #{issued.fetch(:token)}" },
            verify_mode: OpenSSL::SSL::VERIFY_PEER,
          ) do |connection|
            socket = connection
            connection.on(:open) do
              connection.send(JSON.generate(_tag: "Request", id: "1", tag: "server.refreshProviders", payload: { instanceId: instance }, headers: []))
            end
            connection.on(:message) do |message|
              begin
                decoded = JSON.parse(message.data, symbolize_names: true)
                messages = decoded.is_a?(Array) ? decoded : [ decoded ]
                messages.each do |response|
                  responses << response if response[:_tag] == "Exit" && response[:requestId].to_s == "1"
                end
              rescue JSON::ParserError
                responses << { exit: { _tag: "Failure" } }
              end
            end
            connection.on(:error) { responses << { exit: { _tag: "Failure" } } }
            connection.on(:close) { responses << { exit: { _tag: "Failure" } } }
          end
          response = responses.pop
          raise "T3 provider #{instance} quota refresh failed" unless response.dig(:exit, :_tag) == "Success"
        end
      ensure
        begin
          socket&.close
        ensure
          begin
            auth("revoke", issued.fetch(:sessionId))
          rescue StandardError
            warn "Could not revoke the temporary T3 session; it expires after five minutes"
          end
        end
      end
    end

    private

    def config
      Settings.all.dig(:agent, :t3) || {}
    end

    def home
      File.expand_path(config[:home].present? ? config[:home] : "~/.t3")
    end

    def origin
      config[:url].present? ? config[:url] : "http://127.0.0.1:3773"
    end

    def auth(*arguments)
      command = config[:command]
      environment = {}
      if command.blank?
        executable = "#{APP}/Contents/MacOS/T3 Code (Alpha)"
        if File.executable?(executable)
          environment["ELECTRON_RUN_AS_NODE"] = "1"
          command = [ executable, "#{APP}/Contents/Resources/app.asar/apps/server/dist/bin.mjs" ]
        else
          command = [ "t3" ]
        end
      end
      stdout, _stderr, status = Open3.capture3(
        environment,
        *command,
        "auth",
        "session",
        *arguments,
        "--base-dir",
        home,
      )
      raise "T3 auth session #{arguments.first} failed" unless status.success?

      stdout
    end

    def model_selection(model, variant)
      provider, model_id = model.to_s.split("/", 2)
      raise "T3 model must use provider/modelid" if provider.blank? || model_id.blank?
      raise "Invalid T3 provider #{provider.inspect}" unless provider.match?(/\A[a-zA-Z0-9_-]+\z/)

      instance = PROVIDERS.fetch(provider, provider)
      path = File.join(home, "caches", "#{instance}.json")
      raise "Open T3 and enable provider #{instance} before launching manager cards" unless File.file?(path)

      catalog = JSON.parse(File.read(path), symbolize_names: true)
      raise "T3 provider #{instance} is not ready" unless catalog[:enabled] == true && catalog[:status] == "ready"

      selected = catalog.fetch(:models).find { |item| item[:slug] == model_id || (item[:aliases] || []).include?(model_id) }
      raise "T3 provider #{instance} does not offer model #{model_id}" if selected.blank?

      descriptors = selected.dig(:capabilities, :optionDescriptors) || []
      options = []
      if variant.present?
        effort = descriptors.find { |item| [ "reasoningEffort", "effort", "reasoning" ].include?(item[:id]) }
        raise "T3 model #{model} does not support effort #{variant}" if effort.blank? || effort.fetch(:options).none? { |item| item[:id] == variant }

        options << { id: effort.fetch(:id), value: variant }
      end
      speed = config[:speed]
      if speed.present?
        raise "T3 speed must be fast or normal" unless [ "fast", "normal" ].include?(speed)

        tier = descriptors.find { |item| item[:id] == "serviceTier" }
        fast_mode = descriptors.find { |item| item[:id] == "fastMode" }
        if tier.present?
          choice = tier.fetch(:options).find { |item| speed == "fast" ? item[:label].to_s.casecmp?("Fast") : item[:id] == "default" }
          raise "T3 model #{model} does not support #{speed} speed" if choice.blank?

          options << { id: tier.fetch(:id), value: choice.fetch(:id) }
        elsif fast_mode.present?
          options << { id: fast_mode.fetch(:id), value: speed == "fast" }
        else
          raise "T3 model #{model} does not support fast speed" if speed == "fast"
        end
      end
      { instanceId: catalog[:instanceId].present? ? catalog[:instanceId] : instance, model: selected.fetch(:slug), options: }
    end

    def workspace(directory)
      stdout, _stderr, status = Open3.capture3("git", "worktree", "list", "--porcelain", "-z", chdir: directory)
      raise "Could not list Git worktrees for T3" unless status.success?

      worktrees = stdout.split("\0\0").map do |block|
        lines = block.split("\0")
        path = lines.find { |line| line.start_with?("worktree ") }&.delete_prefix("worktree ")
        branch = lines.find { |line| line.start_with?("branch ") }&.delete_prefix("branch refs/heads/")
        { path: path.present? && File.directory?(path) ? File.realpath(path) : path, branch: }
      end
      current = worktrees.find { |item| item[:path] == directory }
      root = worktrees.first&.fetch(:path)
      raise "Could not resolve the Git checkout for T3" if root.blank? || current.blank?

      { root:, branch: current[:branch] }
    end

    def project(directory, headers)
      directory = File.expand_path(directory)
      snapshot = Req.call(url: "#{origin}/api/orchestration/snapshot", headers:)
      existing = snapshot.fetch(:projects).find { |item| item[:workspaceRoot] == directory && item[:deletedAt].blank? }
      return existing.fetch(:id) if existing.present?

      id = SecureRandom.uuid
      dispatch(
        {
          type: "project.create",
          projectId: id,
          title: File.basename(directory),
          workspaceRoot: directory,
        },
        headers,
      )
      id
    end

    def dispatch(payload, headers)
      Req.call(
        url: "#{origin}/api/orchestration/dispatch",
        method: :post,
        headers:,
        payload: { commandId: SecureRandom.uuid, createdAt: Time.now.utc.iso8601(3), **payload },
      )
    end
  end
end
