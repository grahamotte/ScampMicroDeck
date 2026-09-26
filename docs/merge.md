# Merge guide

Use this for existing downstream repositories that still have Codeberg remotes and a `kanban/` board. Code Moto now uses GitHub as `origin`, Linear instead of kanban, and a `manager/` that starts agents from Linear cards.

This first merge is not a normal `$merge`. Do the remote and Linear setup below before relying on `mise merge` or `$merge-all`. Later merges follow `.agents/skills/merge/SKILL.md`.

## Before the merge

Work on `master` with a clean tree. Record `git rev-parse HEAD` as the recovery point.

Push `codemoto.org` first. Downstream merges fetch GitHub Code Moto, so unpushed local Code Moto commits are silently left out.

Older downstream `mise test` fails to load deploy tests when `EDITOR` is unset (pry shells out, and `TestSafety` blocks it). If that is the only precheck failure, run the precheck with `EDITOR=vi mise test`. The fix arrives with this merge.

### Git remotes

Codeberg is gone. Typical downstream remotes today:

| Remote | Typical current URL | Action |
| --- | --- | --- |
| `codeberg` | `ssh://git@codeberg.org/grahamotte/<app>.git` | Remove |
| `github` | `git@github.com:grahamotte/<app>.git` | Remove after `origin` is GitHub |
| `origin_backup` | GitHub | Remove if redundant with `origin` |
| `origin` | Missing, or still Codeberg | Set to the app's GitHub repo |
| `upstream` | Codeberg `codemoto.org` | Set to `git@github.com:grahamotte/codemoto.org.git` |
| `deployment` | DigitalOcean bare repo | Keep |

```sh
git remote remove codeberg
git remote remove github
git remote remove origin_backup

git remote add origin git@github.com:grahamotte/<app>.git
# or: git remote set-url origin git@github.com:grahamotte/<app>.git

git remote add upstream git@github.com:grahamotte/codemoto.org.git
# or: git remote set-url upstream git@github.com:grahamotte/codemoto.org.git

git config remote.origin.gh-resolved base
```

`origin` must be the app's GitHub repo. The manager fetches `origin`, and agents open PRs with `gh pr create`. With both `origin` and `upstream` on GitHub, `gh` picks `upstream` unless `remote.origin.gh-resolved` is `base`.

Do not run the **old** `mise merge` until this merge lands. That task still rewrites `upstream` to Codeberg. Merge GitHub Code Moto by hand this once:

```sh
git checkout master
git config remote.upstream.tagOpt --no-tags
git fetch --no-tags upstream master
git merge --no-edit --no-ff upstream/master
```

After this merge, `mise merge` points `upstream` at GitHub and is safe.

### Tags

Older merges fetched Code Moto's tags into downstream repositories. `mise merge` now fetches with `--no-tags` and deletes local tags whose name and SHA match an upstream tag, but the first merge still runs the old task. Clean up by hand once:

```sh
git ls-remote --tags upstream | grep -v "\^{}$" | while read -r sha ref; do tag="${ref#refs/tags/}"; if [ "$(git rev-parse -q --verify "refs/tags/$tag")" = "$sha" ]; then git tag -d "$tag"; fi; done
```

If a fetch fails with `bad object refs/tags/<tag>` or `did not send all necessary objects`, a local tag points at commits that an old rebase rewrote. Delete that local tag and fetch `origin` again. If the app's own GitHub tag is not on `master` (`git merge-base --is-ancestor <tag> master`), find the rewritten equivalent by subject, author date, and `git patch-id --stable`, then move the tag with `git tag -f` and `git push -f origin refs/tags/<tag>`.

### Environment

Update the gitignored `.env.development` and `.env.production`. Merge does not edit them. `.env.default` usually takes Code Moto's version unchanged.

Remove:

- `CODEBERG_REPO`
- `CODEBERG_TOKEN`
- `OPENCODE_TOKEN` (renamed)
- `PLANE_TOKEN`, `PLANE_WORKSPACE`, `PLANE_PROJECT` if present

Set:

```
GITHUB_REPO="git@github.com:grahamotte/<app>.git"
GITHUB_TOKEN=...
OPENROUTER_TOKEN=...
LINEAR_TOKEN=...
LINEAR_WORKSPACE=gotte
LINEAR_TEAM=<APP_KEY>
AGENT_RUNNER=openchamber
AGENT_MODEL=xai/grok-4.6
AGENT_VARIANT=high
```

Copy the token, workspace, and agent values from `../codemoto.org/.env.development` and `.env.production`.

`GITHUB_REPO` is this app, not `codemoto.org`. `mise push` deletes and re-adds `origin` from `GITHUB_REPO` before pushing `master`, so a wrong value pushes the app into another repository. `LINEAR_TEAM` is this app's Linear team key, not `MOTO`. `LINEAR_WORKSPACE` is the Linear org `urlKey`.

Check that `GITHUB_TOKEN` actually authenticates; placeholder values are common:

```sh
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/repos/grahamotte/<app>
```

## During the merge

