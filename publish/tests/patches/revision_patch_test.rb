require_relative "../test_helper"

class AppsRevisionPatchTest < Minitest::Test
  def test_uploads_only_macos_to_github_once
    ios = Apps.targets.fetch(0)
    target = ios.merge(name: :macos, platform: "MAC_OS")
    Apps.targets << target
    FileUtils.mkdir_p(Apps.archive_path(target))
    commands = []
    options = nil
    Cmd.stubs(:local).with do |command|
      commands << command
      if command.include?("xcodebuild")
        path = command.split.fetch(command.split.index("-exportOptionsPlist") + 1)
        options = File.read(path)
        FileUtils.mkdir_p(File.join(Apps.revision_export_path(target), "App.app"))
      elsif command.include?("ditto")
        File.write(Apps.revision_path(target), "signed-app")
      end
      true
    end.returns("Developer ID Application\nstatus: Accepted")
    Req.expects(:call).with { |request| request[:method].blank? }.once.returns([])
    Req.expects(:call).with { |request| request[:method] == :post && request[:payload].present? }
      .once
      .returns(id: 1, assets: [])
    Req.expects(:call).with do |request|
      request[:method] == :post && request[:url].include?("/assets") && request[:body].include?("signed-app")
    end.once.returns({})

    Apps::RevisionPatch.apply
    Apps::RevisionPatch.apply

    command = commands.find { |value| value.include?("xcodebuild") }
    assert_includes command, "xcodebuild -exportArchive"
    Apps.authentication_arguments.each { |argument| assert_includes command, Shellwords.escape(argument) }
    assert_includes options, "developer-id"
    refute_includes options, "release-testing"
    assert commands.any? { |command| command.include?("security import") }
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

  def test_replaces_changed_asset
    target = Apps.targets.fetch(0)
    target[:platform] = "MAC_OS"
    FileUtils.mkdir_p(Apps.archive_path(target))
    FileUtils.mkdir_p(File.dirname(Apps.revision_path(target)))
    File.write(Apps.revision_path(target), "new")
    Req.expects(:call).with { |request| request[:method].blank? }.returns([
      {
        id: 1,
        tag_name: "v#{Apps.version}",
        assets: [ { id: 2, name: File.basename(Apps.revision_path(target)), digest: "sha256:old" } ],
      },
    ])
    Req.expects(:call).with do |request|
      request[:method] == :delete && request[:url].end_with?("/releases/assets/2")
    end.returns({})
    Req.expects(:call).with do |request|
      request[:method] == :post && request[:url].include?("uploads.github.com") && request[:body] == "new"
    end.returns({})

    Apps::RevisionPatch.apply

    refute Apps::RevisionPatch.needed?
  end
end
