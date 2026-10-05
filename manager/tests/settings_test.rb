require_relative "test_helper"

class SettingsTest < Minitest::Test
  def test_reads_configured_path
    assert_equal "codemoto.org", Settings.all[:domain]
  end

  def test_memoizes_until_reset
    Settings.all
    File.write(Settings.path, JSON.generate(domain: "other.org"))

    assert_equal "codemoto.org", Settings.all[:domain]
  end

  def test_reset_restores_default_path
    Settings.reset

    assert_equal File.expand_path("../../config.json", __dir__), Settings.path
    assert Settings.all.key?(:domain)
  end
end
