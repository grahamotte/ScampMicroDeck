# Manager

Linear dispatch lives in [Mr. Moto](https://github.com/grahamotte/mr-moto), the sister repository checked out at `../mr-moto`. A single install manages Code Moto and every downstream repository listed under `projects` in `../mr-moto/config.json`. It syncs Linear columns and tags, starts agents for queued and approved cards, and creates and removes card worktrees. See its `docs/manager.md` for runners, labels, agent selection, and the manager configuration. The shared card workflow lives in `../mr-moto/docs/workflow.md` and is mirrored for Code Moto projects in `AGENTS.md`.

Code Moto's `manager/` keeps the per-repository tasks:

- `mise manager:secrets` reads `1passwordServiceAccountToken` from the global file and passes it to 1Password through `OP_SERVICE_ACCOUNT_TOKEN`. Repository `secrets` references and `.env.default` control which app secrets are fetched and their layout. The token is never copied into repository configuration or generated env files.
- `mise manager:spawn <domain>` clones Code Moto into a new app. Add the new checkout to `projects` in Mr. Moto's config, with explicit workspace, team and path fields, so Mr. Moto manages it.
- `mise manager:merge <branch>` merges the latest Code Moto into a downstream repository.

## Code Moto merge cards

Cards that invoke the `merge` skill and request local env-file cleanup must target `.env.development` and `.env.production` in the main checkout, where the post-merge `git pull --ff-only` runs. The card worktree contains temporary copies that disappear when it is removed.

Before completing a merge card, follow the merge skill's main-checkout steps: confirm master or main, pull the merged changes, run `mise manager:secrets` from that checkout root in a non-login shell, and verify the refreshed files against the merged `.env.default`. Code Moto keys must appear once in template order and grouping before the separator line, with downstream-only keys afterward. Apply cleanup to the corresponding 1Password item fields so regeneration preserves it. A failed refresh or layout check leaves the card blocked rather than completed.

## Operation templates

Linear operation templates invoke checked-in skills. Keep execution steps and completion rules in the skill; templates contain only the invocation and operation inputs.

| Template | Skill | Inputs |
| --- | --- | --- |
| Deploy | `deploy` | None |
| Merge | `merge` | Repository-specific concerns when needed |
| Merge All | `merge-all` | None |
| Publish - full | `publish` | Full publish |
| Publish - stop before prepare | `publish` | TestFlight only |
| Publish - stop before submission | `publish` | Stop before submission |
| Triage Jobs | `triage-jobs-card` | None |
| Set Default Model All | `set-default-model-all` | Target runner, model, and variant (blank variant is allowed) |
| Cleanup All Mains | `cleanup-all-mains` | None |

Workspace-wide operation templates name the checked-in skill location. Merge All, Cleanup All Mains, and Set Default Model All use the shared skills in the Code Moto main checkout, even when the card belongs to Mr. Moto or a non-Code Moto project. Cleanup and default-model operations cover every project in Mr. Moto's registry; Code Moto merges only cover Code Moto downstreams. Deploy, publish, and job triage use the target repository's own skills and tooling.

Creating or editing these templates does not execute their operations. Blank Default templates and personal recurring reminders are not operation workflows.

## Repository discovery for all-repository skills

The inventory starts from `projects` in `../mr-moto/config.json`, the main checkouts Mr. Moto manages. It lists project objects with explicit `workspace`, `team`, and `path`. Read manager settings from these entries; do not load them from managed repository configuration. The inventory also includes non-Code Moto repos; exclude those from Code Moto merge operations. Also check sibling directories of the Code Moto main checkout for repositories with a `codemoto` remote that are missing from `projects`, and report any as gaps. Locate main checkouts through `git worktree list --porcelain`, deduplicate by Git common directory, and exclude linked card worktrees. Mr. Moto itself is a sister repository, not a downstream.

Include Code Moto itself and confirm downstream membership using the Code Moto `codemoto` remote (or legacy `upstream`), shared Code Moto Git ancestry, and the repository's `AGENTS.md`. Read each entry for its workspace, team, path, GitHub repository and optional `gitRemote` (default `origin`). Fetch origin and identify its actual remote default branch; never assume local master is current. If an expected downstream lacks a local checkout, or membership is ambiguous, record the gap as a blocker rather than silently omitting it. Report the inventory, exclusions, and results on the supplied tracking card.

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
