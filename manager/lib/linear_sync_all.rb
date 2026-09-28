require "open3"

class LinearSyncAll
  TASK = '[tasks."manager:linear_sync"]'

  class << self
    def call
      directories.each { |directory| sync(directory) }
    end

    def directories
      Dir.children(parent).sort.filter_map do |name|
        path = File.join(parent, name)
        path if syncable?(path)
      end
    end

    private

    def parent
      File.expand_path("..", Worktree.root)
    end

    def syncable?(path)
      File.directory?(path) &&
        File.directory?(File.join(path, ".git")) &&
        File.file?(toml(path)) &&
        File.read(toml(path)).include?(TASK)
    end

    def toml(path)
      File.join(path, "mise.toml")
    end

    def sync(directory)
      stdout, stderr, status = Open3.capture3("mise", "manager:linear_sync", chdir: directory)
      $stdout.print(stdout)
      $stderr.print(stderr) if stderr.present?
      return if status.success?

      message = stderr.strip
      message = stdout.strip if message.blank?
      raise "mise manager:linear_sync failed in #{directory}: #{message}"
    end
  end
end
