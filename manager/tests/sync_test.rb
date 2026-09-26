require_relative "test_helper"

class SyncTest < Minitest::Test
  def test_syncs_statuses_and_tags_without_triggering
    calls = stub_sync(states: unsynced_states, tags: [], git_automations: default_git_automations)

    output, = capture_io { Sync.call }

    assert calls.any? { |call| graphql?(call, "query Workspace") }
    assert calls.any? { |call| graphql?(call, "query States") }
    assert calls.any? { |call| graphql?(call, "query Tags") }
    assert calls.any? { |call| graphql?(call, "query GitAutomationStates") }
    assert calls.any? { |call| graphql?(call, "mutation WorkflowState") }
    assert calls.any? { |call| graphql?(call, "mutation IssueLabelCreate") }
    deletes = calls.select { |call| graphql?(call, "mutation GitAutomationStateDelete") }
    assert_equal [ "ga-start", "ga-review", "ga-merge" ], deletes.map { |call| call.dig(:payload, :variables, :id) }
    assert_empty calls.select { |call| graphql?(call, "query Issues") }
    assert_empty calls.select { |call| graphql?(call, "mutation IssueUpdate") }
    assert_empty calls.select { |call| call[:url].to_s.end_with?("/api/openchamber/sessions") }
    assert_includes output, "created Working"
    assert_includes output, "created working tag"
    assert_includes output, "removed git automation start (In Progress)"
    refute_includes output, "started working"
  end

  def test_is_noop_when_already_synced
    calls = stub_sync

    output, = capture_io { Sync.call }

    assert_equal "", output
    assert_empty calls.select { |call| graphql?(call, "mutation WorkflowState") }
    assert_empty calls.select { |call| graphql?(call, "mutation IssueLabelCreate") }
    assert_empty calls.select { |call| graphql?(call, "mutation IssueLabelUpdate") }
    assert_empty calls.select { |call| graphql?(call, "mutation GitAutomationStateDelete") }
    assert_empty calls.select { |call| graphql?(call, "query Issues") }
    assert_empty calls.select { |call| graphql?(call, "mutation IssueUpdate") }
  end

  def test_reraises_http_errors
    Req.stubs(:call).raises(Faraday::ConnectionFailed.new("Failed to open TCP connection to api.linear.app"))

    error = assert_raises(Faraday::ConnectionFailed) { Sync.call }

    assert_equal "Failed to open TCP connection to api.linear.app", error.message
  end

  private

  def graphql?(opts, fragment)
    opts[:url] == Linear::HOST && opts.dig(:payload, :query).to_s.include?(fragment)
  end

  def synced_states
    Linear::STATUSES.each_with_index.map do |status, index|
      position = index.to_f
      { id: "s-#{status[:name].downcase}", **status, position: }
    end
  end

  def synced_tags
    Linear::TAGS.map do |tag|
      { id: "l-#{tag[:name].downcase}", **tag }
    end
  end

  def unsynced_states
    [
      { id: "s-backlog", name: "Backlog", type: "backlog", color: "#f2994a", position: 0.0 },
      { id: "s-todo", name: "Todo", type: "unstarted", color: "#e2e2e2", position: 1.0 },
      { id: "s-progress", name: "In Progress", type: "started", color: "#f2c94c", position: 2.0 },
      { id: "s-done", name: "Done", type: "completed", color: "#5e6ad2", position: 3.0 },
      { id: "s-canceled", name: "Canceled", type: "canceled", color: "#95a2b3", position: 4.0 },
    ]
  end

  def default_git_automations
    [
      { id: "ga-start", event: "start", state: { name: "In Progress" } },
      { id: "ga-review", event: "review", state: { name: "In Review" } },
      { id: "ga-merge", event: "merge", state: { name: "Done" } },
    ]
  end

  def stub_sync(states: nil, tags: nil, git_automations: nil)
    calls = []
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Workspace")

      calls << opts
      true
    end.returns(
      {
        data: {
          organization: { urlKey: "gotte" },
          teams: { nodes: [ { id: "team-1", key: "MOTO" } ] },
        },
      },
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query States")

      calls << opts
      true
    end.returns(
      {
        data: {
          team: {
            states: {
              nodes: states || synced_states,
            },
          },
        },
      },
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Tags")

      calls << opts
      true
    end.returns(
      {
        data: {
          team: {
            labels: {
              nodes: tags || synced_tags,
            },
          },
        },
      },
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation WorkflowStateCreate")

      calls << opts
      true
    end.returns({ data: { workflowStateCreate: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation WorkflowStateUpdate")

      calls << opts
      true
    end.returns({ data: { workflowStateUpdate: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation WorkflowStateArchive")

      calls << opts
      true
    end.returns({ data: { workflowStateArchive: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation IssueLabelCreate")

      calls << opts
      true
    end.returns({ data: { issueLabelCreate: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation IssueLabelUpdate")

      calls << opts
      true
    end.returns({ data: { issueLabelUpdate: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query GitAutomationStates")

      calls << opts
      true
    end.returns(
      {
        data: {
          team: {
            gitAutomationStates: {
              nodes: git_automations || [],
            },
          },
        },
      },
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation GitAutomationStateDelete")

      calls << opts
      true
    end.returns({ data: { gitAutomationStateDelete: { success: true } } })
    calls
  end
end
