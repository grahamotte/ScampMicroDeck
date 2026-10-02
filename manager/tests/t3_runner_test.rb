require_relative "test_helper"

class T3RunnerTest < Minitest::Test
  def setup
    super
    @home = File.join(@worktree_test_dir, "t3")
    Settings.all[:agent][:t3] = { home: @home, command: [ "t3" ] }
    Settings.all[:agent][:model] = "openai/gpt-6.1-sol"
    @catalog = {
      instanceId: "codex",
      enabled: true,
      status: "ready",
      models: [
        {
          slug: "gpt-6.1-sol",
          aliases: [ "sol" ],
          capabilities: {
            optionDescriptors: [
              { id: "reasoningEffort", options: [ { id: "high" }, { id: "medium" } ] },
              { id: "serviceTier", options: [ { id: "default", label: "Standard" }, { id: "priority", label: "Fast" } ] },
            ],
          },
        },
      ],
    }
    write_catalog
    @commands = []
    @requests = []
    @projects = []
    @failure = nil
    @auth_failure = nil
    @directory = File.join(@worktree_test_dir, "card")
    FileUtils.mkdir_p(@directory)
    @worktrees = nil
    @git_success = true
    test = self
    git_status = Object.new
    git_status.define_singleton_method(:success?) { test.instance_variable_get(:@git_success) }
    status = Object.new
    status.define_singleton_method(:success?) { test.instance_variable_get(:@commands).last[4] != test.instance_variable_get(:@auth_failure) }
    Open3.stubs(:capture3).with do |*arguments|
      next false unless arguments[1] == "t3"

      @commands << arguments
      true
    end.returns([ JSON.generate(token: "t3-token", sessionId: "auth-1"), "secret-error", status ])
    git_output = +""
    Open3.stubs(:capture3).with do |*arguments, **kwargs|
      next false unless arguments == [ "git", "worktree", "list", "--porcelain", "-z" ]

      git_output.replace(@worktrees || porcelain([ kwargs.fetch(:chdir), "master" ]))
      true
    end.returns([ git_output, "secret-git-error", git_status ])
    response = {}
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      @requests << opts
      type = opts.dig(:payload, :type)
      raise "dispatch failed" if type.present? && type == @failure

      response.replace(opts[:url].end_with?("/snapshot") ? { projects: @projects } : { sequence: 1 })
      true
    end.returns(response)
  end

  def test_refreshes_provider_using_authenticated_rpc_and_revokes_session
    socket, sent, events = quota_socket
    WebSocket::Client::Simple.expects(:connect).with(
      "ws://127.0.0.1:3773/ws",
      headers: { "Authorization" => "Bearer t3-token" },
      verify_mode: OpenSSL::SSL::VERIFY_PEER,
    ).yields(socket).returns(socket)

    T3Runner.refresh_provider("codex")

    assert_equal({ _tag: "Request", id: "1", tag: "server.refreshProviders", payload: { instanceId: "codex" }, headers: [] }, JSON.parse(sent.first, symbolize_names: true))
    assert_includes events, :closed
    assert_equal "revoke", @commands.last[4]
    assert_equal "auth-1", @commands.last[5]
  end

  def test_refresh_failure_closes_socket_and_revokes_session
    socket, _, events = quota_socket(success: false)
    WebSocket::Client::Simple.expects(:connect).yields(socket).returns(socket)

    assert_raises(RuntimeError) { T3Runner.refresh_provider("codex") }

    assert_includes events, :closed
    assert_equal "revoke", @commands.last[4]
  end

  def test_refresh_connection_failure_revokes_session
    WebSocket::Client::Simple.expects(:connect).raises(Timeout::Error)

    assert_raises(Timeout::Error) { T3Runner.refresh_provider("codex") }

    assert_equal "revoke", @commands.last[4]
  end

  def test_refresh_socket_cleanup_failure_still_revokes_session
    socket, = quota_socket
    socket.define_singleton_method(:close) { raise IOError }
    WebSocket::Client::Simple.expects(:connect).yields(socket).returns(socket)

    assert_raises(IOError) { T3Runner.refresh_provider("codex") }

    assert_equal "revoke", @commands.last[4]
  end

  def test_creates_project_thread_and_turn_with_short_lived_auth
    result = Agent.start("do the work", runner: "t3", directory: @directory)

    assert_equal [ "project.create", "thread.create", "thread.turn.start" ], dispatches.map { |item| item[:type] }
    project, thread, turn = dispatches
    assert_equal File.realpath(@directory), project[:workspaceRoot]
    assert_equal project[:projectId], thread[:projectId]
    assert_equal "master", thread[:branch]
    assert_nil thread[:worktreePath]
    assert_equal thread[:threadId], turn[:threadId]
    assert_equal({ threadId: thread[:threadId] }, result)
    assert_equal "do the work", turn.dig(:message, :text)
    assert_equal [], turn.dig(:message, :attachments)
    assert_equal "user", turn.dig(:message, :role)
    assert_equal "full-access", turn[:runtimeMode]
    assert_equal "default", turn[:interactionMode]
    assert_equal({ instanceId: "codex", model: "gpt-6.1-sol", options: [ { id: "reasoningEffort", value: "high" } ] }, turn[:modelSelection])
    assert_equal turn[:modelSelection], thread[:modelSelection]
    assert @requests.all? { |item| item[:headers] == { "Authorization" => "Bearer t3-token" } }
    assert_equal [ {}, "t3", "auth", "session", "issue", "--ttl", "5m", "--label", "Code Moto manager", "--json", "--base-dir", @home ], @commands.first
    assert_equal [ {}, "t3", "auth", "session", "revoke", "auth-1", "--base-dir", @home ], @commands.last
    assert_equal dispatches.length, dispatches.map { |item| item[:commandId] }.uniq.length
    dispatches.each { |item| assert Time.iso8601(item[:createdAt]) }
  end

  def test_uses_configured_runner_and_reuses_active_project
    Settings.all[:agent][:runner] = "t3"
    @projects = [ { id: "old", workspaceRoot: File.realpath(@directory), deletedAt: "yesterday" }, { id: "project-1", workspaceRoot: File.realpath(@directory), deletedAt: nil } ]

    Agent.start("work", directory: @directory)

    assert_equal [ "thread.create", "thread.turn.start" ], dispatches.map { |item| item[:type] }
    assert_equal "project-1", dispatches.first[:projectId]
  end

  def test_worktree_reuses_main_project_instead_of_worktree_project
    @worktrees = porcelain([ Worktree.root, "master" ], [ @directory, "moto-73" ])
    @projects = [
      { id: "worktree-project", workspaceRoot: File.realpath(@directory) },
      { id: "deleted-main", workspaceRoot: File.realpath(Worktree.root), deletedAt: "yesterday" },
      { id: "main-project", workspaceRoot: File.realpath(Worktree.root) },
    ]

    Agent.start("work", runner: "t3", directory: @directory)

    assert_equal [ "thread.create", "thread.turn.start" ], dispatches.map { |item| item[:type] }
    assert_equal "main-project", dispatches.first[:projectId]
    assert_equal File.realpath(@directory), dispatches.first[:worktreePath]
    assert_equal "moto-73", dispatches.first[:branch]
  end

  def test_worktree_creates_main_project_when_missing
    @worktrees = porcelain([ Worktree.root, "master" ], [ @directory, "moto-73" ])

    Agent.start("work", runner: "t3", directory: @directory)

    project, thread = dispatches
    assert_equal File.realpath(Worktree.root), project[:workspaceRoot]
    assert_equal File.basename(Worktree.root), project[:title]
    assert_equal project[:projectId], thread[:projectId]
    assert_equal File.realpath(@directory), thread[:worktreePath]
    assert_equal "moto-73", thread[:branch]
  end

  def test_detached_worktree_has_no_branch
    @worktrees = porcelain([ Worktree.root, "master" ], [ @directory, nil ])

    Agent.start("work", runner: "t3", directory: @directory)

    assert_nil dispatches[1][:branch]
    assert_equal File.realpath(@directory), dispatches[1][:worktreePath]
  end

  def test_symlinked_worktree_uses_real_path
    @worktrees = porcelain([ Worktree.root, "master" ], [ @directory, "moto-73" ])
    link = File.join(@worktree_test_dir, "card-link")
    File.symlink(@directory, link)

    Agent.start("work", runner: "t3", directory: link)

    assert_equal File.realpath(@directory), dispatches[1][:worktreePath]
  end

  def test_git_failure_does_not_issue_auth_or_create_project
    @git_success = false

    error = assert_raises(RuntimeError) { Agent.start("work", runner: "t3", directory: @directory) }

    assert_equal "Could not list Git worktrees for T3", error.message
    assert_equal [], @commands
    assert_equal [], @requests
  end

  def test_missing_checkout_does_not_create_project
    @worktrees = porcelain([ Worktree.root, "master" ])

    assert_raises(RuntimeError) { Agent.start("work", runner: "t3", directory: @directory) }

    assert_equal [], @commands
    assert_equal [], @requests
  end

  def test_unrelated_missing_worktree_does_not_block_launch
    @worktrees = porcelain([ Worktree.root, "master" ], [ "/missing/old-card", "moto-1" ], [ @directory, "moto-73" ])

    Agent.start("work", runner: "t3", directory: @directory)

    assert_equal File.realpath(Worktree.root), dispatches.first[:workspaceRoot]
    assert_equal File.realpath(@directory), dispatches[1][:worktreePath]
  end

  def test_worktree_path_with_spaces_and_newlines
    directory = File.join(@worktree_test_dir, "card with\na newline")
    FileUtils.mkdir_p(directory)
    @worktrees = porcelain([ Worktree.root, "master" ], [ directory, "moto-73" ])

    Agent.start("work", runner: "t3", directory: directory)

    assert_equal File.realpath(directory), dispatches[1][:worktreePath]
    assert_equal "moto-73", dispatches[1][:branch]
  end

  def test_overrides_model_and_effort_and_resolves_alias
    Agent.start("work", runner: "t3", model: "codex/sol", variant: "medium")

    assert_equal "gpt-6.1-sol", dispatches.last.dig(:modelSelection, :model)
    assert_equal [ { id: "reasoningEffort", value: "medium" } ], options
  end

  def test_uses_custom_origin
    Settings.all[:agent][:t3][:url] = "http://127.0.0.1:4000"

    Agent.start("work", runner: "t3")

    assert @requests.all? { |item| item[:url].start_with?("http://127.0.0.1:4000/") }
  end

  def test_fast_and_normal_use_catalog_service_tiers
    Settings.all[:agent][:t3][:speed] = "fast"
    Agent.start("work", runner: "t3")
    assert_includes options, { id: "serviceTier", value: "priority" }

    Settings.all[:agent][:t3][:speed] = "normal"
    Agent.start("work", runner: "t3")
    assert_includes options, { id: "serviceTier", value: "default" }
  end

  def test_claude_provider_uses_effort_and_fast_mode
    @catalog[:instanceId] = "claudeAgent"
    @catalog[:models][0][:slug] = "claude-opus-5-5"
    @catalog[:models][0][:capabilities][:optionDescriptors] = [
      { id: "effort", options: [ { id: "high" } ] },
      { id: "fastMode", type: "boolean" },
    ]
    write_catalog("claudeAgent")
    Settings.all[:agent][:t3][:speed] = "fast"

    Agent.start("work", runner: "t3", model: "anthropic/claude-opus-5-5")

    assert_equal "claudeAgent", dispatches.last.dig(:modelSelection, :instanceId)
    assert_equal [ { id: "effort", value: "high" }, { id: "fastMode", value: true } ], options
    Settings.all[:agent][:t3][:speed] = "normal"
    Agent.start("work", runner: "t3", model: "anthropic/claude-opus-5-5")
    assert_includes options, { id: "fastMode", value: false }
  end

  def test_no_effort_or_speed_for_models_without_options
    @catalog[:models][0][:capabilities] = {}
    write_catalog
    Settings.all[:agent][:variant] = nil
    Settings.all[:agent][:t3][:speed] = "normal"

    Agent.start("work", runner: "t3")

    assert_empty options
  end

  def test_rejects_malformed_model_and_path_traversal_before_auth
    [ "", "openai/", "/model", "../model", "../../codex/model" ].each do |model|
      Settings.all[:agent][:model] = model
      assert_raises(RuntimeError) { Agent.start("work", runner: "t3") }
    end
    assert_empty @commands
    assert_empty @requests
  end

  def test_rejects_missing_disabled_and_unknown_models_before_auth
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3", model: "unknown/model") }
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3", model: "openai/nope") }
    @catalog[:enabled] = false
    write_catalog
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3") }
    assert_empty @commands
  end

  def test_rejects_unsupported_effort_and_speed_before_auth
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3", variant: "ultra") }
    Settings.all[:agent][:t3][:speed] = "slow"
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3") }
    Settings.all[:agent][:t3][:speed] = "fast"
    @catalog[:models][0][:capabilities][:optionDescriptors].pop
    write_catalog
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3") }
    assert_empty @commands
  end

  def test_auth_failure_does_not_send_requests_or_expose_output
    @auth_failure = "issue"
    error = assert_raises(RuntimeError) { Agent.start("work", runner: "t3") }

    assert_equal "T3 auth session issue failed", error.message
    assert_empty @requests
  end

  def test_thread_failure_revokes_auth_without_deleting_uncreated_thread
    @failure = "thread.create"
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3") }

    refute dispatches.any? { |item| item[:type] == "thread.delete" }
    assert_equal "revoke", @commands.last[4]
  end

  def test_turn_failure_removes_thread_and_revokes_auth
    @failure = "thread.turn.start"
    assert_raises(RuntimeError) { Agent.start("work", runner: "t3") }

    assert_equal "thread.delete", dispatches.last[:type]
    assert_equal dispatches[1][:threadId], dispatches.last[:threadId]
    assert_equal "revoke", @commands.last[4]
  end

  def test_revoke_failure_does_not_report_successful_launch_as_failed
    @auth_failure = "revoke"
    result = nil
    _, error = capture_io { result = Agent.start("work", runner: "t3") }

    assert result[:threadId].present?
    assert_includes error, "expires after five minutes"
    refute_includes error, "secret-error"
  end

  private

  def quota_socket(success: true)
    sent = []
    events = []
    socket = Object.new
    socket.define_singleton_method(:send) { |message| sent << message }
    socket.define_singleton_method(:close) { events << :closed }
    socket.define_singleton_method(:on) do |event, &callback|
      events << event
      callback.call if event == :open
      if event == :message
        callback.call(Struct.new(:data).new(JSON.generate(_tag: "Pong")))
        callback.call(Struct.new(:data).new(JSON.generate([
          { _tag: "Exit", requestId: "other", exit: { _tag: "Success" } },
          { _tag: "Exit", requestId: "1", exit: { _tag: success ? "Success" : "Failure" } },
        ])))
      end
    end
    [ socket, sent, events ]
  end

  def porcelain(*worktrees)
    worktrees.map do |path, branch|
      "worktree #{path}\0HEAD abc\0#{branch.present? ? "branch refs/heads/#{branch}" : "detached"}\0\0"
    end.join
  end

  def write_catalog(instance = "codex")
    FileUtils.mkdir_p(File.join(@home, "caches"))
    File.write(File.join(@home, "caches", "#{instance}.json"), JSON.generate(@catalog))
  end

  def dispatches
    @requests.filter_map { |item| item[:payload] }
  end

  def options
    dispatches.last.dig(:modelSelection, :options)
  end
end
