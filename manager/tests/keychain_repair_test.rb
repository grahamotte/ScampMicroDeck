require_relative "test_helper"
require "stringio"

class KeychainRepairTest < Minitest::Test
  def setup
    @output = StringIO.new
    @keychain = Worktree.keychain
    @login = @keychain.login
    @ok = Struct.new(:success?).new(true)
  end

  def test_reports_healthy_keychains
    Open3.expects(:capture3).with { |command, *arguments| command == "security" && arguments.include?("-s") }.never

    assert KeychainRepair.new(output: @output).call

    assert_equal "The host keychain configuration is healthy.\n", @output.string
  end

  def test_resets_replaced_keychains
    other = File.join(File.dirname(@login), "other.keychain-db")
    File.write(other, "other")
    Open3.stubs(:capture3).with("security", "default-keychain", "-d", "user").returns([ "\"#{other}\"\n", "", @ok ], [ "\"#{other}\"\n", "", @ok ], [ "\"#{other}\"\n", "", @ok ], [ "\"#{@login}\"\n", "", @ok ])
    Open3.expects(:capture3).with("security", "default-keychain", "-d", "user", "-s", @login).returns([ "", "", @ok ])

    assert KeychainRepair.new(output: @output).call

    assert_equal(
      [
        "- default keychain is #{other}, not #{@login}",
        "Reset the default keychain and search list to #{@login}.",
      ],
      @output.string.lines.map(&:chomp),
    )
  end

  def test_restores_renamed_login_keychain
    renamed = File.join(File.dirname(@login), "login_renamed_1.keychain-db")
    File.write(renamed, "original login keychain")
    Open3.expects(:capture3).with { |command, *arguments| command == "security" && arguments.include?("-s") }.never

    assert KeychainRepair.new(output: @output).call

    backup = Dir.glob(File.join(File.dirname(@login), "login_backup_*.keychain-db")).first
    assert_equal "login", File.read(backup)
    assert_equal "original login keychain", File.read(@login)
    assert_equal(
      [
        "- #{renamed} is larger than #{@login} and may hold the original login keychain",
        "Restored #{@login} from #{renamed}.",
        "Saved the previous login keychain to #{backup}.",
        "Log out and back in so macOS reloads the login keychain.",
        "Reset the default keychain and search list to #{@login}.",
      ],
      @output.string.lines.map(&:chomp),
    )
  end

  def test_reports_remaining_problems
    other = File.join(File.dirname(@login), "other.keychain-db")
    File.write(other, "other")
    Open3.stubs(:capture3).with("security", "default-keychain", "-d", "user").returns([ "\"#{other}\"\n", "", @ok ])
    Open3.expects(:capture3).with("security", "default-keychain", "-d", "user", "-s", @login).returns([ "", "", @ok ])

    refute KeychainRepair.new(output: @output).call

    assert_includes @output.string, "Still needs attention: default keychain is #{other}, not #{@login}\n"
  end

  def test_waits_for_running_tasks
    FileUtils.mkdir_p(@keychain.state_root)
    File.write(
      File.join(@keychain.state_root, "20260101000000000000-#{Process.pid}.json"),
      JSON.generate(pid: Process.pid, snapshot: { search: [ @login ], default: @login }),
    )
    Open3.expects(:capture3).with { |command, *arguments| command == "security" && arguments.include?("-s") }.never

    refute KeychainRepair.new(output: @output).call

    assert_equal "A task is using a temporary keychain. Run this again after it finishes.\n", @output.string
  end

end
