# AGENTS.md

## Code Moto

This repo is based on Code Moto. Code Moto is a basis/template repository that provides tools and patterns for downstream repositories. From a downstream repository, the basis repository is typically available at `../CodeMoto`. If the current repository is named `CodeMoto`, changes affect the Code Moto framework itself.

Repositories based on Code Moto may omit components or add their own. Backport broadly useful tools and changes to `CodeMoto` when practical.

The "Repo Specific" section blow contains rules specific to this repo only.

## Project Rules

1. Do not introduce bugs or regressions.
2. Before writing code, find analogous code in the repository and follow its established patterns.
3. Do not add comments to code. Preserve existing comments unless they are incorrect or obsolete.
4. Check code changes with `mise test`, which runs every test suite and type check. There is no lint task or linter config, so do not run linters such as RuboCop or ESLint.
5. Use root `mise` tasks instead of invoking underlying tools directly when an applicable task exists.
6. Give every task in the root `mise.toml` a `description` so `mise tasks` lists what it does.
7. Do not create a canvas or visualization unless the user specifically requests one.
8. Mr. Moto copies the main checkout's `.env.*` files into the card worktrees it opens, so do not copy them again. Copy `.env.development` and `.env.production` from the main checkout only into a worktree you open some other way, before running tests or mise tasks.
9. All code changes and other changes to tracked repository files need a PR, pushed with `mr push` and opened with `mr pr create`. Operations without tracked repository changes need no PR, empty commit, or branch. Never commit to or push `master`, and never make repository changes outside the PR flow.
10. Work from `origin/master`: start branches from it, and do not rely on local `master` being current.
11. If you spend significant time unnecessarily or the instructions misdirect you, and the issue could be backported to Code Moto (`CodeMoto` / MOTO), report it with enough detail for Mr. Moto to track the basis-repository follow-up. Keep app-specific issues separate.
12. On macOS, run root `mise` tasks from the worktree root in a non-login shell. For Codex `exec_command`, set `login: false` explicitly on each call that runs `mise`, including through wrappers. If Bundler reports system Ruby or a missing Bundler version, check tool resolution and retry the same root task this way before changing dependencies. Confirm the pinned tools with `mise which ruby` and `mise which bundle`; do not install gems into system Ruby, change lockfiles, or downgrade pinned versions to fix a shell-resolution failure. Agent shells on macOS run zsh, not bash: quote globs and URLs containing `?`, do not rely on unquoted variables splitting into words, remember that zsh arrays start at 1, and run bash scripts with `bash -c` or as a file with a bash shebang.
13. `AGENTS.md` is the only agent-instruction file. Do not add `.agents/`, `.claude/`, `.codex/`, or `CLAUDE.md`; put repeatable operations in `runbooks/`.

## API

- The backend API is one GraphQL endpoint, `POST /graphql` on the `api` subdomain, built with graphql-ruby in `backend/app/graphql` around `AppSchema` and open to introspection.
- Every root field in `Types::QueryType` and `Types::MutationType` declares `access:`, either `:public` or `:user`. `:user` takes `Authorization: Bearer` with either the 7-day JWT from the `createToken` mutation, refreshed in the `refresh-token` response header, or the user's non-expiring API token from `createApiToken`, formatted `<prefix>_<user id>_<secret>` and stored as a bcrypt digest. Changing the password or calling `User#revoke_tokens!` invalidates the user's JWTs and deletes the API token. The prefix is `apiTokenPrefix` in `config.json`, or `database` when that is unset.
- Raise `GraphQL::ExecutionError` with an `extensions.code` such as `NOT_FOUND`, `INVALID`, `UNAUTHENTICATED`, or `RATE_LIMITED` for expected failures, and limit public fields with `RateLimit`.
- Batch associations and counts with `GraphQL::Dataloader` instead of loading them per object.
- Frontends call the API through `gql` in `frontend/utils/req.ts` with Zod-validated responses.
- Add plain routes only for responses that are not JSON or callers that cannot send GraphQL, such as `GET /noop/ping` for deploy status.

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

## Production Logs

