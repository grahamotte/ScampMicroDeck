require_relative "../test_helper"

class AppsTest < Minitest::Test
  def test_loads_configuration
    assert_equal "1.2.3", Apps.version
    assert_equal "456", Apps.build
    assert_equal "Description", Apps.config.fetch(:description)
    assert_equal "Changes", Apps.config.fetch(:whatsNew)
    refute Apps.skip_app_stores?
    assert_equal :ios, Apps.targets.fetch(0).fetch(:name)
    assert_equal File.join(@publish_test_dir, "artifacts", "1.2.3", "ios.xcarchive"), Apps.archive_path(Apps.targets.fetch(0))
    Apps.config[:name] = "Example App"
    assert_equal File.join(@publish_test_dir, "artifacts", "1.2.3", "revisions", "Example-App-ios-1.2.3.ipa"), Apps.revision_path(Apps.targets.fetch(0))
  end

  def test_main_root_resolves_linked_worktrees_to_their_main_checkout
    main = File.join(@publish_test_dir, "code", "app.com")
    worktree = File.join(@publish_test_dir, "code", "app.com-moto-1")
    FileUtils.mkdir_p(File.join(main, ".git", "worktrees", "app.com-moto-1"))
    FileUtils.mkdir_p(worktree)
    File.write(File.join(worktree, ".git"), "gitdir: #{File.join(main, ".git", "worktrees", "app.com-moto-1")}\n")

    assert_equal main, Apps.main_root(main)
    assert_equal main, Apps.main_root(worktree)
  end

  def test_main_root_rejects_an_unreadable_worktree_link
    worktree = File.join(@publish_test_dir, "broken")
    FileUtils.mkdir_p(worktree)
    File.write(File.join(worktree, ".git"), "nothing\n")

    error = assert_raises(RuntimeError) { Apps.main_root(worktree) }

    assert_includes error.message, "Cannot locate the main checkout"
  end

  def test_mr_installed_checks_path
    assert Apps.mr_installed?
    ENV["PATH"] = File.join(@publish_test_dir, "missing")

    refute Apps.mr_installed?
  end

  def test_loads_skip_app_stores
    Apps.config[:skip_app_stores] = true

    assert Apps.skip_app_stores?
  end

  def test_configures_review_submission
    assert Apps.prepare_for_review?
    assert Apps.submit_for_review?

    Apps.submit_for_review = false

    assert Apps.prepare_for_review?
    refute Apps.submit_for_review?

    Apps.submit_for_review = true
    Apps.prepare_for_review = false

    refute Apps.prepare_for_review?
    refute Apps.submit_for_review?
  end

  def test_resolves_review_attachment_path
    attachment = { path: "apps/review/sample.zip" }

    assert_equal File.join(Constants.local_root, "apps/review/sample.zip"), Apps.review_attachment_path(attachment)
  end

  def test_builds_authentication_arguments
    arguments = Apps.authentication_arguments

    assert_includes arguments, ENV.fetch("APPLE_KEY_ID")
    assert_includes arguments, ENV.fetch("APPLE_ISSUER_ID")
    assert File.file?(Apps.private_key_path)
    assert_equal 0600, File.stat(Apps.private_key_path).mode & 0777
    assert_equal ENV.fetch("APPLE_KEY_SECRET_BASE64").unpack1("m0"), File.binread(Apps.private_key_path)
  end

  def test_adds_the_temporary_keychain_without_changing_the_default
    keychain = File.join(Apps.tmp_root, "signing-#{Process.pid}.keychain-db")
    login = File.join(@publish_test_dir, "Library", "Keychains", "login.keychain-db")
    FileUtils.mkdir_p(File.dirname(login))
    File.write(login, "login")
    commands = []
    Cmd.stubs(:local).with { |command| commands << command; true }.returns("Apple Distribution")
    stub_security([ "list-keychains", "-d", "user" ], "\"#{login}\"", "\"#{keychain}\" \"#{login}\"")
    stub_security([ "default-keychain", "-d", "user" ], "\"#{login}\"", "\"#{login}\"")
    Cmd.expects(:local).with(Shellwords.join([ "security", "list-keychains", "-d", "user", "-s", login ])).returns("")

    Apps.with_signing_certificate("Apple Distribution", "APPLE_DISTRIBUTION") do
      assert_equal 1, Dir.glob(File.join(@publish_test_dir, ".config", "codemoto", "keychain", "*.json")).size
    end

    assert_includes commands, Shellwords.join([ "security", "import", File.expand_path("../../lib/apps/apple_certificate_authorities.pem", __dir__), "-k", keychain, "-f", "pemseq" ])
    assert_includes commands, Shellwords.join([ "security", "list-keychains", "-d", "user", "-s", keychain, login, "/System/Library/Keychains/SystemRootCertificates.keychain" ])
    refute_includes commands, Shellwords.join([ "security", "default-keychain", "-d", "user", "-s", keychain ])
    assert_includes commands, Shellwords.join([ "security", "delete-keychain", keychain ])
    assert commands.any? { |command| command.start_with?("/usr/bin/openssl pkcs12") }
    refute commands.any? { |command| command.include?("brew") }
    assert_empty Dir.glob(File.join(@publish_test_dir, ".config", "codemoto", "keychain", "*.json"))
  end

  def test_restores_host_keychains_when_signing_fails
    keychain = File.join(Apps.tmp_root, "signing-#{Process.pid}.keychain-db")
    login = File.join(@publish_test_dir, "Library", "Keychains", "login.keychain-db")
    FileUtils.mkdir_p(File.dirname(login))
    File.write(login, "login")
    Cmd.stubs(:local).returns("")
    stub_security([ "list-keychains", "-d", "user" ], "\"#{login}\"", "\"#{keychain}\" \"#{login}\"")
    stub_security([ "default-keychain", "-d", "user" ], "\"#{login}\"", "\"#{login}\"")
    Cmd.expects(:local).with(Shellwords.join([ "security", "list-keychains", "-d", "user", "-s", login ])).returns("")

    error = assert_raises(RuntimeError) { Apps.with_signing_certificate("Apple Distribution", "APPLE_DISTRIBUTION") { } }

    assert_equal "Missing Apple Distribution identity", error.message
  end

  def test_reports_invalid_json
    File.write(Constants.config_path, "{")
    Apps.reset
    Apps.root = File.join(@publish_test_dir, "apps")

    error = assert_raises(RuntimeError) { Apps.config }

    assert_includes error.message, "Invalid JSON"
  end

  private

  def stub_security(arguments, before, after)
    Cmd.stubs(:local).with(Shellwords.join([ "security", *arguments ])).returns(before).then.returns(after)
  end
end
