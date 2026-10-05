---
name: merge-all
description: Create queued merge cards for every Code Moto downstream repository when requested by the user or a Linear card.
---

# Merge All

1. Discover all downstream repositories using [repository discovery](../../../docs/manager.md#repository-discovery-for-all-repository-skills). Exclude Code Moto itself. Use the registered-project inventory command supplied in the launch prompt to obtain each project’s team, workspace, path, and configured Git remote. Do not read manager configuration files. Locate the registered Code Moto main checkout and fetch its configured remote.
2. Fetch each downstream’s configured Git remote. Review recent Code Moto commits and the changes not yet incorporated into each downstream default branch. Identify relevant compatibility concerns and downstream-specific changes. Describe concerns without prescribing implementation solutions.
3. Use the project-scoped Linear commands supplied in the launch prompt to check each downstream team for an existing unfinished merge card. Reuse one covering this rollout, adding only new relevant concerns; do not create duplicates. Otherwise enqueue a card titled `Merge` using the launch prompt’s supplied commands. Give it self-contained instructions: verify a clean checkout and baseline `mise test`; run the target repository’s `mise merge <card-branch>`; resolve conflicts while preserving the basis merge history; run `mise test`; deliver a PR using the supplied management commands; after approval and merge, update the clean main checkout, perform required env-file cleanup, refresh its env files with the Mr. Moto secrets command supplied in its launch prompt, and verify the regenerated env-file layout without exposing secrets. Include repository-specific concerns and required inputs. Do not refer to another repository’s skills. Select each target project and team using the inventory and supplied management command prefixes.
4. Comment on the parent tracking card with the complete repository inventory and identifiers of the created or reused merge cards. This operation schedules the rollout; the downstream cards own executing their merges.

Report whether every downstream has a suitable card. If discovery or card creation is blocked, record partial results and the blocker. Hand off the tracking card to Review even when this operation creates no tracked changes or PR. Record "No PR needed" and "Remaining work: none" when reporting is finished; the Approved session then completes the card. When blocked, hand off Planned using the launch prompt’s commands.
