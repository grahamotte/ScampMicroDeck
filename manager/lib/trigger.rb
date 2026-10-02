class Trigger
  READY = "ready"
  WORKING = "working"
  INTERACTIVE = "interactive"
  APPROVED = "approved"
  COMPLETED = "completed"
  CANCELED = "canceled"

  class << self
    def call
      check_keychain
      filter = {
        or: [
          { state: { name: { in: Linear.state_names(READY, APPROVED) } } },
          {
            and: [
              { state: { name: { in: Linear.state_names(COMPLETED, CANCELED) } } },
              { updatedAt: { gte: "-P30D" } },
            ],
          },
        ],
      }
      Linear.issues(filter:).group_by { |item| Linear.column(item) }.each do |column, items|
        case column
        when COMPLETED, CANCELED
          cleaned = items.select { |item| cleanup_worktree(item) }
          pull_master if column == COMPLETED && cleaned.present?
          next
        end

        item = items.find do |candidate|
          next false if Linear.tagged?(candidate, WORKING)
          next false if column == READY && (Linear.tagged?(candidate, "runner: #{INTERACTIVE}") || Linear.tagged?(candidate, INTERACTIVE))

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
          Linear.tag(item, WORKING)
          next if merge_approved(item)

          start_agent(item, merge_prompt(item), tagged: true)
          puts "merging #{Linear.identifier(item)}"
        end
      end
    end

    private

    def check_keychain
      keychain = Worktree.keychain
      keychain.recover.each { |file| puts "restored keychains from #{file}" }
      keychain.release.each { |path| puts "removed missing keychain #{path}" }
      problems = keychain.problems
      return if problems.blank?

      puts "WARNING: the host keychain configuration needs attention"
      problems.each { |problem| puts "- #{problem}" }
      puts "Run `mise manager:keychain` to restore the login keychain."
    rescue StandardError => error
      puts "keychain check failed: #{error.message}"
    end

    def cleanup_worktree(item)
      return false unless Worktree.remove(item)

      puts "removed worktree for #{Linear.identifier(item)}"
      true
    end

    def pull_master
      branch = Worktree.pull_master
      puts "updated #{branch}" if branch.present?
    rescue StandardError => error
      puts "failed to update master: #{error.message}"
    end

    def merge_approved(item)
      return false unless ApprovedMerge.call(item)

      branch = Worktree.pull_master
      puts "updated #{branch}" if branch.present?
      Linear.move(item, COMPLETED)
      Linear.untag(item, WORKING)
      puts "merged #{Linear.identifier(item)}"
      true
    rescue StandardError => error
      puts "automatic merge failed for #{Linear.identifier(item)}: #{error.message}"
      false
    end

    def start_agent(item, prompt, directory: nil, tagged: false)
      Linear.tag(item, WORKING) unless tagged
      begin
        directory ||= Worktree.directory(item)
        selections = {
          runner: Linear.runner(item),
          model: Linear.model(item),
          variant: Linear.variant(item),
        }
        selections[:runner] = Settings.all.dig(:agent, :runner) if selections[:runner].to_s.casecmp?(INTERACTIVE)
        selections.each do |key, value|
          next if value.present?

          default = Settings.all.dig(:agent, key)
          next if default.blank?

          Linear.tag(item, "#{key}: #{default}")
          selections[key] = default
        end
        Agent.start(
          prompt,
          directory:,
          **selections,
        )
      rescue StandardError
        Linear.untag(item, WORKING)
        raise
      end
    end

    def work_prompt(item)
      completion = if Linear.tagged?(item, "skip review")
        <<~PROMPT
          - This card has the `skip review` tag. If there are tracked repository changes, merge the linked PR immediately with `gh pr merge` using `GITHUB_TOKEN`, resolving conflicts and passing required checks first. Verify that the PR is merged before completing the card or removing its worktree. If the merge is blocked, follow step 6. Operations without tracked repository changes complete without a PR when the whole task is done.
          - If the main checkout is on master or main and has no uncommitted changes, run `git pull --ff-only` there. Do not switch branches.
          - Move the card to completed only when the whole task is done; otherwise keep it in working and record the remaining steps
          - Remove the working tag
          - Only when the whole task is done, from the main checkout, remove only this card's worktree with `git worktree remove`. Do this last, after all card updates and repository work are finished. Do not remove the main checkout.
        PROMPT
      else
        <<~PROMPT
          - Remove the working tag
          - Move the card to review if there are tracked repository changes awaiting review and the whole task is ready; otherwise move it to completed only when the whole task is done. If other steps remain, keep it in working and record them.
        PROMPT
      end

      <<~PROMPT
        Do this Linear issue: #{Linear.url(item)}

        The manager runs this card. Do not use the `interactive-card` skill.

        Do not assign users to cards when creating or working on them. Leave existing assignees unchanged.

        This may be a new card or a kickback with corrections in later comments. There may already be a worktree, commits, and a PR.

        1. This session is already in the card worktree. Env files and schema.rb were copied from the main checkout.
        2. Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits.
        3. Read the card and all comments. If the card names a skill, follow it; where the skill says how to finish the card, do that instead of steps 5 and 6, then remove the working tag. Step 7 still applies.
           Every task, including operations, needs a Linear card. Reuse this tracking card for the whole task and record individual operations and steps here; do not create a new card for each step. Completing one operation or PR does not complete a larger task. A GitHub PR is required only for code changes or other changes to tracked repository files. Operations without tracked repository changes need no PR, empty commit, or branch. Do not require GitHub PR access for such operations.
        4. Implement the work. You may edit existing commits or add new ones.
        5. If you finish:
           - If there are tracked repository changes, commit them, push the branch, and create or update the card's PR:
             - Open a GitHub PR with `gh pr create` using `GITHUB_TOKEN` if the card has no open PR for these changes; reuse an open PR or create a new one on this card after a prior PR has finished
             - Link the PR to the card
           - Comment on the card with a brief summary of what changed and a short fenced pseudocode block showing how the change works at a high level. Use readable, imperfect Ruby in a fenced `ruby` block; the pseudocode does not need to run. Use named components and indentation to show the flow of inputs, key decisions, and results. Keep it structural and concise; do not explain the flow in paragraphs or include low-level implementation details.
        #{completion.lines.map { |line| "   #{line}" }.join.rstrip}
        6. If the card is blocked or the change is not possible:
           - Comment on the card explaining why
           - Remove the working tag
           - Move the card to planned
        7. If you spent significant time unnecessarily or the instructions misdirected you, and the issue could be backported to Code Moto (`codemoto.org` / MOTO), search the MOTO backlog for a matching card first. If one exists, comment with a brief summary of your experience. Otherwise create a MOTO backlog card. Do not file app-specific issues.
      PROMPT
    end

    def merge_prompt(item)
      <<~PROMPT
        This Linear issue is approved: #{Linear.url(item)}

        The manager runs this card. Do not use the `interactive-card` skill.

        Approval of this card means its whole task is ready to finish. Read the card and all comments before merging. If they show remaining steps beyond the PR, record them and keep the card in working after the merge; do not complete it.

        Do not assign users to cards when creating or working on them. Leave existing assignees unchanged.

        1. Rebase the GitHub PR on the card. Resolve merge conflicts.
        2. Merge the PR with `gh pr merge` using `GITHUB_TOKEN`.
        3. If the main checkout is on master or main and has no uncommitted changes, run `git pull --ff-only` there. Do not switch branches.
        4. Move the card to completed. Do this only when the whole task is done; otherwise keep it in working and record the remaining steps.
        5. Remove the working tag.
      PROMPT
    end
  end
end
