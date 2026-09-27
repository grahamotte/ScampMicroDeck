---
name: merge
description: Merge the latest Code Moto into a downstream repository through a PR without rewriting its history. Use only when the user explicitly invokes `$merge`, asks to use the merge skill by name, or a Linear card says to run the merge skill.
---

# Merge

The merge branch is the card branch when running for a card, otherwise `codemoto-merge`.

## Precheck

Check and report every item. Do not stop after the first failure. Abort the merge if any item fails.

- The repository is a Git worktree with a valid `HEAD`.
- It has no uncommitted changes.
- It has no Git operation in progress.
- After `git fetch origin` and `git checkout --detach origin/master`, `mise test` passes.

## Workflow

1. Run `mise merge <branch>`. It checks out the merge branch, creating it from `origin/master` if needed, prints the merge recovery point, and merges Code Moto's `master`. Report the recovery point.
2. If it stops with conflicts, inspect the output and repository state. Resolve every conflict, stage the resolutions, and run `GIT_EDITOR=true git merge --continue`. Repeat until the merge finishes.
3. Preserve the intent of both Code Moto and downstream changes. Keep `AGENTS.md` **Repo Specific** and app-specific skills. Inspect surrounding code, history, and tests when a resolution is not obvious.
4. Ask the user only when there is genuine ambiguity with materially different valid outcomes, or progress requires information or authority only they can provide. Explain the exact decision needed; do not stop merely because a conflict or failure occurred.
5. Run `mise test` after the merge succeeds. Fix merge-related failures, commit the fixes, and rerun the whole suite until it passes.
6. Push with `git push -u origin HEAD:<branch>` and open a GitHub PR with `gh pr create --head <branch>`.
7. Merge the PR with `gh pr merge --merge --delete-branch`. Never squash or rebase it, never rebase the branch, and never force push; the merge commit must keep Code Moto's history.
8. Report the completed merge, PR, conflict resolutions, merge commit, and test results.

## Linear card

When running for a Linear card, finish the card here instead of sending it to `review`:

- Comment with the recovery point as soon as `mise merge` prints it.
- Link the PR to the card.
- On success, comment with the PR, merge commit, conflict resolutions, and test results, then move the card to `completed`.
- When blocked, comment with the blocker and the recovery point, then move the card to `planned`.
