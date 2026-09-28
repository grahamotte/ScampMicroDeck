class Cmd
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

    private

    def command_succeeded?
      Process.last_status.blank? || Process.last_status.success?
    end
  end
end
