---
name: deploy
description: Deploy `origin/master` to production. Use only when the user explicitly invokes `$deploy`, asks to use the deploy skill by name, or a Linear card says to run the deploy skill.
---

# Deploy

`mise deploy` fetches `origin` and deploys `origin/master`, whatever is checked out locally. Only merged changes are deployed.

1. Run `mise deploy`. It takes several minutes. It prints `deploying origin/master <sha>`; record the SHA.
2. If it fails because of a trivial problem in the repository, fix it through a PR:
   - Work on the card branch when running for a card, otherwise on a new branch from `origin/master`.
   - Run `mise test`, commit, push, and open a PR with `gh pr create`.
   - Link the fix PR to the deploy card.
   - Merge it with `gh pr merge --merge --delete-branch`, then run `mise deploy` again.
3. If a failure is not trivial, or is outside the repository (server, DNS, provider, credentials), stop. Do not work around it with manual server changes. Make the failure and its impact immediately clear, with the relevant log output from `deploy/log/`.
4. When the deploy succeeds, report the deployed SHA, any PRs merged along the way, and anything notable from the run.

## Linear card

Record the result on the card that invoked this skill. Complete the card only when its whole task is done; otherwise continue with its remaining work.

- On success, comment with the deployed SHA and any PRs merged.
- When blocked, comment with the failure and what is needed to unblock it, then move the card to `planned`.
