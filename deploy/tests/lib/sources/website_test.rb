require_relative "../../test_helper"

class Sources::WebsiteTest < Minitest::Test
  def teardown
    Sources::Website.checkout = nil
    super
  end

  def test_droplet
    refute Sources::Website.droplet?
  end

  def test_paths
    Sources::Website.checkout = nil

    assert_equal File.join(Constants.local_root, "deploy", "tmp", "website"), Sources::Website.checkout
    assert_equal File.join(Constants.local_root, "deploy", "tmp", "website", "website"), Sources::Website.root
  end

  def test_wrangler_config
    assert_equal(
      {
        name: "example-com",
        compatibility_date: Sources::Website::COMPATIBILITY_DATE,
        assets: { directory: "./dist", not_found_handling: "404-page" },
        routes: [
          { pattern: "example.com", custom_domain: true },
          { pattern: "www.example.com", custom_domain: true },
        ],
      },
      Sources::Website.wrangler_config,
    )
  end

  def test_droplet_record
    assert Sources::Website.droplet_record?(name: "example.com", type: "A", proxied: false)
    assert Sources::Website.droplet_record?(name: "www.example.com", type: "CNAME", proxied: false)
    refute Sources::Website.droplet_record?(name: "example.com", type: "AAAA", proxied: true)
    refute Sources::Website.droplet_record?(name: "example.com", type: "MX", proxied: false)
    refute Sources::Website.droplet_record?(name: "app.example.com", type: "A", proxied: false)
  end
end
