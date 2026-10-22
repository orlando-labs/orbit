# Orbit 1.0 observability contract

Status: normative stage-4 contract, version 1.0, 2026-07-22.

Orbit observes a request at the `App` boundary. A buffered request ends after
response validation; a streaming request remains in flight until its producer
finishes or fails. Telemetry failures never replace an application response or
a transport cancellation.

## Configuration

```sputnik
import orbit
import orbit.telemetry

sink = telemetry.JsonLogSink(
  redaction: telemetry.RedactionPolicy(fields: ["request.id"]))
observability = telemetry.Telemetry(
  sink: sink,
  metrics: telemetry.MetricsRegistry(max_series: 8192),
  tracer: telemetry.Tracer(sink))

app = orbit.App(routes: routes, telemetry: observability)
```

`Telemetry` creates a JSON-lines sink, bounded registry, server tracer, and
health probe by default. It generates a bounded secure request ID when the
incoming value is absent or invalid and returns it as `x-request-id`.
`AccessLogMiddleware` remains a convenience API and now emits the same
structured access schema; the `App(telemetry:)` boundary is the production
configuration because it also observes framework-generated errors.
Do not install both observers for the same request unless duplicate events are
an explicit sampling test.

## Structured events and redaction

Every event has `event.kind`. Access events have `event.name` equal to
`http.server.request` and these stable fields:

| Field | Contract |
|---|---|
| `request.id` | Validated or generated correlation ID. |
| `http.request.method` | Bounded method name accepted by Orbit. |
| `http.route` | Matched route template, or `<unmatched>`; never the raw path. |
| `http.response.status_code` | Final status, or `null` if no response exists. |
| `duration_ns` | Monotonic duration through final stream completion. |
| `http.response.body.size` | Buffered or successfully written stream payload bytes. |
| `outcome` | `success`, `client_error`, `error`, or `cancelled`. |
| `trace_id`, `span_id` | Correlation identifiers when tracing is enabled. |

Error events use `event.name = orbit.error`, the same request/method/route
correlation, and a bounded `error.type`. Exception messages, backtraces, raw
paths, query strings, bodies, cookies, authorization/session headers, and
arbitrary headers are not part of either schema. `RedactionPolicy(fields:)`
replaces additionally configured exact field names with `[REDACTED]` before a
sink receives them. JSON encoding prevents record injection.

Lifecycle shutdown events contain only outcome, duration, active request
count, and forced-shutdown count. A sink should ship JSON lines to the
deployment collector; it must not add sensitive request material later.

## Metrics

`MetricsRegistry#snapshot` is machine-readable and
`MetricsRegistry#response` is a safe JSON endpoint response. The registry
contains:

- `http.server.requests`, `http.server.active_requests`, errors and response
  body bytes;
- `http.server.request.duration` in seconds with the OpenTelemetry recommended
  explicit boundaries, count, sum, and cumulative bucket counts;
- active/completed/failed stream state;
- attached native server connection, rejection, capacity, keep-alive,
  in-flight, and forced-shutdown state under `orbit.server`;
- clean/forced shutdown counts and drain duration;
- explicitly registered integration-pool active/capacity/waiting gauges.

The optional `orbit.integrations.orm.PoolIntegration` publishes its leased,
maximum, and waiting values automatically after server attachment and each
controller lease. Other integrations use `set_integration_pool` at their own
lifecycle boundaries.

Request series are keyed only by method, route template, status class, and
outcome. `max_series` is finite (8192 by default); new excess combinations are
folded into `__overflow__`. Integration names are explicitly supplied,
bounded to 64 entries and 64 characters, and must never contain tenant/user
identifiers.

## Tracing

Server spans follow OpenTelemetry semantic conventions 1.43.0: kind `SERVER`,
name `METHOD route-template`, and the current `http.request.method`,
`http.route`, `http.response.status_code`, `http.response.body.size`,
`url.scheme`, `server.address`, `client.address`, and `network.protocol.name`
attribute names. Span duration is identical to the request-duration metric and
includes stream production.

Incoming W3C version-00 `traceparent` is accepted only after exact syntax,
non-zero ID, and lowercase-hex validation, and only when `SecurityPolicy` has
marked the peer as a trusted proxy. Invalid or untrusted context starts a new
trace. `tracestate` is not accepted or propagated because Orbit has no outbound
HTTP instrumentation contract yet.

To prevent sensitive identifiers entering telemetry, the default tracer sets
`url.path` to `[REDACTED]` while retaining `http.route`. Operators may choose
`capture_url_path: true` only after an application-specific privacy review.
Header capture is intentionally unsupported by the default tracer.

References: [OpenTelemetry HTTP spans](https://opentelemetry.io/docs/specs/semconv/http/http-spans/),
[OpenTelemetry HTTP metrics](https://opentelemetry.io/docs/specs/semconv/http/http-metrics/),
and [W3C Trace Context](https://www.w3.org/TR/trace-context/).

## Operational endpoints

`Telemetry#health` is attached to the `ServerHandle` during bind:

- `liveness()` returns `200 {"status":"ok"}` while the process can execute;
- `readiness()` returns 200 only while the handle is accepting and every
  lifecycle-aware integration is ready; it returns 503 before attachment,
  during drain, and after shutdown;
- `MetricsRegistry#response` returns the bounded snapshot without exception
  messages or secrets.

Applications expose these through dedicated static routes. The trusted edge
must authorize them and apply the finite request timeout from the deployment
contract. Exclusion from access logs is an explicit application policy, never
an implicit path-name rule.
