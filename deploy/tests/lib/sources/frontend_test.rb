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
    assert_includes locations, 'location ~ ^/(apple-touch-icon[^/]*\\.png|favicon[^/]*\\.(ico|png))$'
    assert_includes locations, 'add_header Cache-Control "no-cache, no-store, must-revalidate"'
    assert_includes locations, "try_files $uri =404;"
    refute_includes locations, "proxy_pass"
    assert_equal 3, locations.scan("add_header Strict-Transport-Security").size
    assert_equal 3, locations.scan("add_header Content-Security-Policy").size
  end

  def test_locations_with_backend_paths
    locations = Sources::Frontend.locations(name: "app", backendPaths: [ "/.well-known/", "~ ^/(llms\\.txt$|mcp|oauth/)" ])

    assert_includes locations, "location /.well-known/ {"
    assert_includes locations, 'location ~ ^/(llms\\.txt$|mcp|oauth/) {'
    assert_equal [ "http://127.0.0.1:3000" ] * 2, locations.scan(/proxy_pass ([^;]+);/).flatten
    locations.scan(/location \S+ \{[^}]*proxy_pass[^}]*\}/).each do |location|
      refute_includes location, "add_header"
    end
  end

  def test_headers
    headers = Sources::Frontend.headers(name: "app")

    assert_includes headers, 'add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;'
    assert_includes headers, 'add_header X-Content-Type-Options "nosniff" always;'
    assert_includes headers, 'add_header Referrer-Policy "strict-origin-when-cross-origin" always;'
    assert_includes headers, %(add_header Content-Security-Policy "#{Sources::Frontend.content_security_policy(name: "app")}" always;)
  end

  def test_content_security_policy
    policy = Sources::Frontend.content_security_policy(name: "app")

    assert_includes policy, "default-src 'self'"
    assert_includes policy, "script-src 'self';"
    assert_includes policy, "connect-src 'self' https://example.com https://*.example.com"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "frame-ancestors 'none'"
    refute_includes policy, '"'
  end

  def test_content_security_policy_from_config
    assert_equal "default-src 'self'", Sources::Frontend.content_security_policy(name: "app", contentSecurityPolicy: "default-src 'self'")
  end

  def test_backend_locations
    assert_equal "", Sources::Frontend.backend_locations(name: "app")
    assert_equal Sources::Backend.proxy_location("/.well-known/"), Sources::Frontend.backend_locations(name: "app", backendPaths: [ "/.well-known/" ])
  end
end
