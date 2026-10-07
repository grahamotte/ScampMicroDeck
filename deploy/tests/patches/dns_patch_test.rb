require_relative "../test_helper"

class DnsPatchTest < Minitest::Test
  def test_needed_without_zone
    Req.expects(:call).returns(result: [])

    assert DnsPatch.needed?
  end

  def test_needed_with_different_records
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone" } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [])
    Req.expects(:call).with(has_entry(:url, "https://api.digitalocean.com/v2/droplets"))
      .returns(droplets: [ active_instance ])

    assert DnsPatch.needed?
  end

  def test_apply_creates_zone_and_records
    Req.expects(:call).with do |options|
      options[:url] == "https://api.cloudflare.com/client/v4/zones" && options[:method].blank?
    end.twice.returns(
      { result: [] },
      { result: [ { name: "example.com", id: "zone" } ] },
    )
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones"))
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [])
    Req.expects(:call).with(has_entry(:url, "https://api.digitalocean.com/v2/droplets"))
      .returns(droplets: [ active_instance ])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .times(10)

    DnsPatch.apply
  end

  private

  def active_instance
    {
      name: "example.com",
      status: "active",
      networks: { v4: [ { type: "public", ip_address: "1.2.3.4" } ] },
    }
  end
end
