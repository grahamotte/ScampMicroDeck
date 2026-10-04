---
name: set-default-model-all
description: Set default agent selections in Mr. Moto for Code Moto and its downstream repositories.
---

# Set Default Model All

Use one tracking card for the entire operation. This operation updates Mr. Moto's tracked manager configuration and requires a Mr. Moto PR.

1. Read the requested runner, model, and variant from the card or user request. These are target defaults, independent of the labels selecting the agent working the card. If a value is missing or still a placeholder, ask for it before editing. An explicitly blank variant is valid. Check supported selections against Mr. Moto's `lib/linear.rb` and runner implementation in `../mr-moto`; report an unsupported combination instead of substituting values.
2. Read `../mr-moto/config.json`. For a requested single default, replace `agentDefaultsBalance` with a one-entry array containing the requested runner, model, and variant. For a requested balanced list, preserve every requested candidate. Balanced candidates require the T3 runner and usable weekly quota; do not silently substitute another runner. Preserve `projects` and all other manager settings. Credentials remain in `~/.config/codemoto/config.json`; never put tokens in tracked repository files. Manager config changes require a Mr. Moto PR.
3. Discover Code Moto and all downstream main checkouts using [repository discovery](../../../docs/manager.md#repository-discovery-for-all-repository-skills). Record the inventory on the tracking card. Inspect project `agent` overrides in Mr. Moto's `projects` map and report any that prevent a repo from inheriting the requested defaults. Do not silently rewrite intentional overrides.
4. Verify the manager values and the resolved defaults for each repository with `AgentSelection.resolve` in a fresh Mr. Moto process, after selecting the repository with `Projects.use`. Existing card selections remain unchanged. Run Mr. Moto's required checks and use its PR flow for the tracked manager configuration. If tracked repository changes are required to support inheritance, use isolated worktrees, required checks, and PRs rather than committing to default branches.
5. Record the requested values, repositories inheriting them, and any explicit overrides on the tracking card. Complete only when the whole requested scope is verified. If blocked, record completed work and the exact blocker, move the card to Planned, and retain any unmerged work for resumption.
