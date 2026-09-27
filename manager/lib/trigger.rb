class Trigger
  READY = "ready"
  WORKING = "working"
  INTERACTIVE = "interactive"
  APPROVED = "approved"
  COMPLETED = "completed"
  CANCELED = "canceled"

  class << self
    def call
      Linear.issues.group_by { |item| Linear.column(item) }.each do |column, items|
        case column
        when COMPLETED, CANCELED
          items.each { |item| cleanup_worktree(item) }
          next
        end

        item = items.find do |candidate|
          next false if Linear.tagged?(candidate, WORKING)
          next false if column == READY && Linear.tagged?(candidate, INTERACTIVE)

          true
        end
        next if item.blank?

        case column
        when READY
          Linear.move(item, WORKING)
          begin
            start_agent(item, work_prompt(item), directory: Worktree.open(item))
          rescue StandardError
            Linear.move(item, READY)
            raise
          end
          puts "started working on #{Linear.identifier(item)}"
        when APPROVED
          start_agent(item, merge_prompt(item), directory: Worktree.directory(item))
          puts "merging #{Linear.identifier(item)}"
        end
      end
    end

    private

    def cleanup_worktree(item)
      return unless Worktree.remove(item)

      puts "removed worktree for #{Linear.identifier(item)}"
    end

    def start_agent(item, prompt, directory:)
      Linear.tag(item, WORKING)
      begin
        Agent.start(
          prompt,
          directory:,
          model: Linear.model(item),
          variant: Linear.variant(item),
        )
      rescue StandardError
        Linear.untag(item, WORKING)
        raise
      end
    end

    def work_prompt(item)
      <<~PROMPT
        Do this Linear issue: #{Linear.url(item)}

        The manager runs this card. Do not use the `interactive-card` skill.

        This may be a new card or a kickback with corrections in later comments. There may already be a worktree, commits, and a PR.

        1. This session is already in the card worktree. Env files and schema.rb were copied from the main checkout.
        2. Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits.
        3. Read the card and all comments. If the card names a skill, follow it; where the skill says how to finish the card, do that instead of steps 5 and 6, then remove the working tag.
        4. Implement the work. You may edit existing commits or add new ones.
        5. If you finish:
           - Commit
           - Open a GitHub PR with `gh pr create` using `GITHUB_TOKEN`
           - Link the PR to the card
           - Comment on the card describing what you did
           - Remove the working tag
           - Move the card to review
        6. If the card is blocked or the change is not possible:
           - Comment on the card explaining why
           - Remove the working tag
           - Move the card to planned
      PROMPT
    end

    def merge_prompt(item)
      <<~PROMPT
        This Linear issue is approved: #{Linear.url(item)}

        The manager runs this card. Do not use the `interactive-card` skill.

        1. Rebase the GitHub PR on the card. Resolve merge conflicts.
        2. Merge the PR with `gh pr merge` using `GITHUB_TOKEN`.
        3. If this session is in the main checkout rather than a worktree, run `git checkout master` and `git pull --ff-only origin master`.
        4. Move the card to completed.
        5. Remove the working tag.
      PROMPT
    end
  end
end
