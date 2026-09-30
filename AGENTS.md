# AGENTS.md

## Code Moto

This repo is based on Code Moto. Code Moto is a basis/template repository that provides tools and patterns for downstream repositories. From a downstream repository, the basis repository is typically available at `../codemoto.org`. If the current repository is named `codemoto.org`, changes affect the Code Moto framework itself.

Repositories based on Code Moto may omit components or add their own. Backport broadly useful tools and changes to `codemoto.org` when practical.

The "Repo Specific" section blow contains rules specific to this repo only.

## Project Rules

1. Do not introduce bugs or regressions.
2. Before writing code, find analogous code in the repository and follow its established patterns.
3. Do not add comments to code. Preserve existing comments unless they are incorrect or obsolete.
4. Lint, type-check, and test code changes using the tasks defined in the root `mise.toml`.
5. Use root `mise` tasks instead of invoking underlying tools directly when an applicable task exists.
6. Do not create a canvas or visualization unless the user specifically requests one.
7. When opening a git worktree, copy `.env.development`, `.env.production`, and `backend/db/schema.rb` from the main checkout into the worktree before running tests or mise tasks.
8. Every change needs a Linear card and a GitHub PR, including operations such as deploys, merges, and publishes. If there is no card, create one first. Never commit to or push `master`, and never make changes outside that flow.
9. Work from `origin/master`: start branches from it, and do not rely on local `master` being current.
10. If you spend significant time unnecessarily or the instructions misdirect you, and the issue could be backported to Code Moto (`codemoto.org` / MOTO), search the MOTO backlog (`mise linear issues search "<issue>" --team MOTO --status Backlog`). If a matching card exists, comment with a brief summary of your experience. Otherwise create a MOTO backlog card. Do not file app-specific issues that cannot be backported.

## Ruby

- Use `.blank?` and `.present?` for presence checks instead of `.empty?`, `.nil?`, or truthiness checks.
- Do not use `sleep`; use an event- or state-based approach instead.
- Add trailing commas to multiline argument lists and collections.

## TypeScript

- Treat nullable values as both `null` and `undefined`; use `nullish()` in Zod schemas and check for both states.
- Use `pnpm`, not `npm`.
- Use `mise tsc` to type-check.
- Prefer Lodash utilities over custom equivalents when Lodash is already available.
- Use shadcn/ui components.
- Use Tailwind CSS for styling.

## Testing

- Never run network requests, system commands, or application sleeps in tests. Stub those boundaries every time.
- Do not stub other units in a unit test. Only stub network requests, system commands, and sleeps so the real local collaborators and full local surface are exercised together.
- Every business-logic file must have one corresponding unit test file. Source and test files are 1:1.
- Test each business-logic unit thoroughly. Configuration, generated files, framework shells, and other files without business logic do not need tests.
- After every code change, run the whole suite with `mise test`.
- Do not write integration tests.

## Linear

Work items are cards in Linear. Use `mise linear <args>`, which runs the [Linearis](https://github.com/linearis-oss/linearis) CLI with `LINEAR_TOKEN`; see `mise linear usage` for commands. Do not use Linear MCP tools. Refer to cards by identifier, for example `MOTO-1`. The default team is `linear.team` in `config.json`; pass `--team <key>` where a command needs one.

Columns, in order: `Backlog`, `Planned`, `Ready`, `Working`, `Review`, `Approved`, `Completed`, `Canceled`.

Tags (pass them by id, not name, since Linearis does not resolve tag names per team):

- `working`: the manager's agent is processing the card. Only add or remove it when a manager prompt tells you to.
- `skip review`: the manager's work agent still creates and links a PR, then merges it, completes the card, and removes its worktree without waiting for review.
- `runner: interactive`: the card is worked with the user instead of by the manager. The manager does not pick it up from `ready`, but still merges it from `approved`.

When the user hands you a Linear card, use the `interactive-card` skill, unless the prompt says the manager runs the card.

Operations are skills, and their cards name the skill to run: `deploy`, `merge`, and `publish`. Each skill finishes its own card and merges its own PRs; `mise deploy`, `mise merge`, and `mise publish` all work from `origin/master`.

## GitHub

Open pull requests on GitHub with `gh`, using `GITHUB_TOKEN` from the environment. `gh` targets `origin`, the app repo from `githubRepo` in `config.json`, never `codemoto`: `mise merge` sets `origin` as the `gh` default, and the `mise` env exports it as `GH_REPO`.

- Push the branch, then `gh pr create`.
- Merge with `gh pr merge`.

## File Structure

- `.agents/skills/` - Project-specific agent skills.
- `.claude/skills` - Symlink to `.agents/skills/` for Claude Code.
- `.env.default` - Template for the `.env.*` secret files.
- `.env.*` - Gitignored secrets, identifiers issued or rotated with them, and `RAILS_ENV`/`NODE_ENV`. Do not expose secret values.
- `.env.service` - Gitignored 1Password service account token (`SERVICE_ACCOUNT_TOKEN`), read from the repository root or, if absent, `~/.config/projects/.env.service`. `mise manager:secrets` uses it to pull every `secrets` key in `config.json` as `.env.<key>` from the `op://` secure note reference.
- `apps/` - Mobile apps for iOS and Android.
- `assets/` - Shared images and media.
- `backend/` - Ruby on Rails API server.
- `config.json` - Non-secret configuration, including mobile app release (`apps`) and website subdomain (`subdomains`) settings. Code reads it directly instead of `ENV`.
- `deploy/` - Backend and frontend deployment tooling.
- `docs/` - Project documentation in Markdown.
- `frontend/` - React website.
- `gems/` - Shared Ruby gems.
- `manager/` - Linear issue polling, agent triggers, secrets, and spawning new apps.
- `publish/` - Mobile app versioning, simulators, and App Store publishing.
- `scripts/` - General-purpose scripts. `scripts/mise/` holds the scripts behind multi-line `mise.toml` tasks.
- `mise.toml` - Project tooling and task definitions.

## Repo Specific

None.
