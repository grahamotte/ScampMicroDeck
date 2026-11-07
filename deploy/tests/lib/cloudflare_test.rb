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

  def test_delete_worker_domain
    Req.expects(:call).with(has_entry(:params, { name: "example.com" }))
      .returns(result: [ { name: "example.com", id: "zone", account: { id: "account" } } ])
    Req.expects(:call).with(
      method: :delete,
      url: "https://api.cloudflare.com/client/v4/accounts/account/workers/domains/domain",
      headers: Cloudflare.headers,
      quiet: true,
    )

    Cloudflare.delete_worker_domain("domain")
  end

  def test_delete_worker
    Cloudflare.instance_variable_set(:@account_id, "account")
    Req.expects(:call).with(
      method: :delete,
      url: "https://api.cloudflare.com/client/v4/accounts/account/workers/scripts/example-com",
      headers: Cloudflare.headers,
      quiet: true,
    )

    Cloudflare.delete_worker("example-com")
  end

  def test_delete_worker_ignores_missing_worker
    Cloudflare.instance_variable_set(:@account_id, "account")
    Req.expects(:call).raises(Faraday::ResourceNotFound.new("not found"))

    assert_nil Cloudflare.delete_worker("example-com")
  end

  def test_dns_record_lookup_follows_pages
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone" } ])
    Req.expects(:call).with(has_entries(
      url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records",
      params: { page: 1, per_page: 100 },
    )).returns(result: [ { id: "one" } ], result_info: { page: 1, total_pages: 2 })
    Req.expects(:call).with(has_entries(
      url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records",
      params: { page: 2, per_page: 100 },
    )).returns(result: [ { id: "two" } ], result_info: { page: 2, total_pages: 2 })

    assert_equal [ { id: "one" }, { id: "two" } ], Cloudflare.current_dns_records
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
        { name: "_dmarc.example.com", type: "TXT", content: "v=DMARC1; p=none" },
        { name: "example.com", type: "TXT", content: "google-site-verification=abc" },
        { name: "send.example.com", type: "TXT", content: "v=spf1 include:amazonses.com ~all" },
        { name: "app.example.com", type: "A", content: "1.2.3.4" },
      ])

    assert_equal(
      [ "example.com TXT", "send.example.com TXT", "app.example.com A" ],
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

    assert_equal [ "MX", "MX", "CNAME", "CNAME", "CNAME", "TXT", "TXT" ], records.map { |x| x[:type] }
    assert_equal "fm1._domainkey.example.com :: CNAME :: fm1.example.com.dkim.fmhosted.com", Cloudflare.fingerprint(records[2])
    assert_equal "example.com :: TXT :: v=spf1 include:spf.messagingengine.com ~all", Cloudflare.fingerprint(records[5])
    assert_equal "_dmarc.example.com :: TXT :: v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com", Cloudflare.fingerprint(records[6])
    assert(records.all? { |x| x[:proxied] == false })
    assert_equal [], Cloudflare.resend_dns_records
  end

  def test_mail_dns_records_with_resend
    configure_resend

    records = Cloudflare.mail_dns_records

    assert_equal 10, records.length
    assert_equal(
      [
        { type: "MX", name: "send.example.com", priority: 10, content: "feedback-smtp.us-east-1.amazonses.com", proxied: false, ttl: 1 },
        { type: "TXT", name: "send.example.com", content: "v=spf1 include:amazonses.com ~all", proxied: false, ttl: 1 },
        { type: "TXT", name: "resend._domainkey.example.com", content: "p=KEY", proxied: false, ttl: 1 },
      ],
      records.last(3),
    )
    assert_equal [], Cloudflare.mail_dns_records("example.net").select { |x| x[:name].start_with?("send.", "resend.") }
  end

  def test_mail_record
    assert Cloudflare.mail_record?({ name: "example.com", type: "MX", content: "in2-smtp.messagingengine.com" })
    assert Cloudflare.mail_record?({ name: "fm3._domainkey", type: "CNAME", content: "fm3.example.com.dkim.fmhosted.com" })
    assert Cloudflare.mail_record?({ name: "example.com", type: "TXT", content: "v=spf1 -all" })
    assert Cloudflare.mail_record?({ name: "example.com", type: "TXT", content: "\"v=spf1 -all\"" })
    assert Cloudflare.mail_record?({ name: "_dmarc.example.com", type: "TXT", content: "v=DMARC1; p=none" })
    refute Cloudflare.mail_record?({ name: "example.com", type: "MX", content: "mx.example.net" })
    refute Cloudflare.mail_record?({ name: "example.com", type: "TXT", content: "google-site-verification=abc" })
    refute Cloudflare.mail_record?({ name: "send.example.com", type: "MX", content: "feedback-smtp.us-east-1.amazonses.com" })
    refute Cloudflare.mail_record?({ name: "resend._domainkey.example.com", type: "TXT", content: "p=KEY" })
  end

  def test_mail_record_with_resend
    configure_resend

    assert Cloudflare.mail_record?({ name: "send.example.com", type: "MX", content: "feedback-smtp.eu-west-1.amazonses.com" })
    assert Cloudflare.mail_record?({ name: "send.example.com", type: "TXT", content: "v=spf1 include:amazonses.com ~all" })
    assert Cloudflare.mail_record?({ name: "resend._domainkey.example.com", type: "TXT", content: "p=OLD" })
    refute Cloudflare.mail_record?({ name: "send.example.com", type: "TXT", content: "other" })
  end

  def test_stale_mail_dns_records
    stub_zone("example.com")
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [
        { id: "old-spf", name: "example.com", type: "TXT", content: "v=spf1 include:spf.messagingengine.com ?all" },
        { id: "spf", name: "example.com", type: "TXT", content: "v=spf1 include:spf.messagingengine.com ~all" },
        { id: "old-dmarc", name: "_dmarc.example.com", type: "TXT", content: "v=DMARC1; p=none" },
        { id: "verify", name: "example.com", type: "TXT", content: "google-site-verification=abc" },
        { id: "mx", name: "example.com", type: "MX", content: "in1-smtp.messagingengine.com" },
        { id: "resend", name: "resend._domainkey.example.com", type: "TXT", content: "p=OLD" },
      ])

    assert_equal [ "old-spf", "old-dmarc" ], Cloudflare.stale_mail_dns_records.map { |x| x[:id] }
  end

  def test_stale_mail_dns_records_with_resend
    configure_resend
    stub_zone("example.com")
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [
        { id: "old-mx", name: "send.example.com", type: "MX", content: "feedback-smtp.eu-west-1.amazonses.com" },
        { id: "spf", name: "send.example.com", type: "TXT", content: "v=spf1 include:amazonses.com ~all" },
        { id: "old-dkim", name: "resend._domainkey.example.com", type: "TXT", content: "p=OLD" },
        { id: "dkim", name: "resend._domainkey.example.com", type: "TXT", content: "p=KEY" },
      ])

    assert_equal [ "old-mx", "old-dkim" ], Cloudflare.stale_mail_dns_records.map { |x| x[:id] }
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
        "example.com :: TXT :: v=spf1 include:spf.messagingengine.com ~all",
        "_dmarc.example.com :: TXT :: v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com",
      ],
      Cloudflare.missing_mail_dns_records.map { |x| Cloudflare.fingerprint(x) },
    )
  end

  def test_mail_dns_records_for_other_domain
    records = Cloudflare.mail_dns_records("example.net")

    assert_equal [ "example.net", "example.net" ], records.first(2).map { |x| x[:name] }
    assert_equal "fm2.example.net.dkim.fmhosted.com", records[3][:content]
    assert_equal "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.net", records.last[:content]
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

  def configure_resend
    config = JSON.parse(File.read(Constants.config_path))
      .merge("resendDomains" => [ { "domain" => "example.com", "region" => "us-east-1", "dkimPublicKey" => "p=KEY" } ])
    File.write(Constants.config_path, JSON.generate(config))
    Constants.instance_variable_set(:@config, nil)
  end

  def stub_zone(domain)
    Req.expects(:call).with(has_entry(:params, { name: domain }))
      .returns(result: [ { name: domain, id: "zone" } ])
  end

  def stub_rulesets(rulesets)
    Req.expects(:call).with { |options| options[:url] == "https://api.cloudflare.com/client/v4/zones/zone/rulesets" && options[:method].blank? }
      .returns(result: rulesets)
  end
end
