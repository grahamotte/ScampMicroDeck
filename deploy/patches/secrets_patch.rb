class SecretsPatch < BasePatch
  class << self
    def always
      Cmd.ssh("umask 077 && touch ? && chmod 600 ?", Constants.remote_env_path, Constants.remote_env_path)
      Cmd.ssh_write(Constants.remote_env_path, Constants.server_env)
      Cmd.ssh(
        "rm -f ? ? ?",
        Constants.remote_env_prod_path,
        File.join(Constants.remote_home_dir, ".env"),
        File.join(Constants.remote_home_dir, ".ssh", "id_rsa"),
      )
    end
  end
end
