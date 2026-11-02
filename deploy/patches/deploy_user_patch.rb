class DeployUserPatch < BasePatch
  class << self
    def needed?
      Cmd.ssh("echo !ass!tits!")
      false
    rescue StandardError
      true
    end

    def apply
      user = Constants.deploy_user
      pass = Constants.deploy_password

      # sudo user
      Cmd.ssh("useradd #{user} -m", user: "root")
      Cmd.ssh("chsh -s /bin/bash #{user}", user: "root")
      Cmd.ssh("chpasswd", user: "root", stdin: "#{user}:#{pass}\n")
      Cmd.ssh("echo '#{user} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers", user: "root")

      # keyfile
      Cmd.ssh("cp -r ~/.ssh /home/#{user}/", user: "root")
      Cmd.ssh_write("/home/#{user}/.ssh/id_rsa", Constants.ssh_key, user: "root")
      Cmd.ssh("chmod 400 /home/#{user}/.ssh/id_rsa", user: "root")
      Cmd.ssh_write("/home/#{user}/.ssh/id_rsa.pub", Constants.ssh_key_pub, user: "root")
      Cmd.ssh("chmod 400 /home/#{user}/.ssh/id_rsa.pub", user: "root")
      Cmd.ssh("chown -R #{user}:#{user} /home/#{user}/", user: "root")
      Cmd.ssh("sed -i -e '$a\\' /home/#{user}/.ssh/authorized_keys", user: "root")

      # lockout root user
      Cmd.ssh_write("/etc/ssh/sshd_config", sshd_conf, user: "root")
      Cmd.ssh("systemctl restart ssh", user: "root")
    end

    private

    def sshd_conf
      <<~TEXT
        PermitRootLogin no
        AuthorizedKeysFile .ssh/authorized_keys
        PasswordAuthentication no
        ChallengeResponseAuthentication no
        UsePAM yes
        PrintMotd no
        Subsystem sftp internal-sftp
        TCPKeepAlive yes
        ClientAliveInterval 30
        MaxAuthTries 30
      TEXT
    end
  end
end
