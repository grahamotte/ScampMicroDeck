require_relative "../test_helper"

class CloudflareTest < Minitest::Test
  def test_zone_lookup_and_create
    Req.expects(:call).with(has_entry(:params, { name: "example.com" }))
      .returns(result: [ { name: "other.com", id: "1" }, { name: "example.com", id: "2" } ])
    assert_equal "2", Cloudflare.zone_id

    Req.expects(:call).with(
      method: :post,
      url: "https://api.cloudflare.com/client/v4/zones",
      headers: Cloudflare.headers,
      quiet: true,
      payload: { name: "example.com" },
    )
    Cloudflare.create_zone
  end

  def test_zone_lookup_handles_failure
    Req.expects(:call).raises("failure")

    assert_nil Cloudflare.zone_id
  end

  def test_dns_record_lookup_and_mutation
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone" } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [ { id: "record" } ])
    assert_equal [ { id: "record" } ], Cloudflare.current_dns_records

    record = { type: "A", name: "example.com", content: "1.2.3.4" }
    Req.expects(:call).with(
      method: :delete,
      url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records/record",
      headers: Cloudflare.headers,
      quiet: true,
    )
    Req.expects(:call).with(
      method: :post,
      url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records",
      headers: Cloudflare.headers,
      quiet: true,
      payload: record,
    )

    Cloudflare.delete_dns_record("record")
    Cloudflare.create_dns_record(record)
  end

  def test_account_id
    Req.expects(:call).with(has_entry(:params, { name: "example.com" }))
      .returns(result: [ { name: "example.com", id: "zone", account: { id: "account" } } ])

    assert_equal "account", Cloudflare.account_id
  end

  def test_droplet_dns_records_skip_website_hosts
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone" } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [
        { name: "example.com", type: "AAAA", content: "100::" },
        { name: "www.example.com", type: "A", content: "1.2.3.4" },
        { name: "example.com", type: "MX", content: "in1-smtp.messagingengine.com" },
        { name: "example.com", type: "TXT", content: "v=spf1" },
        { name: "app.example.com", type: "A", content: "1.2.3.4" },
      ])

    assert_equal(
      [ "example.com TXT", "app.example.com A" ],
      Cloudflare.droplet_dns_records.map { |x| "#{x[:name]} #{x[:type]}" },
    )
  end

  def test_enable_always_use_https
    Cloudflare.instance_variable_set(:@zone_ids, { "example.com" => "zone" })
    Req.expects(:call).with(
      method: :patch,
      url: "https://api.cloudflare.com/client/v4/zones/zone/settings/always_use_https",
      headers: Cloudflare.headers,
      quiet: true,
      payload: { value: "on" },
    )

    Cloudflare.enable_always_use_https
  end

  def test_without_zone
    Req.expects(:call).twice.returns(result: [])

    assert_equal [], Cloudflare.current_dns_records
    refute Cloudflare.current_records_are_desired?
  end

  def test_desired_dns_records
    Req.expects(:call).returns(droplets: [
      {
        name: "example.com",
        status: "active",
        networks: { v4: [ { type: "public", ip_address: "1.2.3.4" } ] },
      },
    ])

    records = Cloudflare.desired_dns_records

    assert_equal 4, records.length
    assert_equal(
      { type: "A", name: "hc.example.com", content: "1.2.3.4", proxied: false, ttl: 1 },
      records[1],
    )
    assert_equal "app.example.com :: A :: 1.2.3.4", Cloudflare.fingerprint(records.first)
    assert_equal "hc.example.com :: A :: 1.2.3.4", Cloudflare.fingerprint(records[1])
    refute(records.any? { |x| x[:type] == "A" && [ "example.com", "www.example.com" ].include?(x[:name]) })
  end

  def test_mail_dns_records
    records = Cloudflare.mail_dns_records

    assert_equal [ "MX", "MX", "CNAME", "CNAME", "CNAME", "TXT" ], records.map { |x| x[:type] }
    assert_equal "fm1._domainkey.example.com :: CNAME :: fm1.example.com.dkim.fmhosted.com", Cloudflare.fingerprint(records[2])
    assert(records.all? { |x| x[:proxied] == false })
  end

  def test_mail_record
    assert Cloudflare.mail_record?({ name: "example.com", type: "MX", content: "in2-smtp.messagingengine.com" })
    assert Cloudflare.mail_record?({ name: "fm3._domainkey", type: "CNAME", content: "fm3.example.com.dkim.fmhosted.com" })
    refute Cloudflare.mail_record?({ name: "example.com", type: "MX", content: "mx.example.net" })
    refute Cloudflare.mail_record?({ name: "example.com", type: "TXT", content: "v=spf1 -all" })
  end

  def test_missing_mail_dns_records
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone" } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [
        { name: "example.com", type: "MX", content: "in1-smtp.messagingengine.com" },
        { name: "fm1._domainkey.example.com", type: "CNAME", content: "fm1.example.com.dkim.fmhosted.com" },
        { name: "example.com", type: "TXT", content: "v=spf1 include:spf.messagingengine.com ?all" },
      ])

    assert_equal(
      [
        "example.com :: MX :: in2-smtp.messagingengine.com",
        "fm2._domainkey.example.com :: CNAME :: fm2.example.com.dkim.fmhosted.com",
        "fm3._domainkey.example.com :: CNAME :: fm3.example.com.dkim.fmhosted.com",
      ],
      Cloudflare.missing_mail_dns_records.map { |x| Cloudflare.fingerprint(x) },
    )
  end

  def test_mail_dns_records_for_other_domain
    records = Cloudflare.mail_dns_records("example.net")

    assert_equal [ "example.net", "example.net" ], records.first(2).map { |x| x[:name] }
    assert_equal "fm2.example.net.dkim.fmhosted.com", records[3][:content]
  end

  def test_redirect_dns_records
    assert_equal(
      [
        { type: "A", name: "example.net", content: "192.0.2.1", proxied: true, ttl: 1 },
        { type: "A", name: "www.example.net", content: "192.0.2.1", proxied: true, ttl: 1 },
      ],
      Cloudflare.redirect_dns_records("example.net"),
    )
  end

  def test_missing_redirect_dns_records
    stub_zone("example.net")
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [
        { name: "example.net", type: "A", content: "192.0.2.1" },
        { name: "www.example.com", type: "A", content: "192.0.2.1" },
      ])

    assert_equal [ "www.example.net" ], Cloudflare.missing_redirect_dns_records("example.net").map { |x| x[:name] }
  end

  def test_redirect_rule
    rule = Cloudflare.redirect_rule("example.net")

    assert_equal "(http.host in {\"example.net\" \"www.example.net\"})", rule[:expression]
    assert_equal "redirect", rule[:action]
    assert_equal(
      {
        target_url: { expression: "concat(\"https://example.com\", http.request.uri.path)" },
        status_code: 301,
        preserve_query_string: true,
      },
      rule.dig(:action_parameters, :from_value),
    )
  end

  def test_redirect_rule_current
    stub_zone("example.net")
    stub_rulesets([ { id: "other", kind: "managed", phase: Cloudflare::REDIRECT_PHASE }, { id: "redirects", kind: "zone", phase: Cloudflare::REDIRECT_PHASE } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/rulesets/redirects"))
      .returns(result: { rules: [ Cloudflare.redirect_rule("example.net").merge(id: "rule", version: "1") ] })

    assert Cloudflare.redirect_rule_current?("example.net")
  end

  def test_redirect_rule_not_current
    stub_zone("example.net")
    stub_rulesets([ { id: "redirects", kind: "zone", phase: Cloudflare::REDIRECT_PHASE } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/rulesets/redirects"))
      .returns(result: { rules: [ Cloudflare.redirect_rule("example.org") ] })

    refute Cloudflare.redirect_rule_current?("example.net")
  end

  def test_redirect_rule_without_ruleset
    stub_zone("example.net")
    stub_rulesets([])

    refute Cloudflare.redirect_rule_current?("example.net")
  end

  def test_write_redirect_rule_creates_ruleset
    stub_zone("example.net")
    stub_rulesets([])
    Req.expects(:call).with(
      method: :post,
      url: "https://api.cloudflare.com/client/v4/zones/zone/rulesets",
      headers: Cloudflare.headers,
      quiet: true,
      payload: {
        name: "Redirect example.net to example.com",
        kind: "zone",
        phase: Cloudflare::REDIRECT_PHASE,
        rules: [ Cloudflare.redirect_rule("example.net") ],
      },
    )

    Cloudflare.write_redirect_rule("example.net")
  end

  def test_write_redirect_rule_replaces_rules
    stub_zone("example.net")
    stub_rulesets([ { id: "redirects", kind: "zone", phase: Cloudflare::REDIRECT_PHASE } ])
    Req.expects(:call).with(
      method: :put,
      url: "https://api.cloudflare.com/client/v4/zones/zone/rulesets/redirects",
      headers: Cloudflare.headers,
      quiet: true,
      payload: { rules: [ Cloudflare.redirect_rule("example.net") ] },
    )

    Cloudflare.write_redirect_rule("example.net")
  end

  private

  def stub_zone(domain)
    Req.expects(:call).with(has_entry(:params, { name: domain }))
      .returns(result: [ { name: domain, id: "zone" } ])
  end

  def stub_rulesets(rulesets)
    Req.expects(:call).with { |options| options[:url] == "https://api.cloudflare.com/client/v4/zones/zone/rulesets" && options[:method].blank? }
      .returns(result: rulesets)
  end
end
