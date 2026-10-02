require_relative "test_helper"

class AgentSelectionTest < Minitest::Test
  def setup
    super
    @home = File.join(@worktree_test_dir, "t3")
    @candidates = [
      { runner: "t3", model: "openai/gpt-6.1-sol", variant: "medium" },
      { runner: "t3", model: "anthropic/claude-opus-5-5", variant: "medium" },
    ]
    File.write(Settings.global_path, JSON.generate(agentDefaultsBalance: @candidates))
    File.write(Settings.path, JSON.generate(agent: { t3: { home: @home } }))
    @refreshes = []
    @refresh = nil
    socket = Object.new
    socket.define_singleton_method(:send) { |message| }
    socket.define_singleton_method(:close) {}
    socket.define_singleton_method(:on) do |event, &callback|
      callback.call if event == :open
      callback.call(Struct.new(:data).new(JSON.generate(_tag: "Exit", requestId: "1", exit: { _tag: "Success" }))) if event == :message
    end
    Open3.stubs(:capture3).with { |*args| args[1] == "t3" }.returns([
      JSON.generate(token: "quota-token", sessionId: "quota-session"), "", Struct.new(:success?).new(true),
    ])
    Settings.all[:agent][:t3][:command] = [ "t3" ]
    WebSocket::Client::Simple.stubs(:connect).with do |url, **options|
      @refreshes << url
      @refresh&.call
      true
    end.yields(socket).returns(socket)
    @now = Time.now
    write_catalog("codex", "gpt-6.1-sol", weekly: 33)
    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 88, session: 50)
  end

  def test_draws_down_higher_weekly_quota_until_session_reserve
    assert_equal @candidates.last, AgentSelection.resolve

    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 75, session: 5)
    assert_equal @candidates.last, AgentSelection.resolve

    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 75, session: 4.9)
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_selects_highest_remaining_weekly_quota_and_breaks_ties_by_list_order
    write_catalog("codex", "gpt-6.1-sol", weekly: 90)
    assert_equal @candidates.first, AgentSelection.resolve
    write_catalog("codex", "gpt-6.1-sol", weekly: 88)
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_rereads_quota_on_each_selection
    assert_equal @candidates.last, AgentSelection.resolve
    write_catalog("codex", "gpt-6.1-sol", weekly: 99)
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_blocks_exhausted_weekly_and_monthly_windows
    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 0)
    assert_equal @candidates.first, AgentSelection.resolve
    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 88, monthly: 4)
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_uses_most_restrictive_weekly_window
    edit_catalog do |catalog|
      catalog[:usageLimits][:windows] << { kind: "weekly", usedPercent: 90 }
    end
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_skips_missing_corrupt_and_unavailable_catalogs
    File.delete(catalog_path)
    assert_equal @candidates.first, AgentSelection.resolve
    File.write(catalog_path, "invalid JSON")
    assert_equal @candidates.first, AgentSelection.resolve
    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 88)
    edit_catalog { |catalog| catalog[:usageLimits][:unavailable] = { reason: "probeFailed" } }
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_skips_stale_future_and_expired_snapshots
    [ @now - 301, @now + 60 ].each do |checked|
      edit_catalog { |catalog| catalog[:usageLimits][:checkedAt] = checked.iso8601 }
      assert_equal @candidates.first, AgentSelection.resolve
    end
    edit_catalog do |catalog|
      catalog[:usageLimits][:checkedAt] = @now.iso8601
      catalog[:usageLimits][:windows].first[:resetsAt] = (@now - 1).iso8601
    end
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_skips_invalid_usage_and_missing_weekly_windows
    [ nil, "12", -1, 101 ].each do |used|
      edit_catalog { |catalog| catalog[:usageLimits][:windows].first[:usedPercent] = used }
      assert_equal @candidates.first, AgentSelection.resolve
    end
    edit_catalog { |catalog| catalog[:usageLimits][:windows] = [ { kind: "session", usedPercent: 0 } ] }
    assert_equal @candidates.first, AgentSelection.resolve
  end

  def test_skips_disabled_unready_and_incompatible_models
    [ { enabled: false }, { status: "error" }, { models: [] } ].each do |changes|
      write_catalog("claudeAgent", "claude-opus-5-5", weekly: 88)
      edit_catalog { |catalog| catalog.merge!(changes) }
      assert_equal @candidates.first, AgentSelection.resolve
    end
    assert_equal @candidates.first.merge(variant: "high"), AgentSelection.resolve(variant: "high")
  end

  def test_raises_when_all_providers_are_unsafe
    write_catalog("codex", "gpt-6.1-sol", weekly: 0)
    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 88, session: 0)
    error = assert_raises(RuntimeError) { AgentSelection.resolve }
    assert_includes error.message, "No balanced agent provider"
  end

  def test_explicit_model_bypasses_balance_and_uses_matching_variant
    File.delete(catalog_path)
    assert_equal @candidates.last, AgentSelection.resolve(model: @candidates.last[:model])
    assert_equal @candidates.last.merge(variant: "high"), AgentSelection.resolve(model: @candidates.last[:model], variant: "high")
  end

  def test_repository_overrides_and_blank_variant_are_preserved
    Settings.all[:agent].merge!(model: @candidates.first[:model], variant: "")
    assert_equal @candidates.first.merge(variant: ""), AgentSelection.resolve
    assert_equal @candidates.last.merge(variant: ""), AgentSelection.resolve(model: @candidates.last[:model])
  end

  def test_explicit_non_t3_runner_and_model_are_preserved
    assert_equal(
      { runner: "openchamber", model: "custom/model", variant: "high" },
      AgentSelection.resolve(runner: "openchamber", model: "custom/model", variant: "high"),
    )
  end

  def test_nil_and_blank_repository_selections_inherit_balanced_defaults
    Settings.all[:agent].merge!(runner: nil, model: " ", variant: nil)
    assert_equal @candidates.last, AgentSelection.resolve
  end

  def test_legacy_defaults_cannot_override_balanced_candidates
    Settings.global[:agentDefaults] = { runner: "openchamber", model: "legacy/model", variant: "high" }
    assert_equal @candidates.last, AgentSelection.resolve
  end

  def test_refreshes_stale_quota_and_scores_the_new_snapshot
    edit_catalog { |catalog| catalog[:usageLimits][:checkedAt] = (@now - 301).iso8601 }
    @refresh = -> { write_catalog("claudeAgent", "claude-opus-5-5", weekly: 99) }

    assert_equal @candidates.last, AgentSelection.resolve
    assert_equal [ "ws://127.0.0.1:3773/ws" ], @refreshes
  end

  def test_does_not_refresh_recent_or_undated_unusable_usage
    [
      nil,
      { checkedAt: "invalid" },
      { unavailable: { reason: "probeFailed" } },
      { checkedAt: @now.iso8601, unavailable: { reason: "probeFailed" } },
      { checkedAt: (@now + 60).iso8601, windows: [ { kind: "weekly", usedPercent: 5 } ] },
      { checkedAt: @now.iso8601, windows: [ { kind: "weekly", usedPercent: 5, resetsAt: (@now - 1).iso8601 } ] },
    ].each do |limits|
      edit_catalog { |catalog| catalog[:usageLimits] = limits }
      assert_equal @candidates.first, AgentSelection.resolve
    end
    assert_equal [], @refreshes
  end

  def test_reuses_quota_under_five_minutes_old
    edit_catalog { |catalog| catalog[:usageLimits][:checkedAt] = (@now - 299).iso8601(6) }

    assert_equal @candidates.last, AgentSelection.resolve
    assert_equal [], @refreshes
  end

  def test_refreshes_old_failed_usage_once
    edit_catalog do |catalog|
      catalog[:usageLimits] = { checkedAt: (@now - 301).iso8601, unavailable: { reason: "probeFailed" } }
    end
    @refresh = -> { write_catalog("claudeAgent", "claude-opus-5-5", weekly: 99) }

    assert_equal @candidates.last, AgentSelection.resolve
    assert_equal 1, @refreshes.length
  end

  def test_failed_refresh_keeps_other_fresh_candidates_available
    edit_catalog { |catalog| catalog[:usageLimits][:checkedAt] = (@now - 301).iso8601 }
    @refresh = -> { raise Timeout::Error }

    assert_equal @candidates.first, AgentSelection.resolve
    assert_equal 1, @refreshes.length
  end

  def test_does_not_refresh_fresh_or_exhausted_quotas_or_explicit_models
    AgentSelection.resolve
    write_catalog("claudeAgent", "claude-opus-5-5", weekly: 0)
    AgentSelection.resolve
    AgentSelection.resolve(model: @candidates.last[:model])

    assert_equal [], @refreshes
  end

  private

  def catalog_path(instance = "claudeAgent")
    File.join(@home, "caches", "#{instance}.json")
  end

  def edit_catalog
    catalog = JSON.parse(File.read(catalog_path), symbolize_names: true)
    yield catalog
    File.write(catalog_path, JSON.generate(catalog))
  end

  def write_catalog(instance, model, **quotas)
    FileUtils.mkdir_p(File.join(@home, "caches"))
    File.write(
      catalog_path(instance),
      JSON.generate(
        instanceId: instance,
        enabled: true,
        status: "ready",
        models: [
          {
            slug: model,
            capabilities: { optionDescriptors: [ { id: "reasoningEffort", options: instance == "codex" ? [ { id: "medium" }, { id: "high" } ] : [ { id: "medium" } ] } ] },
          },
        ],
        usageLimits: {
          checkedAt: @now.iso8601,
          windows: quotas.map { |kind, remaining| { kind: kind.to_s, usedPercent: 100 - remaining } },
        },
      ),
    )
  end
end
