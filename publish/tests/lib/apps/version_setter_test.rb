require_relative "../../test_helper"

class AppsVersionSetterTest < Minitest::Test
  def test_sets_config_and_every_unique_apple_project
    root = File.join(@publish_test_dir, "root")
    config_path = File.join(root, "config.json")
    first_project = File.join(root, "apps", "apple", "First.xcodeproj")
    second_project = File.join(root, "apps", "apple", "Second.xcodeproj")
    FileUtils.mkdir_p(first_project)
    FileUtils.mkdir_p(second_project)
    File.write(File.join(first_project, "project.pbxproj"), "MARKETING_VERSION = 1.2.3; CURRENT_PROJECT_VERSION = 456;")
    File.write(File.join(second_project, "project.pbxproj"), "CURRENT_PROJECT_VERSION = 1;\nMARKETING_VERSION = 1.2.3;")
    File.write(
      config_path,
      JSON.generate(
        "domain" => "example.com",
        "apps" => {
          "build" => "456",
          "targets" => {
            "apple" => {
              "ios" => { "project" => "apps/apple/First.xcodeproj" },
              "macos" => { "project" => "apps/apple/First.xcodeproj" },
              "tvos" => { "project" => "apps/apple/Second.xcodeproj" },
            },
            "android" => {},
          },
          "version" => "1.2.3",
          "whatsNew" => "Changes",
        },
      ),
    )

    Apps::VersionSetter.call("2.0.1", root:)

    config = JSON.parse(File.read(config_path))
    assert_equal "example.com", config.fetch("domain")
    assert_equal "2.0.1", config.dig("apps", "version")
    assert_equal "2.0.1", config.dig("apps", "build")
    assert_equal "Changes", config.dig("apps", "whatsNew")
    assert_equal "MARKETING_VERSION = 2.0.1; CURRENT_PROJECT_VERSION = 2.0.1;", File.read(File.join(first_project, "project.pbxproj"))
    assert_equal "CURRENT_PROJECT_VERSION = 2.0.1;\nMARKETING_VERSION = 2.0.1;", File.read(File.join(second_project, "project.pbxproj"))
  end

  def test_rejects_invalid_versions_before_writing
    root = File.join(@publish_test_dir, "root")

    error = assert_raises(RuntimeError) { Apps::VersionSetter.call("1.2", root:) }

    assert_equal "Invalid version 1.2", error.message
    refute_path_exists root
  end

  def test_rejects_configured_unsupported_targets
    root = File.join(@publish_test_dir, "root")
    config_path = File.join(root, "config.json")
    project = File.join(root, "apps", "apple", "App.xcodeproj")
    FileUtils.mkdir_p(project)
    File.write(File.join(project, "project.pbxproj"), "MARKETING_VERSION = 1.2.3;")
    File.write(
      config_path,
      JSON.generate(
        "apps" => {
          "targets" => {
            "apple" => { "ios" => { "project" => "apps/apple/App.xcodeproj" } },
            "android" => { "phone" => {} },
          },
        },
      ),
    )

    error = assert_raises(RuntimeError) { Apps::VersionSetter.call("1.2.3", root:) }

    assert_equal "Unsupported deploy target android", error.message
    assert_equal "MARKETING_VERSION = 1.2.3;", File.read(File.join(project, "project.pbxproj"))
  end
end
