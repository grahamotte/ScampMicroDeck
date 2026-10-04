---
name: cleanup-all-mains
description: Update all Mr. Moto registered main checkouts, verify clean default branches, and refresh configured Code Moto secrets when requested by the user or a Linear card.
---

# Cleanup All Mains

Use one tracking card for the entire operation. Do not create downstream cards. This operation normally changes no tracked files and needs no PR or empty commit.

1. Read `projects` from Mr. Moto's `config.json` (`../mr-moto/config.json`). Include every registered project, including Mr. Moto and non-Code Moto repos. Entries are objects with explicit `workspace`, `team`, and `path`. Resolve main checkouts through `git worktree list --porcelain`, deduplicate by Git common directory, and record the inventory on the tracking card. A missing checkout is a blocker; continue checking the others.
2. Inspect each main checkout's branch, status (including untracked files), worktrees, and any Git operation in progress. Preserve local changes, commits, and active card worktrees. Do not reset, clean, discard, or stash changes to claim a clean result. Report a dirty checkout or unfinished Git operation as blocked and continue checking the other repositories.
3. Use each project's configured `gitRemote` (default `origin`). Fetch that remote and identify its actual default branch using `git remote set-head <gitRemote> --auto` and `refs/remotes/<gitRemote>/HEAD`; it can be `master`, `main`, `latest`, or another name. If a clean main checkout is on another branch, record that branch and its HEAD before switching to the default branch; leave the original branch and commits intact. If the default branch is checked out elsewhere, report the blocker instead of forcing it.
4. From each main checkout, run `git pull --ff-only <gitRemote> <default-branch>`. If the branch has diverged or contains unpublished commits, preserve them and report the blocker. Verify the branch matches the remote default branch and the checkout has no local diffs or untracked files.
5. Refresh secrets only for projects with configured `secrets` in their app `config.json` and a root `manager:secrets` task. Run root `mise manager:secrets` from that main checkout in a non-login shell and verify every configured environment produced its `.env.<key>` file without printing secret values. Projects without secret configuration need no refresh; missing tooling for configured secrets is a blocker. Recheck Git status after refresh. A failed refresh or a newly dirty checkout leaves that repository incomplete.
6. Comment on the tracking card with each main checkout's path, branch, resulting SHA, clean-status result, secrets-refresh result (including when not applicable), and any blockers. No tracked changes may bypass the PR flow; if a repository fix is needed, use an isolated branch from its remote default branch, run its required checks, link and merge its PR under this same card, then repeat the affected checks.

Complete the card without review only when every repository passes and the card's whole task is done. Otherwise move it to Planned with a concrete explanation.
