require_relative "../test_helper"

class WebsitePatchTest < Minitest::Test
  def setup
    super
    @env = ENV.to_h.slice("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID")
    @checkout = Dir.mktmpdir
    Sources::Website.checkout = @checkout
  end

  def teardown
    %w[CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID].each { |key| ENV[key] = @env[key] }
    FileUtils.rm_rf(@checkout)
    Sources::Website.checkout = nil
    super
  end

  def test_call
    root = File.join(@checkout, "website")
    FileUtils.mkdir_p(root)
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones"))
      .returns(result: [ { name: "example.com", id: "zone", account: { id: "account" } } ])
      .twice
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [
        { id: "apex", name: "example.com", type: "A", proxied: false },
        { id: "worker", name: "www.example.com", type: "AAAA", proxied: true },
        { id: "mail", name: "example.com", type: "MX", proxied: false },
        { id: "app", name: "app.example.com", type: "A", proxied: false },
      ])
    Req.expects(:call).with(has_entries(method: :delete, url: "https://api.cloudflare.com/client/v4/zones/zone/dns_records/apex"))
    Req.expects(:call).with(has_entries(method: :patch, url: "https://api.cloudflare.com/client/v4/zones/zone/settings/always_use_https"))
    commands = sequence("commands")
    Cmd.expects(:local).with("git fetch origin master").in_sequence(commands)
    Cmd.expects(:local).with("git rev-parse origin/master").returns("abc123\n").in_sequence(commands)
    Cmd.expects(:local).with("rm -rf ?", @checkout).in_sequence(commands)
    Cmd.expects(:local).with("git worktree prune").in_sequence(commands)
    Cmd.expects(:local).with("git worktree add --detach ? ?", @checkout, "abc123").in_sequence(commands)
    Cmd.expects(:local).with("cd ? && pnpm install --frozen-lockfile && pnpm exec astro build", root).in_sequence(commands)
    Cmd.expects(:local).with("cd ? && pnpm exec wrangler deploy", root).in_sequence(commands)
    Cmd.expects(:local).with("git worktree remove --force ?", @checkout).in_sequence(commands)

    WebsitePatch.call

    assert_equal "cloudflare-token", ENV["CLOUDFLARE_API_TOKEN"]
    assert_equal "account", ENV["CLOUDFLARE_ACCOUNT_ID"]
    assert_equal(
      JSON.parse(JSON.generate(Sources::Website.wrangler_config)),
      JSON.parse(File.read(File.join(root, "wrangler.json"))),
    )
  end

  def test_creates_missing_zone
    FileUtils.mkdir_p(Sources::Website.root)
    Cmd.stubs(:local).returns("abc123\n")
    Req.expects(:call).with do |options|
      options[:url] == "https://api.cloudflare.com/client/v4/zones" && options[:method].blank?
    end.times(3).returns(
      { result: [] },
      { result: [ { name: "example.com", id: "zone", account: { id: "account" } } ] },
      { result: [ { name: "example.com", id: "zone", account: { id: "account" } } ] },
    )
    Req.expects(:call).with(has_entries(method: :post, url: "https://api.cloudflare.com/client/v4/zones"))
    Req.expects(:call).with(has_entries(method: :patch, url: "https://api.cloudflare.com/client/v4/zones/zone/settings/always_use_https"))
    Req.expects(:call).with(has_entry(:url, "https://api.cloudflare.com/client/v4/zones/zone/dns_records"))
      .returns(result: [])

    WebsitePatch.call
  end

  def test_needed
    assert WebsitePatch.needed?

    Subdomains.instance_variable_set(:@all, [ { name: "app", subdomains: [ "app" ], source: "frontend" } ])

    refute WebsitePatch.needed?
  end

  def test_call_skips_without_website
    Subdomains.instance_variable_set(:@all, [ { name: "app", subdomains: [ "app" ], source: "frontend" } ])

    WebsitePatch.call
  end
end
