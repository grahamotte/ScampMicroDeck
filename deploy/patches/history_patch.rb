class HistoryPatch < BasePatch
  JOURNAL_MAX_USE = "4G"
  SYSSTAT_HISTORY_DAYS = 28
  TIMER_PATH = "/etc/systemd/system/sysstat-collect.timer.d/every-minute.conf"
  JOURNALD_PATH = "/etc/systemd/journald.conf.d/history.conf"

  class << self
    def always
      Instance.install_package("sysstat", bin: "sar")
      Cmd.ssh("sudo sed -i -E 's/^ENABLED=.*/ENABLED=\"true\"/' /etc/default/sysstat")
      Cmd.ssh(
        "sudo sed -i -E 's/^HISTORY=.*/HISTORY=#{SYSSTAT_HISTORY_DAYS}/; " \
        "s/^COMPRESSAFTER=.*/COMPRESSAFTER=#{SYSSTAT_HISTORY_DAYS + 3}/' /etc/sysstat/sysstat",
      )
      Cmd.ssh("sudo mkdir -p #{File.dirname(TIMER_PATH)} #{File.dirname(JOURNALD_PATH)}")
      timer_changed = write(TIMER_PATH, timer)
      journald_changed = write(JOURNALD_PATH, journald)
      Cmd.ssh("sudo systemctl daemon-reload")
      Cmd.ssh("sudo systemctl enable --now sysstat.service sysstat-collect.timer")
      Cmd.ssh("sudo systemctl restart sysstat-collect.timer") if timer_changed
      Cmd.ssh("sudo systemctl restart systemd-journald") if journald_changed
      Cmd.ssh("sudo usermod -aG systemd-journal,adm #{Constants.deploy_user}")
    end

    def needed?
      Cmd.ssh("dpkg-query -W -f='${Status}' do-agent 2>/dev/null || true").include?("install ok installed")
    end

    def apply
      Cmd.ssh("sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y do-agent")
      Cmd.ssh("sudo rm -f /etc/apt/sources.list.d/digitalocean-agent.list /usr/share/keyrings/digitalocean-agent-keyring.gpg")
    end

    private

    def write(path, content)
      return false if Cache.unchanged?(path, content)

      Cmd.ssh_write(path, content, sudo: true)
      true
    end

    def timer = <<~TEXT
      [Timer]
      OnCalendar=
      OnCalendar=*:*:00
    TEXT

    def journald = <<~TEXT
      [Journal]
      Storage=persistent
      SystemMaxUse=#{JOURNAL_MAX_USE}
    TEXT
  end
end
