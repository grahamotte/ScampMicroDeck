# Logging

Rails processes keep writing logs to STDOUT, so journald, `mise deploy:log`, and `mise deploy:status` work as before. In production and development, when `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, and `OTEL_SERVICE_NAME` are all set, they also ship every Rails logger line to Grafana Cloud Loki over OTLP/HTTP with protobuf. In test, or with any of those keys unset, nothing is shipped.

Shipping uses the OpenTelemetry Ruby logs SDK. Lines are queued in memory, exported in batches from a background thread, dropped when the queue is full or Grafana is unreachable, and flushed when the process exits.

## Credentials

One Grafana Cloud stack and one token serve every project. Store these keys in each project's 1Password item, in the development and production environments:

- `OTEL_EXPORTER_OTLP_ENDPOINT`: the stack's OTLP gateway, such as `https://otlp-gateway-prod-us-west-0.grafana.net/otlp`.
- `OTEL_EXPORTER_OTLP_HEADERS`: `Authorization=Basic <base64 of instanceID:token>`, exactly as Grafana's OpenTelemetry page generates it. A literal space after `Basic` works; `%20` also works.
- `OTEL_EXPORTER_OTLP_PROTOCOL`: `http/protobuf`.
- `OTEL_SERVICE_NAME`: a short, stable name for the app, such as `MOTO`. It becomes the `service_name` label.

Create the token from the stack's OpenTelemetry tile with `logs:write`. Add `metrics:write` and `traces:write` when metrics and traces are added; the same endpoint and headers carry them.

## Labels and fields

- `service_name`: `OTEL_SERVICE_NAME`.
- `deployment_environment`: the Rails environment, `production` or `development`.
- `service_version`: the git commit SHA the process booted from.
- `host_name`: the machine's hostname.
- `service_instance_id`: the process, `api` for Puma, `job` for the GoodJob worker, and `rails` for runners and consoles.
- `severity_text` and `detected_level`: the Ruby logger level. `ERROR` lines have `detected_level="error"` and `FATAL` lines have `detected_level="critical"`.
- `event_name`: the Rails instrumentation event that wrote the line, such as `sql.active_record`, `start_processing.action_controller`, `process_action.action_controller`, or `perform.active_job`. Lines written directly with `Rails.logger`, including Rails' `Started GET` request line, have none.
- `request_id`: the request id on lines written while a controller action runs, from `Processing by` through `Completed`, including its errors.
- `job_class` and `job_id`: the ActiveJob class and id on lines written while a job performs, including its errors.
- `exception_type` and `error_fingerprint`: set on lines written by the `Rails.error` subscriber for unhandled controller exceptions, job exceptions, and GoodJob thread errors. The fingerprint hashes the exception class and the first application backtrace line without its line number, so it stays stable across deploys and days. The body holds the class, message, and the first 30 backtrace lines.

## Queries

Every error-level line for an app:

```logql
{service_name="MOTO", deployment_environment="production"} | detected_level=~"error|critical"
```

Reported exceptions only, one per occurrence, with a fingerprint to group by:

```logql
{service_name="MOTO", deployment_environment="production"} | error_fingerprint!=""
```

Distinct fingerprints over the last day:

```logql
sum by (error_fingerprint, exception_type) (count_over_time({service_name="MOTO", deployment_environment="production"} | error_fingerprint!="" [1d]))
```

`GET /api/noop/error` raises `Test backend error` and produces a fingerprinted line from the `api` process.
