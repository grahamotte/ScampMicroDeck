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
3. Run `mise publish:approved_version` to find the latest version actually approved by App Store Connect, or, when `skip_app_stores` is set, the latest version released to the project's repository. Find the `Version` commit that set that approved version and review every subsequent change when writing `whatsNew`, including changes already included in newer unapproved versions. If it prints `none`, review changes from the beginning of the repository. Write a concise, user-facing summary based on that full range, using `Bug fixes.` when nothing user-facing is notable.
4. Run `mise publish:set_version <version>` and `mise test`, then commit only the version files with the message `Version`.
5. Deliver the version commit through the supplied repository review instructions and hand off Review with the selected publish mode and release commands as remaining work. The Approved session releases only after the version PR has been merged and verified.

## Release

1. Run `git fetch origin` and `git checkout --detach origin/master`. The publish tasks refuse to run unless the worktree is clean and `HEAD` is `origin/master`.
2. Run the publish task for the mode and follow it until every configured target finishes. Let the task perform its own stages; do not reproduce stages manually or edit its cache. If App Store Connect is still processing a build, wait and rerun the same command so it can resume.
3. If `origin/master` moves past the `Version` merge before the publish finishes, stop and report it instead of publishing a different commit.
4. If anything else fails, stop publishing and help the user diagnose it before proceeding. Make the failure immediately clear, focus on the error and its impact, inspect the relevant logs and state, and work with the user on recovery instead of presenting a routine release summary.
5. On macOS, when `apps.homebrew` is configured and the app's cask is installed on this Mac (`brew list --cask grahamotte/tap/TOKEN`, where `TOKEN` is the app's `name` lowercased, with each run of other characters replaced by `-`), update it: run `brew update`, then `brew upgrade --cask grahamotte/tap/TOKEN`. If the app was running, quit it with `osascript -e 'quit app "NAME"'` and reopen it with `open -a "NAME"`.
6. When publishing succeeds, briefly report the version, release notes, version PR, repository releases, and App Store status for each target.

The macOS revision is signed, notarized, and released to the project's repository through Mr. Moto's `mr release`, run in the main checkout; `mr` must be on PATH. When `apps.homebrew` is configured, publishing then updates the app's Homebrew cask through `mr cask`. Other Apple targets are distributed through App Store Connect. Report stop-before-submission builds as prepared for review, not submitted, and TestFlight-only builds as uploaded for TestFlight, not prepared or submitted for review.

## Results

Report the version PR and release result. When blocked, report the failure, its impact, and the state publishing stopped in.

## Finishing

Every card that runs this runbook finishes with the comment, push, and move steps from the start of the session's prompt. This section overrides where the status prompt says to move the card.

Record results on the invoking card when present. In a work session, move successful work to Review even when no tracked changes or PR are needed; explicitly record "No PR needed" and "Remaining work: none" when applicable. The Approved session finishes any remaining steps, then completes the card. When blocked, report what is needed and move the card to Planned.
