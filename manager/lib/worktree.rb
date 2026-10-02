require "fileutils"
require "open3"

class Worktree
  SCHEMA = "backend/db/schema.rb"

  class << self
    def reset
      @root = nil
      @keychain = nil
    end

    def root
      @root || Agent::ROOT
    end

    def root=(value)
      @root = value
    end

    def keychain
      @keychain ||= Keychain.new
    end

    def keychain=(value)
      @keychain = value
    end

    def open(item)
      path = existing(item) || add(item)
      copy_files(path) unless path == root
      path
    end

    def directory(item)
      existing(item) || root
    end

    def remove(item)
      path = path_for(item)
      return false unless Dir.exist?(path)

      keychain.release(path)
      run("git", "worktree", "remove", "--force", path)
      true
    end

    def pull_master
      branch = run("git", "branch", "--show-current").strip
      return if branch != "master" && branch != "main"
      return if run("git", "status", "--porcelain").present?

      run("git", "pull", "--ff-only", "origin", branch)
      branch
    end

    def path_for(item)
      File.expand_path("../#{File.basename(root)}-#{branch_for(item)}", root)
    end

    private

    def existing(item)
      path = path_for(item)
      return path if Dir.exist?(path)

      find(item)
    end

    def find(item)
      branch = branch_for(item)
      listed = worktrees
      upstreams = run(
        "git",
        "for-each-ref",
        "--format=%(refname:short) %(upstream:short)",
        "refs/heads",
      ).lines.to_h { |line| line.split.values_at(0, 1) }
      found = listed.find do |worktree|
        worktree[:branch] == branch || upstreams[worktree[:branch]] == "origin/#{branch}"
      end
      found&.fetch(:path)
    end

    def worktrees
      run("git", "worktree", "list", "--porcelain").split("\n\n").map do |block|
        lines = block.lines.map(&:strip)
        path = lines.find { |line| line.start_with?("worktree ") }&.delete_prefix("worktree ")
        branch = lines.find { |line| line.start_with?("branch ") }&.delete_prefix("branch refs/heads/")
        { path:, branch: }
      end
    end

    def add(item)
      path = path_for(item)
      run("git", "fetch", "origin")
      branch = branch_for(item)
      listed = refs
      if listed.match?(%r{ refs/heads/#{Regexp.escape(branch)}$})
        run("git", "worktree", "add", path, branch)
      elsif listed.match?(%r{ refs/remotes/origin/#{Regexp.escape(branch)}$})
        run("git", "worktree", "add", "-b", branch, path, "origin/#{branch}")
      else
        run("git", "worktree", "add", "-b", branch, path, "origin/master")
      end
      path
    end

    def copy_files(path)
      env_files.each { |name| copy_file(name, path) }
      copy_file(SCHEMA, path)
    end

    def env_files
      Dir.children(root).select do |name|
        (name == ".env" || name.start_with?(".env.")) && name != ".env.default"
      end
    end

    def copy_file(relative, path)
      source = File.join(root, relative)
      return unless File.file?(source)

      destination = File.join(path, relative)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(source, destination)
    end

    def branch_for(item)
      Linear.identifier(item).downcase
    end

    def refs
      stdout, _stderr, status = Open3.capture3("git", "show-ref", chdir: root)
      status.success? ? stdout : ""
    end

    def run(*command)
      stdout, stderr, status = Open3.capture3(*command, chdir: root)
      message = stderr.strip
      message = stdout.strip if message.blank?
      raise "#{command.join(" ")} failed: #{message}" unless status.success?

      stdout
    end
  end
end
