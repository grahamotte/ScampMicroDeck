---
name: merge
description: Merge the latest Code Moto into a downstream repository without rewriting its history. Use only when the user explicitly invokes `$merge` or asks to use the merge skill by name.
---

# Workflow

The merge branch is `codemoto-merge`.

1. Before starting the merge, run the `merge-precheck` skill. If the precheck fails, abort the merge.
2. Record `git rev-parse HEAD` and echo it to the user as the merge recovery point.
3. Run `git fetch origin`, then `git checkout -B codemoto-merge origin/master`.
4. Run `mise merge`.
5. If it stops with conflicts, inspect the output and repository state. Resolve every conflict, stage the resolutions, and run `GIT_EDITOR=true git merge --continue`. Repeat until the merge finishes.
6. Preserve the intent of both Code Moto and downstream changes. Inspect surrounding code, history, and tests when a resolution is not obvious.
7. Ask the user only when there is genuine ambiguity with materially different valid outcomes, or progress requires information or authority only they can provide. Explain the exact decision needed; do not stop merely because a conflict or failure occurred.
8. Run `mise test` after the merge succeeds. Fix merge-related failures, commit the fixes, and rerun the whole suite until it passes.
9. Push with `git push -u origin HEAD:codemoto-merge` and open a GitHub PR with `gh pr create --head codemoto-merge`.
10. Merge the PR with `gh pr merge --merge --delete-branch`. Never squash or rebase it; the merge commit must keep Code Moto's history.
11. Run `mise manager:gotomain`.
12. Report the completed merge, PR, conflict resolutions, merge commit, and test results.
