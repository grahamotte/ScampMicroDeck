require_relative "../test_helper"

class SubdomainsTest < Minitest::Test
  def test_domains
    assert_equal(
      [ "example.com", "www.example.com" ],
      Subdomains.domains(subdomains: [ "", "www" ]),
    )
  end

  def test_all_frontends_and_domains
    assert_equal [ "website", "app", "hc", "api", "jobs" ], Subdomains.all.map { |x| x[:name] }
    assert_equal [ "app", "hc" ], Subdomains.frontends.map { |x| x[:name] }
    assert_equal(
      [ "app.example.com", "hc.example.com", "api.example.com", "jobs.example.com" ],
      Subdomains.domains,
    )
  end

  def test_websites
    assert_equal [ "website" ], Subdomains.websites.map { |x| x[:name] }
    assert_equal [ "app", "hc", "api", "jobs" ], Subdomains.droplet.map { |x| x[:name] }
    assert_equal [ "example.com", "www.example.com" ], Subdomains.website_domains
  end

  def test_source
    assert_equal(
      [ Sources::Website, Sources::Frontend, Sources::Frontend, Sources::Backend, Sources::Backend ],
      Subdomains.all.map { |x| Subdomains.source(x) },
    )
  end

  def test_from
    assert_equal [ "api", "jobs" ], Subdomains.from("backend").map { |x| x[:name] }
    assert_equal [ "app", "hc" ], Subdomains.from("frontend").map { |x| x[:name] }
  end

  def test_all_requires_known_source
    File.write(
      Constants.config_path,
      JSON.generate(domain: "example.com", subdomains: [ { name: "app", subdomains: [ "app" ] } ]),
    )
    Constants.instance_variable_set(:@config, nil)

    error = assert_raises(RuntimeError) { Subdomains.all }
    assert_equal "config.json subdomain app has unknown source nil", error.message
  end

  def test_url
    assert_equal "https://api.example.com", Subdomains.url("api")
    assert_equal "https://example.com", Subdomains.url("website")
  end

  def test_droplet
    assert Subdomains.droplet?

    Subdomains.instance_variable_set(:@all, [ { name: "website", subdomains: [ "" ], source: "website" } ])

    refute Subdomains.droplet?
    assert_equal [], Subdomains.domains
  end
end
