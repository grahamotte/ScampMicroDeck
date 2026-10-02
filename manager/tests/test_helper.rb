require "bundler/setup"
require "fileutils"
require "minitest/autorun"
require "minitest/parallel_fork"
require "mocha/minitest"
require "tmpdir"
require "webmock/minitest"
require "test_safety"
WebMock.disable_net_connect!
def Minitest.parallel_fork_number = 4

require_relative "../lib/require"

module ManagerTestMethods
  REQ_CALL = Req.method(:call)

  def req_opts(args, kwargs)
    kwargs.present? ? kwargs : args.first
  end
end

Req.define_singleton_method(:call) { |*, **| raise UnsafeTestOperation, "Req.call must be stubbed in manager tests" }

{
  "LINEAR_TOKEN" => "linear-token",
  "test" => "true",
}.each { |key, value| ENV[key] = value }

module ManagerTestIsolation
  def before_setup
    Linear.reset
    Worktree.reset
    @worktree_test_dir = Dir.mktmpdir("manager-worktree")
    Worktree.root = File.join(@worktree_test_dir, "repo")
    FileUtils.mkdir_p(Worktree.root)
    Worktree.keychain = Keychain.new(home: @worktree_test_dir)
    FileUtils.mkdir_p(File.dirname(Worktree.keychain.login))
    File.write(Worktree.keychain.login, "login")
    Settings.path = File.join(@worktree_test_dir, "config.json")
    File.write(
      Settings.path,
      JSON.generate(
        githubRepo: "git@github.com:grahamotte/codemoto.org.git",
        linear: { workspace: "gotte", team: "MOTO" },
        agent: { runner: "openchamber", model: "openai/gpt-6.1-sol", variant: "high" },
      ),
    )
    super
    Open3.stubs(:capture3).with { |command, *| command == "security" }.returns([ "\"#{Worktree.keychain.login}\"\n", "", Struct.new(:success?).new(true) ])
  end

  def after_teardown
    Worktree.reset
    Settings.reset
    FileUtils.remove_entry(@worktree_test_dir) if @worktree_test_dir
    super
  end
end

Minitest::Test.include(ManagerTestMethods)
Minitest::Test.prepend(ManagerTestIsolation)
