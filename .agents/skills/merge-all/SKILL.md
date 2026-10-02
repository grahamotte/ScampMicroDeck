---
name: merge-all
description: Create Ready merge cards for every Code Moto downstream repository when requested by the user or a Linear card.
---

# Merge All

1. Discover all downstream repositories using [repository discovery](../../../docs/manager.md#repository-discovery-for-all-repository-skills). Exclude Code Moto itself. Read each repository's `linear.team` and workspace from `config.json`.
2. Fetch Code Moto and each downstream origin. Review recent Code Moto commits and the changes not yet incorporated into each downstream default branch. Identify relevant compatibility concerns and downstream-specific changes. Describe concerns without prescribing implementation solutions.
3. Use `mise linear` to check each downstream team for an existing unfinished merge card. Reuse one covering this rollout, adding only new relevant concerns; do not create duplicates. Otherwise create a card in `🤖 Ready` titled `Merge`, with a description invoking the `merge` skill plus any repository-specific concerns. Use the downstream checkout's environment and team.
4. Comment on the parent tracking card with the complete repository inventory and identifiers of the created or reused merge cards. This operation schedules the rollout; the downstream cards own executing their merges.

Complete the parent card directly without review once every downstream has a suitable card and its whole scope is done. No PR is needed for scheduling alone. If discovery or card creation is blocked, record partial results and move the parent to Planned. Remove the working tag when running for the manager.
