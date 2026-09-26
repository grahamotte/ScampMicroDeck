---
name: merge-precheck
description: Check whether a downstream repository can safely merge Code Moto. Use when invoked by the merge or merge-all skill, or when the user explicitly invokes `$merge-precheck` or asks to use the merge-precheck skill by name.
---

# Workflow

Check and report every item. Do not stop after the first failure. Fail the precheck if any item fails.

- The repository is a Git worktree with a valid `HEAD`.
- The current branch is `master`.
- It has no uncommitted changes.
- It has no Git operation in progress.
- After `git fetch origin`, `master` has no commits missing from `origin/master`.
- `mise test` passes.
