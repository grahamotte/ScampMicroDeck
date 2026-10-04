---
name: interactive-card
description: Work a Linear card interactively with the user and manage its lifecycle and any PRs for repository changes. Use when the user hands you a Linear card URL or identifier to work on, or asks to use the interactive-card skill by name. Do not use when the prompt says the manager runs the card.
---

# Interactive Card

You work this card with the user and manage it through the workflow in `AGENTS.md`. Mr. Moto supplies the same workflow in `../mr-moto/docs/workflow.md`; read it when available. All registered projects use the configured forge PR adapter. The card branch is the lowercased card identifier, for example `moto-1` for `MOTO-1`.

## Start

1. Read the card with `mise linear issues read <card> --with-comment-threads --with-attachments`.
2. Tag the card `runner: interactive` and move it to `🤖 Working` (Linearis needs the exact column name). Do not add the `working` tag; the manager starts no work agent for interactive cards.
3. When tracked repository files need changes, set up the checkout:
   - In a worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`), stay on its current branch. Copy the env files and `backend/db/schema.rb` from the main checkout if they are missing.
   - In the main checkout, fetch the configured Git remote. Check out the card branch if it exists; otherwise create it from the configured remote's actual default branch. Never commit to the default branch.
4. Work through the card with the user. If it names a skill, follow it. For code changes, lint, type-check, and run `mise test`. For operations, verify the result and record progress on the card.

## Review

When repository changes are ready to merge, or the user asks for review:

1. Commit and push with `git push -u <gitRemote> HEAD:<card branch>`. The manager finds the card's worktree through this branch.
2. Use `mise -C <mr-moto-checkout> pr <project> create <CARD> --title "<title>" --body-file <path>` to create or update the open card PR and link it to Linear.
3. Comment the handoff described in `AGENTS.md` and move the card to `review`. Do not do work that depends on the merge.

For later changes to an open PR, push to it and comment with what changed and an updated handoff.

## Finish

When the user moves the card to `approved`, the manager's Approved agent merges it and finishes the work in the handoff. Do nothing.

If the user approves the PR in this session instead, do that work yourself:

1. Inspect the handoff PR first. Unless already merged, reconcile with the configured remote's actual default branch, preserving merge commits with a merge instead of a rebase, run checks, and push with `--force-with-lease`.
2. Inspect the PR head SHA and checks after pushing, merge using `mise pr` with the explicit number and verified SHA, and safely update the main checkout as described under Pull Requests in `AGENTS.md`. Additional tracked changes after the merge need another linked PR and an updated handoff; skip-review cards merge that PR themselves.
3. Do the remaining work, then move the card to `completed`.

Without repository changes, complete the card when its whole task is done. When blocked, comment the blocker and move the card to `planned`.
