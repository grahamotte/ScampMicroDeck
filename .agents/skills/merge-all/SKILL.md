---
name: merge-all
description: Create queued merge cards for every Code Moto downstream repository when requested by the user or a Linear card.
---

# Merge All

1. Discover all downstream repositories using [repository discovery](../../../docs/manager.md#repository-discovery-for-all-repository-skills). Exclude Code Moto itself. Use the registered-project inventory command named in `mr --help` to obtain each project’s team, workspace, path, and origin remote. Do not read manager configuration files. Locate the registered Code Moto main checkout and fetch its origin remote.
2. Fetch each downstream’s origin remote. Review recent Code Moto commits and the changes not yet incorporated into each downstream default branch. Identify relevant compatibility concerns and downstream-specific changes. Describe concerns without prescribing implementation solutions.
3. From each downstream's main checkout path, use `mr card search Merge` to check its team for an existing unfinished merge card. Reuse one covering this rollout, adding only new relevant concerns with `mr card comment --body-file <file> <CARD>`; do not create duplicates. Otherwise create a card titled `Merge` with `mr card create Merge --body-file <file>` there. Give it self-contained instructions: verify a clean checkout and baseline `mise test`; run the target repository’s `mise merge <card-branch>`; resolve conflicts while preserving the basis merge history; run `mise test`; deliver a PR with `mr push` and `mr pr create`; after approval and merge, update the clean main checkout, perform required env-file cleanup, refresh its env files with `mr secrets`, and verify the regenerated env-file layout without exposing secrets. Include repository-specific concerns and required inputs. Do not refer to another repository’s skills. Run `mr` from each target project's main checkout so it selects that project and team.
4. Comment on the parent tracking card with the complete repository inventory and identifiers of the created or reused merge cards. This operation schedules the rollout; the downstream cards own executing their merges.

Report whether every downstream has a suitable card. If discovery or card creation is blocked, record partial results and the blocker. Hand off the tracking card to Review even when this operation creates no tracked changes or PR. Record "No PR needed" and "Remaining work: none" when reporting is finished; the Approved session then completes the card. When blocked, hand off Planned using the launch prompt’s commands.
