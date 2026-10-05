---
name: merge
description: Merge the latest Code Moto into a downstream repository through a PR without rewriting its history. Use only when the user explicitly invokes `$merge`, asks to use the merge skill by name, or a Linear card says to run the merge skill.
---

# Merge

The merge branch is the card branch when running for a card, otherwise `codemoto-merge`.

## Precheck

Check and report every item. Do not stop after the first failure. Abort the merge if any item fails.

- The repository is a Git worktree with a valid `HEAD`.
- It has no uncommitted changes.
- It has no Git operation in progress.
- After `git fetch origin` and `git checkout --detach origin/master`, `mise test` passes.

## Workflow

1. Run `mise merge <branch>`. It uses the `codemoto` remote for the basis repository and migrates a legacy `upstream` remote only when its URL points to Code Moto. Unrelated `upstream` remotes are preserved. It checks out the merge branch, creating it from `origin/master` if needed, prints the merge recovery point, and merges Code Moto's `master`. Report the recovery point.
2. If it stops with conflicts, inspect the output and repository state. Resolve every conflict, stage the resolutions, and run `GIT_EDITOR=true git merge --continue`. Repeat until the merge finishes.
3. Preserve the intent of both Code Moto and downstream changes. Keep `AGENTS.md` **Repo Specific** and app-specific skills. Inspect surrounding code, history, and tests when a resolution is not obvious.
4. Ask the user only when there is genuine ambiguity with materially different valid outcomes, or progress requires information or authority only they can provide. Explain the exact decision needed; do not stop merely because a conflict or failure occurred.
5. Run `mise test` after the merge succeeds. Fix merge-related failures, commit the fixes, and rerun the whole suite until it passes.
6. If the repository is already up to date and there are no new commits or tracked file changes to bring into `origin/master`, report that result and hand off Review without a commit or PR, explicitly recording whether any main-checkout work remains. Preserve merge commits through a PR even when the final file contents match. Otherwise, deliver the merge branch through the supplied repository review instructions.
7. Hand off Review with the PR and steps 8–10 as remaining work. The Approved session continues those steps only after the PR has been merged and verified under the supplied repository review instructions. Never squash or rebase it, never rebase the branch, and never force push; the merge commit must keep Code Moto's history.
8. Locate the main checkout with `git worktree list --porcelain`. Confirm it is on master or main and has no uncommitted changes, then run `git pull --ff-only` there so it matches origin. Do not switch branches. If it cannot be updated, report the blocker.
9. Perform any local env-file cleanup in that main checkout: `.env.development` and `.env.production` copied into the card worktree are temporary and are removed with the worktree. Preserve secret values and downstream-only keys. Arrange the Code Moto keys in the order and grouping of the main checkout's merged `.env.default`, followed by its separator line, then downstream-only keys. Remove settings only after their values have been preserved in `config.json`.
10. Refresh the main checkout's env files with the Mr. Moto secrets command supplied in the launch prompt, in a non-login shell. It overwrites local env files, so any required cleanup must also be reflected in the corresponding 1Password item fields. Verify every regenerated `.env.<key>` in the main checkout against its `.env.default`, including `.env.development` and `.env.production`: every Code Moto key appears once in template order and grouping before the separator, and downstream-only keys follow it. Inspect key names and layout without printing secret values. If no secrets command is supplied, refresh fails, or the layout is wrong, correct the source item fields and regenerate when possible; otherwise report the blocker.
11. Report the completed merge, PR, conflict resolutions, merge commit, test results, main checkout path and branch, and secrets refresh and layout verification results.

## Downstream notes

- `Path.mv` and `Path.cp` raise if the destination already exists unless the caller passes `overwrite: true`. They never nest a source inside an existing destination directory. Downstream callers that intentionally overwrite must pass `overwrite: true`.

