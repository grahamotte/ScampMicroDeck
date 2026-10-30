require_relative "../../test_helper"

class Sources::FrontendTest < Minitest::Test
  def test_droplet
    assert Sources::Frontend.droplet?
  end

  def test_dist
    assert_equal "/var/www/example.com/frontend/dist/app", Sources::Frontend.dist(name: "app")
  end

  def test_build
    Cmd.expects(:ssh).with("cd /var/www/example.com/frontend; set -a; source ../.env; VITE_SUBDOMAIN=app mise exec -- pnpm exec vite build")

    Sources::Frontend.build(name: "app")
  end

  def test_locations
    locations = Sources::Frontend.locations(name: "hc")

    assert_includes locations, "root /var/www/example.com/frontend/dist/hc;"
    assert_includes locations, "try_files $uri /index.html;"
    assert_includes locations, "location /assets/"
    refute_includes locations, "proxy_pass"
  end
end
