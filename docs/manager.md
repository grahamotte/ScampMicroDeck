# Manager runners and labels

`mise manager:sync` (also available as `mise manager:linear_sync`) reconciles the configured Linear team's workflow, labels, and Git automations. It creates the manager's runner, model, and variant labels and deletes labels outside the managed set, including shared workspace labels returned for the team. Deleting a shared label removes it from cards across the workspace. Labels owned by other teams are left alone. The manager-driven Ready and Approved columns are named `🤖 Ready` and `🤖 Approved`; sync renames plain `Ready` and `Approved` in place, and the manager matches either name. Run sync before triggering cards.

`mise manager:trigger` filters issues in Linear before paginating: all Ready and Approved cards remain eligible regardless of age, while Completed and Canceled cards are fetched for worktree cleanup only when updated within the last 30 days. Other columns are excluded. The window uses the last update rather than creation, so an old card that is newly completed or canceled still gets cleaned up. Worktrees for terminal cards unchanged for more than 30 days need manual removal if the manager missed the cleanup window.

Cards can override the defaults in `config.json` using these labels:

- `runner: openchamber`, `runner: t3`, or `runner: interactive`
- `model: <provider>/<modelid>`
- `variant: <effort>`

When the trigger starts a card, it fills in missing labels from the resolved agent configuration: `agentDefaults` in `~/.config/codemoto/config.json`, overridden by repository `agent.runner`, `agent.model`, and `agent.variant`. Existing selections take precedence. A blank default variant leaves that label unset. Move a card to Review or Approved only when its whole task is ready; approval of one PR within a larger task does not approve the card. When a card reaches Approved, the manager first tries to merge its single linked PR in the configured GitHub repository. A clean, mergeable PR targeting master or main is merged with its head commit checked, and the manager confirms it is merged before updating a clean main checkout, completing the card, and removing the working tag. An already merged PR can also complete the card. Missing or ambiguous links, conflicts, pending checks, queued merges, and command failures fall back to the merge agent. The recorded selections apply to that agent; edit the labels to change its runner or model.

`runner: interactive` marks work started manually with the user. The manager skips those cards in Ready, and tries the same automatic merge when Approved, using its configured runner if an agent is needed. Sync renames the old `interactive` label in place, preserving its ID and existing card assignments.

`skip review` tells the manager's work agent to create and link a PR for tracked repository changes, then merge it immediately after resolving conflicts and passing required checks. The agent confirms any required PR is merged and updates a clean main checkout. It completes the card and removes its worktree only when the whole task is done, removing the worktree from the main checkout as its final step. Operations without tracked repository changes need no PR, empty commit, or branch. If other steps remain, the agent records them, keeps the card in Working, retains its worktree, and removes the working tag. A blocked merge returns the card to Planned with an explanation. Cards without the tag go to Review when repository changes await review and the whole task is ready, or Completed when the whole task is done without a PR. Named skills record operation results on the same tracking card and complete it only when its full scope is done.

Reuse one tracking card for the whole task, including individual operations and PRs. Record each step and any remaining work there. A finished operation or merged PR leaves a larger card in Working while steps remain, or Planned when blocked. Do not create a separate card for each step.

The model picker contains eight options:

- `openai/gpt-6.1-sol`
- `openai/gpt-6-astra`
- `anthropic/claude-opus-5-5`
- `anthropic/claude-sonnet-5-5`
- `xai/grok-4.7`
- `google/gemini-3.1-pro`
- `cursor/composer-2.5`
- `cursor/grok-4.7`

Availability and supported effort levels depend on the runner, provider account, and model. A model without effort options needs a blank default variant. For OpenChamber, model and variant values are forwarded as before.

## Global configuration

`~/.config/codemoto/config.json` holds machine-wide settings for every Code Moto checkout. Keep its permissions private because it contains the 1Password service account token.

```json
{
  "agentDefaults": {
    "runner": "t3",
    "model": "openai/gpt-6.1-sol",
    "variant": "medium"
  },
  "1passwordServiceAccountToken": "<service-account-token>"
}
```

Repository `config.json` keeps app-specific settings and optional `agent` overrides, including runner options such as `agent.t3`. Omit runner, model, and variant to inherit the global defaults. An explicitly blank repository variant overrides the global variant. Existing Linear selections still take precedence. Edit the global file to change the defaults for all inheriting repos; no repository PR or merge is needed. Each new manager process reads the current global file.

