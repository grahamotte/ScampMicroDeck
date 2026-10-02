require_relative "test_helper"

class WorktreeTest < Minitest::Test
  WORKTREE_LIST = [ "git", "worktree", "list", "--porcelain" ].freeze
  FOR_EACH_REF = [ "git", "for-each-ref", "--format=%(refname:short) %(upstream:short)", "refs/heads" ].freeze

  def test_opens_new_worktree_from_origin_master
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    write_source(".env.development", "DEV=1")
    write_source(".env.production", "PROD=1")
    write_source("backend/db/schema.rb", "schema")
    stub_git

    assert_equal path, Worktree.open(item)

    assert_includes git_commands, [ "git", "fetch", "origin" ]
    assert_includes git_commands, [ "git", "worktree", "add", "-b", "moto-17", path, "origin/master" ]
    assert_equal "DEV=1", File.read(File.join(path, ".env.development"))
    assert_equal "PROD=1", File.read(File.join(path, ".env.production"))
    assert_equal "schema", File.read(File.join(path, "backend/db/schema.rb"))
  end

  def test_recreates_missing_prunable_card_worktree_on_existing_branch
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    stub_git(
      show_ref: "abc refs/heads/moto-17\n",
      worktree_list: porcelain([ Worktree.root, "master" ], [ path, "moto-17" ]) + "prunable gitdir file points to non-existent location\n",
    )

    assert_equal path, Worktree.open(item)

    assert_includes git_commands, [ "git", "worktree", "add", "--force", path, "moto-17" ]
  end

  def test_directory_ignores_prunable_card_worktree
    stub_git(worktree_list: porcelain([ Worktree.root, "master" ], [ other_path, "moto-17" ]) + "prunable gitdir file points to non-existent location\n")

    assert_equal Worktree.root, Worktree.directory({ identifier: "MOTO-17" })
    refute Dir.exist?(other_path)
  end

  def test_preserves_leftover_directory_without_git_entry
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "work.txt"), "unfinished work")

    error = assert_raises(RuntimeError) { Worktree.open(item) }

    assert_includes error.message, "has no .git entry"
    assert_equal "unfinished work", File.read(File.join(path, "work.txt"))
    assert_equal [], git_commands
  end

  def test_adds_existing_local_branch
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    stub_git(show_ref: "abc refs/heads/moto-17\n")

    Worktree.open(item)

    assert_includes git_commands, [ "git", "worktree", "add", path, "moto-17" ]
    refute_includes git_commands, [ "git", "worktree", "add", "-b", "moto-17", path, "origin/master" ]
  end

  def test_adds_existing_remote_branch
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    stub_git(show_ref: "abc refs/remotes/origin/moto-17\n")

    Worktree.open(item)

    assert_includes git_commands, [ "git", "worktree", "add", "-b", "moto-17", path, "origin/moto-17" ]
  end

  def test_prefers_local_branch_over_remote
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    stub_git(show_ref: "abc refs/heads/moto-17\ndef refs/remotes/origin/moto-17\n")

    Worktree.open(item)

    assert_includes git_commands, [ "git", "worktree", "add", path, "moto-17" ]
    refute git_commands.any? { |command| command.include?("-b") }
  end

  def test_skips_git_when_worktree_already_exists
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, ".git"), "gitdir: card")
    write_source(".env.development", "DEV=1")

    Worktree.open(item)

    assert_equal [], git_commands
    assert_equal "DEV=1", File.read(File.join(path, ".env.development"))
  end

  def test_overwrites_existing_copied_files
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, ".git"), "gitdir: card")
    File.write(File.join(path, ".env.development"), "OLD")
    write_source(".env.development", "NEW")

    Worktree.open(item)

    assert_equal "NEW", File.read(File.join(path, ".env.development"))
  end

  def test_skips_missing_and_tracked_env_files
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    write_source(".env.default", "tracked")
    write_source("backend/db/schema.rb", "schema")
    stub_git

    Worktree.open(item)

    refute File.exist?(File.join(path, ".env.development"))
    refute File.exist?(File.join(path, ".env.default"))
    assert_equal "schema", File.read(File.join(path, "backend/db/schema.rb"))
  end

  def test_copies_root_env_file
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    write_source(".env", "SECRET=1")
    stub_git

    Worktree.open(item)

    assert_equal "SECRET=1", File.read(File.join(path, ".env"))
  end

  def test_removes_existing_worktree
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    FileUtils.mkdir_p(path)
    stub_git

    assert Worktree.remove(item)

    assert_includes git_commands, [ "git", "worktree", "remove", "--force", path ]
    refute Dir.exist?(path)
  end

  def test_remove_releases_keychains_inside_worktree
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    temporary = File.join(path, "publish", "tmp", "apps", "signing-1.keychain-db")
    login = Worktree.keychain.login
    FileUtils.mkdir_p(File.dirname(temporary))
    File.write(temporary, "temporary")
    stub_git
    stub_security(search: temporary, default: temporary)
    Open3.expects(:capture3).with("security", "list-keychains", "-d", "user", "-s", login).returns([ "", "", status(true) ])
    Open3.expects(:capture3).with("security", "default-keychain", "-d", "user", "-s", login).returns([ "", "", status(true) ])

    assert Worktree.remove(item)

    assert_includes git_commands, [ "git", "worktree", "remove", "--force", path ]
  end

  def test_remove_keeps_worktree_when_keychain_release_fails
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    temporary = File.join(path, "signing.keychain-db")
    FileUtils.mkdir_p(path)
    File.write(temporary, "temporary")
    stub_git
    stub_security(search: temporary, default: temporary)
    Open3.stubs(:capture3).with { |command, *arguments| command == "security" && arguments.include?("-s") }.returns([ "", "denied", status(false) ])

    error = assert_raises(RuntimeError) { Worktree.remove(item) }

    assert_includes error.message, "denied"
    assert Dir.exist?(path)
    assert_equal [], git_commands
  end

  def test_remove_leaves_keychains_outside_worktree
    item = { identifier: "MOTO-17" }
    FileUtils.mkdir_p(Worktree.path_for(item))
    stub_git
    Open3.expects(:capture3).with { |command, *arguments| command == "security" && arguments.include?("-s") }.never

    assert Worktree.remove(item)
  end

  def test_skips_remove_when_missing
    item = { identifier: "MOTO-17" }
    stub_git

    refute Worktree.remove(item)

    assert_equal [], git_commands
  end

  def test_pulls_master_when_clean
    stub_git

    assert_equal "master", Worktree.pull_master

    assert_equal [ [ "git", "pull", "--ff-only", "origin", "master" ] ], git_commands
  end

  def test_pulls_main_when_clean
    stub_git(branch: "main")

    assert_equal "main", Worktree.pull_master

    assert_equal [ [ "git", "pull", "--ff-only", "origin", "main" ] ], git_commands
  end

  def test_skips_pull_when_not_on_master_or_main
    stub_git(branch: "moto-56")

    assert_nil Worktree.pull_master

    assert_equal [], git_commands
  end

  def test_skips_pull_when_dirty
    stub_git(porcelain: " M manager/lib/worktree.rb\n")

    assert_nil Worktree.pull_master

    assert_equal [], git_commands
  end

  def test_raises_when_pull_master_fails
    stub_git
    Open3.stubs(:capture3).with("git", "pull", "--ff-only", "origin", "master", chdir: Worktree.root).returns(
      [ "", "network error", status(false) ],
    )

    error = assert_raises(RuntimeError) { Worktree.pull_master }

    assert_equal "git pull --ff-only origin master failed: network error", error.message
  end

  def test_raises_when_remove_fails
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    FileUtils.mkdir_p(path)
    Open3.stubs(:capture3).with { |command, *| command == "git" }.returns([ "", "locked", status(false) ])

    error = assert_raises(RuntimeError) { Worktree.remove(item) }

    assert_equal "git worktree remove --force #{path} failed: locked", error.message
  end

  def test_directory_uses_existing_worktree
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, ".git"), "gitdir: card")

    assert_equal path, Worktree.directory(item)
  end

  def test_directory_falls_back_to_root
    stub_git(worktree_list: porcelain([ Worktree.root, "master" ], [ other_path, "claude/other" ]))

    assert_equal Worktree.root, Worktree.directory({ identifier: "MOTO-17" })
  end

  def test_directory_finds_worktree_on_card_branch
    stub_git(worktree_list: porcelain([ Worktree.root, "master" ], [ other_path, "moto-17" ]))

    assert_equal other_path, Worktree.directory({ identifier: "MOTO-17" })
  end

  def test_directory_finds_worktree_pushing_to_card_branch
    stub_git(
      worktree_list: porcelain([ Worktree.root, "master" ], [ other_path, "claude/brave-fox" ]),
      for_each_ref: "master origin/master\nclaude/brave-fox origin/moto-17\nclaude/other\n",
    )

    assert_equal other_path, Worktree.directory({ identifier: "MOTO-17" })
  end

  def test_directory_ignores_similar_branches
    stub_git(
      worktree_list: porcelain([ Worktree.root, "master" ], [ other_path, "moto-170" ]),
      for_each_ref: "moto-170 origin/moto-170\n",
    )

    assert_equal Worktree.root, Worktree.directory({ identifier: "MOTO-17" })
  end

  def test_directory_skips_detached_worktrees
    stub_git(worktree_list: "worktree #{Worktree.root}\nHEAD abc\nbranch refs/heads/master\n\nworktree #{other_path}\nHEAD def\ndetached\n")

    assert_equal Worktree.root, Worktree.directory({ identifier: "MOTO-17" })
  end

  def test_directory_prefers_manager_worktree
    item = { identifier: "MOTO-17" }
    path = Worktree.path_for(item)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, ".git"), "gitdir: card")
    stub_git(worktree_list: porcelain([ other_path, "moto-17" ]))

    assert_equal path, Worktree.directory(item)
    assert_equal [], git_commands
  end

  def test_open_uses_found_worktree_and_copies_files
    write_source(".env.development", "DEV=1")
    write_source("backend/db/schema.rb", "schema")
    FileUtils.mkdir_p(other_path)
    stub_git(worktree_list: porcelain([ Worktree.root, "master" ], [ other_path, "moto-17" ]))

    assert_equal other_path, Worktree.open({ identifier: "MOTO-17" })

    refute git_commands.any? { |command| command[1] == "worktree" && command[2] == "add" }
    refute_includes git_commands, [ "git", "fetch", "origin" ]
    assert_equal "DEV=1", File.read(File.join(other_path, ".env.development"))
    assert_equal "schema", File.read(File.join(other_path, "backend/db/schema.rb"))
  end

  def test_open_uses_main_checkout_on_card_branch_without_copying
    write_source(".env.development", "DEV=1")
    stub_git(worktree_list: porcelain([ Worktree.root, "moto-17" ]))

    assert_equal Worktree.root, Worktree.open({ identifier: "MOTO-17" })

    refute git_commands.any? { |command| command[1] == "worktree" && command[2] == "add" }
    assert_equal "DEV=1", File.read(File.join(Worktree.root, ".env.development"))
  end

  def test_remove_ignores_found_worktree
    FileUtils.mkdir_p(other_path)
    stub_git(worktree_list: porcelain([ other_path, "moto-17" ]))

    refute Worktree.remove({ identifier: "MOTO-17" })

    assert_equal [], git_commands
    assert Dir.exist?(other_path)
  end

  def test_raises_when_worktree_list_fails
    Open3.stubs(:capture3).returns([ "", "not a git repository", status(false) ])

    error = assert_raises(RuntimeError) { Worktree.directory({ identifier: "MOTO-17" }) }

    assert_equal "git worktree list --porcelain failed: not a git repository", error.message
  end

  def test_raises_when_git_fails
    Open3.stubs(:capture3).returns([ "", "network error", status(false) ])

    Open3.stubs(:capture3).with(*WORKTREE_LIST, chdir: Worktree.root).returns([ "", "", status(true) ])
    Open3.stubs(:capture3).with(*FOR_EACH_REF, chdir: Worktree.root).returns([ "", "", status(true) ])

    error = assert_raises(RuntimeError) { Worktree.open({ identifier: "MOTO-17" }) }

    assert_equal "git fetch origin failed: network error", error.message
  end

  def test_path_uses_repo_basename_and_downcased_identifier
    assert_equal(
      File.expand_path("../#{File.basename(Worktree.root)}-moto-17", Worktree.root),
      Worktree.path_for({ identifier: "MOTO-17" }),
    )
  end

  private

  def other_path
    File.join(@worktree_test_dir, "app-worktree")
  end

  def porcelain(*worktrees)
    worktrees.map { |path, branch| "worktree #{path}\nHEAD abc\nbranch refs/heads/#{branch}\n" }.join("\n")
  end

  def git_commands
    @git_commands || []
  end

  def stub_security(search:, default:)
    Open3.stubs(:capture3).with("security", "list-keychains", "-d", "user").returns([ "\"#{search}\"\n", "", status(true) ])
    Open3.stubs(:capture3).with("security", "default-keychain", "-d", "user").returns([ "\"#{default}\"\n", "", status(true) ])
  end

  def write_source(relative, contents)
    path = File.join(Worktree.root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def stub_git(show_ref: "", worktree_list: "", for_each_ref: "", branch: "master", porcelain: "")
    @git_commands = []
    ok = status(true)
    Open3.stubs(:capture3).with do |*args, **_kwargs|
      next false if args.first == "security"
      next false if args == [ "git", "show-ref" ]
      next false if args == WORKTREE_LIST
      next false if args == FOR_EACH_REF
      next false if args == [ "git", "branch", "--show-current" ]
      next false if args == [ "git", "status", "--porcelain" ]

      @git_commands << args
      if args[1] == "worktree" && args[2] == "add"
        arguments = args.drop(3).reject { |argument| argument == "--force" }
        path = arguments[0] == "-b" ? arguments[2] : arguments[0]
        FileUtils.mkdir_p(path)
      elsif args[1] == "worktree" && args[2] == "remove"
        FileUtils.remove_entry(args.last) if Dir.exist?(args.last)
      end
      true
    end.returns([ "", "", ok ])
    Open3.stubs(:capture3).with("git", "show-ref", chdir: Worktree.root).returns([ show_ref, "", ok ])
    Open3.stubs(:capture3).with(*WORKTREE_LIST, chdir: Worktree.root).returns([ worktree_list, "", ok ])
    Open3.stubs(:capture3).with(*FOR_EACH_REF, chdir: Worktree.root).returns([ for_each_ref, "", ok ])
    Open3.stubs(:capture3).with("git", "branch", "--show-current", chdir: Worktree.root).returns([ "#{branch}\n", "", ok ])
    Open3.stubs(:capture3).with("git", "status", "--porcelain", chdir: Worktree.root).returns([ porcelain, "", ok ])
  end

  def status(success)
    Object.new.tap { |object| object.define_singleton_method(:success?) { success } }
  end
end
