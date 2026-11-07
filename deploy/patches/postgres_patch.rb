class PostgresPatch < BasePatch
  class << self
    def needed?
      return true if Instance.not_installed?("psql")
      return true if !user_exists?(Constants.deploy_user)
      return true if !user_exists?(Constants.app_user)
      return true if !db_exists?
      return true if !db_owned_by_app?
      return true if !pg_hba_conf_current?
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

      Cmd.ssh("sudo -u postgres createuser -s #{Constants.deploy_user}") unless user_exists?(Constants.deploy_user)
      Cmd.ssh("sudo -u postgres createuser --no-superuser --no-createdb --no-createrole #{Constants.app_user}") unless user_exists?(Constants.app_user)

      Cmd.ssh("sudo -u postgres createdb -O #{Constants.app_user} #{Constants.db_name}") unless db_exists?

      unless db_owned_by_app?
        Cmd.ssh("sudo -u postgres psql -d #{Constants.db_name} -c \"ALTER DATABASE #{Constants.db_name} OWNER TO #{Constants.app_user}\"")
        Cmd.ssh("sudo -u postgres psql -d #{Constants.db_name} -c \"REASSIGN OWNED BY #{Constants.deploy_user} TO #{Constants.app_user}\"")
      end

      Instance.restart_service("postgresql")
    end

    private

    def pg_hba_conf_path = "/etc/postgresql/18/main/pg_hba.conf"

    def pg_hba_conf = <<~TEXT
      local   all             postgres                                peer
      local   all             all                                     peer
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256
      local   replication     all                                     peer
      host    replication     all             127.0.0.1/32            scram-sha-256
      host    replication     all             ::1/128                 scram-sha-256
    TEXT

    def journal_conf_path = "/etc/postgresql/18/main/conf.d/journal.conf"

    def journal_conf = <<~TEXT
      log_destination = 'syslog'
      syslog_ident = 'postgres'
    TEXT

    def pg_hba_conf_current?
      Cmd.ssh("sudo cat #{pg_hba_conf_path} 2>/dev/null || true") == pg_hba_conf
    end

    def journal_conf_current?
      Cmd.ssh("sudo cat #{journal_conf_path} 2>/dev/null || true") == journal_conf
    end

    def user_exists?(name)
      Cmd
        .ssh("sudo -u postgres psql -c \"SELECT 'asstits' FROM pg_roles WHERE rolname = '#{name}'\"")
        .include?("asstits")
    rescue StandardError => e
      puts e.message
      false
    end

    def db_owned_by_app?
      Cmd.ssh("sudo -u postgres psql -d #{Constants.db_name} -Atc \"#{db_owned_by_app_query}\"").strip == "t"
    rescue StandardError => e
      puts e.message
      false
    end

    def db_owned_by_app_query
      [
        "SELECT pg_get_userbyid(datdba) = '#{Constants.app_user}'",
        "AND NOT EXISTS (SELECT 1 FROM (#{owners_query}) AS objects WHERE pg_get_userbyid(owner) = '#{Constants.deploy_user}')",
        "FROM pg_database WHERE datname = current_database()",
      ].join(" ")
    end

    def owners_query
      [
        "SELECT relowner AS owner FROM pg_class",
        "SELECT proowner FROM pg_proc",
        "SELECT typowner FROM pg_type",
        "SELECT nspowner FROM pg_namespace",
      ].join(" UNION ALL ")
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
