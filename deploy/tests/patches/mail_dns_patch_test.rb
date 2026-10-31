require_relative "../test_helper"

class MailDnsPatchTest < Minitest::Test
  def test_needed_without_zone
    Req.expects(:call).returns(result: [])

    assert MailDnsPatch.needed?
  end

  def test_needed_with_missing_records
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone" } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [ { name: "example.com", type: "MX", content: "in1-smtp.messagingengine.com" } ])

    assert MailDnsPatch.needed?
  end

  def test_not_needed_with_all_records
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone" } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: Cloudflare.mail_dns_records)

    refute MailDnsPatch.needed?
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
      .returns(result: [ { name: "example.com", type: "MX", content: "in1-smtp.messagingengine.com" } ])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .times(5)

    MailDnsPatch.apply
  end

  def test_apply_includes_redirect_domains
    File.write(Constants.config_path, JSON.generate(domain: "example.com", redirectDomains: [ "example.net" ]))
    Constants.instance_variable_set(:@config, nil)
    Cloudflare.instance_variable_set(:@zone_ids, { "example.com" => "zone", "example.net" => "net-zone" })
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .twice.returns(result: Cloudflare.mail_dns_records)
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/net-zone/dns_records"))
      .twice.returns(result: [])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/net-zone/dns_records"))
      .times(6)

    assert MailDnsPatch.needed?
    MailDnsPatch.apply
  end
end
