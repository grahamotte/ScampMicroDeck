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

  def test_rails_max_threads_is_optional
    Settings.instance_variable_set(:@all, { database: "sundial" })

    assert_nil Settings.rails_max_threads

    Settings.instance_variable_set(:@all, { database: "sundial", railsMaxThreads: 8 })

    assert_equal 8, Settings.rails_max_threads
  end

  def test_root
    assert_equal File.expand_path("../../..", __dir__), Settings.root
  end

  def test_test_database_for_main_checkout
    configure

    Dir.mktmpdir do |dir|
      Dir.mkdir(File.join(dir, ".git"))

      assert_equal "sundial_test", Settings.test_database(dir)
    end
  end

  def test_test_database_for_worktree
    configure

    Dir.mktmpdir do |dir|
      checkout = File.join(dir, "Sundial-moto.175")
      Dir.mkdir(checkout)
      File.write(File.join(checkout, ".git"), "gitdir: /tmp/x")

      assert_equal "sundial_test_sundial_moto_175", Settings.test_database(checkout)
    end
  end

  def test_test_database_fits_parallel_worker_suffix
    configure

    Dir.mktmpdir do |dir|
      checkout = File.join(dir, "a" * 80)
      Dir.mkdir(checkout)
      File.write(File.join(checkout, ".git"), "gitdir: /tmp/x")

      assert_equal "sundial_test_#{"a" * 43}", Settings.test_database(checkout)
    end
  end

  def test_stale_test_databases
    configure

    Dir.mktmpdir do |dir|
      main = File.join(dir, "Sundial")
      live = File.join(dir, "Sundial-live-1")
      Dir.mkdir(main)
      Dir.mkdir(File.join(main, ".git"))
      Dir.mkdir(live)
      File.write(File.join(live, ".git"), "gitdir: /tmp/x")
      databases = [
        "postgres",
        "sundial_development",
        "sundial_test",
        "sundial_test_0",
        "sundial_test_sundial_live_1",
        "sundial_test_sundial_live_1_2",
        "sundial_test_sundial_live",
        "sundial_test_sundial_gone",
        "sundial_test_sundial_gone_1",
        "other_test_sundial_gone",
      ]

      assert_equal(
        [ "sundial_test_sundial_live", "sundial_test_sundial_gone", "sundial_test_sundial_gone_1" ],
        Settings.stale_test_databases(databases, [ main, live ]),
      )
    end
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

  def test_urls_are_nil_without_subdomain
    configure

    assert_nil Settings.url("missing")
    assert_nil Settings.development_url("missing")
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
