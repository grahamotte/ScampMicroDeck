require "bundler/setup"
require "minitest/autorun"
require "minitest/parallel_fork"
require "mocha/minitest"
require "webmock/minitest"
require "test_safety"
require "tmpdir"
WebMock.disable_net_connect!
def Minitest.parallel_fork_number = 4
ENV["EDITOR"] ||= "vi"

require_relative "../lib/require"

module DeployTestMethods
  CMD_LOCAL = Cmd.method(:local)
  REQ_CALL = Req.method(:call)
end

[ BasePatch, Cloudflare, Instance ].each do |klass|
  klass.define_singleton_method(:puts) { |*| }
end

Cmd.define_singleton_method(:local) { |*, **| raise UnsafeTestOperation, "Cmd.local must be stubbed in deploy tests" }
Cmd.define_singleton_method(:ssh) { |*, **| raise UnsafeTestOperation, "Cmd.ssh must be stubbed in deploy tests" }
Cmd.define_singleton_method(:ssh_write) { |*, **| raise UnsafeTestOperation, "Cmd.ssh_write must be stubbed in deploy tests" }
Req.define_singleton_method(:call) { |*, **| raise UnsafeTestOperation, "Req.call must be stubbed in deploy tests" }
Net::SSH.define_singleton_method(:start) { |*, **| raise UnsafeTestOperation, "Net::SSH.start must be stubbed in deploy tests" }

{
  "BACKUP_ACCESS_KEY_ID" => "access",
  "BACKUP_BUCKET" => "backups",
  "BACKUP_ENDPOINT" => "https://storage.example.com",
  "BACKUP_SECRET_ACCESS_KEY" => "secret",
  "CLOUDFLARE_TOKEN" => "cloudflare-token",
  "DEPLOY_PASSWORD" => "password",
  "DEPLOY_SSH_KEY" => "private-key",
  "DEPLOY_SSH_KEY_FINGERPRINT" => "fingerprint",
  "DEPLOY_SSH_KEY_PUB" => "public-key",
  "DEPLOY_USER" => "deploy",
  "DIGITAL_OCEAN_TOKEN" => "digital-ocean-token",
  "test" => "true",
}.each { |key, value| ENV[key] = value }

module DeployTestIsolation
  def before_setup
    @deploy_test_dir = Dir.mktmpdir
    $cache = Cache.new(dir: File.join(@deploy_test_dir, "cache"))
    configure_config_fixture
    Constants.instance_variable_set(:@ssh_key_path, File.join(@deploy_test_dir, "id_rsa"))
    Instance.clear
    Cloudflare.instance_variable_set(:@zone_id, nil)
    Subdomains.instance_variable_set(:@all, nil)
    DependenciesPatch.instance_variable_set(:@current_versions, nil)
    CertPatch.instance_variable_set(:@certificate, nil)
    super
  end

  def after_teardown
    FileUtils.rm_rf(@deploy_test_dir)
    Constants.config_path = nil
    Constants.local_env_path = nil
    Constants.instance_variable_set(:@config, nil)
    super
  end

  private

  def configure_config_fixture
    Constants.config_path = File.join(@deploy_test_dir, "config.json")
    Constants.instance_variable_set(:@config, nil)
    Constants.local_env_path = File.join(@deploy_test_dir, ".env.production")
    File.write(Constants.local_env_path, "RAILS_ENV=production\nNODE_ENV=production\n")
    File.write(
      Constants.config_path,
      JSON.generate(
        domain: "example.com",
        githubRepo: "git@github.com:example/app.git",
        database: "app",
        instance: { region: "test-region", size: "test-size" },
        subdomains: [
          { name: "www", subdomains: [ "", "www" ], directory: "frontend/subdomains/www" },
          { name: "hc", subdomains: [ "hc" ], directory: "frontend/subdomains/hc" },
          { name: "jobs", subdomains: [ "jobs" ], backend: true },
        ],
      ),
    )
  end
end

Minitest::Test.prepend(DeployTestIsolation)
