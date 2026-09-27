require_relative "test_helper"

class LinearTest < Minitest::Test
  def test_issues_unwraps_nodes
    stub_linear(
      issues: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" } },
      ],
    )

    assert_equal "item-1", Linear.issues.first.fetch(:id)
  end

  def test_issues_paginates
    stub_linear
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Issues")

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

    assert_equal [ "item-1", "item-2" ], Linear.issues.map { |item| item.fetch(:id) }
  end

  def test_column_from_state_name
    assert_equal "ready", Linear.column({ state: { id: "s-ready", name: "Ready" } })
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

  def test_issue_fetches_by_identifier
    calls = stub_linear(issue: { id: "item-1", identifier: "MOTO-1", title: "Fix it", team: { key: "MOTO" } })

    assert_equal "Fix it", Linear.issue("MOTO-1").fetch(:title)

    payload = calls.find { |call| graphql?(call, "query Issue(") }
    assert_equal({ id: "MOTO-1" }, payload.dig(:payload, :variables))
    assert calls.any? { |call| graphql?(call, "query Workspace") }
  end

  def test_issue_rejects_other_team
    stub_linear(issue: { id: "item-1", identifier: "APP-1", team: { key: "APP" } })

    error = assert_raises(RuntimeError) { Linear.issue("APP-1") }

    assert_equal 'Linear issue APP-1 is in team "APP", expected "MOTO"', error.message
  end

  def test_issue_checks_workspace_before_fetching
    calls = stub_linear(organization: "other")

    error = assert_raises(RuntimeError) { Linear.issue("MOTO-1") }

    assert_equal 'Linear workspace is "other", expected "gotte"', error.message
    assert_empty calls.select { |call| graphql?(call, "query Issue(") }
  end

  def test_create_issue
    calls = stub_linear(
      created: { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2" },
    )

    issue = Linear.create("New card", "Do the thing", "working")

    assert_equal "MOTO-2", issue.fetch(:identifier)
    assert_equal "https://linear.app/gotte/issue/MOTO-2", issue.fetch(:url)
    payload = calls.find { |call| graphql?(call, "mutation IssueCreate") }
    assert_equal(
      {
        input: {
          teamId: "team-1",
          title: "New card",
          description: "Do the thing",
          stateId: "s-working",
        },
      },
      payload.dig(:payload, :variables),
    )
  end

  def test_create_omits_blank_description
    calls = stub_linear

    Linear.create("New card", nil, "working")

    payload = calls.find { |call| graphql?(call, "mutation IssueCreate") }
    assert_equal(
      { input: { teamId: "team-1", title: "New card", stateId: "s-working" } },
      payload.dig(:payload, :variables),
    )
  end

  def test_comment_creates_comment
    calls = stub_linear

    Linear.comment({ id: "item-1" }, "Done")

    payload = calls.find { |call| graphql?(call, "mutation CommentCreate") }
    assert_equal({ input: { issueId: "item-1", body: "Done" } }, payload.dig(:payload, :variables))
  end

  def test_link_attaches_url_with_title
    calls = stub_linear

    Linear.link({ id: "item-1" }, "https://github.com/o/r/pull/1", "PR")

    payload = calls.find { |call| graphql?(call, "mutation AttachmentLinkURL") }
    assert_equal(
      { issueId: "item-1", url: "https://github.com/o/r/pull/1", title: "PR" },
      payload.dig(:payload, :variables),
    )
  end

  def test_link_omits_blank_title
    calls = stub_linear

    Linear.link({ id: "item-1" }, "https://github.com/o/r/pull/1", nil)

    payload = calls.find { |call| graphql?(call, "mutation AttachmentLinkURL") }
    assert_equal({ issueId: "item-1", url: "https://github.com/o/r/pull/1" }, payload.dig(:payload, :variables))
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
    assert_includes output, "created variant: high tag"
    assert_includes output, "created model: xai/grok-4.6 tag"
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
      "xai/grok-4.6",
      Linear.model({ labels: { nodes: [ { id: "l-model", name: "model: xai/grok-4.6" } ] } }),
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

  def test_sync_statuses_renames_creates_and_removes
    calls = stub_linear(states: default_linear_states)

    output, = capture_io { Linear.sync_statuses }

    updates = calls.select { |call| graphql?(call, "mutation WorkflowStateUpdate") }.map { |call| call.dig(:payload, :variables) }
    creates = calls.select { |call| graphql?(call, "mutation WorkflowStateCreate") }.map { |call| call.dig(:payload, :variables, :input) }
    archives = calls.select { |call| graphql?(call, "mutation WorkflowStateArchive") }.map { |call| call.dig(:payload, :variables, :id) }

    assert_equal "Planned", updates.find { |variables| variables[:id] == "s-todo" }.dig(:input, :name)
    assert_equal "Ready", updates.find { |variables| variables[:id] == "s-progress" }.dig(:input, :name)
    assert_equal "#26b5ce", updates.find { |variables| variables[:id] == "s-progress" }.dig(:input, :color)
    assert_equal "Completed", updates.find { |variables| variables[:id] == "s-done" }.dig(:input, :name)
    assert_equal [ "Working", "Review", "Approved" ], creates.map { |input| input[:name] }
    assert_equal [ 3.0, 4.0, 5.0 ], creates.map { |input| input[:position] }
    refute updates.any? { |variables| variables.dig(:input, :position).present? }
    assert_equal [ "s-groom" ], archives
    assert_includes output, "renamed Todo to Planned"
    assert_includes output, "renamed In Progress to Ready"
    assert_includes output, "renamed Done to Completed"
    assert_includes output, "created Working"
    assert_includes output, "created Review"
    assert_includes output, "created Approved"
    assert_includes output, "removed Grooming"
    refute_includes output, "removed Duplicate"
    refute_includes archives, "s-dup"
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
    calls = stub_linear(states: ranked_started_states(ready: 0.0, working: 1000.0, review: 2000.0, approved: 3000.0))

    output, = capture_io { Linear.sync_statuses }

    assert_empty calls.select { |call| graphql?(call, "mutation") }
    assert_equal "", output
  end

  def test_sync_statuses_reorders_started_group
    calls = stub_linear(states: ranked_started_states(ready: 0.0, working: 3000.0, review: 2000.0, approved: 1000.0))

    output, = capture_io { Linear.sync_statuses }

    updates = calls.select { |call| graphql?(call, "mutation WorkflowStateUpdate") }.map { |call| call.dig(:payload, :variables) }
    assert_equal [
      { id: "s-working", input: { position: 1.0 } },
      { id: "s-review", input: { position: 2.0 } },
      { id: "s-approved", input: { position: 3.0 } },
    ], updates
    assert_equal "", output
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

  def test_create_with_parent
    calls = stub_linear

    Linear.create("Child", "Body", "working", parent: "MOTO-1")

    payload = calls.find { |call| graphql?(call, "mutation IssueCreate") }
    assert_equal "MOTO-1", payload.dig(:payload, :variables, :input, :parentId)
  end

  def test_comment_with_parent
    calls = stub_linear

    Linear.comment({ id: "item-1" }, "Reply", parent: "c-1")

    payload = calls.find { |call| graphql?(call, "mutation CommentCreate") }
    assert_equal({ input: { issueId: "item-1", body: "Reply", parentId: "c-1" } }, payload.dig(:payload, :variables))
  end

  def test_link_skips_duplicate_url
    calls = stub_linear

    result = Linear.link(
      { id: "item-1", attachments: { nodes: [ { id: "a-1", url: "https://github.com/o/r/pull/1" } ] } },
      "https://github.com/o/r/pull/1",
      "PR",
    )

    refute result
    assert_empty calls.select { |call| graphql?(call, "mutation AttachmentLinkURL") }
  end

  def test_link_treats_duplicate_error_as_already_linked
    stub_linear
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation AttachmentLinkURL")

      true
    end.returns({ errors: [ { message: "Duplicate attachment for duplicate url" } ] })

    refute Linear.link({ id: "item-1" }, "https://github.com/o/r/pull/1", "PR")
  end

  def test_unlink_deletes_attachment
    calls = stub_linear

    Linear.unlink(
      { id: "item-1", identifier: "MOTO-1", attachments: { nodes: [ { id: "a-1", url: "https://github.com/o/r/pull/1" } ] } },
      "https://github.com/o/r/pull/1",
    )

    payload = calls.find { |call| graphql?(call, "mutation AttachmentDelete") }
    assert_equal({ id: "a-1" }, payload.dig(:payload, :variables))
  end

  def test_update_sends_input
    calls = stub_linear

    Linear.update({ id: "item-1" }, { title: "New", assigneeId: nil })

    payload = calls.find { |call| graphql?(call, "mutation IssueUpdate") }
    assert_equal({ id: "item-1", input: { title: "New", assigneeId: nil } }, payload.dig(:payload, :variables))
  end

  def test_list_filters_column_tag_and_search
    stub_linear(
      issues: [
        { id: "item-1", identifier: "MOTO-1", title: "Fix login", state: { name: "Ready" }, labels: { nodes: [ { name: "working" } ] } },
        { id: "item-2", identifier: "MOTO-2", title: "Other", state: { name: "Working" }, labels: { nodes: [] } },
        { id: "item-3", identifier: "MOTO-3", title: "Fix logout", state: { name: "Ready" }, labels: { nodes: [ { name: "working" } ] } },
      ],
    )

    assert_equal [ "MOTO-1" ], Linear.list(column: "ready", tag: "working", search: "login").map { |item| item[:identifier] }
  end

  def test_relate_maps_blocked_by
    calls = stub_linear(
      issue: { id: "item-2", identifier: "MOTO-2", team: { key: "MOTO" } },
    )

    Linear.relate({ id: "item-1", identifier: "MOTO-1" }, "blocked-by", "MOTO-2")

    payload = calls.find { |call| graphql?(call, "mutation IssueRelationCreate") }
    assert_equal(
      { input: { issueId: "item-2", relatedIssueId: "item-1", type: "blocks" } },
      payload.dig(:payload, :variables),
    )
  end

  def test_unrelate_deletes_matching_relation
    calls = stub_linear(issue: { id: "item-2", identifier: "MOTO-2", team: { key: "MOTO" } })

    Linear.unrelate(
      {
        id: "item-1",
        identifier: "MOTO-1",
        relations: { nodes: [ { id: "rel-1", type: "related", relatedIssue: { id: "item-2" } } ] },
      },
      "MOTO-2",
    )

    payload = calls.find { |call| graphql?(call, "mutation IssueRelationDelete") }
    assert_equal({ id: "rel-1" }, payload.dig(:payload, :variables))
  end

  def test_user_id_matches_name_and_me
    stub_linear(
      users: [ { id: "u-1", name: "Graham", displayName: "Graham O", email: "g@example.com" } ],
      viewer: { id: "u-me", name: "Me" },
    )

    assert_equal "u-1", Linear.user_id("graham")
    assert_equal "u-me", Linear.user_id("me")
  end

  def test_project_id_matches_name
    stub_linear(projects: [ { id: "p-1", name: "Code Moto" } ])

    assert_equal "p-1", Linear.project_id("code moto")
  end

  def test_issue_allows_other_team_when_overridden
    stub_linear(
      teams: [ { id: "team-1", key: "MOTO" }, { id: "team-me", key: "ME" } ],
      issue: { id: "item-me", identifier: "ME-42", team: { key: "ME" } },
    )

    found = Linear.with_team("ME") { Linear.issue("ME-42") }

    assert_equal "ME-42", found.fetch(:identifier)
    assert_equal "MOTO", Linear.team_key
  end

  def test_normalize_description_and_hash
    assert_equal "- [ ] item\nexample.com", Linear.normalize_description("* [ ] item\n[example.com](http://example.com)")
    assert_equal Digest::SHA256.hexdigest("old"), Linear.description_hash("old")
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
      { id: "s-#{status[:name].downcase}", **status, position: }
    end
  end

  def synced_tags
    Linear::TAGS.map do |tag|
      { id: "l-#{tag[:name].downcase}", **tag }
    end
  end

  def ranked_started_states(ready:, working:, review:, approved:)
    Linear::STATUSES.map do |status|
      position = case status[:name]
      when "Ready" then ready
      when "Working" then working
      when "Review" then review
      when "Approved" then approved
      else 0.0
      end
      { id: "s-#{status[:name].downcase}", **status, position: }
    end
  end

  def default_git_automations
    [
      { id: "ga-start", event: "start", state: { name: "In Progress" } },
      { id: "ga-review", event: "review", state: { name: "In Review" } },
      { id: "ga-merge", event: "merge", state: { name: "Done" } },
    ]
  end

  def stub_linear(organization: "gotte", teams: nil, states: nil, issues: nil, tags: nil, issue: nil, created: nil, git_automations: nil, users: nil, projects: nil, viewer: nil)
    calls = []
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Issue(")

      calls << opts
      true
    end.returns({ data: { issue: issue || { id: "item-1", identifier: "MOTO-1", team: { key: "MOTO" } } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation IssueCreate")

      calls << opts
      true
    end.returns(
      {
        data: {
          issueCreate: {
            success: true,
            issue: created || { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2" },
          },
        },
      },
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation CommentCreate")

      calls << opts
      true
    end.returns({ data: { commentCreate: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation AttachmentLinkURL")

      calls << opts
      true
    end.returns({ data: { attachmentLinkURL: { success: true } } })
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
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Users")

      calls << opts
      true
    end.returns({ data: { users: { nodes: users || [] } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Viewer")

      calls << opts
      true
    end.returns({ data: { viewer: viewer || { id: "u-me", name: "Me" } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Projects")

      calls << opts
      true
    end.returns({ data: { team: { projects: { nodes: projects || [] } } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Comment(")

      calls << opts
      true
    end.returns({ data: { comment: { id: "c-1", user: { id: "u-me" }, issue: { identifier: "MOTO-1", team: { key: "MOTO" } } } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation CommentUpdate")

      calls << opts
      true
    end.returns({ data: { commentUpdate: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation CommentDelete")

      calls << opts
      true
    end.returns({ data: { commentDelete: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation AttachmentDelete")

      calls << opts
      true
    end.returns({ data: { attachmentDelete: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation IssueRelationCreate")

      calls << opts
      true
    end.returns({ data: { issueRelationCreate: { success: true } } })
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "mutation IssueRelationDelete")

      calls << opts
      true
    end.returns({ data: { issueRelationDelete: { success: true } } })
    calls
  end
end
