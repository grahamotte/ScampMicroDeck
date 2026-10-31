# Deploy

`mise deploy` fetches `origin` and deploys `origin/master`, whatever is checked out locally. It provisions and updates the droplet when `config.json` has `frontend` or `backend` subdomains, builds the Astro website and deploys it to Cloudflare Workers when it has `website` subdomains, and sets up Cloudflare redirects for any `redirectDomains`. It adds Fastmail mail records to the domain and each redirect domain on every deploy. Only merged changes are deployed.

1. Read the Repo Specific section of this repository's `AGENTS.md`. Continue only if it states that the repository is deployed. If it states that the repository is not deployed, or says nothing about deployment, do not run `mise deploy`: hand off Planned (or Review with "deploy not applicable" when the card only asked for a conditional deploy) and say the repository does not deploy. When `config.json` has `frontend` or `backend` subdomains, a missing or placeholder `DIGITAL_OCEAN_TOKEN` means the repository is not deployed; it is not an expired token.
2. Run `mise deploy`. It takes several minutes. It prints `deploying origin/master <sha>`; record the SHA. With `website` subdomains it also prints `deploying website origin/master <sha>`.
3. If it fails because of a trivial problem in the repository, fix it through a PR:
   - Work on the card branch when running for a card, otherwise on a new branch from `origin/master`.
   - Run `mise test` and deliver the fix through the supplied repository review instructions.
   - Link the fix PR to the deploy card.
   - Hand off Review with the fix PR and `mise deploy` retry as remaining work. The Approved session retries only after the fix PR has been merged and verified.
4. If a failure is not trivial, or is outside the repository (server, DNS, provider, credentials), stop. Do not work around it with manual server changes. Make the failure and its impact immediately clear, with the relevant log output from `deploy/log/`.
5. When the deploy succeeds, report the deployed SHA, any PRs merged along the way, and anything notable from the run.

## Website

The website deploy (`WebsitePatch`) uses `CLOUDFLARE_TOKEN`, which needs Zone DNS Edit, Workers Scripts Edit, and Workers Routes Edit permissions. The domain's zone must be active on Cloudflare; if the deploy creates the zone, the registrar's nameservers must be pointed at Cloudflare before the custom domains work. It removes unproxied A, AAAA, and CNAME records on the website hosts so Workers custom domains can claim them, and `DnsPatch` leaves those hosts alone.

## New Hostnames

Do not look up a hostname before the deploy that creates it. Resolvers, including macOS's, cache the miss, and checks after the deploy keep failing until it expires; flushing the macOS cache needs a password agents do not have. After the deploy, check every configured subdomain, including `www`, against the zone's own nameservers, which never cache: find one with `dig +short NS DOMAIN`, then run `dig @NAMESERVER HOST`, and check the site with `curl --resolve HOST:443:IP https://HOST` using an address it returned.

## Results

Report the deployed SHA and any fix PRs. When blocked, report the failure and what is needed to unblock it.

## Finishing

Every card that runs this runbook finishes with the comment, push, and move steps from the start of the session's prompt. This section overrides where the status prompt says to move the card.

Record results on the invoking card when present. In a work session, move successful work to Review even when no tracked changes or PR are needed; explicitly record "No PR needed" and "Remaining work: none" when applicable. The Approved session finishes any remaining steps, then completes the card. When blocked, report what is needed and move the card to Planned.
