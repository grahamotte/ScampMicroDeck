---
name: publish
description: Version and publish Code Moto across its configured Apple targets, repository releases, and App Store Connect. Use only when the user explicitly invokes `$publish`, asks to use the publish skill by name, or a Linear card says to run the publish skill.
---

# Publish

The version branch is the card branch when running for a card, otherwise `publish-<version>`.

## Mode

The request or card chooses the mode. Default to a full publish.

- Full: prepare App Store versions and submit them for review with `mise publish`.
- Stop before submission: prepare App Store versions for review without submitting with `mise publish:stop_before_submit`.
- TestFlight only: upload builds without changing App Store versions, metadata, review details, or review submissions with `mise publish:stop_before_prepare`.

## Version

1. Require a clean worktree. Run `git fetch origin` and create the version branch from `origin/master`. Read the `apps` section of `config.json` for the current version and configured targets.
2. Review the commits since the most recent commit named `Version` and choose the smallest appropriate semantic version bump from the current configured version: major for breaking changes, minor for new user-facing capabilities, and patch for everything else. Ask before a major bump. A publish request permits a patch release when there are no notable changes.
3. Run `mise publish:approved_version` to find the latest version actually approved by App Store Connect. Find the `Version` commit that set that approved version and review every subsequent change when writing `whatsNew`, including changes already included in newer unapproved versions. If no approved version exists, review changes from the beginning of the repository. Write a concise, user-facing summary based on that full range, using `Bug fixes.` when nothing user-facing is notable.
4. Run `mise publish:set_version <version>` and `mise test`, then commit only the version files with the message `Version`.
5. Push with `git push -u origin HEAD:<branch>`, open a PR with `gh pr create --head <branch>`, and merge it with `gh pr merge --merge --delete-branch`.

## Release

1. Run `git fetch origin` and `git checkout --detach origin/master`. The publish tasks refuse to run unless the worktree is clean and `HEAD` is `origin/master`.
2. Run the publish task for the mode and follow it until every configured target finishes. Let the task perform its own stages; do not reproduce stages manually or edit its cache. If App Store Connect is still processing a build, wait and rerun the same command so it can resume.
3. If `origin/master` moves past the `Version` merge before the publish finishes, stop and report it instead of publishing a different commit.
4. If anything else fails, stop publishing and help the user diagnose it before proceeding. Make the failure immediately clear, focus on the error and its impact, inspect the relevant logs and state, and work with the user on recovery instead of presenting a routine release summary.
5. When publishing succeeds, briefly report the version, release notes, version PR, repository releases, and App Store status for each target.

The macOS revision is signed, notarized, and released through GitHub. Other Apple targets are distributed through App Store Connect. Report stop-before-submission builds as prepared for review, not submitted, and TestFlight-only builds as uploaded for TestFlight, not prepared or submitted for review.

## Linear card

Record the result on the card that invoked this skill. Complete the card only when its whole task is done; otherwise continue with its remaining work.

- Link the version PR to the card.
- On success, comment with the release report.
- When blocked, comment with the failure, its impact, and the state publishing stopped in, then move the card to `planned`.