`mise manager:secrets` reads `1passwordServiceAccountToken` from the global file and passes it to 1Password through `OP_SERVICE_ACCOUNT_TOKEN`. It no longer reads `.env.service`. Repository `secrets` references and `.env.default` still control which app secrets are fetched and their layout. The token is never copied into repository configuration or generated env files. A missing global file leaves explicit repo settings available; secrets refresh requires the global token.

## Host keychain protection

Tasks that change the user's keychain settings, such as publish signing, wrap the change in `Keychain#protect` from `gems/keychain`. It saves the search list and default keychain under `~/.config/codemoto/keychain` and restores whichever changed when the block finishes, raises, or is interrupted. The login keychain setting is not touched; `security login-keychain -s` fails on current macOS, so tasks cannot change it either.

Each `mise manager:trigger` run first restores snapshots left by processes that are no longer running and removes keychains whose files no longer exist from the search list and default. Before removing a card worktree, the manager also removes keychains stored inside it; if that fails, the worktree is kept. The trigger then warns when the default keychain is not `~/Library/Keychains/login.keychain-db`, the search list omits it, or a larger `login_renamed_*.keychain-db` suggests macOS replaced the login keychain. These checks are skipped while a protected task is running.

Run `mise manager:keychain` to repair the warned state. It resets the default keychain to the login keychain and adds the login keychain to the search list. If a larger `login_renamed_*` file exists, it saves the current login keychain as `login_backup_<timestamp>.keychain-db`, copies the largest renamed file back to `login.keychain-db`, and asks you to log out and back in.

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

Creating or editing these templates does not execute their operations. Blank Default templates and personal recurring reminders are not operation workflows.

## Repository discovery for all-repository skills

Locate the main checkout through `git worktree list --porcelain`, rather than treating a card worktree as a separate repository. Enumerate sibling main checkouts under its parent directory, following the discovery pattern in `manager/lib/linear_sync_all.rb`: a main checkout has a `.git` directory and root `mise.toml` with the `manager:linear_sync` task. Deduplicate by Git common directory and exclude linked card worktrees.

Include Code Moto itself and confirm downstream membership using the Code Moto `codemoto` remote (or legacy `upstream`), shared Code Moto Git ancestry, and the repository's `AGENTS.md`. Read each repository's own `config.json` for its GitHub origin and Linear team. Fetch origin and identify its actual remote default branch; never assume local master is current. If an expected downstream lacks a local checkout, or membership is ambiguous, record the gap as a blocker rather than silently omitting it. Report the inventory, exclusions, and results on the supplied tracking card.

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

## T3 Code

Start T3 Code and enable/authenticate the provider you want to use. For example, these settings select Codex through T3:

```json
{
  "agent": {
    "runner": "t3",
    "model": "openai/gpt-6.1-sol",
    "variant": "medium",
    "t3": {
      "speed": "normal"
    }
  }
}
```

Provider prefixes map to T3 instances as follows:

| Prefix | Default T3 instance |
| --- | --- |
| `openai` | `codex` |
| `anthropic` | `claudeAgent` |
| `xai` | `grok` |
| `google` | `antigravity` |
| `cursor` | `cursor` |

You can also use a configured T3 instance ID as the prefix, such as `codex/gpt-6.1-sol`. The manager validates the model and effort against the running app's cached provider catalog before dispatching. `cursor/grok-4.7` selects Cursor's Grok model; `xai/grok-4.7` selects the separate Grok provider.

Optional `agent.t3` settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `url` | `http://127.0.0.1:3773` | Local T3 backend origin |
| `home` | `~/.t3` | Data directory used by this backend |
| `command` | Installed macOS Alpha app, otherwise `["t3"]` | Argument array for the T3 CLI |
| `speed` | Provider default | `fast` or `normal` |

Speed uses the catalog's service tier or Fast Mode option. This accommodates provider-specific values such as Codex's `priority` tier. Unsupported model, effort, or fast-speed selections fail before starting a thread.

The CLI issues a five-minute bearer token for each launch and revokes it afterward. No permanent T3 token is required in the environment. CLI, catalog, and backend must belong to the same local T3 installation. The macOS Alpha app can supply its bundled CLI even when `t3` is absent from PATH.

The manager reuses a project matching the card checkout, or registers that directory as a project, then creates a thread and sends the prompt through `/api/orchestration/dispatch`. Threads run in T3's `full-access` mode for unattended manager work. T3's API, CLI, and cache layouts are internal interfaces and may require adapter updates after an app upgrade.
