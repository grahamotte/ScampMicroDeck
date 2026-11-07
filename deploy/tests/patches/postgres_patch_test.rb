require_relative "../test_helper"

class PostgresPatchTest < Minitest::Test
  USER_CHECK = "sudo -u postgres psql -c \"SELECT 'asstits' FROM pg_roles WHERE rolname = 'deploy'\""
  APP_USER_CHECK = "sudo -u postgres psql -c \"SELECT 'asstits' FROM pg_roles WHERE rolname = 'app'\""
  DB_CHECK = "sudo -u postgres psql -l | grep app_production"
  OWNER_CHECK = "sudo -u postgres psql -d app_production -Atc \"" \
    "SELECT pg_get_userbyid(datdba) = 'app' " \
    "AND NOT EXISTS (SELECT 1 FROM (" \
    "SELECT relowner AS owner FROM pg_class UNION ALL " \
    "SELECT proowner FROM pg_proc UNION ALL " \
    "SELECT typowner FROM pg_type UNION ALL " \
    "SELECT nspowner FROM pg_namespace" \
    ") AS objects WHERE pg_get_userbyid(owner) = 'deploy') " \
    "FROM pg_database WHERE datname = current_database()\""
  PG_HBA_CHECK = "sudo cat /etc/postgresql/18/main/pg_hba.conf 2>/dev/null || true"
  JOURNAL_CHECK = "sudo cat /etc/postgresql/18/main/conf.d/journal.conf 2>/dev/null || true"
  JOURNAL_CONF = "log_destination = 'syslog'\nsyslog_ident = 'postgres'\n"
  ALTER_OWNER = "sudo -u postgres psql -d app_production -c \"ALTER DATABASE app_production OWNER TO app\""
  REASSIGN = "sudo -u postgres psql -d app_production -c \"REASSIGN OWNED BY deploy TO app\""
  CHECKS = [ "which psql", USER_CHECK, APP_USER_CHECK, DB_CHECK, OWNER_CHECK ].freeze

  def test_needed
    Cmd.expects(:ssh).with("which psql").returns("")
    assert PostgresPatch.needed?

    expect_current
    refute PostgresPatch.needed?

    expect_current(app_user: "")
    assert PostgresPatch.needed?

    expect_current(owner: "f\n")
    assert PostgresPatch.needed?

    expect_current(pg_hba: pg_hba_conf.gsub("scram-sha-256", "trust"))
    assert PostgresPatch.needed?

    expect_current(journal: "")
    assert PostgresPatch.needed?
  end

  def test_apply_existing_postgres
    commands = stub_commands
    Cmd.expects(:ssh).with("which psql").returns("/usr/bin/psql")
    Cmd.expects(:ssh).with(USER_CHECK).returns("asstits")
    Cmd.expects(:ssh).with(APP_USER_CHECK).returns("asstits")
    Cmd.expects(:ssh).with(DB_CHECK).returns("app_production")
    Cmd.expects(:ssh).with(OWNER_CHECK).returns("t\n")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/))
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    Cmd.expects(:ssh_write)
      .with("/etc/postgresql/18/main/pg_hba.conf", pg_hba_conf, sudo: true)
    Cmd.expects(:ssh_write)
      .with("/etc/postgresql/18/main/conf.d/journal.conf", JOURNAL_CONF, sudo: true)

    PostgresPatch.apply

    assert_includes commands, "sudo systemctl stop postgresql.service"
    assert_includes commands, "sudo systemctl start postgresql.service"
    refute commands.any? { |command| command.include?("createuser") }
    refute commands.any? { |command| command.include?("postgres createdb") }
    refute_includes commands, REASSIGN
  end

  def test_apply_moves_existing_database_to_app_user
    commands = stub_commands
    Cmd.expects(:ssh).with("which psql").returns("/usr/bin/psql")
    Cmd.expects(:ssh).with(USER_CHECK).returns("asstits")
    Cmd.expects(:ssh).with(APP_USER_CHECK).returns("")
    Cmd.expects(:ssh).with(DB_CHECK).returns("app_production")
    Cmd.expects(:ssh).with(OWNER_CHECK).returns("f\n")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/))
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    Cmd.expects(:ssh_write).twice

    PostgresPatch.apply

    create = commands.index("sudo -u postgres createuser --no-superuser --no-createdb --no-createrole app")
    alter = commands.index(ALTER_OWNER)
    reassign = commands.index(REASSIGN)
    restart = commands.index("sudo systemctl stop postgresql.service")
    refute_nil create
    assert create < alter
    assert alter < reassign
    assert reassign < restart
    refute_includes commands, "sudo -u postgres createuser -s deploy"
    refute commands.any? { |command| command.include?("postgres createdb") }
  end

  def test_apply_installs_postgres_and_creates_database
    commands = stub_commands
    Cmd.expects(:ssh).with("which psql").returns("")
    Cmd.expects(:ssh).with(USER_CHECK).returns("")
    Cmd.expects(:ssh).with(APP_USER_CHECK).returns("")
    Cmd.expects(:ssh).with(DB_CHECK).returns("")
    Cmd.expects(:ssh).with(OWNER_CHECK).returns("t\n")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/)).twice
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    Cmd.expects(:ssh_write).twice

    PostgresPatch.apply

    assert commands.any? { |command| command.include?("install postgresql-18 libpq-dev") }
    assert_includes commands, "sudo -u postgres createuser -s deploy"
    assert_includes commands, "sudo -u postgres createuser --no-superuser --no-createdb --no-createrole app"
    assert_includes commands, "sudo -u postgres createdb -O app app_production"
    refute_includes commands, REASSIGN
  end

  def test_pg_hba_conf_never_trusts_connections
    refute_includes pg_hba_conf, "trust"
    assert_includes pg_hba_conf, "host    all             all             127.0.0.1/32            scram-sha-256\n"
    assert_includes pg_hba_conf, "host    all             all             ::1/128                 scram-sha-256\n"
    assert_includes pg_hba_conf, "local   replication     all                                     peer\n"
  end

  def test_existence_checks_handle_failures
    Cmd.expects(:ssh).with(USER_CHECK).raises("failure")
    refute PostgresPatch.send(:user_exists?, "deploy")

    Cmd.expects(:ssh).with(DB_CHECK).raises("failure")
    refute PostgresPatch.send(:db_exists?)

    Cmd.expects(:ssh).with(OWNER_CHECK).raises("failure")
    refute PostgresPatch.send(:db_owned_by_app?)
  end

  private

  def pg_hba_conf = PostgresPatch.send(:pg_hba_conf)

  def stub_commands
    commands = []
    Cmd.stubs(:ssh).with do |command, *|
      commands << command
      !CHECKS.include?(command) && !command.start_with?("systemctl show")
    end.returns("")
    commands
  end

  def expect_current(app_user: "asstits", owner: "t\n", pg_hba: pg_hba_conf, journal: JOURNAL_CONF)
    Cmd.expects(:ssh).with("which psql").returns("/usr/bin/psql")
    Cmd.expects(:ssh).with(USER_CHECK).returns("asstits")
    Cmd.expects(:ssh).with(APP_USER_CHECK).returns(app_user)
    return if app_user.blank?

    Cmd.expects(:ssh).with(DB_CHECK).returns("app_production")
    Cmd.expects(:ssh).with(OWNER_CHECK).returns(owner)
    return if owner.strip != "t"

    Cmd.expects(:ssh).with(PG_HBA_CHECK).returns(pg_hba)
    return if pg_hba != pg_hba_conf

    Cmd.expects(:ssh).with(JOURNAL_CHECK).returns(journal)
  end
end
