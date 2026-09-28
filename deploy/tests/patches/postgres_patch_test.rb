require_relative "../test_helper"

class PostgresPatchTest < Minitest::Test
  USER_CHECK = "sudo -u postgres psql -c \"SELECT 'asstits' FROM pg_roles WHERE rolname = 'deploy'\""
  DB_CHECK = "sudo -u postgres psql -l | grep app_production"

  def test_needed
    Cmd.expects(:ssh).with("which psql").returns("")
    assert PostgresPatch.needed?

    Cmd.expects(:ssh).with("which psql").returns("/usr/bin/psql")
    Cmd.expects(:ssh).with(USER_CHECK).returns("asstits")
    Cmd.expects(:ssh).with(DB_CHECK).returns("app_production")
    refute PostgresPatch.needed?
  end

  def test_apply_existing_postgres
    commands = []
    Cmd.stubs(:ssh).with do |command, *|
      commands << command
      ![ "which psql", USER_CHECK, DB_CHECK ].include?(command) && !command.start_with?("systemctl show")
    end.returns("")
    Cmd.expects(:ssh).with("which psql").returns("/usr/bin/psql")
    Cmd.expects(:ssh).with(USER_CHECK).returns("asstits")
    Cmd.expects(:ssh).with(DB_CHECK).returns("app_production")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/))
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    Cmd.expects(:ssh_write)
      .with("/etc/postgresql/18/main/pg_hba.conf", includes("127.0.0.1/32"), sudo: true)

    PostgresPatch.apply

    assert_includes commands, "sudo systemctl stop postgresql.service"
    assert_includes commands, "sudo systemctl start postgresql.service"
    refute commands.any? { |command| command.include?("createuser") }
    refute commands.any? { |command| command.include?("createdb") }
  end

  def test_apply_installs_postgres_and_creates_database
    commands = []
    Cmd.stubs(:ssh).with do |command, *|
      commands << command
      ![ "which psql", USER_CHECK, DB_CHECK ].include?(command) && !command.start_with?("systemctl show")
    end.returns("")
    Cmd.expects(:ssh).with("which psql").returns("")
    Cmd.expects(:ssh).with(USER_CHECK).returns("")
    Cmd.expects(:ssh).with(DB_CHECK).returns("")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/)).twice
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    Cmd.expects(:ssh_write)

    PostgresPatch.apply

    assert commands.any? { |command| command.include?("install postgresql-18 libpq-dev") }
    assert_includes commands, "sudo -u postgres createuser -s deploy"
    assert_includes commands, "sudo -u postgres createdb app_production"
  end

  def test_existence_checks_handle_failures
    Cmd.expects(:ssh).with(USER_CHECK).raises("failure")
    refute PostgresPatch.send(:user_exists?)

    Cmd.expects(:ssh).with(DB_CHECK).raises("failure")
    refute PostgresPatch.send(:db_exists?)
  end
end
