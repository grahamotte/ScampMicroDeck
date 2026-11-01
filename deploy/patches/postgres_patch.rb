class PostgresPatch < BasePatch
  class << self
    def needed?
      return true if Instance.not_installed?("psql")
      return true if !user_exists?
      return true if !db_exists?
      return true if !journal_conf_current?

      false
    end

    def apply
      if Instance.not_installed?("psql")
        # https://gist.github.com/ammarshah/40535b7e6c76597bda58afece875b7e6
        Cmd.ssh("sudo apt install curl ca-certificates")
        Cmd.ssh("sudo install -d /usr/share/postgresql-common/pgdg")
        Cmd.ssh(
          "sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc"
        )
        Cmd.ssh(
          "sudo sh -c 'echo \"deb [arch=amd64 signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main\" > /etc/apt/sources.list.d/pgdg.list'"
        )
        Cmd.ssh("sudo DEBIAN_FRONTEND=noninteractive apt update")
        Cmd.ssh("sudo DEBIAN_FRONTEND=noninteractive apt-get -y install postgresql-18 libpq-dev")
        Instance.start_service("postgresql")
      end

      Cmd.ssh_write(pg_hba_conf_path, pg_hba_conf, sudo: true)
      Cmd.ssh_write(journal_conf_path, journal_conf, sudo: true)

      Cmd.ssh("sudo -u postgres createuser -s #{Constants.deploy_user}") unless user_exists?

      Cmd.ssh("sudo -u postgres createdb #{Constants.db_name}") unless db_exists?

      Instance.restart_service("postgresql")
    end

    private

    def pg_hba_conf_path = "/etc/postgresql/18/main/pg_hba.conf"

    def pg_hba_conf = <<~TEXT
      local   all             postgres                                peer
      local   all             all                                     peer
      host    all             all             127.0.0.1/32            trust
      host    all             all             ::1/128                 trust
      local   replication     all                                     trust
      host    replication     all             127.0.0.1/32            trust
      host    replication     all             ::1/128                 trust
    TEXT

    def journal_conf_path = "/etc/postgresql/18/main/conf.d/journal.conf"

    def journal_conf = <<~TEXT
      log_destination = 'syslog'
      syslog_ident = 'postgres'
    TEXT

    def journal_conf_current?
      Cmd.ssh("sudo cat #{journal_conf_path} 2>/dev/null || true") == journal_conf
    end

    def user_exists?
      Cmd
        .ssh("sudo -u postgres psql -c \"SELECT 'asstits' FROM pg_roles WHERE rolname = '#{Constants.deploy_user}'\"")
        .include?("asstits")
    rescue StandardError => e
      puts e.message
      false
    end

    def db_exists?
      Cmd
        .ssh("sudo -u postgres psql -l | grep #{Constants.db_name}")
        .include?("#{Constants.db_name}")
    rescue StandardError => e
      puts e.message
      false
    end
  end
end
