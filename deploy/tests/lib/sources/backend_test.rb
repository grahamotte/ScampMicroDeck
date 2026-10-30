require_relative "../../test_helper"

class Sources::BackendTest < Minitest::Test
  def test_droplet
    assert Sources::Backend.droplet?
  end

  def test_locations
    locations = Sources::Backend.locations(name: "api")

    assert_includes locations, "location / {"
    assert_includes locations, "proxy_pass http://127.0.0.1:3000;"
    assert_includes locations, "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
  end
end
