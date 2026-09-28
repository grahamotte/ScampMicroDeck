require_relative "../test_helper"

class DbBackupPatchTest < Minitest::Test
  def test_always
    commands = []
    Cmd.stubs(:ssh).with { |command, *| commands << command; true }.returns("")

    DbBackupPatch.always

    dump = commands.find { |command| command.include?("pg_dump") }
    key = dump.match(%r{/home/deploy/(app_production_\d+\.sql)})[1]
    assert_includes commands, "which aws"
    assert_includes commands, "sudo apt-get install -y awscli"
    assert_includes dump, "-U deploy --clean app_production"
    assert commands.any? { |command| command.include?("s3 cp /home/deploy/#{key} s3://backups/#{key}") }
    assert_includes commands, "rm -f /home/deploy/#{key}"
  end
end
