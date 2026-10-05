require_relative "../test_helper"

class AppsValidationPatchTest < Minitest::Test
  def setup
    Cmd.stubs(:local).with("git fetch origin master").returns("")
    Cmd.stubs(:local).with("git status --porcelain").returns("")
    Cmd.stubs(:local).with("git rev-parse HEAD").returns("abc123\n")
    Cmd.stubs(:local).with("git rev-parse origin/master").returns("abc123\n")
  end

  def test_validates_configuration
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    Apps::ValidationPatch.apply
  end

  def test_rejects_missing_credentials
    value = ENV.delete("APPLE_KEY_ID")
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "Missing APPLE_KEY_ID", error.message
  ensure
    ENV["APPLE_KEY_ID"] = value
  end

  def test_requires_mr_for_macos_releases
    Apps.targets.fetch(0)[:platform] = "MAC_OS"
    ENV["PATH"] = File.join(@publish_test_dir, "missing")
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "mr not found on PATH; run mise install_mr in Mr. Moto to publish macOS releases", error.message
  end

  def test_rejects_missing_metadata
    Apps.config[:description] = ""
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "Missing description in app configuration", error.message
  end

  def test_rejects_invalid_skip_app_stores
    Apps.config[:skip_app_stores] = "true"
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "skip_app_stores must be true or false in app configuration", error.message
  end

  def test_requires_demo_credentials_when_sign_in_is_required
    Apps.config[:demoAccountName] = ""
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "Missing demoAccountName in app configuration", error.message
  end

  def test_rejects_a_review_attachment_without_a_path
    Apps.config[:reviewAttachments] = [ {} ]
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "Missing review attachment path in app configuration", error.message
  end

  def test_rejects_a_missing_review_attachment
    Apps.config[:reviewAttachments] = [ { path: "apps/review/sample.zip" } ]
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "Missing apps/review/sample.zip", error.message
  end

  def test_accepts_an_existing_review_attachment
    path = File.join(Apps.root, "review", "sample.zip")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "attachment")
    Apps.config[:reviewAttachments] = [ { path: } ]
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    Apps::ValidationPatch.apply
  end

  def test_skips_app_store_validation_for_repository_releases
    Apps.config[:skip_app_stores] = true
    Apps.config[:description] = ""
    Apps.config[:demoAccountRequired] = nil
    Apps.targets.fetch(0)[:platform] = "MAC_OS"
    Apps.targets.fetch(0).delete(:screenshots)
    FileUtils.rm_f(Apps.export_options_path)
    values = %w[
      APPLE_DISTRIBUTION_CERTIFICATE_BASE64
      APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD
      APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64
      APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD
    ].to_h { |name| [ name, ENV.delete(name) ] }
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    Apps::ValidationPatch.apply
  ensure
    values&.each { |name, value| ENV[name] = value }
  end

  def test_requires_macos_target_for_repository_releases
    Apps.config[:skip_app_stores] = true
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "Missing macOS target for repository release", error.message
  end

  def test_rejects_uncommitted_changes
    Cmd.stubs(:local).with("git status --porcelain").returns(" M config.json\n")
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "Uncommitted changes; publish from a clean checkout of origin/master", error.message
  end

  def test_rejects_a_checkout_behind_origin_master
    Cmd.stubs(:local).with("git rev-parse origin/master").returns("def456\n")
    Cmd.expects(:local).with("xcodebuild -version").returns("Xcode")

    error = assert_raises(RuntimeError) { Apps::ValidationPatch.apply }

    assert_equal "HEAD is not origin/master; publish from a clean checkout of origin/master", error.message
  end
end