- Non-secret configuration moved from `.env.*` into the root `config.json`, which also absorbed `apps/config.json` (as `apps`) and `frontend/subdomains.json` (as `subdomains`). When merging this change, build the downstream `config.json` from the downstream's own `apps/config.json`, `subdomains.json`, and main checkout's `.env.production` values instead of keeping Code Moto's, and set `database` to the downstream database name without its `_development`/`_production` suffix. `.env.*` files keep secrets plus the identifiers issued or rotated with them (Apple team/issuer/key IDs, deploy user and SSH public key/fingerprint, backup bucket/endpoint, dashboard username) and always set `RAILS_ENV`/`NODE_ENV`; `.env.default` is their template. Clean the main checkout's local env files and their source notes as in workflow steps 9–10, and report which settings keys were removed.
- Each repo's 1Password `op://` references (Code Moto defaults are `development` and `production`) live in its Mr. Moto project registry entry, which Mr. Moto's secrets command pulls as `.env.<key>`. Never use Code Moto's references for a downstream repo. Its items are `op://Projects/<App Name> Development` and `op://Projects/<App Name> Production`, where `<App Name>` is the title-cased app name (for example `Scamp Micro Deck`). Report a missing registry entry rather than adding references to `config.json`.
- 1Password secrets moved from each item's `notesPlain` secure note into one concealed field per env key, labeled with the key name. `secrets` references in `config.json` now name the item (`op://<vault>/<item>`) instead of its `notesPlain` field. Drop the `/notesPlain` suffix from every downstream reference, including downstream-only keys. Before running `mise manager:secrets`, confirm each referenced item has its fields; if an item only has a note, report it as a blocker rather than editing it.
- Mobile app publishing moved from `deploy/` into the standalone `publish/` package (`lib/apps*`, `patches/apps/*` flattened into `publish/patches/`, and `publish.rb`, `approved_version.rb`, `set_version.rb`, `simulate.rb`). Move downstream changes to those files into `publish/`. The tasks are now `mise publish`, `publish:stop_before_prepare`, `publish:stop_before_submit`, `publish:approved_version`, `publish:set_version`, and `publish:simulate`. `mise secrets` is now `mise manager:secrets`, `deploy:spawn` is `manager:spawn` (code in `manager/lib/spawn.rb`), `manager:sync`/`manager:syncall` are `manager:linear_sync`/`manager:linear_syncall`, `merge` is `manager:merge` and `xcode` is `publish:xcode` (both keep their aliases), multi-line task bodies moved into `scripts/mise/`, and `manager:watch` and the `update` tasks are gone; use the `upgrade` skill instead. Update downstream task references to match.

- Linear dispatch moved out of Code Moto into the sister repository Mr. Moto (`../mr-moto`). It manages every checkout listed under `projects` in `../mr-moto/config.json`. `manager/` now keeps only spawn and merge. The `manager:trigger`, `manager:triggerall`, `manager:linear_sync` (`manager:sync`), `manager:linear_syncall`, and `manager:keychain` tasks are gone. Remove downstream references to them or to the deleted manager files, and report any needed repository registration separately. Mr. Moto also manages non-Code Moto repos; do not merge Code Moto into those. Remove mirrored Linear workflow and label rules from downstream `AGENTS.md`, the `interactive-card` skill, the `mise linear` task and Linearis tool, project `linear` settings, and the `LINEAR_TOKEN` env template key, and any repository-local Linear/GitHub/Forgejo credential handling. Mr. Moto owns enqueueing and card lifecycles; downstream operation tooling does not define them.

- Credentials and secrets refresh moved into Mr. Moto. `~/.config/codemoto/config.json`, `mise manager:secrets`, `manager/lib/secrets.rb`, `manager/secrets.rb`, `scripts/mise/manager_secrets.sh`, `Settings.global`, and the `secrets` key in `config.json` are gone; Mr. Moto's project registry holds each repo's 1Password references and its `secrets` command writes the `.env.<key>` files. Remove the downstream `secrets` key, including downstream-only environments such as `helios` or `poseidon`, after confirming Mr. Moto's registry has the same references, and remove downstream references to the deleted files and task. GitHub artifact publishing reads `GITHUB_TOKEN` from `.env.production`, so `.env.default` lists `GITHUB_TOKEN` again; keep it in Code Moto's position. The project's 1Password items must have a `GITHUB_TOKEN` field.

## Piped mise tasks

Code Moto sets `[task_config] shell = "bash -o errexit -o pipefail -c"` so inline mise tasks use bash with `errexit` and `pipefail`. After merging, piped tasks in the downstream repo fail if any command in the pipeline fails. That is intended; for example good.gratis `sync:mirror` and `sync:cookies` should fail when the Ruby script raises instead of when `tee` exits. Add `|| true` only when a pipeline is supposed to ignore a non-zero producer, such as `grep` with no matches or `head` closing early.

## Results

Report the recovery point as soon as `mise merge` prints it. After the merge, verify steps 8–10 and report the PR, merge commit, conflict resolutions, tests, main checkout path and branch, and secrets refresh and layout results. Worktree env-file copies do not satisfy main-checkout verification. When blocked, include the recovery point. Record results on the invoking card when present. In a work session, hand off successful work to Review even when no tracked changes or PR are needed; explicitly record "No PR needed" and "Remaining work: none" when applicable. The Approved session finishes any remaining steps, then completes the card. When blocked, hand off Planned using the launch prompt’s commands.
