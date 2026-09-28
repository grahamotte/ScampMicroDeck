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
end
