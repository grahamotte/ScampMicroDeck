# MOTO-67 downstream merge rollout

Created Ready merge cards for all seven Code Moto forks. Linear has no projects; the Personal team is not a fork. This records the rollout requested by [MOTO-67](https://linear.app/gotte/issue/MOTO-67/merge-all).

Reviewed Code Moto master at `f924ac739f0ac071cd371b6762c775b82280fe37`. All forks share merge base `886be10171aadab54aed4871f9ef8e5cb97c7a37`. Fetched each downstream origin and Code Moto upstream before comparing histories and running `git merge-tree --write-tree`. Trial merges did not change checkouts.

Every card invokes the merge skill and requests `agent.runner: t3` and `agent.model: openai/gpt-6.1-sol`, with no requested variant change. Each includes the incoming manager, labels, lifecycle, documentation, and T3 worktree changes from MOTO-62, MOTO-65, MOTO-66, and MOTO-68 through MOTO-73.

## Cards

### badgeonbar.com

[BOB-8](https://linear.app/gotte/issue/BOB-8/merge) — reviewed downstream master `f3c49b138dafdbaa2e01fc5857f868435b2f6e78`.

- Trial merge reports an add/add conflict in `README.md`: Badge On Bar has app introduction, screenshots, and signed/notarized GitHub release instructions; incoming Code Moto adds framework documentation.
- `AGENTS.md` has Badge On Bar architecture and release rules; `mise.toml` has `app:generate-assets`.

### freyaplayer.com

[FP-15](https://linear.app/gotte/issue/FP-15/merge) — reviewed downstream master `025c0a43ead79766ad3a8268b6f6ffa325a59f65`.

- Trial merge reports an add/add conflict in `README.md`: Freya Player has app introduction, screenshots, App Store links, and Apple workflow instructions; incoming Code Moto adds framework documentation.
- `AGENTS.md` has Freya Player architecture and playback rules. The downstream `.agents/skills/impeccable/` package is app-specific.

### good.gratis

[GG-48](https://linear.app/gotte/issue/GG-48/merge) — reviewed downstream master `534efd70b69fe48a8df6b0b2e62a1e332df25767`.

- Trial merge reports a modify/delete conflict in the customized ASCII-art `README.txt`, which Code Moto replaces with `README.md`.
- Trial merge reports a conflict in the `config.json` agent block: downstream uses `openchamber`, `xai/grok-4.7`, and variant `high`; incoming uses `t3`, `openai/gpt-6.1-sol`, and variant `medium`. The requested runner/model change does not request a variant change.
- `mise.toml` includes ingestion and sync tasks and an OpenCode tool entry. Downstream skills include grill, import-youtube-likes, prune-feeds, prune-streams, and triage-jobs.

### littlewhile_app

[LIT-29](https://linear.app/gotte/issue/LIT-29/merge) — reviewed downstream master `2daaad3eeeba2fde4990e553342cd0d80956fe4d`.

- Trial merge reports a conflict in the `config.json` agent block: downstream uses `openchamber`, `xai/grok-4.7`, and variant `high`; incoming uses `t3`, `openai/gpt-6.1-sol`, and variant `medium`. The requested runner/model change does not request a variant change.
- `AGENTS.md` has Little While app context, including alarms, notifications, and Live Activities.

### mesahandbook.com

[BOOK-9](https://linear.app/gotte/issue/BOOK-9/merge) — reviewed downstream master `9fe9daa571120fb17541dce38f508ba0b88433b9`.

- Trial merge reports a modify/delete conflict in the customized ASCII-art `README.txt`, which Code Moto replaces with `README.md`.
- `mise.toml` has downstream DOCX dependency/test tasks and frontend concept code generation.

### nozsig.com

[NOZ-12](https://linear.app/gotte/issue/NOZ-12/merge) — reviewed downstream master `b68aff30cd20f5fbb89acf87a96807c39d00aed2`.

- Trial merge reports a conflict in the `config.json` agent block: downstream uses `openchamber`, `xai/grok-4.7`, and variant `high`; incoming uses `t3`, `openai/gpt-6.1-sol`, and variant `medium`. The requested runner/model change does not request a variant change.
- Nozsig is a server provisioning manager. Its Repo Specific rules exclude backend, frontend, apps, deploy, and publish components; their mise tasks are commented out. Provisioning tasks, safety guards, debug and wipe-check-reset skills, and downstream `manager/tests/spawn_test.rb` changes are relevant.
- `config.json` secrets keys are `development`, `helios`, and `poseidon`, rather than the framework development/production pair. These are outside the trial merge conflict.

### scampmicrodeck.com

[SMD-12](https://linear.app/gotte/issue/SMD-12/merge) — reviewed downstream master `fd0b1f57a6ed4a0723104a8b1a3b48cf61e6335a`.

- Trial merge reports an add/add conflict in `README.md`: Scamp Micro Deck has app introduction, screenshots, Mac App Store links, and release instructions; incoming Code Moto adds framework documentation.
- There are no downstream changes to manager, shared skills, mise tasks, or AGENTS.md relative to the common merge base.
