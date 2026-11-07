require_relative "../test_helper"

class AppUserPatchTest < Minitest::Test
  DIRS = "/var/www/example.com/backend/tmp /var/www/example.com/backend/storage /var/www/example.com/backend/log"

  def test_always
    commands = []
    Cmd.stubs(:ssh).with { |command, *| commands << command; true }.returns("")

    AppUserPatch.always

    assert_equal(
      [
        "id -u app > /dev/null 2>&1 || sudo useradd --system --user-group --create-home --home-dir /home/app --shell /usr/sbin/nologin app",
        "sudo usermod -aG app deploy",
        "which setfacl",
        "sudo apt-get install -y acl",
        "sudo setfacl -m u:app:x /home/deploy",
        "chmod -R go+rX /home/deploy/.local/share/mise",
        "sudo mkdir -p #{DIRS} && sudo chown -R app:app #{DIRS} && sudo chmod 2770 #{DIRS}",
      ],
      commands,
    )
  end

  def test_always_skips_installed_acl
    commands = []
    Cmd.stubs(:ssh).with { |command, *| commands << command; true }.returns("/usr/bin/setfacl")

    AppUserPatch.always

    refute_includes commands, "sudo apt-get install -y acl"
    refute commands.any? { |command| command.include?("sudoers") || command.include?("NOPASSWD") }
  end
end
