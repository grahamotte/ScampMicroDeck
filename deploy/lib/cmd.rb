class Cmd
  class SshError < RuntimeError
    attr_reader :output

    def initialize(message, output:)
      @output = output
      super(message)
    end
  end

  class << self
    def local(command, *opts)
      command = command.split("?").zip(opts.map { |x| Shellwords.escape(x) }).flatten.join if opts.present?
      command = command.gsub("\\*", "*")

      puts "CMD #{command}".green

      res = `#{command}`
      puts res
      raise "Command failed: #{command}" unless command_succeeded?

      res
    end

    def ssh(command, *opts, user: Constants.deploy_user, quiet: false)
      command = command.split("?").zip(opts.map { |x| Shellwords.escape(x) }).flatten.join if opts.present?
      command = command.gsub("\\*", "*")

      puts "SSH #{command}".green unless quiet

      text = +""
      code = 0

      Net::SSH.start(Instance.ip, user, keys: [ Constants.ssh_key_path ], keys_only: true) do |s|
        s.open_channel do |channel|
          channel.exec(command) do
            channel.on_data { |_, x| print(x) unless quiet; text += x }
            channel.on_extended_data { |_, _, x| print(x) unless quiet; text += x }
            channel.on_request("exit-status") { |_, x| code = x.read_long }
          end
        end
        s.loop
      end

      text = text.force_encoding(Encoding::UTF_8)
      raise SshError.new("SSH command failed: #{command}", output: text) if code != 0

      text
    end

    def ssh_write(path, content, user: Constants.deploy_user, sudo: false)
      if Cache.unchanged?(path, content)
        puts "SSH skip write #{path} because it hasn't changed"
        return
      end

      tmp_remote_path = "#{user == 'root' ? '/root' : "/home/#{user}"}/#{SecureRandom.hex(16)}"
      tmp_local_path = "/tmp/#{SecureRandom.hex(16)}"
      File.write(tmp_local_path, content)
      bash = sudo && user != "root" ? "sudo bash" : "bash"
      local("rsync -av -e \"ssh -i ?\" ? #{user}@#{Instance.ip}:?", Constants.ssh_key_path, tmp_local_path, tmp_remote_path, user:)
      ssh("#{bash} -c 'cat ? > ?'", tmp_remote_path, path, user:)
      ssh("rm #{tmp_remote_path}", user:)
      Cache.set(path, content)
    end

    private

    def command_succeeded?
      Process.last_status.blank? || Process.last_status.success?
    end
  end
end
