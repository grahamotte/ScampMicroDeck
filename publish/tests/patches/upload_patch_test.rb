require_relative "../test_helper"

class AppsUploadPatchTest < Minitest::Test
  def test_skips_app_store_uploads
    Apps.config[:skip_app_stores] = true

    refute Apps::UploadPatch.needed?
    Apps::UploadPatch.call
  end

  def test_uploads_archives_once
    target = Apps.targets.fetch(0)
    FileUtils.mkdir_p(Apps.archive_path(target))
    commands = []
    Cmd.stubs(:local).with { |command| commands << command; true }.returns("Apple Distribution")

    Apps::UploadPatch.apply
    Apps::UploadPatch.apply

    command = commands.find { |value| value.include?("xcodebuild") }
    assert_includes command, "xcodebuild -exportArchive"
    assert commands.any? { |value| value.include?("security import") }
    Apps.authentication_arguments.each { |argument| assert_includes command, Shellwords.escape(argument) }
    refute Apps::UploadPatch.needed?
  end

  def test_requires_archive
    assert_raises(RuntimeError) { Apps::UploadPatch.apply }
  end

  def test_imports_installer_identity_for_macos
    root = Apps.root
    tmp_root = Apps.tmp_root
    config_path = Constants.config_path
    config = JSON.parse(File.read(config_path))
    target = config.dig("apps", "targets", "apple").delete("ios")
    target["platform"] = "MAC_OS"
    config.dig("apps", "targets", "apple")["macos"] = target
    File.write(config_path, JSON.generate(config))
    Apps.reset
    Apps.root = root
    Apps.tmp_root = tmp_root
    target = Apps.targets.fetch(0)
    FileUtils.mkdir_p(Apps.archive_path(target))
    commands = []
    Cmd.stubs(:local).with { |command| commands << command; true }.returns("Apple Distribution Mac Developer Installer")

    Apps::UploadPatch.apply

    assert commands.any? { |command| command.include?("env:APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD") }
    assert commands.any? { |command| command == "security find-identity -v #{Apps.tmp_root}/signing-#{Process.pid}.keychain-db" }
  end
end
