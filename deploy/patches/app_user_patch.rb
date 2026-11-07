class AppUserPatch < BasePatch
  class << self
    def always
      user = Constants.app_user
      dirs = Constants.app_writable_dirs.join(" ")

      Cmd.ssh("id -u #{user} > /dev/null 2>&1 || sudo useradd --system --user-group --create-home --home-dir #{Constants.app_home_dir} --shell /usr/sbin/nologin #{user}")
      Cmd.ssh("sudo usermod -aG #{user} #{Constants.deploy_user}")
      Instance.install_package("acl", bin: "setfacl")
      Cmd.ssh("sudo setfacl -m u:#{user}:x #{Constants.remote_home_dir}")
      Cmd.ssh("chmod -R go+rX #{Constants.remote_mise_data_dir}")
      Cmd.ssh("sudo mkdir -p #{dirs} && sudo chown -R #{user}:#{user} #{dirs} && sudo chmod 2770 #{dirs}")
    end
  end
end
