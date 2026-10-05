require_relative "../test_helper"

class AppsRevisionPatchTest < Minitest::Test
  def test_releases_only_macos_through_mr_moto_once
    ios = Apps.targets.fetch(0)
    target = ios.merge(name: :macos, platform: "MAC_OS")
    Apps.targets << target
    FileUtils.mkdir_p(Apps.archive_path(target))
    commands = []
    options = nil
    notes = nil
    bundler = nil
    Cmd.stubs(:local).with do |command|
      commands << command
      if command.include?("xcodebuild")
        path = command.split.fetch(command.split.index("-exportOptionsPlist") + 1)
        options = File.read(path)
        FileUtils.mkdir_p(File.join(Apps.revision_export_path(target), "App.app"))
      elsif command.include?("ditto")
        File.write(Apps.revision_path(target), "signed-app")
      elsif command.start_with?("mise ")
        arguments = Shellwords.split(command)
        notes = File.read(arguments.fetch(arguments.index("--notes-file") + 1))
        bundler = ENV["BUNDLE_GEMFILE"]
      end
      true
    end.returns("Developer ID Application\nstatus: Accepted")
    Req.expects(:call).never

    Apps::RevisionPatch.apply
    Apps::RevisionPatch.apply

    command = commands.find { |value| value.include?("xcodebuild") }
    assert_includes command, "xcodebuild -exportArchive"
    Apps.authentication_arguments.each { |argument| assert_includes command, Shellwords.escape(argument) }
    assert_includes options, "developer-id"
    refute_includes options, "release-testing"
    assert commands.any? { |command| command.include?("security import") }
    releases = commands.select { |value| value.start_with?("mise ") }.map { |value| Shellwords.split(value) }
    assert_equal 1, releases.length
    release = releases.fetch(0)
    assert_equal [ "mise", "-C", ENV.fetch("MR_MOTO_ROOT"), "release", Apps.project_name, "--tag", "v#{Apps.version}" ], release.first(7)
    assert_equal Apps.revision_path(target), release.fetch(release.index("--asset") + 1)
    assert_equal "-macos-#{Apps.version}.zip", release.fetch(release.index("--obsolete-suffix") + 1)
    assert_equal "Changes", notes
    assert_nil bundler
    refute File.exist?(Apps.revision_path(ios))
    refute Apps::RevisionPatch.needed?
  end

  def test_ignores_non_macos_targets
    Cmd.expects(:local).never
    Req.expects(:call).never

    refute Apps::RevisionPatch.needed?
    Apps::RevisionPatch.apply
  end

  def test_repository_only_release_exports_and_notarizes_macos
    target = Apps.targets.fetch(0)
    target[:name] = :macos
    target[:platform] = "MAC_OS"
    Apps.config[:name] = "Example App"
    Apps.config[:skip_app_stores] = true
    FileUtils.mkdir_p(Apps.archive_path(target))
    commands = []
    options = nil
    Cmd.stubs(:local).with do |command|
      commands << command
      if command.include?("xcodebuild")
        path = command.split.fetch(command.split.index("-exportOptionsPlist") + 1)
        options = File.read(path)
        FileUtils.mkdir_p(File.join(Apps.revision_export_path(target), "App-macOS.app"))
      elsif command.include?("ditto")
        File.write(Apps.revision_path(target), "signed-app")
      end
      true
    end.returns("Developer ID Application\nstatus: Accepted")

    Apps::RevisionPatch.send(:package, target)

    assert_includes options, "developer-id"
    assert commands.any? { |command| command.include?("notarytool submit") }
    assert commands.any? { |command| command.include?("stapler staple") }
    assert commands.any? { |command| command.include?("spctl --assess") }
    assert commands.any? { |command| command.include?("Example\\ App.app") }
    assert commands.any? { |command| command.include?("security import") }
    assert commands.any? { |command| command.include?("codesign --force --deep --options runtime") }
    refute commands.any? { |command| command.include?(ENV.fetch("APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD")) }
    assert_equal 2, commands.count { |command| command.include?("ditto") }
  end

  def test_requires_archive
    Apps.targets.fetch(0)[:platform] = "MAC_OS"

    assert_raises(RuntimeError) { Apps::RevisionPatch.apply }
  end

  def test_failed_release_is_retried
    target = Apps.targets.fetch(0)
    target[:platform] = "MAC_OS"
    FileUtils.mkdir_p(Apps.archive_path(target))
    FileUtils.mkdir_p(File.dirname(Apps.revision_path(target)))
    File.write(Apps.revision_path(target), "new")
    Cmd.expects(:local).with { |command| command.start_with?("mise ") }.raises(RuntimeError, "Command failed")

    assert_raises(RuntimeError) { Apps::RevisionPatch.apply }

    assert Apps::RevisionPatch.needed?
  end
end
