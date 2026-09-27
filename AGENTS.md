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

Work items are cards in Linear. Use the `mise linear:*` tasks, which call the Linear API with `LINEAR_TOKEN`, `LINEAR_WORKSPACE`, and `LINEAR_TEAM` from the environment. Do not use Linear MCP tools. Refer to cards by identifier, for example `MOTO-1`; take it from the card URL if given one.

Columns, in order: `backlog`, `planned`, `ready`, `working`, `review`, `approved`, `completed`, `canceled`.

- Create a card: `mise linear:create "<title>" "<markdown body>" [--column backlog] [--parent MOTO-1]`
- Read a card, its links, comments, children, and relations: `mise linear:show MOTO-1`
- Print only the description markdown: `mise linear:show MOTO-1 --raw`
- List cards: `mise linear:list [--column ready] [--tag working] [--search query]`
- Move a card: `mise linear:move MOTO-1 review`
- Edit title, description, or fields: `mise linear:edit MOTO-1 [--title "<t>"] [--body "<markdown>"|--body-file <path>] [--expect-file <path>|--expect-hash <sha256>] [--priority high] [--estimate 3] [--assignee me] [--due 2026-10-01] [--project "<name>"] [--parent MOTO-1]`
- Clear fields: `mise linear:edit MOTO-1 --clear-priority --clear-estimate --clear-assignee --clear-due --clear-project --clear-parent`
- Comment: `mise linear:comment MOTO-1 "<markdown>"` or `mise linear:comment MOTO-1 --body-file <path> [--reply <comment-id>]`
- Edit your comment: `mise linear:comment-edit <comment-id> "<markdown>"`
- Delete your comment: `mise linear:comment-delete <comment-id>`
- Link a PR: `mise linear:link MOTO-1 <url> "<title>"` (succeeds if the URL is already attached)
- Remove a link: `mise linear:unlink MOTO-1 <url>`
- Tag a card: `mise linear:tag MOTO-1 <tag>`
- Untag a card: `mise linear:untag MOTO-1 <tag>`
- Relations: `mise linear:relate MOTO-1 blocks MOTO-2` (`blocks`, `blocked-by`, `related`, `duplicate`)
- Remove a relation: `mise linear:unrelate MOTO-1 MOTO-2`
- Other team in this workspace: pass `--team ME` instead of changing `LINEAR_TEAM`. Without it, cards outside `LINEAR_TEAM` are refused.

When updating a description, pass `--expect-file` (the previous `linear:show --raw` output) or `--expect-hash` (the `Description hash` from `linear:show`). The edit is refused if the card description changed since that read.

Linear normalizes markdown on write: `* [ ]` becomes `- [ ]`, bare domains are autolinked, and `~~` around code spans can be mangled. After `linear:edit`, check the stored description rather than assuming byte equality with what you sent. Long markdown should go through `--body-file` so the shell does not mangle it.

Tags:

- `working`: the manager's agent is processing the card. Only add or remove it when a manager prompt tells you to.
- `interactive`: the card is worked with the user instead of by the manager. The manager does not pick it up from `ready`, but still merges it from `approved`.

When the user hands you a Linear card, use the `interactive-card` skill, unless the prompt says the manager runs the card.

Operations are skills, and their cards name the skill to run: `deploy`, `merge`, and `publish`. Each skill finishes its own card and merges its own PRs; `mise deploy`, `mise merge`, and `mise deploy:publish` all work from `origin/master`.

## GitHub

Open pull requests on GitHub with `gh`, using `GITHUB_TOKEN` from the environment. `gh` targets `origin`, the app repo from `GITHUB_REPO`, never `upstream`: `mise merge` sets `origin` as the `gh` default, and the `mise` env exports it as `GH_REPO`.

- Push the branch, then `gh pr create`.
- Merge with `gh pr merge`.

## File Structure

- `.agents/skills/` - Project-specific agent skills.
- `.claude/skills` - Symlink to `.agents/skills/` for Claude Code.
- `.env.*` - Environment configuration and secrets. Do not expose secret values.
- `apps/` - Mobile apps for iOS and Android.
- `apps/config.json` - Mobile app release configuration.
- `assets/` - Shared images and media.
- `backend/` - Ruby on Rails API server.
- `deploy/` - Backend, frontend, and mobile app deployment tooling.
- `docs/` - Project documentation in Markdown.
- `frontend/` - React website.
- `frontend/subdomains.json` - Website subdomain configuration.
- `gems/` - Shared Ruby gems.
- `manager/` - Linear issue polling and agent triggers.
- `scripts/` - General-purpose scripts.
- `mise.toml` - Project tooling and task definitions.

## Repo Specific

None.
