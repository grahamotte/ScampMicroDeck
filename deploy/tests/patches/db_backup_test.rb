require_relative "../test_helper"

class DbBackupPatchTest < Minitest::Test
  def test_always
    commands = []
    stdins = []
    Cmd.stubs(:ssh).with { |command, *, **opts| commands << command; stdins << opts[:stdin]; true }.returns("")

    DbBackupPatch.always

    dump = commands.find { |command| command.include?("pg_dump") }
    key = dump.match(%r{/home/deploy/(app_production_\d+\.sql)})[1]
    assert_includes commands, "which aws"
    assert_includes commands, "sudo apt-get install -y awscli"
    assert_includes dump, "-U deploy --clean app_production"
    assert commands.any? { |command| command.include?("s3 cp /home/deploy/#{key} s3://backups/#{key}") }
    assert_includes commands, "rm -f /home/deploy/#{key}"
    assert_includes stdins, "access\nsecret\n"
    refute commands.any? { |command| command.include?("access") || command.include?("secret") }
  end
end
