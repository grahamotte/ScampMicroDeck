require_relative "test_helper"

class SettingsTest < Minitest::Test
  def test_reads_configured_path
    assert_equal "gotte", Settings.all.dig(:linear, :workspace)
    assert_equal "high", Settings.all.dig(:agent, :variant)
  end

  def test_memoizes_until_reset
    Settings.all
    File.write(Settings.path, JSON.generate(linear: { workspace: "other" }))

    assert_equal "gotte", Settings.all.dig(:linear, :workspace)
  end

  def test_reset_restores_default_path
    Settings.reset

    assert_equal File.expand_path("../../config.json", __dir__), Settings.path
    assert Settings.all.key?(:linear)
  end

  def test_legacy_defaults_are_ignored_and_global_secrets_are_not_copied
    write_global(agentDefaults: { runner: "t3", model: "legacy-model", variant: "medium" }, "1passwordServiceAccountToken": "private-token")
    File.write(Settings.path, JSON.generate(linear: { workspace: "local" }))

    assert_equal({}, Settings.all[:agent])
    assert_equal "local", Settings.all.dig(:linear, :workspace)
    refute Settings.all.key?(:"1passwordServiceAccountToken")
  end

  def test_repository_settings_are_kept_separate_from_balanced_defaults
    write_global(agentDefaultsBalance: [ { runner: "t3", model: "openai/gpt-6.1-sol", variant: "medium" } ])
    File.write(Settings.path, JSON.generate(agent: { variant: "", t3: { speed: "normal" } }))

    assert_equal({ variant: "", t3: { speed: "normal" } }, Settings.all[:agent])
  end

  def test_missing_global_config_preserves_local_settings
    assert_equal "openchamber", Settings.all.dig(:agent, :runner)
    assert_equal({}, Settings.global)
  end

  def test_global_config_is_memoized_until_reset
    write_global(agentDefaults: { model: "first" })
    assert_equal "first", Settings.global.dig(:agentDefaults, :model)
    write_global(agentDefaults: { model: "second" })
    assert_equal "first", Settings.global.dig(:agentDefaults, :model)
    global_path = Settings.global_path
    Settings.reset
    Settings.global_path = global_path
    assert_equal "second", Settings.global.dig(:agentDefaults, :model)
  end

  def test_service_account_token_comes_from_global_config
    write_global("1passwordServiceAccountToken": "private-token")

    assert_equal "private-token", Settings.service_account_token
  end

  def test_missing_or_invalid_service_account_token_has_actionable_error
    [ nil, "", " ", 42 ].each do |token|
      Settings.reset
      Settings.global_path = File.join(@worktree_test_dir, "global-config.json")
      write_global("1passwordServiceAccountToken": token)

      error = assert_raises(RuntimeError) { Settings.service_account_token }
      assert_includes error.message, "Set 1passwordServiceAccountToken"
    end
  end

  def test_invalid_global_json_does_not_expose_contents
    File.write(Settings.global_path, '{"1passwordServiceAccountToken": "private-token", broken}')

    error = assert_raises(RuntimeError) { Settings.global }
    assert_includes error.message, Settings.global_path
    refute_includes error.message, "private-token"
  end

  def test_global_config_requires_an_object
    write_global([])

    error = assert_raises(RuntimeError) { Settings.global }
    assert_includes error.message, "must be an object"
  end

  def test_balanced_defaults_require_valid_t3_selections
    [
      nil,
      [],
      "private-invalid-value",
      [ "private-invalid-value" ],
      [ { runner: "openchamber", model: "openai/model" } ],
      [ { runner: "t3", model: "../private-invalid-value" } ],
      [ { runner: "t3", model: "openai/model", variant: 42 } ],
    ].each do |invalid|
      Settings.reset
      Settings.global_path = File.join(@worktree_test_dir, "global-config.json")
      write_global(agentDefaultsBalance: invalid)

      error = assert_raises(RuntimeError) { Settings.global }
      assert_includes error.message, "agentDefaultsBalance must be a nonempty array"
      refute_includes error.message, "private-invalid-value"
    end
  end

  def test_balanced_defaults_allow_missing_and_blank_variants
    candidates = [ { runner: "t3", model: "openai/model" }, { runner: "t3", model: "anthropic/model", variant: "" } ]
    write_global(agentDefaultsBalance: candidates)

    assert_equal candidates, Settings.global[:agentDefaultsBalance]
  end

  def test_reset_restores_default_global_path
    Settings.reset

    assert_equal File.expand_path("~/.config/codemoto/config.json"), Settings.global_path
  end

  private

  def write_global(config)
    File.write(Settings.global_path, JSON.generate(config))
  end

end
