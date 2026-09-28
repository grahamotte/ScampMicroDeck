---
name: interactive-card
description: Work a Linear card interactively with the user and manage its lifecycle and PR. Use when the user hands you a Linear card URL or identifier to work on, or asks to use the interactive-card skill by name. Do not use when the prompt says the manager runs the card.
---

# Interactive Card

The manager does not drive this card. You move the card and open the PR yourself while working with the user. Use the `mise linear` commands described in `AGENTS.md`.

The card branch is the lowercased card identifier, for example `moto-1` for `MOTO-1`.

## Start

1. Read the card with `mise linear issues read <card> --with-comment-threads --with-attachments`.
2. Tag the card `interactive`. The manager does not pick up `interactive` cards from `ready`.
3. Move the card to `working`.
4. Set up the checkout:
   - In a worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`), stay on its current branch. Copy the env files and `backend/db/schema.rb` from the main checkout if they are missing.
   - In the main checkout, run `git fetch origin`. Check out the card branch if it exists; otherwise create it from `origin/master`. Never commit to `master`.
5. Work through the card with the user. Lint, type-check, and run `mise test`.

If the card names a skill that finishes the card itself, such as `deploy`, `merge`, or `publish`, follow that skill instead of Review and Approve.

## Review

When the work is done or the user asks for review:

1. Commit.
2. Push to the card branch on origin with `git push -u origin HEAD:<card branch>`. The manager finds the card's worktree through this branch.
3. Open a GitHub PR with `gh pr create --head <card branch>` using `GITHUB_TOKEN`, unless the card already has one.
4. Link the PR to the card.
5. Comment on the card describing what you did.
6. Move the card to `review`.

For later changes, push to the same PR, comment on the card with what changed, and keep the card in `review`.

## Approve

If the user moves the card to `approved` in Linear, the manager merges it. Do nothing.

If the user tells you the card is approved:

1. Rebase the PR onto `origin/master`. Resolve merge conflicts and push with `--force-with-lease`.
2. Merge the PR with `gh pr merge` using `GITHUB_TOKEN`.
3. If the main checkout is on master or main and has no uncommitted changes, run `git pull --ff-only` there. Do not switch branches.
4. Move the card to `completed`.
