require_relative "../test_helper"

class CloudflareTest < Minitest::Test
  def test_zone_lookup_and_create
    Req.expects(:call).returns(result: [ { name: "other.com", id: "1" }, { name: "example.com", id: "2" } ])
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

    assert_equal 10, records.length
    assert_equal(
      { type: "A", name: "www.example.com", content: "1.2.3.4", proxied: false, ttl: 1 },
      records[1],
    )
    assert_equal "example.com :: A :: 1.2.3.4", Cloudflare.fingerprint(records.first)
    assert_equal "www.example.com :: A :: 1.2.3.4", Cloudflare.fingerprint(records[1])
  end
end
