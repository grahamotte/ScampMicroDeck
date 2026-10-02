require_relative "test_helper"

class TriggerTest < Minitest::Test
  def test_fetches_all_actionable_cards_and_only_recent_terminal_cards
    calls = stub_manager(items: [])

    assert_output("") { Trigger.call }

    query = calls.find { |call| graphql?(call, "query Issues") }
    assert_equal(
      {
        or: [
          { state: { name: { in: [ "Ready", "Approved" ] } } },
          {
            and: [
              { state: { name: { in: [ "Completed", "Canceled" ] } } },
              { updatedAt: { gte: "-P30D" } },
            ],
          },
        ],
      },
      query.dig(:payload, :variables, :filter),
    )
  end

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
        *default_label_inputs,
      ],
      issue_update_inputs(calls),
    )
    prompt = prompt_for(calls, "MOTO-1")
    assert_includes prompt, "Do this Linear issue: https://linear.app/gotte/issue/MOTO-1"
    assert_includes prompt, "The manager runs this card. Do not use the `interactive-card` skill."
    assert_includes prompt, "Do not assign users to cards when creating or working on them. Leave existing assignees unchanged."
    assert_includes prompt, "This may be a new card or a kickback with corrections in later comments."
    assert_includes prompt, "There may already be a worktree, commits, and a PR."
    assert_includes prompt, "This session is already in the card worktree. Env files and schema.rb were copied from the main checkout."
    assert_includes prompt, "Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits."
    assert_includes prompt, "You may edit existing commits or add new ones."
    assert_includes prompt, "Open a GitHub PR with `gh pr create` using `GITHUB_TOKEN`"
    assert_includes prompt, "A GitHub PR is required only for code changes or other changes to tracked repository files."
    assert_includes prompt, "Operations without tracked repository changes need no PR, empty commit, or branch."
    assert_includes prompt, "Do not require GitHub PR access for such operations."
    assert_includes prompt, "Reuse this tracking card for the whole task and record individual operations and steps here; do not create a new card for each step."
    assert_includes prompt, "Completing one operation or PR does not complete a larger task."
    assert_includes prompt, "reuse an open PR or create a new one on this card after a prior PR has finished"
    assert_includes prompt, "If there are tracked repository changes, commit them, push the branch, and create or update the card's PR:"
    assert_includes prompt, "if the card has no open PR for these changes"
    assert_includes prompt, "Comment on the card with a brief summary of what changed and a short fenced pseudocode block showing how the change works at a high level."
    assert_includes prompt, "Use readable, imperfect Ruby in a fenced `ruby` block; the pseudocode does not need to run."
    assert_includes prompt, "Use named components and indentation to show the flow of inputs, key decisions, and results."
    assert_includes prompt, "Keep it structural and concise; do not explain the flow in paragraphs or include low-level implementation details."
    assert_includes prompt, "Remove the working tag"
    assert_includes prompt, "Move the card to review"
    assert_includes prompt, "Move the card to review if there are tracked repository changes awaiting review and the whole task is ready; otherwise move it to completed only when the whole task is done."
    refute_includes prompt, "Merge the linked PR immediately"
    refute_includes prompt, "remove only this card's worktree"
    assert_includes prompt, "Move the card to planned"
    assert_includes prompt, "If the card names a skill, follow it; where the skill says how to finish the card, do that instead of steps 5 and 6, then remove the working tag. Step 7 still applies."
    assert_includes prompt, "If you spent significant time unnecessarily or the instructions misdirected you, and the issue could be backported to Code Moto (`codemoto.org` / MOTO), search the MOTO backlog for a matching card first."
    assert_includes prompt, "If one exists, comment with a brief summary of your experience. Otherwise create a MOTO backlog card. Do not file app-specific issues."
    refute_includes prompt, "Hard set to the current origin main."
    refute_includes prompt, "Open a worktree."
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-2") }
    assert_equal Worktree.path_for({ identifier: "MOTO-1" }), directory_for(calls, "MOTO-1")
    assert_equal "openai/gpt-6.1-sol", session_for(calls, "MOTO-1").fetch(:model)
    assert_equal "high", session_for(calls, "MOTO-1").fetch(:variant)
  end

  def test_skip_review_prompt_creates_pr_and_merges_before_completing_and_cleaning_up
    calls = stub_manager(
      items: [
        {
          id: "item-1",
          identifier: "MOTO-1",
          url: "https://linear.app/gotte/issue/MOTO-1",
          state: { name: "Ready" },
          labels: { nodes: [ { name: "Skip Review" } ] },
        },
      ],
    )

    capture_io { Trigger.call }

    prompt = prompt_for(calls, "MOTO-1")
    assert_includes prompt, "Open a GitHub PR with `gh pr create` using `GITHUB_TOKEN`"
    assert_includes prompt, "Link the PR to the card"
    assert_includes prompt, "Comment on the card with a brief summary"
    assert_includes prompt, "This card has the `skip review` tag."
    assert_includes prompt, "If there are tracked repository changes, merge the linked PR immediately with `gh pr merge` using `GITHUB_TOKEN`"
    assert_includes prompt, "Operations without tracked repository changes complete without a PR when the whole task is done."
    assert_includes prompt, "resolving conflicts and passing required checks first"
    assert_includes prompt, "Verify that the PR is merged before completing the card or removing its worktree."
    assert_includes prompt, "If the merge is blocked, follow step 6."
    assert_includes prompt, "run `git pull --ff-only` there. Do not switch branches."
    assert_includes prompt, "Move the card to completed only when the whole task is done; otherwise keep it in working and record the remaining steps"
    assert_includes prompt, "Remove the working tag"
    assert_includes prompt, "Only when the whole task is done, from the main checkout, remove only this card's worktree with `git worktree remove`."
    assert_includes prompt, "Do this last, after all card updates and repository work are finished. Do not remove the main checkout."
    assert_includes prompt, "where the skill says how to finish the card, do that instead of steps 5 and 6"
    assert_includes prompt, "Move the card to planned"
    refute_includes prompt, "Move the card to review"
    assert_operator prompt.index("Link the PR to the card"), :<, prompt.index("merge the linked PR immediately")
    assert_operator prompt.index("merge the linked PR immediately"), :<, prompt.index("Move the card to completed")
    assert_operator prompt.index("Move the card to completed"), :<, prompt.index("remove only this card's worktree")
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

  def test_preserves_preset_labels_and_records_only_missing_defaults
    calls = stub_manager(items: [
      {
        id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1",
        state: { name: "Ready" },
        labels: { nodes: [ { name: "runner: openchamber" }, { name: "model: anthropic/claude-sonnet-5-5" }, { name: "variant: medium" } ] },
      },
    ])

    capture_io { Trigger.call }

    assert_equal [ { stateId: "s-working" }, { addedLabelIds: [ "l-working" ] } ], issue_update_inputs(calls)
    assert_equal "anthropic/claude-sonnet-5-5", session_for(calls, "MOTO-1")[:model]
    assert_equal "medium", session_for(calls, "MOTO-1")[:variant]
  end

  def test_omits_blank_default_variant_tag
    Settings.all[:agent][:variant] = ""
    calls = stub_manager(items: [
      { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Ready" } },
    ])

    capture_io { Trigger.call }

    labels = issue_update_inputs(calls).filter_map { |input| input[:addedLabelIds] }.flatten
    assert_equal [ "l-working", "l-runner: openchamber", "l-model: openai/gpt-6.1-sol" ], labels
    refute session_for(calls, "MOTO-1").key?(:variant) && session_for(calls, "MOTO-1")[:variant].present?
  end

  def test_preset_t3_runner_reaches_t3_transport
    calls = stub_manager(items: [
      {
        id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Ready" },
        labels: { nodes: [ { name: "runner: t3" }, { name: "model: openai/gpt-6.1-sol" } ] },
      },
    ])
    home = File.join(@worktree_test_dir, "t3")
    FileUtils.mkdir_p(File.join(home, "caches"))
    File.write(File.join(home, "caches/codex.json"), JSON.generate(
      instanceId: "codex", enabled: true, status: "ready",
      models: [ { slug: "gpt-6.1-sol", capabilities: { optionDescriptors: [ { id: "reasoningEffort", options: [ { id: "high" } ] } ] } } ],
    ))
    Settings.all[:agent][:t3] = { home:, command: [ "t3" ] }
    status = Object.new
    status.define_singleton_method(:success?) { true }
    Open3.stubs(:capture3).with { |*args| args[1] == "t3" }.returns([ JSON.generate(token: "token", sessionId: "session"), "", status ])
    card_directory = Worktree.path_for({ identifier: "MOTO-1" })
    Open3.stubs(:capture3).with do |*args, **kwargs|
      args == [ "git", "worktree", "list", "--porcelain", "-z" ] && kwargs[:chdir] == File.realpath(card_directory)
    end.returns([
      "worktree #{Worktree.root}\0HEAD abc\0branch refs/heads/master\0\0worktree #{card_directory}\0HEAD def\0branch refs/heads/moto-1\0\0",
      "", status,
    ])
    requests = []
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless opts[:url].start_with?("http://127.0.0.1:3773/")

      requests << opts
      true
    end.returns({ projects: [], sequence: 1 })

    capture_io { Trigger.call }

    assert_equal [ { stateId: "s-working" }, { addedLabelIds: [ "l-working" ] }, { addedLabelIds: [ "l-variant: high" ] } ], issue_update_inputs(calls)
    turn = requests.find { |item| item.dig(:payload, :type) == "thread.turn.start" }
    assert_includes turn.dig(:payload, :message, :text), "MOTO-1"
    assert_equal "codex", turn.dig(:payload, :modelSelection, :instanceId)
    project = requests.find { |item| item.dig(:payload, :type) == "project.create" }
    thread = requests.find { |item| item.dig(:payload, :type) == "thread.create" }
    assert_equal File.realpath(Worktree.root), project.dig(:payload, :workspaceRoot)
    assert_equal File.realpath(card_directory), thread.dig(:payload, :worktreePath)
    assert_equal "moto-1", thread.dig(:payload, :branch)
    assert_nil session_for(calls, "MOTO-1")
  end

  def test_merges_approved_card_without_starting_agent
    calls = stub_manager(items: [
      { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { name: "Approved" } },
    ])
    stub_automatic_merge

    output, = capture_io { Trigger.call }

    assert_equal "updated master\nmerged MOTO-3\n", output
    assert_equal [ { addedLabelIds: [ "l-working" ] }, { stateId: "s-completed" }, { removedLabelIds: [ "l-working" ] } ], issue_update_inputs(calls)
    assert_nil session_for(calls, "MOTO-3")
    assert_includes git_commands, [ "gh", "pr", "merge", "https://github.com/grahamotte/codemoto.org/pull/3", "--repo", "grahamotte/codemoto.org", "--merge", "--match-head-commit", "abc" ]
    assert_includes git_commands, [ "git", "pull", "--ff-only", "origin", "master" ]
  end

  def test_completes_automatic_merge_without_pulling_dirty_checkout
    calls = stub_manager(items: [
      { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { name: "Approved" } },
    ])
    stub_automatic_merge
    Open3.stubs(:capture3).with("git", "status", "--porcelain", chdir: Worktree.root).returns([ " M file.rb", "", Struct.new(:success?).new(true) ])

    output, = capture_io { Trigger.call }

    assert_equal "merged MOTO-3\n", output
    assert_includes issue_update_inputs(calls), { stateId: "s-completed" }
    refute git_commands.any? { |command| command[1] == "pull" }
    assert_nil session_for(calls, "MOTO-3")
  end

  def test_falls_back_when_main_checkout_cannot_be_updated
    calls = stub_manager(items: [
      { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { name: "Approved" } },
    ])
    stub_automatic_merge
    Open3.stubs(:capture3).with("git", "pull", "--ff-only", "origin", "master", chdir: Worktree.root).returns([ "", "diverged", Struct.new(:success?).new(false) ])

    output, = capture_io { Trigger.call }

    assert_includes output, "diverged"
    refute_includes issue_update_inputs(calls), { stateId: "s-completed" }
    assert session_for(calls, "MOTO-3").present?
  end

  def test_falls_back_to_agent_when_automatic_merge_command_fails
    calls = stub_manager(items: [
      { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { name: "Approved" } },
    ])
    Open3.stubs(:capture3).with("mise", "linear", "issues", "read", "MOTO-3", "--with-attachments", chdir: Worktree.root).returns([
      "", "could not read card", Struct.new(:success?).new(false),
    ])

    output, = capture_io { Trigger.call }

    assert_includes output, "automatic merge failed for MOTO-3:"
    assert_includes output, "could not read card"
    assert_includes output, "merging MOTO-3"
    assert_equal [ { addedLabelIds: [ "l-working" ] }, *default_label_inputs ], issue_update_inputs(calls)
    assert session_for(calls, "MOTO-3").present?
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
      [ { addedLabelIds: [ "l-working" ] }, *default_label_inputs ],
      issue_update_inputs(calls),
    )
    prompt = prompt_for(calls, "MOTO-3")
    assert_includes prompt, "This Linear issue is approved: https://linear.app/gotte/issue/MOTO-3"
    assert_includes prompt, "The manager runs this card. Do not use the `interactive-card` skill."
    assert_includes prompt, "Rebase the GitHub PR on the card."
    assert_includes prompt, "Merge the PR with `gh pr merge` using `GITHUB_TOKEN`."
    assert_includes prompt, "Remove the working tag."
    assert_includes prompt, "Move the card to completed. Do this only when the whole task is done; otherwise keep it in working and record the remaining steps."
    assert_includes prompt, "Read the card and all comments before merging."
    assert_includes prompt, "If they show remaining steps beyond the PR, record them and keep the card in working after the merge; do not complete it."
    assert_includes prompt, "If the main checkout is on master or main and has no uncommitted changes, run `git pull --ff-only` there. Do not switch branches."
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
        *default_label_inputs,
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
        *default_label_inputs,
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
    refute git_commands.any? { |command| command[1] == "pull" }
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

    assert_equal "removed worktree for MOTO-4\nupdated master\nremoved worktree for MOTO-5\n", output
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

    assert_equal "removed worktree for MOTO-4\nupdated master\n", output
    refute Dir.exist?(path)
  end

  def test_does_not_pull_master_for_canceled_cards
    FileUtils.mkdir_p(Worktree.path_for({ identifier: "MOTO-5" }))
    calls = stub_manager(
      items: [
        { id: "item-5", identifier: "MOTO-5", url: "https://linear.app/gotte/issue/MOTO-5", state: { id: "s-canceled", name: "Canceled" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "removed worktree for MOTO-5\n", output
    assert_empty issue_update_inputs(calls)
    refute git_commands.any? { |command| command[1] == "pull" }
  end

  def test_pulls_master_once_when_removing_completed_worktrees
    FileUtils.mkdir_p(Worktree.path_for({ identifier: "MOTO-4" }))
    FileUtils.mkdir_p(Worktree.path_for({ identifier: "MOTO-10" }))
    stub_manager(
      items: [
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
        { id: "item-4b", identifier: "MOTO-10", url: "https://linear.app/gotte/issue/MOTO-10", state: { id: "s-completed", name: "Completed" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "removed worktree for MOTO-4\nremoved worktree for MOTO-10\nupdated master\n", output
    assert_equal 1, git_commands.count { |command| command == [ "git", "pull", "--ff-only", "origin", "master" ] }
    refute git_commands.any? { |command| command[1] == "checkout" }
  end

  def test_skips_master_pull_when_not_on_master_or_main
    FileUtils.mkdir_p(Worktree.path_for({ identifier: "MOTO-4" }))
    stub_manager(
      items: [
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
      ],
    )
    ok = Object.new
    ok.define_singleton_method(:success?) { true }
    Open3.stubs(:capture3).with("git", "branch", "--show-current", chdir: Worktree.root).returns([ "moto-56\n", "", ok ])

    output, = capture_io { Trigger.call }

    assert_equal "removed worktree for MOTO-4\n", output
    refute git_commands.any? { |command| command[1] == "pull" }
  end

  def test_skips_master_pull_when_dirty
    FileUtils.mkdir_p(Worktree.path_for({ identifier: "MOTO-4" }))
    stub_manager(
      items: [
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
      ],
    )
    ok = Object.new
    ok.define_singleton_method(:success?) { true }
    Open3.stubs(:capture3).with("git", "status", "--porcelain", chdir: Worktree.root).returns([ " M file.rb\n", "", ok ])

    output, = capture_io { Trigger.call }

    assert_equal "removed worktree for MOTO-4\n", output
    refute git_commands.any? { |command| command[1] == "pull" }
  end

  def test_continues_when_master_pull_fails
    FileUtils.mkdir_p(Worktree.path_for({ identifier: "MOTO-4" }))
    stub_manager(
      items: [
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
      ],
    )
    failed = Object.new
    failed.define_singleton_method(:success?) { false }
    Open3.stubs(:capture3).with("git", "pull", "--ff-only", "origin", "master", chdir: Worktree.root).returns(
      [ "", "network error", failed ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "removed worktree for MOTO-4\nfailed to update master: git pull --ff-only origin master failed: network error\n", output
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
    assert_equal 9, calls.count { |call| graphql?(call, "mutation IssueUpdate") }
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
    assert_equal 9, calls.count { |call| graphql?(call, "mutation IssueUpdate") }
    assert_includes prompt_for(calls, "MOTO-1"), "This session is already in the card worktree. Env files and schema.rb were copied from the main checkout."
    assert_includes prompt_for(calls, "MOTO-1"), "Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits."
    assert_includes prompt_for(calls, "MOTO-3"), "Rebase the GitHub PR on the card."
    assert_includes prompt_for(calls, "MOTO-3"), "Do not assign users to cards when creating or working on them. Leave existing assignees unchanged."
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

  def test_skips_legacy_interactive_cards_before_label_migration
    calls = stub_manager(items: [
      { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Ready" }, labels: { nodes: [ { name: "interactive" } ] } },
    ])

    output, = capture_io { Trigger.call }

    assert_equal "", output
    assert_empty issue_update_inputs(calls)
  end

  def test_skips_interactive_cards_in_ready
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" }, labels: { nodes: [ { id: "l-interactive", name: "runner: interactive" } ] } },
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
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-ready", name: "Ready" }, labels: { nodes: [ { id: "l-interactive", name: "RUNNER: INTERACTIVE" } ] } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "", output
    assert_empty issue_update_inputs(calls)
  end

  def test_merges_interactive_cards_when_approved
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" }, labels: { nodes: [ { id: "l-interactive", name: "Runner: Interactive" } ] } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "merging MOTO-3\n", output
    assert_includes prompt_for(calls, "MOTO-3"), "This Linear issue is approved: https://linear.app/gotte/issue/MOTO-3"
    assert_equal "openai/gpt-6.1-sol", session_for(calls, "MOTO-3")[:model]
    labels = issue_update_inputs(calls).filter_map { |input| input[:addedLabelIds] }.flatten
    assert_equal [ "l-working", "l-model: openai/gpt-6.1-sol", "l-variant: high" ], labels
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
      [ { addedLabelIds: [ "l-working" ] }, *default_label_inputs ],
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
    @git_commands = []
    ok = Object.new
    ok.define_singleton_method(:success?) { true }
    Open3.stubs(:capture3).with do |*args, **_kwargs|
      next false if args == [ "git", "branch", "--show-current" ]
      next false if args == [ "git", "status", "--porcelain" ]

      @git_commands << args
      if args[1] == "worktree" && args[2] == "add"
        path = args[3] == "-b" ? args[5] : args[3]
        FileUtils.mkdir_p(path)
      elsif args[1] == "worktree" && args[2] == "remove"
        FileUtils.remove_entry(args.last) if Dir.exist?(args.last)
      end
      true
    end.returns([ "", "", ok ])
    Open3.stubs(:capture3).with("mise", "linear", "issues", "read", anything, "--with-attachments", chdir: Worktree.root).returns([ JSON.generate(attachments: { nodes: [] }), "", ok ])
    Open3.stubs(:capture3).with("git", "branch", "--show-current", chdir: Worktree.root).returns([ "master\n", "", ok ])
    Open3.stubs(:capture3).with("git", "status", "--porcelain", chdir: Worktree.root).returns([ "", "", ok ])
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
                { id: "s-completed", name: "Completed", type: "completed" },
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
              nodes: Linear::TAGS.map { |tag| { id: "l-#{tag[:name]}", **tag } },
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

  def stub_automatic_merge
    url = "https://github.com/grahamotte/codemoto.org/pull/3"
    ok = Struct.new(:success?).new(true)
    Open3.stubs(:capture3).with("mise", "linear", "issues", "read", "MOTO-3", "--with-attachments", chdir: Worktree.root).returns([
      JSON.generate(attachments: { nodes: [ { url: } ] }), "", ok,
    ])
    pr = { state: "OPEN", baseRefName: "master", headRefOid: "abc", mergeable: "MERGEABLE", mergeStateStatus: "CLEAN" }
    Open3.stubs(:capture3).with("gh", "pr", "view", url, "--repo", "grahamotte/codemoto.org", "--json", "state,baseRefName,headRefOid,mergeable,mergeStateStatus", chdir: Worktree.root).returns(
      [ JSON.generate(pr), "", ok ],
      [ JSON.generate(pr.merge(state: "MERGED")), "", ok ],
    )

  end

  def default_label_inputs
    [
      { addedLabelIds: [ "l-runner: openchamber" ] },
      { addedLabelIds: [ "l-model: openai/gpt-6.1-sol" ] },
      { addedLabelIds: [ "l-variant: high" ] },
    ]
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

  def git_commands
    @git_commands || []
  end
end
