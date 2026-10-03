class Trigger
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
          { state: { name: { in: Linear.state_names(WORKING, APPROVED) } } },
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
          next false if column == WORKING && Linear.interactive?(candidate)

          true
        end
        next if item.blank?

        case column
        when WORKING
          start_agent(item, work_prompt(item))
          puts "started working on #{Linear.identifier(item)}"
        when APPROVED
          start_agent(item, approved_prompt(item))
          puts "started approved work on #{Linear.identifier(item)}"
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

    def start_agent(item, prompt)
      Linear.tag(item, WORKING)
      begin
        directory = Worktree.open(item)
        selections = {
          runner: Linear.runner(item),
          model: Linear.model(item),
          variant: Linear.variant(item),
        }
        interactive = selections[:runner].to_s.casecmp?(INTERACTIVE)
        selections[:runner] = nil if interactive
        defaults = AgentSelection.resolve(**selections)
        selections[:runner] = defaults[:runner] if interactive
        selections.each do |key, value|
          next if value.present?

          default = defaults[key]
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
      handoff = if Linear.tagged?(item, "skip review")
        <<~PROMPT
          - Completed: this card has the `skip review` tag, so it never goes to Review. For tracked repository changes, commit, push the card branch, create or update the card's PR, and link it to the card. Resolve conflicts and required checks, merge it and update the main checkout as described under GitHub in `AGENTS.md`, and verify it merged. Then do the remaining work, and complete the card only when its whole task is done.
        PROMPT
      else
        <<~PROMPT
          - Review: tracked repository changes are ready to merge. Commit, push the card branch, create or update the card's PR, and link it to the card. Do not do work that depends on the merge, such as deploying; the handoff comment lists it for the Approved agent.
          - Completed: the whole task is done and nothing awaits review or merge.
        PROMPT
      end

      <<~PROMPT
        Work this Linear card: #{Linear.url(item)}

        The manager runs this card in a new agent session. Do not use the `interactive-card` skill. Follow the card workflow in `AGENTS.md`. This session is in the card worktree, with env files and schema.rb copied from the main checkout. The card may be new or returned from Review with corrections in later comments, so a branch, commits, and a PR may already exist.

        1. Read the card and all comments. If the card names a skill, follow it.
        2. Rebase onto the current origin main, or merge it instead if the branch has merge commits. Do not hard-reset; keep existing commits.
        3. Do the work. You may edit existing commits or add new ones.
        4. Comment on the card with a brief summary of what changed and a short pseudocode block of how it works. A separate Approved agent with no memory of this session finishes the card after review, so before handing off to Review, make this comment its handoff: the PR to merge, remaining work after the merge in order (naming skills such as `deploy`), relevant inputs and constraints, work already done, and verification required before completion. Write "Remaining work: none" when nothing remains after the merge.
        5. Hand off with exactly one outcome, then remove the `working` tag:
        #{handoff.lines.map { |line| "   #{line}" }.join.rstrip}
           - Planned: a blocker requires the user to re-evaluate the card. Comment explaining it.
      PROMPT
    end

    def approved_prompt(item)
      <<~PROMPT
        This Linear card is approved: #{Linear.url(item)}

        The manager runs this card in a new agent session with no memory of earlier sessions. Do not use the `interactive-card` skill. Follow the card workflow in `AGENTS.md`. This session is in the card worktree, with env files and schema.rb copied from the main checkout. Approval authorizes you to merge the reviewed PR and finish the card's remaining work.

        1. Read the card and all comments, including the latest handoff comment. It names the PR to merge, the remaining work in order, and the verification required before completion.
        2. If the PR to merge is unclear, do not merge. Otherwise, unless it is already merged, rebase it onto the current origin main (or merge origin main if the branch has merge commits), resolve conflicts, push with `--force-with-lease`, wait for required checks, and merge it with `gh pr merge`.
        3. If the main checkout is on master or main and has no uncommitted changes, run `git pull --ff-only` there. Do not switch branches.
        4. Do the remaining work from the handoff in order, following any named skills, and record each result on the card. A missing or ambiguous handoff does not mean nothing remains.
        5. Hand off with exactly one outcome, then remove the `working` tag:
           - Completed: all remaining work is done and verified.
           - Review: new tracked repository changes need review. Create and link a new PR and comment a new handoff.
           - Planned: a blocker, or a missing or ambiguous handoff, requires the user to re-evaluate the card. Comment explaining it.
      PROMPT
    end
  end
end
