require_relative "test_helper"

class LinearSyncAllTest < Minitest::Test
  def test_syncs_current_repo_and_siblings_with_the_task
    current = add_repo(File.basename(Worktree.root))
    other = add_repo("other.org")
    FileUtils.mkdir_p(File.join(parent, "plain"))
    commands = stub_mise

    output, = capture_io { LinearSyncAll.call }

    assert_equal [ current, other ].sort, commands.map { |command| command[:directory] }
    assert_equal [ current, other ].sort.map { |directory| "Syncing #{directory}\n" }.join, output
    assert commands.all? { |command| command[:args] == [ "mise", "manager:linear_sync" ] }
  end

  def test_skips_repos_without_manager_sync
    add_repo("app.org", toml: "[tasks.\"manager:other\"]\nrun = \"true\"\n")
    commands = stub_mise
    capture_io { LinearSyncAll.call }

    assert_empty commands
  end

  def test_skips_worktrees
    add_repo("app.org")
    add_worktree("app.org-moto-1")
    commands = stub_mise

    capture_io { LinearSyncAll.call }

    assert_equal [ File.join(parent, "app.org") ], commands.map { |command| command[:directory] }
  end

  def test_runs_in_sorted_order
    add_repo("zeta.org")
    add_repo("alpha.org")
    commands = stub_mise

    capture_io { LinearSyncAll.call }

    assert_equal [ "alpha.org", "zeta.org" ], commands.map { |command| File.basename(command[:directory]) }
  end

  def test_prints_sync_output
    add_repo("app.org")
    stub_mise(stdout: "created Working\n")

    output, = capture_io { LinearSyncAll.call }

    assert_equal "Syncing #{File.join(parent, "app.org")}\ncreated Working\n", output
  end

  def test_raises_when_sync_fails
    add_repo("alpha.org")
    add_repo("zeta.org")
    commands = stub_mise(stderr: "boom", success: false)

    error = assert_raises(RuntimeError) { capture_io { LinearSyncAll.call } }

    assert_equal "mise manager:linear_sync failed in #{File.join(parent, "alpha.org")}: boom", error.message
    assert_equal [ "alpha.org" ], commands.map { |command| File.basename(command[:directory]) }
  end

  def test_uses_stdout_when_stderr_is_blank
    add_repo("app.org")
    stub_mise(stdout: "failed", success: false)

    error = assert_raises(RuntimeError) { capture_io { LinearSyncAll.call } }

    assert_equal "mise manager:linear_sync failed in #{File.join(parent, "app.org")}: failed", error.message
  end

  def test_streams_output_before_waiting_for_exit
    directory = add_repo("app.org")
    wait = Object.new
    wait.define_singleton_method(:value) do
      raise "Output was buffered" unless $stdout.string.include?("created Working\n")

      Struct.new(:success?).new(true)
    end
    Open3.stubs(:popen2e).yields(StringIO.new, StringIO.new("created Working\n"), wait)

    output, = capture_io { LinearSyncAll.call }

    assert_equal "Syncing #{directory}\ncreated Working\n", output
  end

  def test_directories_lists_syncable_repos
    current = add_repo(File.basename(Worktree.root))
    other = add_repo("other.org")
    add_repo("skip.org", toml: "")
    add_worktree("other.org-moto-1")

    assert_equal [ current, other ].sort, LinearSyncAll.directories
  end

  private

  def parent
    File.expand_path("..", Worktree.root)
  end

  def add_repo(name, toml: "[tasks.\"manager:linear_sync\"]\nrun = \"true\"\n")
    path = File.join(parent, name)
    FileUtils.mkdir_p(File.join(path, ".git"))
    File.write(File.join(path, "mise.toml"), toml)
    path
  end

  def add_worktree(name)
    path = add_repo(name)
    FileUtils.rm_rf(File.join(path, ".git"))
    File.write(File.join(path, ".git"), "gitdir: /tmp/git")
    path
  end

  def stub_mise(stdout: "", stderr: "", success: true)
    commands = []
    status = Object.new
    status.define_singleton_method(:success?) { success }
    Open3.stubs(:popen2e).with do |*args, **kwargs|
      commands << { args:, directory: kwargs[:chdir] }
      true
    end.yields(StringIO.new, StringIO.new(stdout + stderr), Struct.new(:value).new(status))
    commands
  end
end
