---
name: deploy
description: Deploy `origin/master` to production. Use only when the user explicitly invokes `$deploy`, asks to use the deploy skill by name, or a Linear card says to run the deploy skill.
---

# Deploy

`mise deploy` fetches `origin` and deploys `origin/master`, whatever is checked out locally. Only merged changes are deployed.

1. Run `mise deploy`. It takes several minutes. It prints `deploying origin/master <sha>`; record the SHA.
2. If it fails because of a trivial problem in the repository, fix it through a PR:
   - Work on the card branch when running for a card, otherwise on a new branch from `origin/master`.
   - Run `mise test`, commit, push, and create or reuse and link a PR through Mr. Moto's configured forge adapter as described under Pull Requests in `AGENTS.md`.
   - Link the fix PR to the deploy card.
   - Inspect the PR head SHA and checks, merge it through Mr. Moto's `mise pr` with the explicit number and verified SHA, confirm the merged state, then run `mise deploy` again.
3. If a failure is not trivial, or is outside the repository (server, DNS, provider, credentials), stop. Do not work around it with manual server changes. Make the failure and its impact immediately clear, with the relevant log output from `deploy/log/`.
4. When the deploy succeeds, report the deployed SHA, any PRs merged along the way, and anything notable from the run.

## Linear card

Every tracked change uses the configured forge PR workflow in `../mr-moto/docs/workflow.md`. Existing open PRs are reused; a merged PR is never reused for subsequent tracked changes. In a manager work session, stop at Review and list merge-dependent steps for the Approved agent, unless `skip review` authorizes merging. Credentials remain in private configuration or the environment.

Record the result on the card that invoked this skill. Complete the card only when its whole task is done; otherwise continue with its remaining work.

- On success, comment with the deployed SHA and any PRs merged.
- When blocked, comment with the failure and what is needed to unblock it, then move the card to `planned`.
