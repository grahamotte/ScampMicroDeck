---
name: deploy
description: Deploy `origin/master` to production. Use only when the user explicitly invokes `$deploy`, asks to use the deploy skill by name, or a Linear card says to run the deploy skill.
---

# Deploy

`mise deploy` fetches `origin` and deploys `origin/master`, whatever is checked out locally. Only merged changes are deployed.

1. Read the Repo Specific section of this repository's `AGENTS.md`. Continue only if it states that the repository is deployed. If it states that the repository is not deployed, or says nothing about deployment, do not run `mise deploy`: hand off Planned (or Review with "deploy not applicable" when the card only asked for a conditional deploy) and say the repository does not deploy. A missing or placeholder `DIGITAL_OCEAN_TOKEN` means the repository is not deployed; it is not an expired token.
2. Run `mise deploy`. It takes several minutes. It prints `deploying origin/master <sha>`; record the SHA.
3. If it fails because of a trivial problem in the repository, fix it through a PR:
   - Work on the card branch when running for a card, otherwise on a new branch from `origin/master`.
   - Run `mise test` and deliver the fix through the supplied repository review instructions.
   - Link the fix PR to the deploy card.
   - Hand off Review with the fix PR and `mise deploy` retry as remaining work. The Approved session retries only after the fix PR has been merged and verified.
4. If a failure is not trivial, or is outside the repository (server, DNS, provider, credentials), stop. Do not work around it with manual server changes. Make the failure and its impact immediately clear, with the relevant log output from `deploy/log/`.
5. When the deploy succeeds, report the deployed SHA, any PRs merged along the way, and anything notable from the run.

## Results

Report the deployed SHA and any fix PRs. When blocked, report the failure and what is needed to unblock it. Record results on the invoking card when present. In a work session, hand off successful work to Review even when no tracked changes or PR are needed; explicitly record "No PR needed" and "Remaining work: none" when applicable. The Approved session finishes any remaining steps, then completes the card. When blocked, hand off Planned with `mr handoff planned`.
