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
    assert_equal "github.com", Apps.revision_repositories.fetch(0).fetch(:host)
    assert_equal "app", Apps.revision_repositories.fetch(0).fetch(:name)
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

  def test_uses_only_the_temporary_keychain_while_signing
    keychain = File.join(Apps.tmp_root, "signing-#{Process.pid}.keychain-db")
    commands = []
    Cmd.stubs(:local).with { |command| commands << command; true }.returns("Apple Distribution")
    Cmd.expects(:local).with("security list-keychains -d user").returns('"/keychain/login.keychain-db"')
    Cmd.expects(:local).with("security default-keychain -d user").returns('"/keychain/login.keychain-db"')

    Apps.with_signing_certificate("Apple Distribution", "APPLE_DISTRIBUTION") { }

    assert_includes commands, Shellwords.join([ "security", "import", File.expand_path("../../lib/apps/apple_certificate_authorities.pem", __dir__), "-k", keychain, "-f", "pemseq" ])
    assert_includes commands, Shellwords.join([ "security", "list-keychains", "-d", "user", "-s", keychain, "/System/Library/Keychains/SystemRootCertificates.keychain" ])
    assert_includes commands, Shellwords.join([ "security", "default-keychain", "-d", "user", "-s", keychain ])
    assert_includes commands, "security default-keychain -d user -s /keychain/login.keychain-db"
    assert_includes commands, "security list-keychains -d user -s /keychain/login.keychain-db"
    assert commands.any? { |command| command.start_with?("/usr/bin/openssl pkcs12") }
    refute commands.any? { |command| command.include?("brew") }
  end

  def test_reports_invalid_json
    File.write(Constants.config_path, "{")
    Apps.reset
    Apps.root = File.join(@publish_test_dir, "apps")

    error = assert_raises(RuntimeError) { Apps.config }

    assert_includes error.message, "Invalid JSON"
  end
end
