# Manager

The launch prompt supplies the session workflow, and Mr. Moto's `mr` CLI, run from the project checkout, handles card access, Git sync and push, PR management, releases, secrets, and handoff; `mr --help` lists its commands. Agents work in their project checkout without reading another repository's documentation or configuration to discover the session workflow. This repository keeps only project-specific operation tooling.

Code Moto's `manager/` keeps the per-repository tasks. Mr. Moto owns credentials and refreshes each project's `.env.*` files from 1Password with its `secrets` command; `.env.default` controls their layout.

- `mise manager:spawn <domain>` clones Code Moto into a new app. The task creates the app checkout and configuration; registration and scheduling are separate Mr. Moto operations.
- `mise manager:merge <branch>` merges the latest Code Moto into a downstream repository.

## Code Moto merge verification

Code Moto merges that require local env-file cleanup must target `.env.development` and `.env.production` in the main checkout, where the post-merge `git pull --ff-only` runs. The card worktree contains temporary copies that disappear when it is removed.

After a Code Moto merge, verify the main checkout: confirm master or main, pull the merged changes, refresh its env files with `mr secrets`, and verify the refreshed files against the merged `.env.default`. Code Moto keys must appear once in template order and grouping before the separator line, with downstream-only keys afterward. Apply cleanup to the corresponding 1Password item fields so regeneration preserves it. Report a failed refresh or layout check as a blocker.

## Repository discovery for all-repository skills

For Code Moto rollouts, obtain registered repository metadata using the inventory command named in `mr --help`. Do not read manager configuration files. Locate the Code Moto main checkout and each project’s main checkout with `git worktree list --porcelain`; deduplicate by Git common directory and exclude linked worktrees. Confirm downstream membership using a `codemoto` remote (or legacy `upstream`), shared Code Moto Git ancestry, and the repository’s `AGENTS.md`. Exclude Mr. Moto and non-Code Moto repositories from basis merges. Also check Code Moto’s sibling directories for downstreams missing from the registry and report gaps rather than silently scheduling an incomplete rollout.

Use each entry’s explicit workspace, team, path, and `origin` workflow remote when enqueueing a merge, running `mr` from that entry's path. Missing checkouts or ambiguous membership are blockers. Fetch origin and use its actual default branch; do not assume local master is current. Report the inventory, exclusions, and rollout concerns on the supplied tracking card. Create cards with `mr card create` and hand off with `mr handoff`.

## macOS agent task execution

Run root `mise` tasks with the card's worktree root as the working directory and a non-login shell. Before running tasks in a newly opened worktree, copy `.env.development`, `.env.production`, and `backend/db/schema.rb` from the main checkout as required by `AGENTS.md`. The manager already copies these files when opening a card worktree.

For Codex's `exec_command`, set `login: false` explicitly on every call that invokes `mise`; the option applies to that call only. This also applies when `exec_command` is called through an orchestration wrapper. For example:

```javascript
await tools.exec_command({
  cmd: "mise test",
  workdir: "/absolute/path/to/card-worktree",
  login: false,
});
```

Other runners should use their equivalent non-login shell option. Keep using the root tasks so their dependencies, environment files, and task shell configuration are applied.

In the failure reported by MOTO-77, login-shell PATH ordering selected `/usr/bin/bundle` and macOS system Ruby 2.6 instead of the Ruby pinned in `mise.toml`. This can look like a missing Bundler version or a Ruby compatibility failure. `mise which ruby` and `mise exec -- ruby --version` resolved the pinned Ruby even while the root task failed. Wrapping the task in `mise exec -- bash -c` also failed in that session; retrying the same root task with `login: false` succeeded.

If this symptom occurs, run these diagnostics from the worktree root with `login: false`:

```sh
command -v ruby
command -v bundle
mise which ruby
mise which bundle
mise exec -- ruby --version
mise exec -- bundle --version
```

The shell may resolve mise shims or installed tool paths. `mise which` should identify the mise-managed installations, and the Ruby version should match `[tools]` in the root `mise.toml`. Retry the original root task in the same non-login execution mode. A successful direct `mise exec` diagnostic alone does not verify the task's environment.

If a pinned tool is missing, use `mise install` in that mode, then retry. If the task still fails, investigate its actual error with the selected tools confirmed. Do not install gems into system Ruby, change lockfiles, or downgrade pinned versions to address a shell-resolution failure. Share tool paths and versions when reporting the failure; do not dump environment variables or secret files.
