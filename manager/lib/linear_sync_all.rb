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
      $stdout.puts "Syncing #{directory}"
      $stdout.flush
      output = +""
      Open3.popen2e("mise", "manager:linear_sync", chdir: directory) do |stdin, stream, wait|
        stdin.close
        stream.each_line do |line|
          output << line
          $stdout.print(line)
          $stdout.flush
        end
        return if wait.value.success?
      end

      raise "mise manager:linear_sync failed in #{directory}: #{output.strip}"
    end
  end
end
