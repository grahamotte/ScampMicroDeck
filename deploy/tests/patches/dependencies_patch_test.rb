require_relative "../test_helper"

class DependenciesPatchTest < Minitest::Test
  def test_always_with_installed_dependencies
    commands = []
    Cmd.stubs(:ssh).with { |command, *| commands << command; true }.returns("/usr/bin/tool")

    DependenciesPatch.always

    assert_includes commands, "which ffmpeg"
    assert_includes commands, "which convert"
    assert_includes commands, "which mise"
    assert_includes commands, 'mise settings add idiomatic_version_file_enable_tools "[]"'
    assert_includes commands, "mise settings set ruby.compile=false"
    assert commands.any? { |command| command.include?("curl -fsSL https://opencode.ai/install") }
    assert commands.any? { |command| command.include?("--no-modify-path") }
    assert commands.any? { |command| command.include?("sudo ln -sf ~/.opencode/bin/opencode /usr/local/bin/opencode") }
    refute commands.any? { |command| command.include?("apt install -y mise") }
  end

  def test_always_installs_missing_dependencies
    commands = []
    Cmd.stubs(:ssh).with { |command, *| commands << command; true }.returns("")

    DependenciesPatch.always

    assert_includes commands, "sudo apt-get install -y ffmpeg"
    assert_includes commands, "sudo apt-get install -y imagemagick"
    assert_includes commands, "sudo apt-get install -y unzip"
    assert commands.any? { |command| command.include?("awscli-exe-linux-$(uname -m).zip") && command.include?("sudo ./aws/install --update") }
    assert_includes commands, "sudo apt install -y mise"
  end

  def test_needed
    versions = DependenciesPatch.send(:tool_versions).transform_values { |version| [ { version:, installed: true } ] }
    Cmd.expects(:ssh).with("mise list --json").returns(JSON.generate(versions))
    refute DependenciesPatch.needed?

    DependenciesPatch.instance_variable_set(:@current_versions, nil)
    Cmd.expects(:ssh).with("mise list --json").returns("{}")
    assert DependenciesPatch.needed?
  end

  def test_tool_versions
    versions = DependenciesPatch.send(:tool_versions)

    assert_equal "4.0.6", versions.fetch("ruby")
    assert_equal "26.7.0", versions.fetch("node")
    refute versions.key?("opencode")
  end

  def test_apply
    commands = []
    Cmd.stubs(:ssh).with { |command, *| commands << command; true }

    DependenciesPatch.apply

    assert_includes commands, "cd /var/www/example.com && mise -y trust -a"
    assert commands.any? { |command| command.include?("build-essential") }
    assert_includes commands, "mkdir -p ~/tmp"
    assert commands.any? { |command| command.include?("mise install --yes") }
  end

  def test_current_versions_handles_failure
    Cmd.expects(:ssh).with("mise list --json").raises("failure")

    assert_equal({}, DependenciesPatch.send(:current_versions))
  end
end
