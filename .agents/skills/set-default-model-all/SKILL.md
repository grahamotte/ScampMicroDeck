---
name: set-default-model-all
description: Set machine-wide default agent runner, model, and variant for Code Moto and its downstream repositories.
---

# Set Default Model All

Use one tracking card for the entire operation. This operation updates local global configuration and normally needs no repository PR.

1. Read the requested runner, model, and variant from the card or user request. These are target defaults, independent of the labels selecting the agent working the card. If a value is missing or still a placeholder, ask for it before editing. An explicitly blank variant is valid. Check supported selections against `manager/lib/linear.rb` and the runner implementation; report an unsupported combination instead of substituting values.
2. Read `~/.config/codemoto/config.json` without printing secret values. Update only `agentDefaults.runner`, `agentDefaults.model`, and `agentDefaults.variant`, preserving `1passwordServiceAccountToken` and all other settings. Create the directory and file when absent, and keep the file private. Never put the global token in tracked repository files.
3. Discover Code Moto and all downstream main checkouts using [repository discovery](../../../docs/manager.md#repository-discovery-for-all-repository-skills). Record the inventory on the tracking card. Inspect repository `agent` overrides and report any that prevent a repo from inheriting the requested defaults. Do not silently rewrite intentional overrides.
4. Verify the global values and the resolved defaults in a fresh manager process for each repository. Existing card selections remain unchanged. No test suite or PR is required for this local configuration operation. If tracked repository changes are required to support inheritance, use isolated worktrees, required checks, and PRs rather than committing to default branches.
5. Record the requested values, repositories inheriting them, and any explicit overrides on the tracking card. Complete only when the whole requested scope is verified. If blocked, record completed work and the exact blocker, move the card to Planned, and retain any unmerged work for resumption. Remove the working tag when running for the manager.