The droplet keeps its own logs and resource history; nothing is shipped elsewhere. Every service logs to the systemd journal at its real priority, so `journalctl -p err` finds errors: Rails as `api` and `job`, nginx errors as `nginx`, nginx access as `nginx_access` (one JSON object per request), and Postgres as `postgres`. Each error reported through `Rails.error`, including unhandled request and job exceptions, is one entry whose message holds `RAILS_ERROR ` followed by a JSON object with `type`, `message`, `fingerprint`, `severity`, `handled`, `source`, `request_id`, `job_class`, `job_id`, and `backtrace`. The GraphQL API answers failed sign-ins and rate limits with HTTP 200, so `nginx_access` cannot show them; each is one `api` warning whose message holds `AUTH_FAILURE ` followed by a JSON object: `bad_credentials` with `operation`, `ip`, and the normalized `email`, or `rate_limited` with the `limit` name, its `key` (an IP or email), `count`, and `to`. Passwords are never logged. `sar` keeps 28 days of per-minute CPU, load, memory, disk, and network history. Query both read-only with `mise deploy:cmd`.

## Apple Workflow

- `mise test` runs the Apple app package tests in `apps/apple/Tests`, which compile the non-UI files listed in `Tests/Package.swift` into the `<Name>Core` target (`AppCore` in Code Moto), tested by `<Name>CoreTests` in Swift 5 language mode. Add new business-logic files to its `sources` and app-only files to its `exclude`.
- Use `mise simulate macos` to build and launch the Debug app and `mise xcode` to open the project macOS Debug builds use the configured bundle ID with a `.debug` suffix and a "Debug" display name so they run beside the installed app, and `mise simulate macos` quits only the Debug build it launched. In a linked worktree, such as a card worktree, the suffix and display name also carry the worktree's name, such as `.debug.moto-12` and "Debug moto-12", so each worktree's Debug build has its own defaults and `mise app:debug` reaches only the build from its own worktree. Derive any support directory a Debug build writes from `Bundle.main.bundleIdentifier`, not a fixed name, so parallel worktrees do not share files.
- Screen capture is not available to agents. To check UI, run the macOS Debug build and use `mise app:debug` with the `DebugHooks` commands, for example `mise app:debug "snap|/tmp/app.png"`, then read the PNG. `mise app:debug` waits for the app to finish each command and exits nonzero with the app's error when the command fails or the app is not running, so chain commands with `&&` and do not hide their output. Debug builds compile with `APP_DEV` and may write under `/tmp`. Commands do not activate the app or order windows front. Pass `DebugHooks.install` a closure to handle app-specific commands; throw `DebugHooks.Failure` from it to report an error. `DebugHooks` is macOS only; for iOS and tvOS simulators, use `xcrun simctl io booted screenshot /tmp/app.png`.

## Session instructions

Use `origin` as the sole workflow repository remote, preserving its hosting provider and actual default branch. A Code Moto basis remote named `codemoto` and an optional `deployment` remote may also be present. Do not add mirrors or alternate origin names. Fetch before updating default branches, use fast-forward-only pulls, and never force-push a default branch.

For card work, use Mr. Moto's `mr` CLI: run `mr card claim <CARD>` and follow its output, and see `mr --help` for the rest. This repository provides implementation instructions, checks, and operation tooling.

## File Structure

