---
name: set-default-model-all
description: Set the default agent runner, model, and variant across Code Moto and its downstream repositories when requested by the user or a Linear card.
---

# Set Default Model All

Use one tracking card for the entire operation, including every repository and PR. Do not create downstream cards.

1. Read the requested runner, model, and variant from the card or user request. These are target defaults, independent of the labels selecting the agent working the card. If a value is missing or still a placeholder, ask for it before editing. An explicitly blank variant is valid. Check supported selections against `manager/lib/linear.rb` and the runner implementation; report an unsupported combination instead of substituting values.
2. Discover Code Moto and all downstream main checkouts using [repository discovery](../../../docs/manager.md#repository-discovery-for-all-repository-skills). Record the full inventory on the tracking card before making changes.
3. For each repository, fetch `origin`, determine whether its default branch is `master` or `main`, and inspect `config.json` on that remote branch. Change only `agent.runner`, `agent.model`, and `agent.variant`. Record repositories already matching the requested values without making empty PRs.
4. For each changed repository, create an isolated branch and worktree from the current remote default branch. Copy `.env.development`, `.env.production`, and `backend/db/schema.rb` from its main checkout before running root mise tasks. Preserve unrelated configuration and follow that repository's `AGENTS.md`.
5. Run the repository's required checks, including `mise test`, from the worktree root in a non-login shell. Commit, push, and create a PR with `gh pr create`, targeting that repository's origin. Link each PR to the shared tracking card and register it with the thread when that tool is available.
6. Merge each PR with `gh pr merge --merge`, confirm it is merged, and verify the three values on the remote default branch. Remove only worktrees and branches created for this operation after their changes are merged. Record the requested values, each repository's result, and all PR URLs on the card.

Complete the card directly without review only when its whole scope is done and every required PR is confirmed merged. If any repository or check is blocked, record completed work and the exact blocker, move the card to Planned, and retain unmerged work for resumption. Remove the working tag when running for the manager.
