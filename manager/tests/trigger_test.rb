require_relative "test_helper"

class TriggerTest < Minitest::Test
  def test_fetches_all_actionable_cards_and_only_recent_terminal_cards
    calls = stub_manager(items: [])

    assert_output("") { Trigger.call }

    query = calls.find { |call| graphql?(call, "query Issues") }
    assert_equal(
      {
        or: [
          { state: { name: { in: [ "🤖 Working", "Working", "🤖 Approved", "Approved" ] } } },
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

  def test_warns_when_host_keychains_need_attention
    stub_manager(items: [])
    login = Worktree.keychain.login
    other = File.join(File.dirname(login), "other.keychain-db")
    File.write(other, "other")
    stub_security(search: other, default: other)

    output, = capture_io { Trigger.call }

    assert_equal(
      [
        "WARNING: the host keychain configuration needs attention",
        "- default keychain is #{other}, not #{login}",
        "- search list does not include #{login}",
        "Run `mise manager:keychain` to restore the login keychain.",
      ],
      output.lines.map(&:chomp),
    )
  end

  def test_restores_keychains_left_by_dead_tasks_and_releases_missing_keychains
    stub_manager(items: [])
    login = Worktree.keychain.login
    missing = File.join(@worktree_test_dir, "deleted", "signing.keychain-db")
    state = File.join(Worktree.keychain.state_root, "20260101000000000000-99999999.json")
    FileUtils.mkdir_p(File.dirname(state))
    File.write(state, JSON.generate(pid: 99_999_999, snapshot: { search: [ login ], default: login }))
    stub_security(search: missing, default: missing)
    Open3.expects(:capture3).with("security", "list-keychains", "-d", "user", "-s", login).twice.returns([ "", "", Struct.new(:success?).new(true) ])
    Open3.expects(:capture3).with("security", "default-keychain", "-d", "user", "-s", login).twice.returns([ "", "", Struct.new(:success?).new(true) ])

    output, = capture_io { Trigger.call }

    assert_includes output, "restored keychains from #{state}\n"
    assert_includes output, "removed missing keychain #{missing}\n"
    refute File.exist?(state)
  end

  def test_continues_when_keychain_check_fails
    stub_manager(items: [])
    Open3.stubs(:capture3).with("security", "list-keychains", "-d", "user").returns([ "", "no keychains", Struct.new(:success?).new(false) ])

    output, = capture_io { Trigger.call }

    assert_equal "keychain check failed: security list-keychains -d user failed: no keychains\n", output
  end

  def test_starts_work_agent_for_queued_working_cards
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "🤖 Working" } },
        { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2", state: { id: "s-planned", name: "Planned" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-1\n", output
    assert_equal [ { addedLabelIds: [ "l-working" ] }, *default_label_inputs ], issue_update_inputs(calls)
    prompt = prompt_for(calls, "MOTO-1")
    assert_includes prompt, "Work this Linear card: https://linear.app/gotte/issue/MOTO-1"
    assert_includes prompt, "The manager runs this card in a new agent session. Do not use the `interactive-card` skill."
    assert_includes prompt, "Follow the card workflow in `AGENTS.md`."
    assert_includes prompt, "This session is in the card worktree, with env files and schema.rb copied from the main checkout."
    assert_includes prompt, "returned from Review with corrections in later comments"
    assert_includes prompt, "Read the card and all comments. If the card names a skill, follow it."
    assert_includes prompt, "Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits."
    assert_includes prompt, "Comment on the card with a brief summary of what changed and a short pseudocode block of how it works."
    assert_includes prompt, "Hand off with exactly one outcome, then remove the `working` tag:"
    assert_includes prompt, "- Review: tracked repository changes are ready to merge."
    assert_includes prompt, "Do not do work that depends on the merge, such as deploying"
    assert_includes prompt, "- Completed: the whole task is done and nothing awaits review or merge."
    assert_includes prompt, "- Planned: a blocker requires the user to re-evaluate the card."
    refute_includes prompt, "skip review"
    refute_includes prompt, "keep it in working"
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-2") }
    assert_equal Worktree.path_for({ identifier: "MOTO-1" }), directory_for(calls, "MOTO-1")
    assert_equal "openai/gpt-6.1-sol", session_for(calls, "MOTO-1").fetch(:model)
    assert_equal "high", session_for(calls, "MOTO-1").fetch(:variant)
  end

  def test_work_prompt_requires_handoff_for_separate_approved_agent
    calls = stub_manager(items: [
      { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Working" } },
    ])

    capture_io { Trigger.call }

    prompt = prompt_for(calls, "MOTO-1")
    assert_includes prompt, "A separate Approved agent with no memory of this session finishes the card after review"
    assert_includes prompt, "before handing off to Review, make this comment its handoff:"
    [
      "the PR to merge",
      "remaining work after the merge in order (naming skills such as `deploy`)",
      "relevant inputs and constraints",
      "work already done",
      "verification required before completion",
      "Write \"Remaining work: none\" when nothing remains after the merge.",
    ].each { |part| assert_includes prompt, part }
    assert_operator prompt.index("make this comment its handoff"), :<, prompt.index("- Review:")
  end

  def test_skip_review_prompt_merges_and_finishes_instead_of_review
    calls = stub_manager(
      items: [
        {
          id: "item-1",
          identifier: "MOTO-1",
          url: "https://linear.app/gotte/issue/MOTO-1",
          state: { name: "Working" },
          labels: { nodes: [ { name: "Skip Review" } ] },
        },
      ],
    )

    capture_io { Trigger.call }

    prompt = prompt_for(calls, "MOTO-1")
    assert_includes prompt, "- Completed: this card has the `skip review` tag, so it never goes to Review."
    assert_includes prompt, "For tracked repository changes, commit, push the card branch, create or update the card's PR, and link it to the card."
    assert_includes prompt, "Resolve conflicts and required checks, merge it and update the main checkout as described under GitHub in `AGENTS.md`, and verify it merged."
    assert_includes prompt, "Then do the remaining work, and complete the card only when its whole task is done."
    assert_includes prompt, "- Planned: a blocker requires the user to re-evaluate the card."
    refute_includes prompt, "- Review:"
    assert_operator prompt.index("link it to the card"), :<, prompt.index("merge it and update the main checkout")
    assert_operator prompt.index("verify it merged"), :<, prompt.index("Then do the remaining work")
  end

  def test_starts_agent_with_model_and_variant_labels
    calls = stub_manager(
      items: [
        {
          id: "item-1",
          identifier: "MOTO-1",
          url: "https://linear.app/gotte/issue/MOTO-1",
          state: { id: "s-working", name: "Working" },
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
        state: { name: "Working" },
        labels: { nodes: [ { name: "runner: openchamber" }, { name: "model: anthropic/claude-sonnet-5-5" }, { name: "variant: medium" } ] },
      },
    ])

    capture_io { Trigger.call }

    assert_equal [ { addedLabelIds: [ "l-working" ] } ], issue_update_inputs(calls)
    assert_equal "anthropic/claude-sonnet-5-5", session_for(calls, "MOTO-1")[:model]
    assert_equal "medium", session_for(calls, "MOTO-1")[:variant]
  end

  def test_omits_blank_default_variant_tag
    Settings.all[:agent][:variant] = ""
    calls = stub_manager(items: [
      { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Working" } },
    ])

    capture_io { Trigger.call }

    labels = issue_update_inputs(calls).filter_map { |input| input[:addedLabelIds] }.flatten
    assert_equal [ "l-working", "l-runner: openchamber", "l-model: openai/gpt-6.1-sol" ], labels
    refute session_for(calls, "MOTO-1").key?(:variant) && session_for(calls, "MOTO-1")[:variant].present?
  end

  def test_preset_t3_runner_reaches_t3_transport
    calls = stub_manager(items: [
      {
        id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Working" },
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

    assert_equal [ { addedLabelIds: [ "l-working" ] }, { addedLabelIds: [ "l-variant: high" ] } ], issue_update_inputs(calls)
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

  def test_balanced_defaults_are_recorded_and_reach_t3_transport
    calls = stub_manager(items: [
      {
        id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Working" },
      },
    ])
    home = File.join(@worktree_test_dir, "t3")
    FileUtils.mkdir_p(File.join(home, "caches"))
    File.write(File.join(home, "caches/codex.json"), JSON.generate(
      instanceId: "codex", enabled: true, status: "ready",
      models: [ { slug: "gpt-6.1-sol", capabilities: { optionDescriptors: [ { id: "reasoningEffort", options: [ { id: "high" } ] } ] } } ],
    ))
    catalog = JSON.parse(File.read(File.join(home, "caches/codex.json")), symbolize_names: true)
    catalog[:usageLimits] = { checkedAt: Time.now.iso8601, windows: [ { kind: "weekly", usedPercent: 67 } ] }
    File.write(File.join(home, "caches/codex.json"), JSON.generate(catalog))
    catalog[:instanceId] = "claudeAgent"
    catalog[:models].first[:slug] = "claude-opus-5-5"
    catalog[:usageLimits][:windows] = [ { kind: "weekly", usedPercent: 12 }, { kind: "session", usedPercent: 50 } ]
    File.write(File.join(home, "caches/claudeAgent.json"), JSON.generate(catalog))
    Settings.all[:agent] = { t3: { home:, command: [ "t3" ] } }
    File.write(Settings.global_path, JSON.generate(agentDefaultsBalance: [
      { runner: "t3", model: "openai/gpt-6.1-sol", variant: "high" },
      { runner: "t3", model: "anthropic/claude-opus-5-5", variant: "high" },
    ]))
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

    assert_equal(
      [
        { addedLabelIds: [ "l-working" ] },
        { addedLabelIds: [ "l-runner: t3" ] },
        { addedLabelIds: [ "l-model: anthropic/claude-opus-5-5" ] },
        { addedLabelIds: [ "l-variant: high" ] },
      ],
      issue_update_inputs(calls),
    )
    turn = requests.find { |item| item.dig(:payload, :type) == "thread.turn.start" }
    assert_includes turn.dig(:payload, :message, :text), "MOTO-1"
    assert_equal "claudeAgent", turn.dig(:payload, :modelSelection, :instanceId)
    project = requests.find { |item| item.dig(:payload, :type) == "project.create" }
    thread = requests.find { |item| item.dig(:payload, :type) == "thread.create" }
    assert_equal File.realpath(Worktree.root), project.dig(:payload, :workspaceRoot)
    assert_equal File.realpath(card_directory), thread.dig(:payload, :worktreePath)
    assert_equal "moto-1", thread.dig(:payload, :branch)
    assert_nil session_for(calls, "MOTO-1")
  end

  def test_leaves_working_card_queued_when_balanced_quota_is_unavailable
    calls = stub_manager(items: [
      { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Working" } },
    ])
    Settings.all[:agent] = { t3: { home: File.join(@worktree_test_dir, "missing-t3") } }
    File.write(Settings.global_path, JSON.generate(agentDefaultsBalance: [
      { runner: "t3", model: "openai/gpt-6.1-sol", variant: "medium" },
    ]))

    capture_io do
      error = assert_raises(RuntimeError) { Trigger.call }
      assert_includes error.message, "No balanced agent provider"
    end

    assert_equal [ { addedLabelIds: [ "l-working" ] }, { removedLabelIds: [ "l-working" ] } ], issue_update_inputs(calls)
    assert_nil session_for(calls, "MOTO-1")
  end

  def test_untags_working_card_when_agent_fails
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" } },
      ],
    )
    stub_failing_agent

    output, = capture_io do
      assert_raises(RuntimeError) { Trigger.call }
    end

    assert_equal "", output
    assert_equal(
      [ { addedLabelIds: [ "l-working" ] }, *default_label_inputs, { removedLabelIds: [ "l-working" ] } ],
      issue_update_inputs(calls),
    )
  end

  def test_starts_approved_agent_without_merging
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "🤖 Approved" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started approved work on MOTO-3\n", output
    assert_equal [ { addedLabelIds: [ "l-working" ] }, *default_label_inputs ], issue_update_inputs(calls)
    refute git_commands.any? { |command| command.first == "gh" }
    refute git_commands.any? { |command| command[0..2] == [ "mise", "linear", "issues" ] }
    refute git_commands.any? { |command| command[1] == "pull" }
    assert_equal Worktree.path_for({ identifier: "MOTO-3" }), directory_for(calls, "MOTO-3")
  end

  def test_approved_prompt_reads_handoff_merges_and_finishes_remaining_work
    calls = stub_manager(items: [
      { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { name: "Approved" } },
    ])

    capture_io { Trigger.call }

    prompt = prompt_for(calls, "MOTO-3")
    assert_includes prompt, "This Linear card is approved: https://linear.app/gotte/issue/MOTO-3"
    assert_includes prompt, "The manager runs this card in a new agent session with no memory of earlier sessions. Do not use the `interactive-card` skill."
    assert_includes prompt, "Approval authorizes you to merge the reviewed PR and finish the card's remaining work."
    assert_includes prompt, "Read the card and all comments, including the latest handoff comment."
    assert_includes prompt, "It names the PR to merge, the remaining work in order, and the verification required before completion."
    assert_includes prompt, "If the PR to merge is unclear, do not merge."
    assert_includes prompt, "unless it is already merged, rebase it onto the current origin main"
    assert_includes prompt, "push with `--force-with-lease`, wait for required checks, and merge it with `gh pr merge`."
    assert_includes prompt, "If the main checkout is on master or main and has no uncommitted changes, run `git pull --ff-only` there. Do not switch branches."
    assert_includes prompt, "Do the remaining work from the handoff in order, following any named skills, and record each result on the card."
    assert_includes prompt, "A missing or ambiguous handoff does not mean nothing remains."
    assert_includes prompt, "- Completed: all remaining work is done and verified."
    assert_includes prompt, "- Review: new tracked repository changes need review. Create and link a new PR and comment a new handoff."
    assert_includes prompt, "- Planned: a blocker, or a missing or ambiguous handoff, requires the user to re-evaluate the card."
    assert_operator prompt.index("including the latest handoff comment"), :<, prompt.index("merge it with `gh pr merge`")
    assert_operator prompt.index("merge it with `gh pr merge`"), :<, prompt.index("Do the remaining work from the handoff")
    assert_operator prompt.index("Do the remaining work from the handoff"), :<, prompt.index("- Completed:")
  end

  def test_approved_card_keeps_worktree_and_is_not_completed_by_manager
    path = Worktree.path_for({ identifier: "MOTO-3" })
    FileUtils.mkdir_p(path)
    File.write(File.join(path, ".git"), "gitdir: card")
    calls = stub_manager(items: [
      { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { name: "Approved" } },
    ])

    capture_io { Trigger.call }

    assert Dir.exist?(path)
    assert_equal path, directory_for(calls, "MOTO-3")
    refute issue_update_inputs(calls).any? { |input| input.key?(:stateId) }
    refute git_commands.any? { |command| command[1] == "worktree" }
  end

  def test_starts_approved_agent_in_worktree_pushing_to_card_branch
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
      ],
    )
    path = File.join(Worktree.root, ".claude/worktrees/brave-fox")
    FileUtils.mkdir_p(path)
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

    assert_equal "started approved work on MOTO-3\n", output
    assert_equal path, directory_for(calls, "MOTO-3")
  end

  def test_untags_when_approved_agent_fails
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
      ],
    )
    stub_failing_agent

    output, = capture_io do
      assert_raises(RuntimeError) { Trigger.call }
    end

    assert_equal "", output
    assert_equal(
      [ { addedLabelIds: [ "l-working" ] }, *default_label_inputs, { removedLabelIds: [ "l-working" ] } ],
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

  def test_starts_one_agent_per_column
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" } },
        { id: "item-1b", identifier: "MOTO-8", url: "https://linear.app/gotte/issue/MOTO-8", state: { id: "s-working", name: "Working" } },
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" } },
        { id: "item-3b", identifier: "MOTO-9", url: "https://linear.app/gotte/issue/MOTO-9", state: { id: "s-approved", name: "Approved" } },
        { id: "item-4", identifier: "MOTO-4", url: "https://linear.app/gotte/issue/MOTO-4", state: { id: "s-completed", name: "Completed" } },
        { id: "item-5", identifier: "MOTO-5", url: "https://linear.app/gotte/issue/MOTO-5", state: { id: "s-canceled", name: "Canceled" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-1\nstarted approved work on MOTO-3\n", output
    assert_equal 8, calls.count { |call| graphql?(call, "mutation IssueUpdate") }
    assert_includes prompt_for(calls, "MOTO-1"), "Work this Linear card"
    assert_includes prompt_for(calls, "MOTO-3"), "This Linear card is approved"
    [ "MOTO-8", "MOTO-9", "MOTO-4", "MOTO-5" ].each do |identifier|
      refute calls.any? { |call| call[:prompt].to_s.include?(identifier) }
    end
  end

  def test_copies_env_and_schema_into_worktree_before_starting
    File.write(File.join(Worktree.root, ".env.development"), "DEV=1")
    FileUtils.mkdir_p(File.join(Worktree.root, "backend/db"))
    File.write(File.join(Worktree.root, "backend/db/schema.rb"), "schema")
    stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" } },
      ],
    )

    capture_io { Trigger.call }

    path = Worktree.path_for({ identifier: "MOTO-1" })
    assert_equal "DEV=1", File.read(File.join(path, ".env.development"))
    assert_equal "schema", File.read(File.join(path, "backend/db/schema.rb"))
  end

  def test_skips_legacy_interactive_cards_before_label_migration
    calls = stub_manager(items: [
      { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { name: "Working" }, labels: { nodes: [ { name: "interactive" } ] } },
    ])

    output, = capture_io { Trigger.call }

    assert_equal "", output
    assert_empty issue_update_inputs(calls)
  end

  def test_skips_interactive_cards_in_working
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" }, labels: { nodes: [ { id: "l-interactive", name: "runner: interactive" } ] } },
        { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2", state: { id: "s-working", name: "Working" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-2\n", output
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-1") }
    assert calls.select { |call| graphql?(call, "mutation IssueUpdate") }.all? { |call| call.dig(:payload, :variables, :id) == "item-2" }
  end

  def test_skips_working_column_when_all_cards_are_interactive
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" }, labels: { nodes: [ { id: "l-interactive", name: "RUNNER: INTERACTIVE" } ] } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "", output
    assert_empty issue_update_inputs(calls)
  end

  def test_starts_approved_agent_for_interactive_cards
    calls = stub_manager(
      items: [
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" }, labels: { nodes: [ { id: "l-interactive", name: "Runner: Interactive" } ] } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started approved work on MOTO-3\n", output
    assert_includes prompt_for(calls, "MOTO-3"), "This Linear card is approved: https://linear.app/gotte/issue/MOTO-3"
    assert_equal "openai/gpt-6.1-sol", session_for(calls, "MOTO-3")[:model]
    labels = issue_update_inputs(calls).filter_map { |input| input[:addedLabelIds] }.flatten
    assert_equal [ "l-working", "l-model: openai/gpt-6.1-sol", "l-variant: high" ], labels
  end

  def test_skips_claimed_cards_with_working_tag
    calls = stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" }, labels: { nodes: [ { id: "l-working", name: "working" } ] } },
        { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2", state: { id: "s-working", name: "Working" } },
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" }, labels: { nodes: [ { id: "l-working", name: "working" } ] } },
        { id: "item-9", identifier: "MOTO-9", url: "https://linear.app/gotte/issue/MOTO-9", state: { id: "s-approved", name: "Approved" } },
      ],
    )

    output, = capture_io { Trigger.call }

    assert_equal "started working on MOTO-2\nstarted approved work on MOTO-9\n", output
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-1") }
    refute calls.any? { |call| call[:prompt].to_s.include?("MOTO-3") }
    updated = calls.select { |call| graphql?(call, "mutation IssueUpdate") }.map { |call| call.dig(:payload, :variables, :id) }.uniq
    assert_equal [ "item-2", "item-9" ], updated
  end

  def test_skips_columns_when_all_cards_have_working_tag
    stub_manager(
      items: [
        { id: "item-1", identifier: "MOTO-1", url: "https://linear.app/gotte/issue/MOTO-1", state: { id: "s-working", name: "Working" }, labels: { nodes: [ { id: "l-working", name: "working" } ] } },
        { id: "item-3", identifier: "MOTO-3", url: "https://linear.app/gotte/issue/MOTO-3", state: { id: "s-approved", name: "Approved" }, labels: { nodes: [ { id: "l-working", name: "working" } ] } },
      ],
    )

    assert_output("") { Trigger.call }
  end

  def test_prints_nothing_when_nothing_is_triggered
    stub_manager(
      items: [
        { id: "item-2", identifier: "MOTO-2", url: "https://linear.app/gotte/issue/MOTO-2", state: { id: "s-planned", name: "Planned" } },
        { id: "item-6", identifier: "MOTO-6", url: "https://linear.app/gotte/issue/MOTO-6", state: { id: "s-review", name: "Review" } },
      ],
    )

    assert_output("") { Trigger.call }
  end

  private

  def graphql?(opts, fragment)
    opts[:url] == Linear::HOST && opts.dig(:payload, :query).to_s.include?(fragment)
  end

  def stub_security(search:, default:)
    ok = Struct.new(:success?).new(true)
    Open3.stubs(:capture3).with("security", "list-keychains", "-d", "user").returns([ "\"#{search}\"\n", "", ok ])
    Open3.stubs(:capture3).with("security", "default-keychain", "-d", "user").returns([ "\"#{default}\"\n", "", ok ])
  end

  def stub_manager(items:)
    calls = []
    @git_commands = []
    ok = Object.new
    ok.define_singleton_method(:success?) { true }
    Open3.stubs(:capture3).with do |*args, **_kwargs|
      next false if args.first == "security"
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
                { id: "s-working", name: "🤖 Working", type: "started" },
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

  def stub_failing_agent
    Req.stubs(:call).with do |*args, **kwargs|
      opts = req_opts(args, kwargs)
      next false unless opts[:url].to_s.end_with?("/api/openchamber/sessions")

      true
    end.raises("agent failed")
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
