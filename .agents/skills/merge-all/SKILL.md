---
name: merge-all
description: Merge the latest Code Moto into every sibling downstream repository. Use only when the user explicitly invokes `$merge-all` or asks to use the merge-all skill by name.
---

# Workflow

1. Require the current directory to be the root of the `codemoto.org` repository. Fail otherwise.
2. Run `mise manager:gotomain`, then require `git rev-parse HEAD` to equal `git rev-parse origin/master`. Abort otherwise. Do not discover or modify any sibling repository until this succeeds.
3. Discover the immediate child directories of the parent directory that contain `.agents/skills/merge/SKILL.md`. Exclude `codemoto.org` itself and sort the repositories by path.
4. Before starting any merge, run Code Moto's `merge-precheck` workflow for each discovered repository. Assign each repository to a subagent working from that repository's root. The prechecks may run in parallel, but wait for all of them and abort the merge-all without merging any repository if a precheck fails.
5. After all preconditions pass, record `git rev-parse HEAD` for every discovered repository and echo each repository and recovery point to the user. Do not start any merge unless every recovery point succeeds.
6. Merge each discovered repository serially. Finish one repository before starting the next, never merge repositories in parallel, and carry relevant conflict-resolution learnings forward to subsequent merges.
7. Read and follow each repository's `.agents/skills/merge/SKILL.md` as the authoritative merge instructions.
8. Never run `git rebase`, `mise rebase`, or a force push.
9. Report the result, PR, merge commit, conflicts, and test results for every discovered repository. If a merge cannot be completed, fail the merge-all and identify the repository and blocker.
