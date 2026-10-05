# AGENTS.md

## Code Moto

This repo is based on Code Moto. Code Moto is a basis/template repository that provides tools and patterns for downstream repositories. From a downstream repository, the basis repository is typically available at `../CodeMoto`. If the current repository is named `CodeMoto`, changes affect the Code Moto framework itself.

Repositories based on Code Moto may omit components or add their own. Backport broadly useful tools and changes to `CodeMoto` when practical.

The "Repo Specific" section blow contains rules specific to this repo only.

## Project Rules

1. Do not introduce bugs or regressions.
2. Before writing code, find analogous code in the repository and follow its established patterns.
3. Do not add comments to code. Preserve existing comments unless they are incorrect or obsolete.
4. Lint, type-check, and test code changes using the tasks defined in the root `mise.toml`.
5. Use root `mise` tasks instead of invoking underlying tools directly when an applicable task exists.
6. Do not create a canvas or visualization unless the user specifically requests one.
7. When opening a git worktree, copy `.env.development`, `.env.production`, and `backend/db/schema.rb` from the main checkout into the worktree before running tests or mise tasks.
8. All code changes and other changes to tracked repository files need a PR through the launch prompt's supplied commands. Operations without tracked repository changes need no PR, empty commit, or branch. Never commit to or push `master`, and never make repository changes outside the PR flow.
9. Work from `origin/master`: start branches from it, and do not rely on local `master` being current.
10. If you spend significant time unnecessarily or the instructions misdirect you, and the issue could be backported to Code Moto (`CodeMoto` / MOTO), report it with enough detail for Mr. Moto to track the basis-repository follow-up. Keep app-specific issues separate.
11. On macOS, run root `mise` tasks from the worktree root in a non-login shell. For Codex `exec_command`, set `login: false` explicitly on each call that runs `mise`, including through wrappers. If Bundler reports system Ruby or a missing Bundler version, check tool resolution and retry the same root task this way before changing dependencies. See [macOS agent task execution](docs/manager.md#macos-agent-task-execution).

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

## Session instructions

Follow the launch prompt for task scope, card access, review, and handoff commands. This repository provides implementation instructions, checks, and operation tooling. The launch prompt supplies the session workflow; do not search another repository for workflow instructions.

## File Structure

- `.agents/skills/` - Project-specific agent skills.
- `.claude/skills` - Symlink to `.agents/skills/` for Claude Code.
- `.env.default` - Template for the `.env.*` secret files.
- `.env.*` - Gitignored secrets, identifiers issued or rotated with them, and `RAILS_ENV`/`NODE_ENV`. Do not expose secret values. Mr. Moto generates them from 1Password with its `secrets` command; each item stores one concealed field per env key, labeled with the key name, and the file follows the `.env.default` layout with extra keys at the end.
- `apps/` - Mobile apps for iOS and Android.
- `assets/` - Shared images and media.
- `backend/` - Ruby on Rails API server.
- `config.json` - Non-secret configuration, including mobile app release (`apps`) and website subdomain (`subdomains`) settings. Code reads it directly instead of `ENV`.
- `deploy/` - Backend and frontend deployment tooling.
- `docs/` - Project documentation in Markdown.
- `frontend/` - React website.
- `gems/` - Shared Ruby gems.
- `manager/` - Project tooling for spawning new apps and Code Moto merges.
- `publish/` - Mobile app versioning, simulators, and App Store publishing.
- `scripts/` - General-purpose scripts. `scripts/mise/` holds the scripts behind multi-line `mise.toml` tasks.
- `mise.toml` - Project tooling and task definitions.

## Repo Specific

None.
