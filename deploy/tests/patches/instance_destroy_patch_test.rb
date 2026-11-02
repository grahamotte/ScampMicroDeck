require_relative "../test_helper"

class InstanceDestroyPatchTest < Minitest::Test
  def test_always
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones")).twice
      .returns(result: [ { name: "example.com", id: "zone", account: { id: "account" } } ])
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [ { id: "one" }, { id: "two" }, { id: "worker", meta: { read_only: true, origin_worker_id: "worker_domain" } } ])
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.cloudflare.com/client/v4/accounts/account/workers/domains/worker_domain"))
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records/one"))
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records/two"))
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.cloudflare.com/client/v4/accounts/account/workers/scripts/example-com"))
    Req.expects(:call).with(has_entries(method: :get, url: "https://api.digitalocean.com/v2/droplets"))
      .returns(droplets: [ { name: "example.com", id: 3 } ])
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.digitalocean.com/v2/droplets/3"))

    InstanceDestroyPatch.always
  end
end
