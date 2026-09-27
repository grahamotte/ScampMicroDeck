require_relative "test_helper"

class CardTest < Minitest::Test
  def test_creates_card_in_backlog
    calls = stub_card(
      created: { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2" },
    )

    output, = capture_io { Card.call("create", "New card", "Do the thing") }

    assert_equal "MOTO-2 https://linear.app/gotte/issue/MOTO-2\n", output
    assert_equal(
      [
        {
          input: {
            teamId: "team-1",
            title: "New card",
            description: "Do the thing",
            stateId: "s-backlog",
          },
        },
      ],
      variables(calls, "mutation IssueCreate"),
    )
    assert_empty variables(calls, "query Issue(")
  end

  def test_creates_card_in_column
    calls = stub_card(
      created: { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2" },
    )

    output, = capture_io { Card.call("create", "New card", "Do the thing", "Ready") }

    assert_equal "MOTO-2 https://linear.app/gotte/issue/MOTO-2\n", output
    assert_equal(
      [
        {
          input: {
            teamId: "team-1",
            title: "New card",
            description: "Do the thing",
            stateId: "s-ready",
          },
        },
      ],
      variables(calls, "mutation IssueCreate"),
    )
  end

  def test_rejects_unknown_create_column
    calls = stub_card

    error = assert_raises(RuntimeError) { Card.call("create", "New card", "Do the thing", "done") }

    assert_includes error.message, 'Unknown column "done"'
    assert_empty variables(calls, "mutation IssueCreate")
  end

  def test_rejects_blank_create_title
    calls = stub_card

    error = assert_raises(RuntimeError) { Card.call("create", "", "Do the thing") }

    assert_equal "Title is blank", error.message
    assert_empty variables(calls, "mutation IssueCreate")
  end

  def test_shows_card_with_links_and_comments_in_order
    stub_card(
      issue: {
        id: "item-1",
        identifier: "MOTO-1",
        title: "Fix login",
        url: "https://linear.app/gotte/issue/MOTO-1",
        description: "Login is broken.",
        team: { key: "MOTO" },
        state: { id: "s-working", name: "Working" },
        labels: { nodes: [ { id: "l-interactive", name: "interactive" }, { id: "l-bug", name: "bug" } ] },
        attachments: { nodes: [ { title: "PR", url: "https://github.com/o/r/pull/1" } ] },
        comments: {
          nodes: [
            { body: "Second", createdAt: "2026-09-02T00:00:00Z", user: { name: "Graham" } },
            { body: "First", createdAt: "2026-09-01T00:00:00Z", user: nil },
          ],
        },
      },
    )

    output, = capture_io { Card.call("show", "MOTO-1") }

    assert_equal <<~TEXT, output
      MOTO-1: Fix login
      State: Working
      Tags: interactive, bug
      URL: https://linear.app/gotte/issue/MOTO-1
      Description hash: #{Linear.description_hash("Login is broken.")}

      Links:
      - PR: https://github.com/o/r/pull/1

      Description:
      Login is broken.

      Comment by unknown at 2026-09-01T00:00:00Z:
      First

      Comment by Graham at 2026-09-02T00:00:00Z:
      Second
    TEXT
  end

  def test_shows_card_without_links_or_comments
    stub_card(issue: { id: "item-1", identifier: "MOTO-1", title: "Fix", url: "https://linear.app/gotte/issue/MOTO-1", team: { key: "MOTO" }, state: { name: "Ready" } })

    output, = capture_io { Card.call("show", "MOTO-1") }

    assert_equal "MOTO-1: Fix\nState: Ready\nTags: \nURL: https://linear.app/gotte/issue/MOTO-1\nDescription hash: #{Linear.description_hash("")}\n\nDescription:\n", output
  end

  def test_moves_card_to_column
    calls = stub_card

    output, = capture_io { Card.call("move", "MOTO-1", "Review") }

    assert_equal "moved MOTO-1 to review\n", output
    assert_equal [ { id: "item-1", input: { stateId: "s-review" } } ], variables(calls, "mutation IssueUpdate")
  end

  def test_rejects_unknown_column
    calls = stub_card

    error = assert_raises(RuntimeError) { Card.call("move", "MOTO-1", "done") }

    assert_includes error.message, 'Unknown column "done"'
    assert_empty variables(calls, "mutation IssueUpdate")
  end

  def test_comments_on_card
    calls = stub_card

    output, = capture_io { Card.call("comment", "MOTO-1", "Did the thing") }

    assert_equal "commented on MOTO-1\n", output
    assert_equal [ { input: { issueId: "item-1", body: "Did the thing" } } ], variables(calls, "mutation CommentCreate")
  end

  def test_rejects_blank_comment
    calls = stub_card

    error = assert_raises(RuntimeError) { Card.call("comment", "MOTO-1", "") }

    assert_equal "Comment body is blank", error.message
    assert_empty variables(calls, "mutation CommentCreate")
  end

  def test_links_url_to_card
    calls = stub_card

    output, = capture_io { Card.call("link", "MOTO-1", "https://github.com/o/r/pull/1", "PR") }

    assert_equal "linked https://github.com/o/r/pull/1 to MOTO-1\n", output
    assert_equal(
      [ { issueId: "item-1", url: "https://github.com/o/r/pull/1", title: "PR" } ],
      variables(calls, "mutation AttachmentLinkURL"),
    )
  end

  def test_links_url_without_title
    calls = stub_card

    capture_io { Card.call("link", "MOTO-1", "https://github.com/o/r/pull/1", "") }

    assert_equal [ { issueId: "item-1", url: "https://github.com/o/r/pull/1" } ], variables(calls, "mutation AttachmentLinkURL")
  end

  def test_rejects_blank_link
    stub_card

    error = assert_raises(RuntimeError) { Card.call("link", "MOTO-1") }

    assert_equal "Link url is blank", error.message
  end

  def test_tags_card
    calls = stub_card

    output, = capture_io { Card.call("tag", "MOTO-1", "interactive") }

    assert_equal "tagged MOTO-1 with interactive\n", output
    assert_equal [ { id: "item-1", input: { addedLabelIds: [ "l-interactive" ] } } ], variables(calls, "mutation IssueUpdate")
  end

  def test_untags_card
    calls = stub_card

    output, = capture_io { Card.call("untag", "MOTO-1", "interactive") }

    assert_equal "untagged interactive from MOTO-1\n", output
    assert_equal [ { id: "item-1", input: { removedLabelIds: [ "l-interactive" ] } } ], variables(calls, "mutation IssueUpdate")
  end

  def test_rejects_unknown_command_without_calling_linear
    calls = stub_card

    error = assert_raises(RuntimeError) { Card.call("delete", "MOTO-1") }

    assert_equal "Unknown command \"delete\", expected one of create, show, list, move, edit, comment, comment-edit, comment-delete, link, unlink, tag, untag, relate, unrelate", error.message
    assert_empty calls
  end

  def test_creates_card_with_parent
    calls = stub_card(
      created: { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2" },
    )

    capture_io { Card.call("create", "Child", "Body", "backlog", "--parent", "MOTO-1") }

    assert_equal(
      [
        {
          input: {
            teamId: "team-1",
            title: "Child",
            description: "Body",
            stateId: "s-backlog",
            parentId: "MOTO-1",
          },
        },
      ],
      variables(calls, "mutation IssueCreate"),
    )
  end

  def test_shows_raw_description
    stub_card(issue: { id: "item-1", identifier: "MOTO-1", title: "Fix", url: "https://linear.app/gotte/issue/MOTO-1", description: "* [ ] item\n", team: { key: "MOTO" } })

    output, = capture_io { Card.call("show", "MOTO-1", "--raw") }

    assert_equal "* [ ] item\n", output
  end

  def test_shows_fields_children_and_relations
    stub_card(
      issue: {
        id: "item-1",
        identifier: "MOTO-1",
        title: "Fix login",
        url: "https://linear.app/gotte/issue/MOTO-1",
        description: "Body",
        priority: 2,
        estimate: 3,
        dueDate: "2026-10-01",
        team: { key: "MOTO" },
        state: { name: "Working" },
        assignee: { name: "Graham", displayName: "Graham O" },
        project: { name: "Code Moto" },
        parent: { identifier: "MOTO-0", title: "Epic" },
        labels: { nodes: [] },
        children: { nodes: [ { identifier: "MOTO-2", title: "Child", state: { name: "Ready" } } ] },
        relations: { nodes: [ { id: "rel-1", type: "blocks", relatedIssue: { id: "item-3", identifier: "MOTO-3", title: "Blocked" } } ] },
        inverseRelations: { nodes: [ { id: "rel-2", type: "blocks", issue: { id: "item-4", identifier: "MOTO-4", title: "Blocker" } } ] },
        comments: { nodes: [ { id: "c-1", body: "Hi", createdAt: "2026-09-01T00:00:00Z", parent: { id: "c-0" }, user: { id: "u-1", name: "Graham" } } ] },
      },
    )

    output, = capture_io { Card.call("show", "MOTO-1") }

    assert_includes output, "Priority: high"
    assert_includes output, "Estimate: 3"
    assert_includes output, "Assignee: Graham O"
    assert_includes output, "Due: 2026-10-01"
    assert_includes output, "Project: Code Moto"
    assert_includes output, "Parent: MOTO-0 Epic"
    assert_includes output, "- MOTO-2: Child (Ready)"
    assert_includes output, "- blocks MOTO-3: Blocked"
    assert_includes output, "- blocked by MOTO-4: Blocker"
    assert_includes output, "Comment c-1 (reply to c-0) by Graham at 2026-09-01T00:00:00Z:"
  end

  def test_lists_cards_with_filters
    calls = stub_card(
      issues: [
        { id: "item-1", identifier: "MOTO-1", title: "Fix login", state: { name: "Ready" }, labels: { nodes: [ { name: "working" } ] } },
        { id: "item-2", identifier: "MOTO-2", title: "Other", state: { name: "Working" }, labels: { nodes: [] } },
        { id: "item-3", identifier: "MOTO-3", title: "Fix logout", state: { name: "Ready" }, labels: { nodes: [ { name: "working" } ] } },
      ],
    )

    output, = capture_io { Card.call("list", "--column", "ready", "--tag", "working", "--search", "login") }

    assert_equal "MOTO-1  ready  Fix login\n", output
    assert_empty variables(calls, "mutation")
  end

  def test_edits_title
    calls = stub_card

    output, = capture_io { Card.call("edit", "MOTO-1", "--title", "New title") }

    assert_equal "updated MOTO-1\n", output
    assert_equal [ { id: "item-1", input: { title: "New title" } } ], variables(calls, "mutation IssueUpdate")
  end

  def test_edits_description_with_expect_hash
    issue = { id: "item-1", identifier: "MOTO-1", description: "old", team: { key: "MOTO" } }
    calls = stub_card(issue:, updated: { id: "item-1", identifier: "MOTO-1", description: "new" })

    output, = capture_io { Card.call("edit", "MOTO-1", "--body", "new", "--expect-hash", Linear.description_hash("old")) }

    assert_equal "updated MOTO-1\n", output
    assert_equal [ { id: "item-1", input: { description: "new" } } ], variables(calls, "mutation IssueUpdate")
  end

  def test_edits_description_with_expect_file
    issue = { id: "item-1", identifier: "MOTO-1", description: "old", team: { key: "MOTO" } }
    stub_card(issue:, updated: { id: "item-1", identifier: "MOTO-1", description: "- [ ] item" })
    expect_path = write_card_file("expect.md", "old")
    body_path = write_card_file("body.md", "* [ ] item")

    output, = capture_io { Card.call("edit", "MOTO-1", "--body-file", body_path, "--expect-file", expect_path) }

    assert_includes output, "updated MOTO-1"
    assert_includes output, "Linear normalized the description."
  end

  def test_refuses_stale_description
    stub_card(issue: { id: "item-1", identifier: "MOTO-1", description: "changed", team: { key: "MOTO" } })

    error = assert_raises(RuntimeError) { Card.call("edit", "MOTO-1", "--body", "new", "--expect-hash", Linear.description_hash("old")) }

    assert_equal "Description changed since it was read; refusing to overwrite", error.message
  end

  def test_refuses_description_edit_without_expect
    calls = stub_card

    error = assert_raises(RuntimeError) { Card.call("edit", "MOTO-1", "--body", "new") }

    assert_equal "Pass --expect-file or --expect-hash to update the description", error.message
    assert_empty variables(calls, "mutation IssueUpdate")
  end

  def test_edits_fields_and_clears
    calls = stub_card(
      users: [ { id: "u-1", name: "Graham", displayName: "Graham O", email: "g@example.com" } ],
      projects: [ { id: "p-1", name: "Code Moto" } ],
    )

    capture_io { Card.call("edit", "MOTO-1", "--priority", "high", "--estimate", "5", "--assignee", "Graham", "--due", "2026-10-01", "--project", "Code Moto", "--parent", "MOTO-0") }

    assert_equal(
      [
        {
          id: "item-1",
          input: {
            priority: 2,
            estimate: 5,
            assigneeId: "u-1",
            dueDate: "2026-10-01",
            projectId: "p-1",
            parentId: "MOTO-0",
          },
        },
      ],
      variables(calls, "mutation IssueUpdate"),
    )

    Linear.reset
    calls = stub_card
    capture_io { Card.call("edit", "MOTO-1", "--clear-priority", "--clear-estimate", "--clear-assignee", "--clear-due", "--clear-project", "--clear-parent") }

    assert_equal(
      [
        {
          id: "item-1",
          input: {
            priority: 0,
            estimate: nil,
            assigneeId: nil,
            dueDate: nil,
            projectId: nil,
            parentId: nil,
          },
        },
      ],
      variables(calls, "mutation IssueUpdate"),
    )
  end

  def test_comments_from_body_file_and_reply
    path = write_card_file("comment.md", "Long comment")
    calls = stub_card

    capture_io { Card.call("comment", "MOTO-1", "--body-file", path, "--reply", "c-1") }

    assert_equal [ { input: { issueId: "item-1", body: "Long comment", parentId: "c-1" } } ], variables(calls, "mutation CommentCreate")
  end

  def test_edits_own_comment
    calls = stub_card(
      comment: { id: "c-1", body: "Hi", user: { id: "u-me", name: "Me" }, issue: { identifier: "MOTO-1", team: { key: "MOTO" } } },
      viewer: { id: "u-me", name: "Me" },
    )

    output, = capture_io { Card.call("comment-edit", "c-1", "--body", "Updated") }

    assert_equal "updated comment c-1\n", output
    assert_equal [ { id: "c-1", input: { body: "Updated" } } ], variables(calls, "mutation CommentUpdate")
  end

  def test_refuses_to_edit_someone_elses_comment
    stub_card(
      comment: { id: "c-1", body: "Hi", user: { id: "u-other", name: "Other" }, issue: { identifier: "MOTO-1", team: { key: "MOTO" } } },
      viewer: { id: "u-me", name: "Me" },
    )

    error = assert_raises(RuntimeError) { Card.call("comment-edit", "c-1", "--body", "Updated") }

    assert_equal "Comment c-1 was not created by you", error.message
  end

  def test_deletes_own_comment
    calls = stub_card(
      comment: { id: "c-1", body: "Hi", user: { id: "u-me", name: "Me" }, issue: { identifier: "MOTO-1", team: { key: "MOTO" } } },
      viewer: { id: "u-me", name: "Me" },
    )

    output, = capture_io { Card.call("comment-delete", "c-1") }

    assert_equal "deleted comment c-1\n", output
    assert_equal [ { id: "c-1" } ], variables(calls, "mutation CommentDelete")
  end

  def test_link_is_idempotent_when_url_already_attached
    calls = stub_card(
      issue: {
        id: "item-1",
        identifier: "MOTO-1",
        team: { key: "MOTO" },
        attachments: { nodes: [ { id: "a-1", title: "PR", url: "https://github.com/o/r/pull/1" } ] },
      },
    )

    output, = capture_io { Card.call("link", "MOTO-1", "https://github.com/o/r/pull/1", "PR") }

    assert_equal "already linked https://github.com/o/r/pull/1 to MOTO-1\n", output
    assert_empty variables(calls, "mutation AttachmentLinkURL")
  end

  def test_unlinks_url
    calls = stub_card(
      issue: {
        id: "item-1",
        identifier: "MOTO-1",
        team: { key: "MOTO" },
        attachments: { nodes: [ { id: "a-1", title: "PR", url: "https://github.com/o/r/pull/1" } ] },
      },
    )

    output, = capture_io { Card.call("unlink", "MOTO-1", "https://github.com/o/r/pull/1") }

    assert_equal "unlinked https://github.com/o/r/pull/1 from MOTO-1\n", output
    assert_equal [ { id: "a-1" } ], variables(calls, "mutation AttachmentDelete")
  end

  def test_relates_and_unrelates_cards
    issue = {
      id: "item-1",
      identifier: "MOTO-1",
      team: { key: "MOTO" },
      relations: { nodes: [ { id: "rel-1", type: "blocks", relatedIssue: { id: "item-2", identifier: "MOTO-2", title: "Other" } } ] },
    }
    calls = stub_card(issue:, related_issue: { id: "item-2", identifier: "MOTO-2", team: { key: "MOTO" } })

    output, = capture_io { Card.call("relate", "MOTO-1", "blocks", "MOTO-2") }

    assert_equal "related MOTO-1 blocks MOTO-2\n", output
    assert_equal(
      [ { input: { issueId: "item-1", relatedIssueId: "item-2", type: "blocks" } } ],
      variables(calls, "mutation IssueRelationCreate"),
    )

    Linear.reset
    calls = stub_card(issue:, related_issue: { id: "item-2", identifier: "MOTO-2", team: { key: "MOTO" } })
    output, = capture_io { Card.call("unrelate", "MOTO-1", "MOTO-2") }

    assert_equal "unrelated MOTO-1 from MOTO-2\n", output
    assert_equal [ { id: "rel-1" } ], variables(calls, "mutation IssueRelationDelete")
  end

  def test_show_other_team_with_team_flag
    stub_card(
      teams: [ { id: "team-1", key: "MOTO" }, { id: "team-me", key: "ME" } ],
      issue: { id: "item-me", identifier: "ME-42", title: "Other", url: "https://linear.app/gotte/issue/ME-42", team: { key: "ME" }, state: { name: "Ready" } },
    )

    output, = capture_io { Card.call("show", "ME-42", "--team", "ME") }

    assert_includes output, "ME-42: Other"
  end

  def test_show_other_team_without_flag_is_refused
    stub_card(issue: { id: "item-me", identifier: "ME-42", team: { key: "ME" } })

    error = assert_raises(RuntimeError) { Card.call("show", "ME-42") }

    assert_equal 'Linear issue ME-42 is in team "ME", expected "MOTO"', error.message
  end

  private

  def graphql?(opts, fragment)
    opts[:url] == Linear::HOST && opts.dig(:payload, :query).to_s.include?(fragment)
  end

  def variables(calls, fragment)
    calls.select { |call| graphql?(call, fragment) }.map { |call| call.dig(:payload, :variables) }
  end

  def write_card_file(name, contents)
    path = File.join(@worktree_test_dir, name)
    File.write(path, contents)
    path
  end

  def stub_card(
    issue: { id: "item-1", identifier: "MOTO-1", team: { key: "MOTO" } },
    created: nil,
    updated: nil,
    issues: nil,
    teams: nil,
    users: nil,
    projects: nil,
    viewer: nil,
    comment: nil,
    related_issue: nil
  )
    calls = []
    responses = {
      "query Workspace" => { organization: { urlKey: "gotte" }, teams: { nodes: teams || [ { id: "team-1", key: "MOTO" } ] } },
      "query Issues" => {
        team: {
          issues: {
            nodes: issues || [],
            pageInfo: { hasNextPage: false, endCursor: nil },
          },
        },
      },
      "query States" => {
        team: {
          states: {
            nodes: Linear::STATUSES.map { |status| { id: "s-#{status[:name].downcase}", **status } },
          },
        },
      },
      "query Tags" => { team: { labels: { nodes: [ { id: "l-interactive", name: "interactive" } ] } } },
      "query Users" => { users: { nodes: users || [] } },
      "query Viewer" => { viewer: viewer || { id: "u-me", name: "Me" } },
      "query Projects" => { team: { projects: { nodes: projects || [] } } },
      "query Comment(" => { comment: comment },
      "mutation IssueCreate" => {
        issueCreate: {
          success: true,
          issue: created || { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2" },
        },
      },
      "mutation IssueUpdate" => {
        issueUpdate: {
          success: true,
          issue: updated || issue,
        },
      },
      "mutation CommentCreate" => { commentCreate: { success: true } },
      "mutation CommentUpdate" => { commentUpdate: { success: true } },
      "mutation CommentDelete" => { commentDelete: { success: true } },
      "mutation AttachmentLinkURL" => { attachmentLinkURL: { success: true } },
      "mutation AttachmentDelete" => { attachmentDelete: { success: true } },
      "mutation IssueRelationCreate" => { issueRelationCreate: { success: true } },
      "mutation IssueRelationDelete" => { issueRelationDelete: { success: true } },
    }
    responses.each do |fragment, data|
      Req.stubs(:call).with do |*args, **kwargs|
        opts = req_opts(args, kwargs)
        next false unless graphql?(opts, fragment)

        calls << opts
        true
      end.returns({ data: })
    end
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless graphql?(opts, "query Issue(")
      next false if related_issue && opts.dig(:payload, :variables, :id).to_s == related_issue[:identifier]

      calls << opts
      true
    end.returns({ data: { issue: } })
    if related_issue
      Req.stubs(:call).with do |*args, **kwargs|
        opts = req_opts(args, kwargs)
        next false unless graphql?(opts, "query Issue(")
        next false unless opts.dig(:payload, :variables, :id).to_s == related_issue[:identifier]

        calls << opts
        true
      end.returns({ data: { issue: related_issue } })
    end
    calls
  end
end
