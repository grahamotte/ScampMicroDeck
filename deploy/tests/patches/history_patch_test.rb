require_relative "../test_helper"

class HistoryPatchTest < Minitest::Test
  DO_AGENT_CHECK = "dpkg-query -W -f='${Status}' do-agent 2>/dev/null || true"

  def test_always_configures_sysstat_and_journald
    commands = []
    writes = {}
    Cmd.stubs(:ssh).with do |command, *|
      commands << command
      command != "which sar"
    end.returns("")
    Cmd.expects(:ssh).with("which sar").returns("")
    Cmd.stubs(:ssh_write).with do |path, content, sudo:|
      writes[path] = content
      sudo
    end

    HistoryPatch.always

    assert_includes commands, "sudo apt-get install -y sysstat"
    assert_includes commands, "sudo sed -i -E 's/^ENABLED=.*/ENABLED=\"true\"/' /etc/default/sysstat"
    assert_includes commands, "sudo sed -i -E 's/^HISTORY=.*/HISTORY=28/; s/^COMPRESSAFTER=.*/COMPRESSAFTER=31/' /etc/sysstat/sysstat"
    assert_equal "[Timer]\nOnCalendar=\nOnCalendar=*:*:00\n", writes.fetch(HistoryPatch::TIMER_PATH)
    assert_equal "[Journal]\nStorage=persistent\nSystemMaxUse=4G\n", writes.fetch(HistoryPatch::JOURNALD_PATH)
    assert_includes commands, "sudo systemctl enable --now sysstat.service sysstat-collect.timer"
    assert_includes commands, "sudo systemctl restart sysstat-collect.timer"
    assert_includes commands, "sudo systemctl restart systemd-journald"
    assert_includes commands, "sudo usermod -aG systemd-journal,adm deploy"
  end

  def test_always_skips_restarts_when_unchanged
    commands = []
    Cache.set(HistoryPatch::TIMER_PATH, HistoryPatch.send(:timer))
    Cache.set(HistoryPatch::JOURNALD_PATH, HistoryPatch.send(:journald))
    Cmd.stubs(:ssh).with do |command, *|
      commands << command
      command != "which sar"
    end.returns("")
    Cmd.expects(:ssh).with("which sar").returns("/usr/bin/sar")
    Cmd.expects(:ssh_write).never

    HistoryPatch.always

    refute_includes commands, "sudo apt-get install -y sysstat"
    refute_includes commands, "sudo systemctl restart sysstat-collect.timer"
    refute_includes commands, "sudo systemctl restart systemd-journald"
    assert_includes commands, "sudo systemctl enable --now sysstat.service sysstat-collect.timer"
  end

  def test_needed
    Cmd.expects(:ssh).with(DO_AGENT_CHECK).returns("install ok installed")
    assert HistoryPatch.needed?

    Cmd.expects(:ssh).with(DO_AGENT_CHECK).returns("")
    refute HistoryPatch.needed?
  end

  def test_apply_removes_do_agent
    Cmd.expects(:ssh).with("sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y do-agent")
    Cmd.expects(:ssh).with("sudo rm -f /etc/apt/sources.list.d/digitalocean-agent.list /usr/share/keyrings/digitalocean-agent-keyring.gpg")

    HistoryPatch.apply
  end
end
