require "test_helper"

class SettingsTest < ActiveSupport::TestCase
  def setup
    super
    @local_domain = ENV.delete("LOCAL_DOMAIN")
  end

  def teardown
    ENV["LOCAL_DOMAIN"] = @local_domain
    Settings.instance_variable_set(:@all, nil)
  end

  def test_reads_root_config
    assert_equal File.expand_path("../../../config.json", __dir__), Settings.path
    assert_equal JSON.parse(File.read(Settings.path), symbolize_names: true), Settings.all
  end

  def test_local_domain_uses_domain_label
    configure

    assert_equal "example.localhost", Settings.local_domain
  end

  def test_local_domain_uses_database_without_domain
    configure(domain: "")

    assert_equal "sundial.localhost", Settings.local_domain
  end

  def test_local_domain_prefers_local_domain
    configure
    ENV["LOCAL_DOMAIN"] = "custom"

    assert_equal "custom.localhost", Settings.local_domain
  end

  def test_local_domain_ignores_blank_local_domain
    configure
    ENV["LOCAL_DOMAIN"] = ""

    assert_equal "example.localhost", Settings.local_domain
  end

  def test_url
    configure

    assert_equal "https://api.example.com", Settings.url("api")
    assert_equal "https://example.com", Settings.url("website")
  end

  def test_development_url
    configure

    assert_equal "https://api.example.localhost", Settings.development_url("api")
    assert_equal "https://example.localhost", Settings.development_url("website")
  end

  def test_origins_exclude_backend_subdomains
    configure

    assert_equal(
      [ "https://example.com", "https://www.example.com", "https://app.example.com" ],
      Settings.origins,
    )
  end

  def test_development_origins
    configure
    origins = Settings.development_origins

    assert(origins.any? { |x| x.match?("https://app.example.localhost") })
    assert(origins.any? { |x| x.match?("https://example.localhost") })
    assert(origins.any? { |x| x.match?("https://quiet-river.trycloudflare.com") })
    refute(origins.any? { |x| x.match?("https://app.other.localhost") })
    refute(origins.any? { |x| x.match?("https://example.localhost.evil.com") })
  end

  private

  def configure(domain: "example.com")
    Settings.instance_variable_set(
      :@all,
      {
        domain:,
        database: "sundial",
        subdomains: [
          { name: "website", subdomains: [ "", "www" ], source: "website" },
          { name: "app", subdomains: [ "app" ], source: "frontend" },
          { name: "api", subdomains: [ "api" ], source: "backend" },
          { name: "jobs", subdomains: [ "jobs" ], source: "backend" },
        ],
      },
    )
  end
end
