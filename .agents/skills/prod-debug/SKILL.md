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
- **Grafana logs**: production Rails logs from the `api` and `job` processes, kept for 14 days in Grafana Cloud Loki. Query them in Grafana Explore; see [logging](../../../docs/logging.md) for labels and fields.
  - Errors: `{service_name="<OTEL_SERVICE_NAME>", deployment_environment="production"} | detected_level=~"error|critical"`.
  - Reported exceptions: add `| error_fingerprint!=""`; group by `error_fingerprint` to find distinct errors. Each line holds the exception class, message, and backtrace.
  - Shipping depends on the `OTEL_*` keys being set; journals remain the fallback.
- **Rails journals**: `api.service` contains Rails request/application logs; `job.service` contains GoodJob worker logs. Access them through `mise deploy:cmd`. `mise deploy:log` follows the `api` journal indefinitely and is intended for humans.
- **`mise runner:production "<Ruby>"`**: run Rails code against production. It can mutate live data.
- **`mise deploy:cmd "<command>"`**: run an arbitrary command on the deployment host. It can mutate the host and production data.
- **`mise console:production`**: interactive Rails console against production. **Do not use — for humans.**

No other `deploy:*` tasks should be used. Tasks like `deploy:ssh`, `deploy:pry`, `deploy:reboot`, `deploy:backup`, `deploy:restore`, `deploy:destroy`, `deploy:htop`, `deploy:deploy`, and `deploy:quick` are deployment management tools, not debugging tools.
