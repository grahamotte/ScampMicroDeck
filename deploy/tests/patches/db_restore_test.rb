require_relative "../test_helper"

class DbRestorePatchTest < Minitest::Test
  def test_always_restores_latest_backup
    commands = restore_commands

    DbRestorePatch.always

    assert commands.any? { |command| command.include?("s3 cp s3://backups/app_production_2.sql /home/deploy/app_production_2.sql") }
    assert_includes commands, "psql -v ON_ERROR_STOP=1 app_production < /home/deploy/app_production_2.sql"
    assert_includes commands, "sudo systemctl start postgresql.service"
    assert_includes commands, "rm -f /home/deploy/app_production_2.sql"
    assert_service_order(commands)
  end

  def test_always_restarts_services_if_restore_fails
    commands = restore_commands(fail_restore: true)

    assert_raises(RuntimeError) { DbRestorePatch.always }

    refute_includes commands, "sudo systemctl start postgresql.service"
    refute_includes commands, "rm -f /home/deploy/app_production_2.sql"
    assert_service_order(commands, restored: false)
  end

  def test_backup_keys_filters_and_sorts
    Cmd.stubs(:ssh).returns(<<~TEXT)
      2026-01-01 1 other_1.sql
      2026-01-02 1 app_production_2.sql
      2026-01-03 1 app_production_1.sql
    TEXT

    assert_equal [ "app_production_1.sql", "app_production_2.sql" ], DbRestorePatch.send(:backup_keys)
  end

  private

  def restore_commands(fail_restore: false)
    commands = []
    Cmd.stubs(:ssh).with do |command, *|
      raise "restore failed" if fail_restore && command.start_with?("psql")

      commands << command
      command != "which aws" && !command.include?("s3 ls") && !command.start_with?("systemctl show")
    end.returns("")
    Cmd.expects(:ssh).with("which aws").returns("/usr/bin/aws")
    Cmd.expects(:ssh).with(includes("s3 ls")).returns("2026-01-01 1 other_1.sql\n2026-01-02 1 app_production_2.sql\n2026-01-03 1 app_production_1.sql")
    Cmd.expects(:ssh).with(regexp_matches(/\Asystemctl show/)).at_least_once
      .returns("LoadState=loaded\nActiveState=active\nFreezerState=running\n")
    commands
  end

  def assert_service_order(commands, restored: true)
    stop_job = commands.index("sudo systemctl stop job.service")
    stop_api = commands.index("sudo systemctl stop api.service")
    start_job = commands.index("sudo systemctl start job.service")
    start_api = commands.index("sudo systemctl start api.service")
    psql = commands.index("psql -v ON_ERROR_STOP=1 app_production < /home/deploy/app_production_2.sql") if restored

    refute_nil stop_job
    refute_nil stop_api
    refute_nil start_job
    refute_nil start_api
    assert stop_job < stop_api
    assert stop_api < start_job
    assert start_job < start_api
    return unless restored

    refute_nil psql
    assert stop_api < psql
    assert psql < start_job
  end
end
