require_relative "test_helper"

class ApprovedMergeTest < Minitest::Test
  URL = "https://github.com/grahamotte/codemoto.org/pull/3"
  ITEM = { identifier: "MOTO-3" }.freeze

  def test_merges_clean_pr_and_checks_that_it_merged
    commands = stub_commands

    assert ApprovedMerge.call(ITEM)
    assert_includes commands, [ "gh", "pr", "merge", URL, "--repo", "grahamotte/codemoto.org", "--merge", "--match-head-commit", "abc" ]
    assert_equal 2, commands.count { |command| command[0..2] == [ "gh", "pr", "view" ] }
  end

  def test_finishes_already_merged_pr_without_merging_again
    commands = stub_commands(pr: { state: "MERGED" })

    assert ApprovedMerge.call(ITEM)
    refute commands.any? { |command| command[2] == "merge" }
  end

  def test_does_not_complete_queued_or_pending_merge
    stub_commands(after: "OPEN")

    refute ApprovedMerge.call(ITEM)
  end

  def test_falls_back_for_missing_or_ambiguous_links
    [ [], [ { url: URL }, { url: "https://github.com/grahamotte/codemoto.org/pull/4" } ], [ { url: "https://github.com/other/repo/pull/3" } ] ].each do |attachments|
      commands = stub_commands(attachments:)

      refute ApprovedMerge.call(ITEM)
      assert_equal 1, commands.length
    end
  end

  def test_ignores_unrelated_attachments_and_deduplicates_links
    stub_commands(attachments: [ { url: URL }, { url: URL }, { url: "https://example.com" } ])

    assert ApprovedMerge.call(ITEM)
  end

  def test_falls_back_for_conflicts_checks_unknown_state_closed_pr_or_other_base
    [
      { mergeable: "CONFLICTING" },
      { mergeable: "UNKNOWN" },
      { mergeStateStatus: "BLOCKED" },
      { mergeStateStatus: "BEHIND" },
      { state: "CLOSED" },
      { baseRefName: "feature" },
    ].each do |pr|
      commands = stub_commands(pr:)

      refute ApprovedMerge.call(ITEM)
      refute commands.any? { |command| command[2] == "merge" }
    end
  end

  def test_supports_main_base
    stub_commands(pr: { baseRefName: "main" })

    assert ApprovedMerge.call(ITEM)
  end

  def test_reports_command_failure
    stub_commands(failure: "merge")

    error = assert_raises(RuntimeError) { ApprovedMerge.call(ITEM) }
    assert_includes error.message, "merge failed"
  end

  def test_rejects_malformed_issue_response
    Open3.stubs(:capture3).returns([ "invalid json", "", Struct.new(:success?).new(true) ])

    assert_raises(JSON::ParserError) { ApprovedMerge.call(ITEM) }
  end

  private

  def stub_commands(attachments: [ { url: URL } ], pr: {}, after: "MERGED", failure: nil)
    commands = []
    details = { state: "OPEN", baseRefName: "master", headRefOid: "abc", mergeable: "MERGEABLE", mergeStateStatus: "CLEAN" }.merge(pr)
    ok = Struct.new(:success?).new(true)
    Open3.stubs(:capture3).with do |*command, **options|
      next false unless command == [ "mise", "linear", "issues", "read", "MOTO-3", "--with-attachments" ]

      assert_equal Worktree.root, options[:chdir]
      commands << command
      true
    end.returns([ JSON.generate(attachments: { nodes: attachments }), "", ok ])
    Open3.stubs(:capture3).with do |*command, **options|
      next false unless command == [ "gh", "pr", "view", URL, "--repo", "grahamotte/codemoto.org", "--json", "state,baseRefName,headRefOid,mergeable,mergeStateStatus" ]

      assert_equal Worktree.root, options[:chdir]
      commands << command
      true
    end.returns(
      [ JSON.generate(details), "", ok ],
      [ JSON.generate(details.merge(state: after)), "", ok ],
    )
    Open3.stubs(:capture3).with do |*command, **options|
      next false unless command == [ "gh", "pr", "merge", URL, "--repo", "grahamotte/codemoto.org", "--merge", "--match-head-commit", "abc" ]

      assert_equal Worktree.root, options[:chdir]
      commands << command
      true
    end.returns([ "", "merge failed", Struct.new(:success?).new(failure.blank?) ])
    commands
  end
end
