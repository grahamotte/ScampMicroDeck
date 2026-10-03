---
name: cleanup-all-mains
description: Update Code Moto and downstream main checkouts, verify clean default branches, and refresh their secrets when requested by the user or a Linear card.
---

# Cleanup All Mains

Use one tracking card for the entire operation. Do not create downstream cards. This operation normally changes no tracked files and needs no PR or empty commit.

1. Discover Code Moto and all downstream main checkouts using [repository discovery](../../../docs/manager.md#repository-discovery-for-all-repository-skills). Record the inventory on the tracking card.
2. Inspect each main checkout's branch, status (including untracked files), worktrees, and any Git operation in progress. Preserve local changes, commits, and active card worktrees. Do not reset, clean, discard, or stash changes to claim a clean result. Report a dirty checkout or unfinished Git operation as blocked and continue checking the other repositories.
3. Fetch `origin` and determine its default branch (`master` or `main`). If a clean main checkout is on another branch, record that branch and its HEAD before switching to the default branch; leave the original branch and commits intact. If the default branch is checked out elsewhere, report the blocker instead of forcing it.
4. From each main checkout, run `git pull --ff-only origin <default-branch>`. If the branch has diverged or contains unpublished commits, preserve them and report the blocker. Verify the branch matches the remote default branch and the checkout has no local diffs or untracked files.
5. Run root `mise manager:secrets` from each updated main checkout in a non-login shell. Verify every configured `secrets` environment produced its `.env.<key>` file without printing secret values. Recheck Git status after refresh. A failed refresh or a newly dirty checkout leaves that repository incomplete.
6. Comment on the tracking card with each main checkout's path, branch, resulting SHA, clean-status result, secrets-refresh result, and any blockers. No tracked changes may bypass the PR flow; if a repository fix is needed, use an isolated branch from its remote default branch, run its required checks, link and merge its PR under this same card, then repeat the affected checks.

Complete the card without review only when every repository passes and the card's whole task is done. Otherwise move it to Planned with a concrete explanation.