Preserve downstream intent. Keep `AGENTS.md` **Repo Specific** and any extra skills that belong to the app.

Expect conflicts in `AGENTS.md`, `mise.toml`, `.env.default`, and skill directories. Incoming Code Moto replaces kanban instructions with Linear and GitHub sections, adds `manager/`, and copies env files plus `backend/db/schema.rb` into card worktrees.

After resolving conflicts, run `mise dependencies` then `mise test`.

## After the merge

### Skills

- Delete leftover `.agents/skills/commit/` (removed; commit when asked).
- Delete leftover `.agents/skills/debug/` (renamed to `prod-debug`; invoke with `$prod-debug`).
- Delete leftover `cards/` if present. It is Code Moto's own card archive.
- Keep app-specific skills.

### Linear

Create a Linear team for the app. Put its key in `LINEAR_TEAM`. Agents use the `mise linear:*` tasks with `LINEAR_TOKEN`, `LINEAR_WORKSPACE`, and `LINEAR_TEAM`; no Linear MCP is needed.

Columns, in order: `backlog`, `planned`, `ready`, `working`, `review`, `approved`, `completed`, `canceled`.

Run `mise manager:sync` to sync those workflow names and colors, create the default tags (`working`, `interactive`, `variant: …`, `model: …`), and clear git automations. Run it only against the team this repo should own. On a new team it renames Linear's default `Todo`, `In Progress`, `In Review`, and `Done` states. Sync also deletes Linear's GitHub git automations (branch/draft PR, PR opened, PR merged); the manager moves cards itself.

### Kanban cards

Create Linear issues from current kanban cards, then delete `kanban/`. The merge removes the board README and `.gitkeep` files but leaves the card files, so delete the directory and commit.

| Kanban column | Linear state |
| --- | --- |
| `1 - Problems to Solve` | `planned` |
| `2 - In Progress` | `ready` if the manager should pick it up, otherwise `working` |
| `3 - In Review` | `review` |
| `4 - Done` | Skip. Already shipped. |
| `5 - Won't Do` | Skip. |

Copy the card title, user value, problem description, notes, and prompts into the Linear description. Keep the card code in the title because cards reference each other by code.

With `LINEAR_*` set, this creates `planned` issues from `1 - Problems to Solve` using the manager's Linear client. Check the team has no matching issues first.

```sh
cd manager && mise exec -- bundle exec ruby -e '
require_relative "lib/require"
team = Linear.send(:team_id)
state = Linear.send(:state_id, "planned")
create = "mutation($input: IssueCreateInput!) { issueCreate(input: $input) { issue { identifier url } } }"
Dir.glob("../kanban/1 - Problems to Solve/*.md").sort.each do |path|
  body = File.read(path, encoding: "UTF-8").sub(/\A# .*\n+/, "")
  input = { teamId: team, stateId: state, title: File.basename(path, ".md"), description: body }
  puts Linear.send(:graphql, create, { input: }).dig(:issueCreate, :issue).values.join("  ")
end'
```

### Manager

`AGENT_RUNNER` picks where agents run. `GITHUB_TOKEN` must work with `gh`. `origin` must be GitHub.

- `openchamber`: OpenChamber must be listening on `http://127.0.0.1:57123`. Uses `AGENT_MODEL` and `AGENT_VARIANT`, overridden by `model:` and `variant:` card tags.
- `claude`: opens a new session in the Claude desktop app with `claude://code/new`, pointed at the card worktree, then presses Enter. Set the Code tab's default permission mode to Bypass permissions and start sessions in the selected folder rather than a new worktree.
- `codex`: opens a new thread in the Codex desktop app with `codex://threads/new`, pointed at the card worktree, then presses Enter. Set Codex to full access (`approval_policy = "never"` and `sandbox_mode = "danger-full-access"` in `~/.codex/config.toml`) and run threads locally rather than in a new worktree.

`claude` and `codex` ignore the model and variant settings; the app's defaults apply. They send the Enter key with `osascript`, so the terminal that runs `mise manager:watch` needs Accessibility access (System Settings → Privacy & Security → Accessibility). Keep the Mac unlocked while the manager runs, and don't type while it starts a session.

```sh
mise manager:sync
mise manager:watch
```

`ready` starts an agent in `../<repo>-<identifier>` after copying `.env.development`, `.env.production`, and `backend/db/schema.rb`. `approved` merges the GitHub PR. `completed` and `canceled` stay on the board; the manager does not start agents for them.

## Verify

1. `git remote -v` shows GitHub `origin` and `upstream`, no Codeberg remotes, and an unchanged `deployment` remote if the app has one. `git config remote.upstream.tagOpt` is `--no-tags`.
2. `gh` can create a PR against `origin`.
3. `mise test` passes without `EDITOR` set.
4. Every local tag is on `master`, and none match Code Moto's tags.
5. One Linear smoke card can move through the board without using team `MOTO`.

Later updates: `$merge` in the app, or `$merge-all` from `codemoto.org`. Never rebase, `mise rebase`, or force-push a downstream merge.
