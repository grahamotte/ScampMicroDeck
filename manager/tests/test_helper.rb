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

ENV["test"] = "true"

module ManagerTestIsolation
  def before_setup
    @manager_test_dir = Dir.mktmpdir("manager")
    Settings.path = File.join(@manager_test_dir, "config.json")
    File.write(
      Settings.path,
      JSON.generate(
        githubRepo: "git@github.com:grahamotte/CodeMoto.git",
        domain: "codemoto.org",
      ),
    )
    super
  end

  def after_teardown
    Settings.reset
    FileUtils.remove_entry(@manager_test_dir) if @manager_test_dir
    super
  end
end

Minitest::Test.prepend(ManagerTestIsolation)
