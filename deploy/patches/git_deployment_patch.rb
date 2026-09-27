class GitDeploymentPatch < BasePatch
  class << self
    def always
      unless remote_git_exists?
        Cmd.local("ssh-keygen -R #{Instance.ip}")
        Cmd.local("ssh-keyscan -H #{Instance.ip} >> ~/.ssh/known_hosts")

        Cmd.local("rm -rf #{Constants.local_git_dir}")
        Cmd.ssh("rm -rf #{Constants.remote_git_dir}")

        Cmd.local("git clone --bare #{Constants.local_root} #{Constants.local_git_dir}")
        Cmd.local("rsync -av -e \"ssh -i #{Constants.ssh_key_path}\" #{Constants.local_git_dir}/ #{Constants.deploy_user}@#{Instance.ip}:#{Constants.remote_git_dir}/")

        Cmd.local("rm -rf #{Constants.local_git_dir}")
      end

      begin
        Cmd.local("GIT_SSH_COMMAND=\"ssh -i #{Constants.ssh_key_path}\" git remote remove deployment")
      rescue StandardError
      end
      Cmd.local("GIT_SSH_COMMAND=\"ssh -i #{Constants.ssh_key_path}\" git remote add deployment #{Constants.deploy_user}@#{Instance.ip}:#{Constants.remote_git_dir}")

      Cmd.local("git fetch origin master")
      sha = Cmd.local("git rev-parse origin/master").strip
      puts "deploying origin/master #{sha}"
      Cmd.local("GIT_SSH_COMMAND=\"ssh -i #{Constants.ssh_key_path}\" git push --force deployment #{sha}:refs/heads/master")

      Cmd.ssh("sudo mkdir -p #{Constants.remote_root}")
      Cmd.ssh("sudo chown -R #{Constants.deploy_user}:#{Constants.deploy_user} #{Constants.remote_root}")

      Cmd.ssh("git clone #{Constants.remote_git_dir} #{Constants.remote_root}") if !remote_root_exists?

      Cmd.ssh("cd #{Constants.remote_root} && git fetch")
      Cmd.ssh("cd #{Constants.remote_root} && git checkout -- .")
      Cmd.ssh("cd #{Constants.remote_root} && git reset --hard origin/master")
    end

    private

    def remote_git_exists?
      Cmd.ssh("[ -d #{Constants.remote_git_dir} ]")
    rescue StandardError => e
      puts e.message
      false
    end

    def remote_root_exists?
      Cmd.ssh("[ -d #{Constants.remote_root}/.git ]")
    rescue StandardError => e
      puts e.message
      false
    end
  end
end
