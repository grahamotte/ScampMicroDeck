require_relative "test_helper"

class TriggerTest < Minitest::Test
  def test_moves_ready_cards_and_starts_work_agent
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" } },
        { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2", state: { id: "s-planned", name: "Planned" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-1\n", output
    assert_equal(
      [
        { stateId: "s-working" },
        { addedLabelIds: [ "l-working" ] },
      ],
      issue_update_inputs(calls),
    )
    prompt = prompt_for(calls, "MOTO-1")
    assert_includes prompt, "Do this Linear issue: https://linear.app/gotte/issue/MOTO-1"
    assert_includes prompt, "The manager runs this card. Do not use the `interactive-card` skill."
    assert_includes prompt, "This may be a new card or a kickback with corrections in later comments."
    assert_includes prompt, "There may already be a worktree, commits, and a PR."
    assert_includes prompt, "This session is already in the card worktree. Env files and schema.rb were copied from the main checkout."
    assert_includes prompt, "Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits."
    assert_includes prompt, "You may edit existing commits or add new ones."
    assert_includes prompt, "Open a GitHub PR with `gh pr create` using `GITHUB_TOKEN`"
    assert_includes prompt, "Comment on the card describing what you did"
    assert_includes prompt, "Remove the working tag"
    assert_includes prompt, "Move the card to review"
    assert_includes prompt, "Move the card to planned"
    assert_includes prompt, "If the card names a skill, follow it; where the skill says how to finish the card, do that instead of steps 5 and 6, then remove the working tag. Step 7 still applies."
    assert_includes prompt, "If you spent significant time unnecessarily or the instructions misdirected you, and the issue could be backported to Code Moto (`codemoto.org` / MOTO), search the MOTO backlog for a matching card first."
    assert_includes prompt, "If one exists, comment with a brief summary of your experience. Otherwise create a MOTO backlog card. Do not file app-specific issues."
    refute_includes prompt, "Hard set to the current origin main."
    refute_includes prompt, "Open a worktree."
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-2") }
    assert_equal Worktree.path_for({ identifier: "MOTO-1" }), directory_for(calls, "MOTO-1")
    assert_equal "xai/grok-4.7", session_for(calls, "MOTO-1").fetch(:model)
    assert_equal "high", session_for(calls, "MOTO-1").fetch(:variant)
  end

  def test_starts_agent_with_model_and_variant_labels
    calls = stub_manager(
      items: [
        {
          id: "item-1",
          identifier: "MOTO-1",
          url: "https://linear.app/gotte/issue/MOTO-1",
          state: { id: "s-ready", name: "Ready" },
          labels: {
            nodes: [
              { id: "l-model", name: "model: anthropic/claude-sonnet-4" },
              { id: "l-variant", name: "variant: medium" },
            ],
          },
        },
      ],
    )

    capture_io { Trigger.call }

    session = session_for(calls, "MOTO-1")
    assert_equal "anthropic/claude-sonnet-4", session.fetch(:model)
    assert_equal "medium", session.fetch(:variant)
  end

  def test_starts_merge_agent_for_approved_cards
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "merging MOTO-3\n", output
    assert_equal(
      [ { addedLabelIds: [ "l-working" ] } ],
      issue_update_inputs(calls),
    )
    prompt = prompt_for(calls, "MOTO-3")
    assert_includes prompt, "This Linear issue is approved: https://linear.app/gotte/issue/MOTO-3"
    assert_includes prompt, "The manager runs this card. Do not use the `interactive-card` skill."
    assert_includes prompt, "Rebase the GitHub PR on the card."
    assert_includes prompt, "Merge the PR with `gh pr merge` using `GITHUB_TOKEN`."
    assert_includes prompt, "Remove the working tag."
    assert_includes prompt, "Move the card to completed."
    assert_includes prompt, "If this session is in the main checkout rather than a worktree, run `git checkout master` and `git pull --ff-only origin master`."
    refute_includes prompt, "gotomain"
    refute_includes prompt, "Remove any worktrees created for this card."
    assert_equal Worktree.root, directory_for(calls, "MOTO-3")
  end

  def test_starts_merge_agent_in_worktree_pushing_to_card_branch
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
      ],
    )
    path = File.join(Worktree.root, ".claude/worktrees/brave-fox")
    ok = Object.new
    ok.define_singleton_method(:success?) { true }
    Open3.stubs(:capture3).with("git", "worktree", "list", "--porcelain", chdir: Worktree.root).returns(
      [
        "worktree #{Worktree.root}\nHEAD abc\nbranch refs/heads/master\n\nworktree #{path}\nHEAD def\nbranch refs/heads/claude/brave-fox\n",
        "",
        ok,
      ],
    )
    Open3.stubs(:capture3).with(
      "git",
      "for-each-ref",
      "--format=%(refname:short) %(upstream:short)",
      "refs/heads",
      chdir: Worktree.root,
    ).returns([ "master origin/master\nclaude/brave-fox origin/moto-3\n", "", ok ])

    output, = capture_io { Trigger.call }

    assert_equal "merging MOTO-3\n", output
    assert_equal path, directory_for(calls, "MOTO-3")
  end

  def test_moves_ready_card_back_when_agent_fails
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" } },
      ],
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless opts[:url].to_s.end_with?("/api/openchamber/sessions")

      true
    end.raises("agent failed")

    output, = capture_io do
      assert_raises(RuntimeError) { Trigger.call }
    end

    assert_equal "", output
    assert_equal(
      [
        { stateId: "s-working" },
        { addedLabelIds: [ "l-working" ] },
        { removedLabelIds: [ "l-working" ] },
        { stateId: "s-ready" },
      ],
      issue_update_inputs(calls),
    )
  end

  def test_untags_when_approved_agent_fails
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
      ],
    )
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless opts[:url].to_s.end_with?("/api/openchamber/sessions")

      true
    end.raises("agent failed")

    output, = capture_io do
      assert_raises(RuntimeError) { Trigger.call }
    end

    assert_equal "", output
    assert_equal(
      [
        { addedLabelIds: [ "l-working" ] },
        { removedLabelIds: [ "l-working" ] },
      ],
      issue_update_inputs(calls),
    )
  end

  def test_skips_agents_for_completed_and_canceled_cards
    calls = stub_manager(
      items: [
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
        { id: "item-5", identifier: "MOTO-5", url: "https://linear.app/gotte/issue/MOTO-5", state: { id: "s-canceled", name: "Canceled" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "", output
    assert_empty issue_update_inputs(calls)
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-4") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-5") }
  end

  def test_removes_worktrees_for_completed_and_canceled_cards
    completed_path = Worktree.path_for({ identifier: "MOTO-4" })
    canceled_path = Worktree.path_for({ identifier: "MOTO-5" })
    FileUtils.mkdir_p(completed_path)
    FileUtils.mkdir_p(canceled_path)
    calls = stub_manager(
      items: [
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
        { id: "item-5", identifier: "MOTO-5", url: "https://linear.app/gotte/issue/MOTO-5", state: { id: "s-canceled", name: "Canceled" } },
        { id: "item-4b", identifier: "MOTO-10", url: "https://linear.app/gotte/issue/MOTO-10", state: { id: "s-completed", name: "Completed" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "removed worktree for MOTO-4\nremoved worktree for MOTO-5\n", output
    refute Dir.exist?(completed_path)
    refute Dir.exist?(canceled_path)
    assert_empty issue_update_inputs(calls)
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-4") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-5") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-10") }
  end

  def test_removes_completed_worktrees_even_with_working_tag
    path = Worktree.path_for({ identifier: "MOTO-4" })
    FileUtils.mkdir_p(path)
    stub_manager(
      items: [
        {
          id: "item-4",
          identifier: "MOTO-4",
          url: "https://linear.app/gotte/issue/MOTO-4",
          state: { id: "s-completed", name: "Completed" },
          labels: { nodes: [ { id: "l-working", name: "working" } ] },
        },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "removed worktree for MOTO-4\n", output
    refute Dir.exist?(path)
  end

  def test_starts_one_agent_per_step
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" } },
        { id: "item-1b", identifier: "MOTO-8", url: "https://linear.app/gotte/issue/MOTO-8", state: { id: "s-ready", name: "Ready" } },
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
        { id: "item-3b", identifier: "MOTO-9", url: "https://linear.app/gotte/issue/MOTO-9", state: { id: "s-approved", name: "Approved" } },
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
        { id: "item-4b", identifier: "MOTO-10", url: "https://linear.app/gotte/issue/MOTO-10", state: { id: "s-completed", name: "Completed" } },
        { id: "item-5", identifier: "MOTO-5", url: "https://linear.app/gotte/issue/MOTO-5", state: { id: "s-canceled", name: "Canceled" } },
        { id: "item-5b", identifier: "MOTO-12", url: "https://linear.app/gotte/issue/MOTO-12", state: { id: "s-canceled", name: "Canceled" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-1\nmerging MOTO-3\n", output
    assert_equal 3, calls.count { |call| graphql?(call, "mutation IssueUpdate") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-8") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-9") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-10") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-12") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-4") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-5") }
    assert prompt_for(calls, "MOTO-1")
    assert prompt_for(calls, "MOTO-3")
  end

  def test_handles_ready_and_approved_together
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" } },
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-1\nmerging MOTO-3\n", output
    assert_equal 3, calls.count { |call| graphql?(call, "mutation IssueUpdate") }
    assert_includes prompt_for(calls, "MOTO-1"), "This session is already in the card worktree. Env files and schema.rb were copied from the main checkout."
    assert_includes prompt_for(calls, "MOTO-1"), "Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits."
    assert_includes prompt_for(calls, "MOTO-3"), "Rebase the GitHub PR on the card."
    assert_equal Worktree.path_for({ identifier: "MOTO-1" }), directory_for(calls, "MOTO-1")
    assert_equal Worktree.root, directory_for(calls, "MOTO-3")
  end

  def test_copies_env_and_schema_into_worktree_before_starting
    File.write(File.join(Worktree.root, ".env.development"), "DEV=1")
    FileUtils.mkdir_p(File.join(Worktree.root, "backend/db"))
    File.write(File.join(Worktree.root, "backend/db/schema.rb"), "schema")
    stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" } },
      ],
    )

    capture_io { Trigger.call }

    path = Worktree.path_for({ identifier: "MOTO-1" })
    assert_equal "DEV=1", File.read(File.join(path, ".env.development"))
    assert_equal "schema", File.read(File.join(path, "backend/db/schema.rb"))
  end

  def test_merges_from_existing_worktree
    path = Worktree.path_for({ identifier: "MOTO-3" })
    FileUtils.mkdir_p(path)
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
      ],
    )

    capture_io { Trigger.call }

    assert_equal path, directory_for(calls, "MOTO-3")
  end

  def test_skips_interactive_cards_in_ready
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" }, labels: { nodes: [ { id: "l-interactive", name: "interactive" } ] } },
        { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2", state: { id: "s-ready", name: "Ready" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-2\n", output
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-1") }
    assert calls.select { |call| graphql?(call, "mutation IssueUpdate") }.all? { |call| call.dig(:payload, :variables, :id) == "item-2" }
  end

  def test_skips_ready_column_when_all_cards_are_interactive
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" }, labels: { nodes: [ { id: "l-interactive", name: "interactive" } ] } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "", output
    assert_empty issue_update_inputs(calls)
  end

  def test_merges_interactive_cards_when_approved
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" }, labels: { nodes: [ { id: "l-interactive", name: "interactive" } ] } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "merging MOTO-3\n", output
    assert_includes prompt_for(calls, "MOTO-3"), "This Linear issue is approved: https://linear.app/gotte/issue/MOTO-3"
  end

  def test_skips_cards_with_working_tag
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" }, labels: { nodes: [ { id: "l-working", name: "working" } ] } },
        { id: "item-9", identifier: "MOTO-9", url: "https://linear.app/gotte/issue/MOTO-9", state: { id: "s-approved", name: "Approved" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "merging MOTO-9\n", output
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-3") }
    assert_equal(
      [ { addedLabelIds: [ "l-working" ] } ],
      issue_update_inputs(calls),
    )
    assert_equal "item-9", calls.find { |call| graphql?(call, "mutation IssueUpdate") }.dig(:payload, :variables, :id)
  end

  def test_skips_column_when_all_cards_have_working_tag
    stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" }, labels: { nodes: [ { id: "l-working", name: "working" } ] } },
      ],
    )

    assert_output("") { Trigger.call }
  end

  def test_prints_nothing_when_nothing_is_triggered
    stub_manager(
      items: [
        { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2", state: { id: "s-planned", name: "Planned" } },
      ],
    )

    assert_output("") { Trigger.call }
  end

  private

  def graphql?(opts, fragment)
    opts[:url] == Linear::HOST && opts.dig(:payload, :query).to_s.include?(fragment)
  end

  def stub_manager(items:)
    calls = []
    ok = Object.new
    ok.define_singleton_method(:success?) { true }
    Open3.stubs(:capture3).with do |*args, **_kwargs|
      if args[1] == "worktree" && args[2] == "add"
        path = args[3] == "-b" ? args[5] : args[3]
        FileUtils.mkdir_p(path)
      elsif args[1] == "worktree" && args[2] == "remove"
        FileUtils.remove_entry(args.last) if Dir.exist?(args.last)
      end
      true
    end.returns([ "", "", ok ])
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless opts[:url].to_s.end_with?("/api/openchamber/sessions")

      calls << {
        prompt: opts.dig(:payload, :prompt),
        directory: opts.dig(:payload, :directory),
        model: opts.dig(:payload, :model),
        variant: opts.dig(:payload, :variant),
      }
      true
    end.returns({ sessionId: "ses-1" })
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
              nodes: [
                { id: "s-ready", name: "Ready", type: "started" },
                { id: "s-working", name: "Working", type: "started" },
                { id: "s-planned", name: "Planned", type: "unstarted" },
                { id: "s-approved", name: "Approved", type: "started" },
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
              nodes: items,
              pageInfo: { hasNextPage: false, endCursor: nil },
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
              nodes: [ { id: "l-working", name: "working" } ],
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
    calls
  end

  def issue_update_inputs(calls)
    calls.select { |call| graphql?(call, "mutation IssueUpdate") }.map { |call| call.dig(:payload, :variables, :input) }
  end

  def prompt_for(calls, identifier)
    calls
      .map { |call| call[:prompt] }
      .compact
      .find { |text| text.include?(identifier) }
  end

  def directory_for(calls, identifier)
    session_for(calls, identifier)&.fetch(:directory)
  end

  def session_for(calls, identifier)
    calls.find { |call| call[:prompt].to_s.include?(identifier) }
  end
end
