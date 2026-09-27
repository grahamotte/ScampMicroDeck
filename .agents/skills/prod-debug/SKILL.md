---
name: prod-debug
description: Debugging tool reference for this project. Use only when the user explicitly invokes `$prod-debug` or asks to use the prod-debug skill by name.
---

# Prod Debug

Debug only. Do not make changes or fix code unless prompted. Ask clarifying questions to narrow the problem.

Do not read `.env`, `.env.production`, or any `.env.*` file — the `mise` tasks already have the appropriate environment access configured.

## Local tools

- **Code and git**: inspect implementation, tests, configuration, schema, and history. Rails schema lives in `backend/db/schema.rb`.
- **`mise runner "<Ruby>"`**: run Ruby application code in development.
- **`mise query "<SQL>"`**: query the development database. Accepts SELECT, WITH, SHOW, EXPLAIN, TABLE, and VALUES.
- **`mise console`**: interactive Rails console. **Do not use — for humans.** Use `mise runner` or `mise query` instead.

## Production tools

- **`mise deploy:status`**: show deployment state, service health, host resources, current deployed commit, and recent `api` and `job` journal warnings. Also confirms whether a deployment host is reachable.
- **`mise query:production "<SQL>"`**: query production in a read-only PostgreSQL transaction. Accepts the same query forms as `mise query`.
- **Solid Errors**: available through `mise query:production`.
  - `solid_errors`: grouped exception class, message, severity, source, fingerprint, resolution, and timestamps.
  - `solid_errors_occurrences`: `error_id`, backtrace, JSON context, and timestamps.
  - Recording depends on Rails and PostgreSQL being available.
- **Rails journals**: `api.service` contains Rails request/application logs; `job.service` contains GoodJob worker logs. Access them through `mise deploy:cmd`. `mise deploy:log` follows the `api` journal indefinitely and is intended for humans.
- **`mise runner:production "<Ruby>"`**: run Rails code against production. It can mutate live data.
- **`mise deploy:cmd "<command>"`**: run an arbitrary command on the deployment host. It can mutate the host and production data.
- **`mise console:production`**: interactive Rails console against production. **Do not use — for humans.**

No other `deploy:*` tasks should be used. Tasks like `deploy:ssh`, `deploy:pry`, `deploy:reboot`, `deploy:backup`, `deploy:restore`, `deploy:destroy`, `deploy:htop`, `deploy:deploy`, and `deploy:quick` are deployment management tools, not debugging tools.
