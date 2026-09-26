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

    assert_equal "MOTO-1: Fix\nState: Ready\nTags: \nURL: https://linear.app/gotte/issue/MOTO-1\n\nDescription:\n", output
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

    assert_equal "Unknown command \"delete\", expected one of create, show, move, comment, link, tag, untag", error.message
    assert_empty calls
  end

  private

  def graphql?(opts, fragment)
    opts[:url] == Linear::HOST && opts.dig(:payload, :query).to_s.include?(fragment)
  end

  def variables(calls, fragment)
    calls.select { |call| graphql?(call, fragment) }.map { |call| call.dig(:payload, :variables) }
  end

  def stub_card(issue: { id: "item-1", identifier: "MOTO-1", team: { key: "MOTO" } }, created: nil)
    calls = []
    responses = {
      "query Workspace" => { organization: { urlKey: "gotte" }, teams: { nodes: [ { id: "team-1", key: "MOTO" } ] } },
      "query Issue(" => { issue: },
      "query States" => {
        team: {
          states: {
            nodes: Linear::STATUSES.map { |status| { id: "s-#{status[:name].downcase}", **status } },
          },
        },
      },
      "query Tags" => { team: { labels: { nodes: [ { id: "l-interactive", name: "interactive" } ] } } },
      "mutation IssueCreate" => {
        issueCreate: {
          success: true,
          issue: created || { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2" },
        },
      },
      "mutation IssueUpdate" => { issueUpdate: { success: true } },
      "mutation CommentCreate" => { commentCreate: { success: true } },
      "mutation AttachmentLinkURL" => { attachmentLinkURL: { success: true } },
    }
    responses.each do |fragment, data|
      Req.stubs(:call).with do |*args, **kwargs|
        opts = req_opts(args, kwargs)
        next false unless graphql?(opts, fragment)

        calls << opts
        true
      end.returns({ data: })
    end
    calls
  end
end
