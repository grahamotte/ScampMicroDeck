require_relative "test_helper"

class LinearTest < Minitest::Test
  def test_issues_unwraps_nodes
    calls = stub_linear(
      issues: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" } },
      ],
    )

    assert_equal "item-1", Linear.issues.first.fetch(:id)
    query = calls.find { |call| graphql?(call, "query Issues") }
    assert_equal({ teamId: "team-1" }, query.dig(:payload, :variables))
  end

  def test_issues_paginates
    calls = stub_linear
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Issues")

      calls << opts
      true
    end.returns(
      {
        data: {
          team: {
            issues: {
              nodes: [ { id: "item-1", identifier: "MOTO-1" } ],
              pageInfo: { hasNextPage: true, endCursor: "cursor-1" },
            },
          },
        },
      },
      {
        data: {
          team: {
            issues: {
              nodes: [ { id: "item-2", identifier: "MOTO-2" } ],
              pageInfo: { hasNextPage: false, endCursor: nil },
            },
          },
        },
      },
    )

    filter = { updatedAt: { gte: "-P30D" } }
    assert_equal [ "item-1", "item-2" ], Linear.issues(filter:).map { |item| item.fetch(:id) }
    queries = calls.select { |call| graphql?(call, "query Issues") }
    assert_equal [
      { teamId: "team-1", filter: },
      { teamId: "team-1", after: "cursor-1", filter: },
    ], queries.map { |call| call.dig(:payload, :variables) }.uniq
    queries.each do |call|
      assert_includes call.dig(:payload, :query), "$filter: IssueFilter"
      assert_includes call.dig(:payload, :query), "filter: $filter"
    end
  end

  def test_column_from_state_name
    assert_equal "working", Linear.column({ state: { id: "s-working", name: "Working" } })
  end

  def test_column_from_robot_state_name
    assert_equal "approved", Linear.column({ state: { id: "s-approved", name: "🤖 Approved" } })
  end

  def test_state_names_include_robot_and_plain_names
    assert_equal [ "🤖 Working", "Working", "Completed" ], Linear.state_names("working", "completed")
  end

  def test_column_from_state_id
    stub_linear

    assert_equal "approved", Linear.column({ state: "s-approved" })
  end

  def test_column_blank_without_state
    assert_nil Linear.column({})
  end

  def test_move_updates_state_id
    calls = stub_linear

    Linear.move({ id: "item-1" }, "working")

    payload = calls.find { |call| graphql?(call, "mutation IssueUpdate") }
    assert_equal Linear::HOST, payload.fetch(:url)
    assert_equal :post, payload.fetch(:method)
    assert_equal({ id: "item-1", input: { stateId: "s-working" } }, payload.dig(:payload, :variables))
    assert_equal({ "Authorization" => "linear-token" }, payload.fetch(:headers))
  end

  def test_tag_adds_label
    calls = stub_linear

    Linear.tag({ id: "item-1" }, "working")

    payload = calls.find { |call| graphql?(call, "mutation IssueUpdate") }
    assert_equal({ id: "item-1", input: { addedLabelIds: [ "l-working" ] } }, payload.dig(:payload, :variables))
  end

  def test_untag_removes_label
    calls = stub_linear

    Linear.untag({ id: "item-1" }, "working")

    payload = calls.find { |call| graphql?(call, "mutation IssueUpdate") }
    assert_equal({ id: "item-1", input: { removedLabelIds: [ "l-working" ] } }, payload.dig(:payload, :variables))
  end

  def test_tag_raises_for_unknown_tag
    stub_linear

    error = assert_raises(RuntimeError) { Linear.tag({ id: "item-1" }, "nope") }

    assert_equal 'Linear tag "nope" not found', error.message
  end

  def test_tagged_from_label_names
    assert Linear.tagged?({ labels: { nodes: [ { id: "l-working", name: "working" } ] } }, "working")
    assert Linear.tagged?({ labels: { nodes: [ { id: "l-working", name: "Working" } ] } }, "working")
    refute Linear.tagged?({ labels: { nodes: [ { id: "l-bug", name: "bug" } ] } }, "working")
    refute Linear.tagged?({ labels: { nodes: [] } }, "working")
    refute Linear.tagged?({}, "working")
  end

  def test_sync_tags_creates_missing_tags
    calls = stub_linear(tags: [])

    output, = capture_io { Linear.sync_tags }

    creates = calls.select { |call| graphql?(call, "mutation IssueLabelCreate") }.map { |call| call.dig(:payload, :variables, :input) }
    assert_equal Linear::TAGS.map { |tag| { teamId: "team-1", **tag } }, creates
    assert_includes output, "created working tag"
    assert_includes creates, { teamId: "team-1", name: "skip review", color: "#4cb782" }
    assert_includes output, "created skip review tag"
    assert_includes output, "created variant: high tag"
    assert_includes output, "created model: xai/grok-4.7 tag"
  end

  def test_sync_tags_renames_interactive_in_place_without_removing_assignments
    tags = synced_tags.map do |tag|
      tag[:name] == "runner: interactive" ? tag.merge(id: "existing-interactive", name: "interactive") : tag
    end
    calls = stub_linear(tags:)

    output, = capture_io { Linear.sync_tags }

    updates = calls.select { |call| graphql?(call, "mutation IssueLabelUpdate") }
    assert_equal [ { id: "existing-interactive", input: { name: "runner: interactive" } } ], updates.map { |call| call.dig(:payload, :variables) }
    assert_empty calls.select { |call| graphql?(call, "mutation IssueLabelCreate") || graphql?(call, "mutation IssueLabelDelete") }
    assert_includes output, "renamed interactive to runner: interactive"
  end

  def test_sync_tags_rejects_conflicting_interactive_labels_before_mutating
    calls = stub_linear(tags: synced_tags + [ { id: "legacy", name: "interactive", team: { id: "team-1" } } ])

    error = assert_raises(RuntimeError) { Linear.sync_tags }

    assert_includes error.message, "Merge the interactive and runner: interactive labels"
    assert_empty calls.select { |call| graphql?(call, "mutation") }
  end

  def test_sync_tags_removes_unknown_team_and_workspace_tags
    calls = stub_linear(tags: synced_tags + [
      { id: "old", name: "old model", team: { id: "team-1" } },
      { id: "shared", name: "shared", team: nil },
      { id: "other", name: "other team", team: { id: "team-2" } },
    ])

    output, = capture_io { Linear.sync_tags }

    deletes = calls.select { |call| graphql?(call, "mutation IssueLabelDelete") }
    assert_equal [ "old", "shared" ], deletes.map { |call| call.dig(:payload, :variables, :id) }
    assert_includes output, "removed old model tag"
  end

  def test_sync_tags_matches_names_case_insensitively
    calls = stub_linear(tags: synced_tags.map { |tag| tag.merge(name: tag[:name].upcase) })

    output, = capture_io { Linear.sync_tags }

    assert_empty calls.select { |call| graphql?(call, "mutation") }
    assert_equal "", output
  end

  def test_sync_tags_paginates_before_removing_unknown_tags
    calls = stub_linear
    pages = [
      { nodes: synced_tags, pageInfo: { hasNextPage: true, endCursor: "next" } },
      { nodes: [ { id: "old", name: "old", team: { id: "team-1" } } ], pageInfo: { hasNextPage: false } },
    ]
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Tags")

      calls << opts
      true
    end.returns(*pages.map { |page| { data: { team: { labels: page } } } })

    capture_io { Linear.sync_tags }

    queries = calls.select { |call| graphql?(call, "query Tags") }
    assert_equal [ { teamId: "team-1" }, { teamId: "team-1", after: "next" } ], queries.map { |call| call.dig(:payload, :variables) }.uniq
    assert calls.any? { |call| graphql?(call, "mutation IssueLabelDelete") && call.dig(:payload, :variables, :id) == "old" }
  end

  def test_runner_from_label_and_missing_runner
    assert_equal "t3", Linear.runner({ labels: { nodes: [ { name: "Runner: t3" } ] } })
    assert_nil Linear.runner({})
    assert_nil Linear.runner({ labels: { nodes: [ { name: "runner:" } ] } })
  end

  def test_sync_tags_is_noop_when_already_synced
    calls = stub_linear

    output, = capture_io { Linear.sync_tags }

    assert_empty calls.select { |call| graphql?(call, "mutation IssueLabelCreate") }
    assert_empty calls.select { |call| graphql?(call, "mutation IssueLabelUpdate") }
    assert_equal "", output
  end

  def test_sync_tags_updates_mismatched_color
    calls = stub_linear(tags: synced_tags.map { |tag| tag[:name] == "working" ? tag.merge(color: "#eb5757") : tag })

    output, = capture_io { Linear.sync_tags }

    updates = calls.select { |call| graphql?(call, "mutation IssueLabelUpdate") }.map { |call| call.dig(:payload, :variables) }
    assert_equal [ { id: "l-working", input: { color: "#f2c94c" } } ], updates
    assert_empty calls.select { |call| graphql?(call, "mutation IssueLabelCreate") }
    assert_equal "", output
  end

  def test_identifier
    assert_equal "MOTO-1", Linear.identifier({ identifier: "MOTO-1" })
  end

  def test_url
    assert_equal "https://linear.app/gotte/issue/MOTO-1", Linear.url({ url: "https://linear.app/gotte/issue/MOTO-1" })
  end

  def test_model_from_label
    assert_equal(
      "xai/grok-4.7",
      Linear.model({ labels: { nodes: [ { id: "l-model", name: "model: xai/grok-4.7" } ] } }),
    )
  end

  def test_variant_from_label
    assert_equal(
      "medium",
      Linear.variant({ labels: { nodes: [ { id: "l-variant", name: "variant: medium" } ] } }),
    )
  end

  def test_model_and_variant_are_case_insensitive_keys
    item = {
      labels: {
        nodes: [
          { id: "l-model", name: "Model: Anthropic/Claude" },
          { id: "l-variant", name: "VARIANT: high" },
        ],
      },
    }

    assert_equal "Anthropic/Claude", Linear.model(item)
    assert_equal "high", Linear.variant(item)
  end

  def test_model_and_variant_nil_without_matching_labels
    item = { labels: { nodes: [ { id: "l-working", name: "working" } ] } }

    assert_nil Linear.model(item)
    assert_nil Linear.variant(item)
    assert_nil Linear.model({})
    assert_nil Linear.variant({ labels: { nodes: [] } })
    assert_nil Linear.model({ labels: { nodes: [ { id: "l-model", name: "model:" } ] } })
  end

  def test_selects_team_by_key
    calls = stub_linear(
      teams: [
        { id: "other", key: "OTHER" },
        { id: "team-1", key: "MOTO" },
      ],
    )

    Linear.move({ id: "item-1" }, "working")

    workspace = calls.find { |call| graphql?(call, "query Workspace") }
    assert_equal({ key: "MOTO" }, workspace.dig(:payload, :variables))
    states = calls.find { |call| graphql?(call, "query States") }
    assert_equal({ teamId: "team-1" }, states.dig(:payload, :variables))
  end

  def test_rejects_wrong_workspace
    stub_linear(organization: "acme")

    error = assert_raises(RuntimeError) { Linear.issues }

    assert_equal "Linear workspace is \"acme\", expected \"gotte\"", error.message
  end

  def test_rejects_missing_team
    stub_linear(teams: [ { id: "other", key: "OTHER" } ])

    error = assert_raises(RuntimeError) { Linear.issues }

    assert_equal "Linear team \"MOTO\" not found", error.message
  end

  def test_raises_graphql_errors
    stub_linear
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Workspace")

      true
    end.returns({ errors: [ { message: "Invalid token" } ] })

    error = assert_raises(RuntimeError) { Linear.issues }

    assert_equal "Invalid token", error.message
  end

  def test_includes_user_presentable_graphql_error
    stub_linear
    Req.stubs(:call).returns(
      {
        errors: [
          {
            message: "Forbidden",
            extensions: { userPresentableMessage: "You are not allowed to update workflow states for this team" },
          },
        ],
      },
    )

    error = assert_raises(RuntimeError) { Linear.issues }

    assert_equal "Forbidden: You are not allowed to update workflow states for this team", error.message
  end

  def test_does_not_repeat_identical_graphql_error_detail
    stub_linear
    Req.stubs(:call).returns(
      { errors: [ { message: "Forbidden", extensions: { userPresentableMessage: "Forbidden" } } ] },
    )

    error = assert_raises(RuntimeError) { Linear.issues }

    assert_equal "Forbidden", error.message
  end

  def test_sync_statuses_renames_creates_and_removes
    calls = stub_linear(states: default_linear_states)

    output, = capture_io { Linear.sync_statuses }

    updates = calls.select { |call| graphql?(call, "mutation WorkflowStateUpdate") }.map { |call| call.dig(:payload, :variables) }
    creates = calls.select { |call| graphql?(call, "mutation WorkflowStateCreate") }.map { |call| call.dig(:payload, :variables, :input) }
    archives = calls.select { |call| graphql?(call, "mutation WorkflowStateArchive") }.map { |call| call.dig(:payload, :variables, :id) }

    assert_equal "Planned", updates.find { |variables| variables[:id] == "s-todo" }.dig(:input, :name)
    assert_equal "🤖 Working", updates.find { |variables| variables[:id] == "s-progress" }.dig(:input, :name)
    assert_nil updates.find { |variables| variables[:id] == "s-progress" }.dig(:input, :color)
    assert_equal "Completed", updates.find { |variables| variables[:id] == "s-done" }.dig(:input, :name)
    assert_equal [ "Review", "🤖 Approved" ], creates.map { |input| input[:name] }
    assert_equal [ 1000.0, 2000.0 ], creates.map { |input| input[:position] }
    refute updates.any? { |variables| variables.dig(:input, :position).present? }
    assert_equal [ "s-groom" ], archives
    assert_includes output, "renamed Todo to Planned"
    assert_includes output, "renamed In Progress to 🤖 Working"
    assert_includes output, "renamed Done to Completed"
    assert_includes output, "created Review"
    assert_includes output, "created 🤖 Approved"
    assert_includes output, "removed Grooming"
    refute_includes output, "removed Duplicate"
    refute_includes archives, "s-dup"
  end

  def test_sync_statuses_adds_robot_to_plain_agent_columns
    states = synced_states.map { |status| status.merge(name: status[:name].delete_prefix(Linear::ROBOT).strip) }
    calls = stub_linear(states:)

    output, = capture_io { Linear.sync_statuses }

    updates = calls.select { |call| graphql?(call, "mutation WorkflowStateUpdate") }.map { |call| call.dig(:payload, :variables) }
    assert_equal [
      { id: "s-working", input: { name: "🤖 Working" } },
      { id: "s-approved", input: { name: "🤖 Approved" } },
    ], updates
    assert_empty calls.select { |call| graphql?(call, "mutation WorkflowStateCreate") }
    assert_empty calls.select { |call| graphql?(call, "mutation WorkflowStateArchive") }
    assert_includes output, "renamed Working to 🤖 Working"
    assert_includes output, "renamed Approved to 🤖 Approved"
  end

  def test_sync_statuses_merges_ready_into_working
    states = [
      { id: "s-backlog", name: "Backlog", type: "backlog", color: "#f2994a", position: 0.0 },
      { id: "s-planned", name: "Planned", type: "unstarted", color: "#95a2b3", position: 1.0 },
      { id: "s-ready", name: "🤖 Ready", type: "started", color: "#26b5ce", position: 2.0 },
      { id: "s-working", name: "Working", type: "started", color: "#f2c94c", position: 3.0 },
      { id: "s-review", name: "Review", type: "started", color: "#f2994a", position: 4.0 },
      { id: "s-approved", name: "🤖 Approved", type: "started", color: "#4cb782", position: 5.0 },
      { id: "s-completed", name: "Completed", type: "completed", color: "#5e6ad2", position: 6.0 },
      { id: "s-canceled", name: "Canceled", type: "canceled", color: "#95a2b3", position: 7.0 },
    ]
    calls = stub_linear(states:)
    synced = states.reject { |state| state[:id] == "s-ready" }.map do |state|
      state[:id] == "s-working" ? state.merge(name: "🤖 Working") : state
    end
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query States")

      calls << opts
      true
    end.returns(
      { data: { team: { states: { nodes: states } } } },
      { data: { team: { states: { nodes: states.map { |state| state[:id] == "s-working" ? state.merge(name: "🤖 Working") : state } } } } },
      { data: { team: { states: { nodes: synced } } } },
    )
    working_issues = [
      { id: "item-claimed", identifier: "MOTO-1", labels: { nodes: [ { name: "working" } ] } },
      { id: "item-interactive", identifier: "MOTO-2", labels: { nodes: [ { name: "runner: interactive" } ] } },
      { id: "item-parked", identifier: "MOTO-3", labels: { nodes: [] } },
    ]
    ready_issues = [
      { id: "item-queued", identifier: "MOTO-4", labels: { nodes: [] } },
      { id: "item-ready-claimed", identifier: "MOTO-5", labels: { nodes: [ { name: "working" } ] } },
    ]
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Issues")

      calls << opts
      true
    end.returns(
      { data: { team: { issues: { nodes: working_issues, pageInfo: { hasNextPage: false, endCursor: nil } } } } },
      { data: { team: { issues: { nodes: ready_issues, pageInfo: { hasNextPage: false, endCursor: nil } } } } },
    )

    output, = capture_io { Linear.sync_statuses }

    filters = calls.select { |call| graphql?(call, "query Issues") }.map { |call| call.dig(:payload, :variables, :filter) }.uniq
    assert_equal [ { state: { id: { eq: "s-working" } } }, { state: { id: { eq: "s-ready" } } } ], filters
    moves = calls.select { |call| graphql?(call, "mutation IssueUpdate") }.map { |call| call.dig(:payload, :variables) }
    assert_equal [
      { id: "item-parked", input: { stateId: "s-planned" } },
      { id: "item-queued", input: { stateId: "s-working" } },
      { id: "item-ready-claimed", input: { stateId: "s-working" } },
    ], moves
    archives = calls.select { |call| graphql?(call, "mutation WorkflowStateArchive") }.map { |call| call.dig(:payload, :variables, :id) }
    assert_equal [ "s-ready" ], archives
    assert_operator calls.index { |call| graphql?(call, "mutation IssueUpdate") }, :<, calls.index { |call| graphql?(call, "mutation WorkflowStateArchive") }
    assert_equal [
      "renamed Working to 🤖 Working",
      "moved MOTO-3 from 🤖 Working to Planned",
      "moved MOTO-4 from 🤖 Ready to 🤖 Working",
      "moved MOTO-5 from 🤖 Ready to 🤖 Working",
      "removed 🤖 Ready",
    ], output.lines.map(&:chomp)
  end

  def test_move_resolves_robot_column_by_plain_name
    calls = stub_linear(states: synced_states)

    Linear.move({ id: "item-1" }, "approved")

    update = calls.find { |call| graphql?(call, "mutation IssueUpdate") }
    assert_equal({ stateId: "s-approved" }, update.dig(:payload, :variables, :input))
  end

  def test_sync_statuses_skips_reserved_archive_errors
    stub_linear(
      states: synced_states + [
        { id: "s-old", name: "Old", type: "started", color: "#f2c94c", position: 9.0 },
      ],
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation WorkflowStateArchive")

      true
    end.returns({ errors: [ { message: "unable to delete reserved state" } ] })

    output, = capture_io { Linear.sync_statuses }

    refute_includes output, "removed Old"
  end

  def test_sync_statuses_is_noop_when_already_synced
    calls = stub_linear(states: synced_states)

    output, = capture_io { Linear.sync_statuses }

    assert_empty calls.select { |call| graphql?(call, "mutation") }
    assert_equal "", output
  end

  def test_sync_statuses_is_noop_when_linear_ranks_preserve_order
    calls = stub_linear(states: ranked_started_states(working: 1000.0, review: 2000.0, approved: 3000.0))

    output, = capture_io { Linear.sync_statuses }

    assert_empty calls.select { |call| graphql?(call, "mutation") }
    assert_equal "", output
  end

  def test_sync_statuses_reorders_started_group
    states = ranked_started_states(working: 3000.0, review: 2000.0, approved: 1000.0)
    states << { id: "s-dup", name: "Duplicate", type: "duplicate", color: "#95a2b3", position: 9000.0 }
    calls = stub_linear(states:)

    output, = capture_io { Linear.sync_statuses }

    updates = calls.select { |call| graphql?(call, "mutation WorkflowStateUpdate") }.map { |call| call.dig(:payload, :variables) }
    assert_equal [
      { id: "s-working", input: { position: 10000.0 } },
      { id: "s-review", input: { position: 11000.0 } },
      { id: "s-approved", input: { position: 12000.0 } },
    ], updates
    assert_equal "", output
  end

  def test_sync_statuses_reorders_tied_positions
    calls = stub_linear(states: ranked_started_states(working: 0.0, review: 0.0, approved: 0.0))

    capture_io { Linear.sync_statuses }

    updates = calls.select { |call| graphql?(call, "mutation WorkflowStateUpdate") }.map { |call| call.dig(:payload, :variables) }
    assert_equal [
      { id: "s-working", input: { position: 1000.0 } },
      { id: "s-review", input: { position: 2000.0 } },
      { id: "s-approved", input: { position: 3000.0 } },
    ], updates
  end

  def test_sync_statuses_clears_descriptions
    states = synced_states.map do |status|
      description = status[:name] == "🤖 Working" ? "Pull request is being reviewed" : ""
      status.merge(description:)
    end
    calls = stub_linear(states:)

    capture_io { Linear.sync_statuses }

    updates = calls.select { |call| graphql?(call, "mutation WorkflowStateUpdate") }.map { |call| call.dig(:payload, :variables) }
    assert_equal Linear::STATUSES.map { |status|
      { id: "s-#{column_key(status[:name])}", input: { description: nil } }
    }, updates
  end

  def test_sync_statuses_uses_token_workspace_and_team
    calls = stub_linear(states: synced_states)

    capture_io { Linear.sync_statuses }

    workspace = calls.find { |call| graphql?(call, "query Workspace") }
    assert_equal({ "Authorization" => "linear-token" }, workspace.fetch(:headers))
    assert_equal({ key: "MOTO" }, workspace.dig(:payload, :variables))
  end

  def test_sync_git_automations_deletes_rules
    calls = stub_linear(git_automations: default_git_automations)

    output, = capture_io { Linear.sync_git_automations }

    deletes = calls.select { |call| graphql?(call, "mutation GitAutomationStateDelete") }
    query = calls.find { |call| graphql?(call, "query GitAutomationStates") }
    assert_equal({ teamId: "team-1" }, query.dig(:payload, :variables))
    assert_equal [ "ga-start", "ga-review", "ga-merge" ], deletes.map { |call| call.dig(:payload, :variables, :id) }
    assert_includes output, "removed git automation start (In Progress)"
    assert_includes output, "removed git automation review (In Review)"
    assert_includes output, "removed git automation merge (Done)"
  end

  def test_sync_git_automations_is_noop_when_none
    calls = stub_linear

    output, = capture_io { Linear.sync_git_automations }

    assert_empty calls.select { |call| graphql?(call, "mutation GitAutomationStateDelete") }
    assert calls.any? { |call| graphql?(call, "query GitAutomationStates") }
    assert_equal "", output
  end

  private

  def graphql?(opts, fragment)
    opts[:url] == Linear::HOST && opts.dig(:payload, :query).to_s.include?(fragment)
  end

  def default_linear_states
    [
      { id: "s-backlog", name: "Backlog", type: "backlog", color: "#f2994a", position: 0.0 },
      { id: "s-todo", name: "Todo", type: "unstarted", color: "#e2e2e2", position: 1.0 },
      { id: "s-groom", name: "Grooming", type: "unstarted", color: "#e2e2e2", position: 1.5 },
      { id: "s-progress", name: "In Progress", type: "started", color: "#f2c94c", position: 2.0 },
      { id: "s-done", name: "Done", type: "completed", color: "#5e6ad2", position: 3.0 },
      { id: "s-canceled", name: "Canceled", type: "canceled", color: "#95a2b3", position: 4.0 },
      { id: "s-dup", name: "Duplicate", type: "duplicate", color: "#95a2b3", position: 5.0 },
    ]
  end

  def synced_states
    Linear::STATUSES.each_with_index.map do |status, index|
      position = index.to_f
      { id: "s-#{column_key(status[:name])}", **status, position: }
    end
  end

  def column_key(name)
    name.delete_prefix(Linear::ROBOT).strip.downcase
  end

  def synced_tags
    Linear::TAGS.map do |tag|
      { id: "l-#{tag[:name].downcase}", **tag }
    end
  end

  def ranked_started_states(working:, review:, approved:)
    Linear::STATUSES.map do |status|
      position = case column_key(status[:name])
      when "working" then working
      when "review" then review
      when "approved" then approved
      else 0.0
      end
      { id: "s-#{column_key(status[:name])}", **status, position: }
    end
  end

  def default_git_automations
    [
      { id: "ga-start", event: "start", state: { name: "In Progress" } },
      { id: "ga-review", event: "review", state: { name: "In Review" } },
      { id: "ga-merge", event: "merge", state: { name: "Done" } },
    ]
  end

  def stub_linear(organization: "gotte", teams: nil, states: nil, issues: nil, tags: nil, git_automations: nil)
    calls = []
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Workspace")

      calls << opts
      true
    end.returns(
      {
        data: {
          organization: { urlKey: organization },
          teams: { nodes: teams || [ { id: "team-1", key: "MOTO" } ] },
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
              nodes: states || [
                { id: "s-ready", name: "Ready", type: "started", color: "#f2c94c", position: 2.0 },
                { id: "s-working", name: "Working", type: "started", color: "#f2c94c", position: 3.0 },
                { id: "s-approved", name: "Approved", type: "started", color: "#f2c94c", position: 5.0 },
              ],
            },
          },
        },
      },
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Issues")

      calls << opts
      true
    end.returns(
      {
        data: {
          team: {
            issues: {
              nodes: issues || [],
              pageInfo: { hasNextPage: false, endCursor: nil },
            },
          },
        },
      },
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation IssueUpdate")

      calls << opts
      true
    end.returns({ data: { issueUpdate: { success: true } } })
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
      next false unless graphql?(opts, "mutation IssueLabelDelete")

      calls << opts
      true
    end.returns({ data: { issueLabelDelete: { success: true } } })
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
