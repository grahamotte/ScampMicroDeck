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
      .twice.returns(result: Cloudflare.mail_dns_records)

    refute MailDnsPatch.needed?
  end

  def test_needed_with_stale_records
    Cloudflare.instance_variable_set(:@zone_ids, { "example.com" => "zone" })
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .twice.returns(result: Cloudflare.mail_dns_records + [ { id: "old", name: "example.com", type: "TXT", content: "v=spf1 include:spf.messagingengine.com ?all" } ])

    assert MailDnsPatch.needed?
  end

  def test_apply_replaces_stale_records
    Cloudflare.instance_variable_set(:@zone_ids, { "example.com" => "zone" })
    current = Cloudflare.mail_dns_records.reject { |x| x[:type] == "TXT" } + [
      { id: "old-spf", name: "example.com", type: "TXT", content: "v=spf1 include:spf.messagingengine.com ?all" },
      { id: "verify", name: "example.com", type: "TXT", content: "google-site-verification=abc" },
    ]
    Req.expects(:call).with { |options| options[:url] == "https://api.cloudflare.com/client/v4/zones/zone/dns_records" && options[:method].blank? }
      .twice.returns(result: current)
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records/old-spf"))
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records", payload: Cloudflare.mail_dns_records[5]))
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records", payload: Cloudflare.mail_dns_records[6]))

    MailDnsPatch.apply
  end

  def test_apply_writes_resend_records
    File.write(Constants.config_path, JSON.generate(domain: "example.com", resendDomains: [ { domain: "example.com", region: "eu-west-1", dkimPublicKey: "p=NEW" } ]))
    Constants.instance_variable_set(:@config, nil)
    Cloudflare.instance_variable_set(:@zone_ids, { "example.com" => "zone" })
    current = Cloudflare.mail_dns_records.first(7) + [
      { id: "old-dkim", name: "resend._domainkey.example.com", type: "TXT", content: "p=OLD" },
    ]
    Req.expects(:call).with { |options| options[:url] == "https://api.cloudflare.com/client/v4/zones/zone/dns_records" && options[:method].blank? }
      .twice.returns(result: current)
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records/old-dkim"))
    Cloudflare.mail_dns_records.last(3).each do |record|
      Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records", payload: record))
    end

    MailDnsPatch.apply
  end

  def test_apply_creates_zone_and_records
    Req.expects(:call).with do |options|
      options[:url] == "https://api.cloudflare.com/client/v4/zones" && options[:method].blank?
    end.twice.returns(
      { result: [] },
      { result: [ { name: "example.com", id: "zone" } ] },
    )
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones"))
    Req.expects(:call).with { |options| options[:url] == "https://api.cloudflare.com/client/v4/zones/zone/dns_records" && options[:method].blank? }
      .twice.returns(result: [ { name: "example.com", type: "MX", content: "in1-smtp.messagingengine.com" } ])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .times(6)

    MailDnsPatch.apply
  end

  def test_apply_includes_redirect_domains
    File.write(Constants.config_path, JSON.generate(domain: "example.com", redirectDomains: [ "example.net" ]))
    Constants.instance_variable_set(:@config, nil)
    Cloudflare.instance_variable_set(:@zone_ids, { "example.com" => "zone", "example.net" => "net-zone" })
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .times(4).returns(result: Cloudflare.mail_dns_records)
    Req.expects(:call).with { |options| options[:url] == "https://api.cloudflare.com/client/v4/zones/net-zone/dns_records" && options[:method].blank? }
      .times(3).returns(result: [])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/net-zone/dns_records"))
      .times(7)

    assert MailDnsPatch.needed?
    MailDnsPatch.apply
  end
end
