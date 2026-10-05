# Scamp Micro Deck

Scamp Micro Deck is a native macOS music player for local folders of audio files, designed to mimic the tedious charm of a real vinyl record player.

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="assets/screenshot-2.png" alt="Scamp Micro Deck screenshot">
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/scamp-micro-deck/id6761630397?mt=12">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/en-us?size=250x83&releaseDate=1775001600" alt="Download on the Mac App Store" height="40">
  </a>
</p>
<!-- markdownlint-enable MD033 -->

This repository is based on Code Moto. It keeps its own Git history and configuration, and merges foundation updates with the merge skill. Code Moto brings a Rails API, a React website, native Apple apps, and project tooling into one checkout so projects can share the same development, testing, deployment, and release workflow.

## What's included

- **App:** A Swift macOS player for local audio folders, with simulator and Mac App Store publishing tools.
- **Backend:** Ruby on Rails with PostgreSQL and GoodJob background jobs.
- **Frontend:** React, TypeScript, Vite, and Tailwind CSS, with separate sites for configured subdomains.
- **Operations:** Server provisioning and deployment, backups, and shared Ruby gems.

## Local development

Install mise and PostgreSQL, and have PostgreSQL running locally. Apple app development and tests also require macOS with Xcode.

1. Run `mise install` to install the tool versions pinned in `mise.toml`.
2. Create `.env.development` and `.env.production` from `.env.default` and fill in the required values. Projects registered in Mr. Moto with 1Password references can generate them with Mr. Moto's `mise secrets <project>` instead.
3. Run `mise dependencies` to install project dependencies.
4. Run `mise db:migrate` to prepare the development database.
5. Run `mise start` to start the API, background jobs, and frontend sites. It prints the local URLs; the API runs at `http://localhost:3000`.

Non-secret project settings live in `config.json`, including the domain, GitHub repository, database name, subdomains, and app release details. Application credentials live in the gitignored `.env.*` files. GitHub release artifact publishing uses `GITHUB_TOKEN` from `.env.production`. Linear and GitHub/Forgejo PR operations use the central commands supplied by Mr. Moto; repository-local tokens are not supported.

## Common commands

| Command | Purpose |
| --- | --- |
| `mise test` | Run all test suites, including frontend type checking |
| `mise tsc` | Type-check the frontend |
| `mise console` | Open the Rails development console |
| `mise simulate macos` | Build and launch the macOS app |
| `mise xcode` | Open the Apple app project |
| `mise publish:set_version 1.5.0` | Update release and Xcode versions |
| `mise publish` | Archive, upload, submit, notarize, and publish a release |

`mise publish` uses the App Store Connect, signing certificate, Codeberg, and GitHub credentials in the ignored `.env.production` file.

Deployment, basis merges, and publishing use the project-specific instructions in [.agents/skills](.agents/skills). Mr. Moto owns card tracking, enqueueing, and the review workflow.

## Repository guide

| Directory | Contents |
| --- | --- |
| `apps/` | Native macOS app and screenshots |
| `backend/` | Rails API and background jobs |
| `frontend/` | React sites and shared frontend code |
| `gems/` | Shared Ruby libraries |
| `deploy/` | Infrastructure and deployment tooling |
| `publish/` | App versioning, simulation, and publishing |
| `manager/` | Secrets refresh, project creation, and Code Moto merges |
| `scripts/` | Scripts behind mise tasks |

See [manager](docs/manager.md) for how Code Moto works with Mr. Moto, [Apple credentials](docs/apple-credentials.md) for publishing setup, and [AGENTS.md](AGENTS.md) for contribution rules.

## Contributing

Issues and PRs welcome.

## License

MIT
