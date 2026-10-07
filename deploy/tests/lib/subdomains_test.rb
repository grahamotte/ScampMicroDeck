require_relative "../test_helper"

class SubdomainsTest < Minitest::Test
  def test_domains
    assert_equal(
      [ "example.com", "www.example.com" ],
      Subdomains.domains(subdomains: [ "", "www" ]),
    )
  end

  def test_all_frontends_domains_and_dist
    assert_equal [ "www", "hc", "jobs" ], Subdomains.all.map { |x| x[:name] }
    assert_equal [ "www", "hc" ], Subdomains.frontends.map { |x| x[:name] }
    assert_equal(
      [ "example.com", "www.example.com", "hc.example.com", "jobs.example.com" ],
      Subdomains.domains,
    )
    assert_equal "/var/www/example.com/frontend/dist/www", Subdomains.dist(Subdomains.all.first)
  end
end
