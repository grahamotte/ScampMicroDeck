---
name: interactive-card
description: Work a Linear card interactively with the user and manage its lifecycle and any PRs for repository changes. Use when the user hands you a Linear card URL or identifier to work on, or asks to use the interactive-card skill by name. Do not use when the prompt says the manager runs the card.
---

# Interactive Card

The manager does not drive this card. You manage the card and any PRs for repository changes while working with the user. Use the `mise linear` commands described in `AGENTS.md`. Reuse this card for the whole task, including its individual operations and steps.

The card branch is the lowercased card identifier, for example `moto-1` for `MOTO-1`.

## Start

1. Read the card with `mise linear issues read <card> --with-comment-threads --with-attachments`.
2. Tag the card `runner: interactive`. The manager does not pick up `runner: interactive` cards from `ready`.
3. Move the card to `working`.
4. When tracked repository files need changes, set up the checkout:
   - In a worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`), stay on its current branch. Copy the env files and `backend/db/schema.rb` from the main checkout if they are missing.
   - In the main checkout, run `git fetch origin`. Check out the card branch if it exists; otherwise create it from `origin/master`. Never commit to `master`.
5. Work through the card with the user. For code changes, lint, type-check, and run `mise test`. For operations, verify the result and record progress on this card. Operations without tracked repository changes need no branch, empty commit, or PR.

If the card names a skill that finishes the card itself, such as `deploy`, `merge`, or `publish`, follow that skill instead of Review and Approve. When the operation is one step of a larger task, record its result and keep the tracking card open until the whole task is done.

## Review

For tracked repository changes, when the work is done or the user asks for review:

1. Commit.
2. Push to the card branch on origin with `git push -u origin HEAD:<card branch>`. The manager finds the card's worktree through this branch.
3. Open a GitHub PR with `gh pr create --head <card branch>` using `GITHUB_TOKEN`, unless the card already has an open PR for these changes. Create a new PR on the same card when a prior PR has finished and further repository changes are needed.
4. Link the PR to the card.
5. Comment on the card describing what you did.
6. Move the card to `review` when the whole task is ready for review. Keep a larger tracking card in `working` while other steps remain.

For later changes to an open PR, push to the same PR and comment on the card with what changed. Keep the card in `working` while other steps remain, or in `review` when the whole task is ready for review.

For operations without tracked repository changes, record the result on the existing card. Complete it when the whole task is done; otherwise keep it in `working`. When blocked, record the blocker and move it to `planned`.

## Approve

Move the card to `approved` only when the whole task is ready to finish. For cards with a PR, if the user moves the card to `approved` in Linear, the manager merges it and completes the card. Do nothing. For operations without a PR, complete the card directly when the whole task is done.

If the user tells you a PR is approved:

1. Rebase the PR onto `origin/master`. Resolve merge conflicts and push with `--force-with-lease`.
2. Merge the PR with `gh pr merge` using `GITHUB_TOKEN`.
3. If the main checkout is on master or main and has no uncommitted changes, run `git pull --ff-only` there. Do not switch branches.
4. Move the card to `completed` when the whole task is done. If other steps remain, keep the tracking card in `working` and record what remains.
