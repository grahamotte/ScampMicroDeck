require "test_helper"

class SettingsTest < ActiveSupport::TestCase
  def setup
    super
    @local_domain = ENV.delete("LOCAL_DOMAIN")
  end

  def teardown
    ENV["LOCAL_DOMAIN"] = @local_domain
  end

  def test_reads_root_config
    assert_equal File.expand_path("../../../config.json", __dir__), Settings.path
    assert_equal JSON.parse(File.read(Settings.path), symbolize_names: true), Settings.all
  end

  def test_development_url_uses_domain_label
    assert_equal "https://#{Settings.all.fetch(:domain).split(".").first}.localhost", Settings.development_url
  end

  def test_development_url_prefers_local_domain
    ENV["LOCAL_DOMAIN"] = "custom"

    assert_equal "https://custom.localhost", Settings.development_url
  end

  def test_development_url_ignores_blank_local_domain
    ENV["LOCAL_DOMAIN"] = ""

    assert_equal "https://#{Settings.all.fetch(:domain).split(".").first}.localhost", Settings.development_url
  end
end