- `runbooks/` - Project operation instructions, such as deployment and publishing.
- `.env.template` - Template for the `.env.*` secret files: every key they hold across all environments, sorted one per line, each with a single-quoted hint for agents instead of a value.
- `.env.*` - Gitignored secrets, identifiers issued or rotated with them, and `RAILS_ENV`/`NODE_ENV`. Do not expose secret values. Mr. Moto generates them from 1Password with its `secrets` command; each item stores one concealed field per env key, labeled with the key name, the file lists the item's keys sorted, and the template, the items, and the files hold the same keys, with empty values allowed. Check them with `mr secrets keys`, never by reading the files.
- `.env.default` (history only) - Commit `d3e848a`, shared by every downstream repository, tracked an `.env.default` whose `DEPLOY_SSH_KEY`, `DEPLOY_SSH_KEY_PUB` (ed25519, `SHA256:yNlp6uQPJPIQgRn+vEgUlY4te/Hbwv4B6ymdtKuwEgg`), and `DEPLOY_PASSWORD` were examples never used on any host or account. They are not exposed secrets: do not report them or ask to rotate them or rewrite history.
- `apps/` - Mobile apps for iOS and Android.
- `assets/` - Shared images and media.
- `backend/` - Ruby on Rails API server.
- `config.json` - Non-secret configuration, including mobile app release (`apps`) and subdomain (`subdomains`) settings. Code reads it directly instead of `ENV`. Each subdomain entry has a required `source`: `website` (the Astro site on Cloudflare Workers), `frontend` (a React site in `frontend/subdomains/<name>` served from the droplet), or `backend` (Rails on the droplet). The default layout puts the website at the apex and `www`, the React app at `app`, and the Rails API at `api`. A config with only `website` entries needs no droplet. A `frontend` entry may list `backendPaths`, nginx location matches such as `"/.well-known/"` or `"~ ^/(mcp|oauth/)"` that its server proxies to Rails instead of serving the React app. Deploy sends HSTS, `nosniff`, a referrer policy, and a same-origin Content Security Policy with the React app's responses but not with those Rails paths; a `frontend` entry's optional `contentSecurityPolicy` string replaces that policy, for example to allow an external font host. Optional `redirectDomains` lists other domains that `mise deploy` 301-redirects to `domain` through Cloudflare, keeping the path and query; deploy replaces each redirect zone's Single Redirect rules. Deploy adds Fastmail MX, DKIM, and SPF (`~all`) records and a `p=quarantine` DMARC record sending reports to `dmarc@` at the same domain to `domain` and every redirect domain, replacing any other SPF or DMARC record there. Optional `resendDomains` lists the domains that also send through Resend, each `{ "domain", "region", "dkimPublicKey" }` with the region and the `resend._domainkey` TXT value copied from the Resend dashboard; deploy adds that domain's `send` MX and SPF records and the Resend DKIM record, and replaces them when the config changes. Deploy writes the droplet one `.env`, mode 0600, holding `.env.production` without the keys and globs listed in the required `operatorOnlyEnvKeys`, which only the operator machine reads. Code Moto lists `APPLE_*`, `CLOUDFLARE_TOKEN`, `DEPLOY_PASSWORD`, `DEPLOY_SSH_KEY_*`, and `DIGITAL_OCEAN_TOKEN`; a project adds its own operator-only keys or removes any its droplet needs. Never list a key the app reads at runtime.
- `deploy/` - Backend and frontend deployment tooling. On the droplet, the `api` and `job` services, migrations, `mise runner:production`, and the production console run as the unprivileged `app` user, which has no sudo or SSH keys, owns the production database, and can write only `backend/tmp`, `backend/storage`, `backend/log`, and its home. The passwordless-sudo deploy user runs everything else.
- `docs/` - Project documentation in Markdown.
- `frontend/` - React frontend sites served from the droplet.
- `gems/` - Shared Ruby gems.
- `website/` - Astro marketing website, deployed to Cloudflare Workers by `mise deploy`.
- `manager/` - Project tooling for spawning new apps and Code Moto merges.
- `publish/` - Mobile app versioning, simulators, and App Store publishing. `mise keychain` restores the user keychain search list after a killed signing run and runs before `mise publish`; `mise keychain --repair` resets the login keychain, default keychain, and search list.
- `scripts/` - General-purpose scripts. `scripts/mise/` holds the scripts behind multi-line `mise.toml` tasks.
- `mise.toml` - Project tooling and task definitions.

## Runbooks

Read the relevant runbook when asked to perform an operation:

- [Deploy](runbooks/deploy.md) - Deploy `origin/master` to production and the website.
- [Publish](runbooks/publish.md) - Version and publish configured Apple apps, only when a release is requested.

Run `mise tasks` to discover available tasks and their descriptions, including development and production debugging tools.

## Repo Specific

### Deployment

This repository is deployed: `mise deploy` publishes only the Astro website in `website/` to Cloudflare Workers at `scampmicrodeck.com`, following the [deploy runbook](runbooks/deploy.md). `config.json` has only `website` subdomains, so there is no droplet; do not add `frontend` or `backend` subdomains, which would make `mise deploy` provision one on DigitalOcean.
