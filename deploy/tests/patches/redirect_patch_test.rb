require_relative "../test_helper"

class RedirectPatchTest < Minitest::Test
  def test_not_needed_without_redirect_domains
    refute RedirectPatch.needed?
  end

  def test_needed_without_zone
    configure_redirect_domains
    Req.expects(:call).returns(result: [])

    assert RedirectPatch.needed?
  end

  def test_needed_with_missing_records
    configure_redirect_domains
    Cloudflare.instance_variable_set(:@zone_ids, { "example.net" => "zone" })
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [])

    assert RedirectPatch.needed?
  end

  def test_not_needed_when_current
    configure_redirect_domains
    Cloudflare.instance_variable_set(:@zone_ids, { "example.net" => "zone" })
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: Cloudflare.redirect_dns_records("example.net"))
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/rulesets"))
      .returns(result: [ { id: "redirects", kind: "zone", phase: Cloudflare::REDIRECT_PHASE } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/rulesets/redirects"))
      .returns(result: { rules: [ Cloudflare.redirect_rule("example.net") ] })

    refute RedirectPatch.needed?
  end

  def test_apply_creates_zone_records_and_rule
    configure_redirect_domains
    Req.expects(:call).with do |options|
      options[:url] == "https://api.cloudflare.com/client/v4/zones" && options[:method].blank?
    end.twice.returns(
      { result: [] },
      { result: [ { name: "example.net", id: "zone" } ] },
    )
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones", payload: { name: "example.net" }))
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .times(2)
    Req.expects(:call).with { |options| options[:url] == "https://api.cloudflare.com/client/v4/zones/zone/rulesets" && options[:method].blank? }
      .returns(result: [])
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones/zone/rulesets"))

    RedirectPatch.apply
  end

  private

  def configure_redirect_domains
    File.write(Constants.config_path, JSON.generate(domain: "example.com", redirectDomains: [ "example.net" ]))
    Constants.instance_variable_set(:@config, nil)
  end
end
