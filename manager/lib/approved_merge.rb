require "open3"

class ApprovedMerge
  class << self
    def call(item)
      issue = JSON.parse(run("mise", "linear", "issues", "read", Linear.identifier(item), "--with-attachments"), symbolize_names: true)
      repository = Settings.all.fetch(:githubRepo).delete_prefix("git@github.com:").delete_suffix(".git")
      urls = issue.fetch(:attachments).fetch(:nodes).filter_map do |attachment|
        url = attachment[:url].to_s
        url if url.match?(%r{\Ahttps://github\.com/#{Regexp.escape(repository)}/pull/\d+\z}i)
      end.uniq
      return false unless urls.length == 1

      url = urls.first
      pr = view(url, repository)
      return false unless [ "master", "main" ].include?(pr[:baseRefName])
      return true if pr[:state] == "MERGED"
      return false unless pr[:state] == "OPEN" && pr[:mergeable] == "MERGEABLE" && pr[:mergeStateStatus] == "CLEAN"

      run("gh", "pr", "merge", url, "--repo", repository, "--merge", "--match-head-commit", pr.fetch(:headRefOid))
      view(url, repository)[:state] == "MERGED"
    end

    private

    def view(url, repository)
      JSON.parse(
        run("gh", "pr", "view", url, "--repo", repository, "--json", "state,baseRefName,headRefOid,mergeable,mergeStateStatus"),
        symbolize_names: true,
      )
    end

    def run(*command)
      stdout, stderr, status = Open3.capture3(*command, chdir: Worktree.root)
      message = stderr.strip
      message = stdout.strip if message.blank?
      raise "#{command.join(" ")} failed: #{message}" unless status.success?

      stdout
    end
  end
end
