require_relative "../../test_helper"
require "stringio"

class KeychainTaskTest < Minitest::Test
  class FakeSecurity
    attr_accessor :search, :default
    attr_reader :calls

    def initialize(search:, default:)
      @search = search
      @default = default
      @calls = []
    end

    def call(*arguments)
      @calls << arguments
      command, *options = arguments
      values = options.include?("-s") ? options.drop(options.index("-s") + 1) : nil
      case command
      when "list-keychains"
        return @search = values if values

        search.map { |path| "    \"#{path}\"\n" }.join
      when "default-keychain"
        return @default = values.first if values

        default ? "    \"#{default}\"\n" : ""
      else
        raise "security #{command} is not supported"
      end
    end

    def changes
      calls.select { |arguments| arguments.include?("-s") }
    end
  end

  def setup
    @home = File.join(@publish_test_dir, "home")
    @keychains = File.join(@home, "Library", "Keychains")
    FileUtils.mkdir_p(@keychains)
    @login = File.join(@keychains, "login.keychain-db")
    File.write(@login, "login")
    @security = FakeSecurity.new(search: [ @login ], default: @login)
    @keychain = Keychain.new(home: @home, runner: @security)
    @output = StringIO.new
  end

  def test_reports_a_healthy_configuration
    assert run_task

    assert_equal "The host keychain configuration is healthy.\n", @output.string
    assert_empty @security.changes
  end

  def test_recovers_the_snapshot_of_a_killed_signing_run
    temporary = File.join(@publish_test_dir, "artifacts", "signing-1.keychain-db")
    state = write_state(pid: 99_999_999, search: [ @login ], default: @login)
    @security.search = [ temporary, @login ]

    assert run_task

    assert_equal [ @login ], @security.search
    assert_equal [ "restored keychains from #{state}", "The host keychain configuration is healthy." ], @output.string.lines.map(&:chomp)
    refute File.exist?(state)
  end

  def test_releases_keychains_that_no_longer_exist
    missing = File.join(@publish_test_dir, "artifacts", "signing-1.keychain-db")
    @security.search = [ missing, @login ]

    assert run_task

    assert_equal [ @login ], @security.search
    assert_equal [ "removed missing keychain #{missing}", "The host keychain configuration is healthy." ], @output.string.lines.map(&:chomp)
  end

  def test_reports_problems_that_need_the_user_and_fails
    other = File.join(@keychains, "other.keychain-db")
    File.write(other, "other")
    @security.default = other

    refute run_task

    assert_equal(
      [
        "- default keychain is #{other}, not #{@login}",
        "Run `mise keychain --repair` to restore the login keychain. Repairing may ask you to log out and back in.",
      ],
      @output.string.lines.map(&:chomp),
    )
    assert_equal other, @security.default
    assert_empty @security.changes
  end

  def test_skips_while_a_signing_run_is_in_progress
    write_state(pid: Process.pid, search: [ @login ], default: @login)
    @security.default = nil

    assert run_task

    assert_equal "A signing run is using a temporary keychain. Run this again after it finishes.\n", @output.string
    assert_empty @security.changes
  end

  def test_repair_waits_for_a_signing_run_and_fails
    write_state(pid: Process.pid, search: [ @login ], default: @login)

    refute run_task(repair: true)

    assert_equal "A signing run is using a temporary keychain. Run this again after it finishes.\n", @output.string
    assert_empty @security.changes
  end

  def test_repair_resets_the_default_keychain_and_search_list
    other = File.join(@keychains, "other.keychain-db")
    File.write(other, "other")
    @security.default = other
    @security.search = [ other, @login ]

    assert run_task(repair: true)

    assert_equal @login, @security.default
    assert_equal [ other, @login ], @security.search
    assert_equal(
      [
        "- default keychain is #{other}, not #{@login}",
        "Reset the default keychain and search list to #{@login}.",
      ],
      @output.string.lines.map(&:chomp),
    )
  end

  def test_repair_restores_a_renamed_login_keychain
    renamed = File.join(@keychains, "login_renamed_1.keychain-db")
    File.write(renamed, "original login keychain")

    assert run_task(repair: true)

    backup = Dir.glob(File.join(@keychains, "login_backup_*.keychain-db")).first
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

  def test_repair_fails_when_a_problem_remains
    File.delete(@login)

    refute run_task(repair: true)

    assert_includes @output.string, "Still needs attention: #{@login} is missing\n"
  end

  private

  def run_task(repair: false)
    Apps::KeychainTask.call(repair:, keychain: @keychain, output: @output)
  end

  def write_state(pid:, search:, default:)
    FileUtils.mkdir_p(@keychain.state_root)
    file = File.join(@keychain.state_root, "20260101000000000000-#{pid}.json")
    File.write(file, JSON.generate(pid:, snapshot: { search:, default: }))
    file
  end
end
