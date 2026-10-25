require_relative "../test_helper"

class AppsCaskPatchTest < Minitest::Test
  def test_publishes_cask_for_released_macos_revision_through_mr
    target = macos_target
    configure_homebrew(zap: [ "~/Library/Application Support/App" ])
    FileUtils.mkdir_p(File.dirname(Apps.revision_path(target)))
    File.write(Apps.revision_path(target), "signed-app")
    published = nil
    bundler = nil
    Cmd.expects(:local).with do |command|
      arguments = Shellwords.split(command)
      published = File.read(arguments.fetch(arguments.index("--file") + 1))
      bundler = ENV["BUNDLE_GEMFILE"]
      arguments.first(6) == [ "cd", Apps.main_root, "&&", "mr", "cask", "--file" ] && arguments.last.end_with?("/app.rb")
    end.returns("")

    assert Apps::CaskPatch.needed?
    Apps::CaskPatch.apply

    expected = <<~'CASK'
      cask "app" do
        version "1.2.3"
        sha256 "%s"

        url "https://github.com/example/app/releases/download/v#{version}/App-macos-#{version}.zip"
        name "App"
        desc "Does things"
        homepage "https://example.com/"

        livecheck do
          url :url
          strategy :github_latest
        end

        depends_on macos: :tahoe

        app "App.app"

        zap trash: "~/Library/Application Support/App"
      end
    CASK
    assert_equal expected.sub("%s", Digest::SHA256.hexdigest("signed-app")), published
    assert_nil bundler
  end

  def test_omits_zap_when_none_is_configured
    target = macos_target
    configure_homebrew
    FileUtils.mkdir_p(File.dirname(Apps.revision_path(target)))
    File.write(Apps.revision_path(target), "signed-app")
    published = nil
    Cmd.expects(:local).with do |command|
      arguments = Shellwords.split(command)
      published = File.read(arguments.fetch(arguments.index("--file") + 1))
      true
    end.returns("")

    Apps::CaskPatch.apply

    refute_includes published, "zap"
    assert published.end_with?("  app \"App.app\"\nend\n")
  end

  def test_follows_homebrew_style_for_bare_homepages_and_zap_paths
    target = macos_target
    Apps.config[:marketingUrl] = "https://example.com"
    configure_homebrew(zap: [ "~/Library/Preferences/org.example.app.plist" ])
    FileUtils.mkdir_p(File.dirname(Apps.revision_path(target)))
    File.write(Apps.revision_path(target), "signed-app")
    published = []
    Cmd.stubs(:local).with do |command|
      arguments = Shellwords.split(command)
      published << File.read(arguments.fetch(arguments.index("--file") + 1))
      true
    end.returns("")

    Apps::CaskPatch.apply
    configure_homebrew(zap: [ "~/Library/Containers/org.example.app", "~/Library/Application Scripts/org.example.app" ])
    Apps::CaskPatch.apply

    assert_includes published.first, "  homepage \"https://example.com/\"\n"
    assert_includes published.first, "  zap trash: \"~/Library/Preferences/org.example.app.plist\"\nend\n"
    assert_includes published.last, "  zap trash: [\n    \"~/Library/Application Scripts/org.example.app\",\n    \"~/Library/Containers/org.example.app\",\n  ]\n"
  end

  def test_not_needed_without_homebrew_configuration_or_macos_target
    macos_target
    Cmd.expects(:local).never

    refute Apps::CaskPatch.needed?

    Apps.targets.fetch(0)[:platform] = "IOS"
    configure_homebrew

    refute Apps::CaskPatch.needed?
  end

  def test_requires_released_revision
    macos_target
    configure_homebrew
    Cmd.expects(:local).never

    error = assert_raises(RuntimeError) { Apps::CaskPatch.apply }

    assert_equal "Missing revision for macos", error.message
  end

  def test_failed_publish_raises
    target = macos_target
    configure_homebrew
    FileUtils.mkdir_p(File.dirname(Apps.revision_path(target)))
    File.write(Apps.revision_path(target), "signed-app")
    Cmd.expects(:local).raises(RuntimeError, "Command failed")

    assert_raises(RuntimeError) { Apps::CaskPatch.apply }
  end

  private

  def macos_target
    target = Apps.targets.fetch(0)
    target[:name] = :macos
    target[:platform] = "MAC_OS"
    target
  end

  def configure_homebrew(**options)
    Apps.config[:homebrew] = { desc: "Does things", macos: "tahoe", **options }
  end
end
