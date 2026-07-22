# Production configuration reference

This reference combines the Ember, security, transport, telemetry, and edge
settings that must be reviewed together. Framework defaults are development
defaults; production records the selected values and a non-secret
configuration digest in deployment metadata.

## Application boundary

| Setting | Development default | Production rule |
|---|---|---|
| `head_fallback` | `true` | Keep unless explicit-HEAD-only semantics are required and tested. |
| `automatic_options` | `true` | Keep or replace with an explicit application/edge OPTIONS policy. |
| `expose_exceptions` | `false` | Must remain `false`. |
| `on_error` | `null` | Optional redacted `ErrorEvent` hook; it must not expose messages or replace cancellation. |
| `telemetry` | `null` | Configure a production sink/exporter, bounded metrics, tracing, and probes. |
| `middleware` | `[]` | Order is security-sensitive; auth/CSRF/CORS placement is application-reviewed. |
| `integrations` | `[]` | Every required integration participates in startup/readiness/stop. |
| `services` | `{}` | Values are application-owned and must be concurrency-safe. |

## Listener and lifecycle

| Setting | Default | Production requirement |
|---|---:|---|
| `host` | `127.0.0.1` | Loopback or a protected private interface reachable only from the trusted edge. |
| `port` | `3000` | Stable service port; `0` is test-only. |
| `workers` | `1` | Size from CPU/load evidence. |
| `max_concurrent_per_worker` | `32` | Finite hard capacity; align pools and edge admission below it. |
| `backlog` | `128` | Finite and no larger than the platform/edge queue budget. |
| `reuse_addr` | `true` | Normally retained. |
| `max_header_bytes` | `65536` | No larger than the edge limit. |
| `max_body_bytes` | `1048576` | No larger than endpoint/parser limits; upload endpoints need an explicit budget. |
| `read_timeout` | `30.0s` | Shorter than the edge upstream read deadline and resistant to slow clients. |
| `write_timeout` | `30.0s` | Compatible with the longest supported stream and edge timeout. |
| `idle_timeout` | `15.0s` | Shorter than edge upstream keep-alive idle time. |
| `max_requests_per_connection` | `100` | Finite; edge reuses but eventually rotates connections. |
| `shutdown_timeout` | `30.0s` | Less than platform termination grace minus readiness propagation/hook overhead. |
| `overload` | `:reject` | Required 1.0 policy; excess connections receive `503` without an app queue. |

Timeout values accept `Float` seconds or `Int` milliseconds. All values are
validated before bind. See [TRANSPORT.md](TRANSPORT.md) for exact lifecycle and
wire behavior.

## Host and trusted proxy policy

Production constructs `SecurityPolicy` explicitly:

```amber
security = ember.SecurityPolicy(
  allowed_hosts: ["app.example.test"],
  trusted_proxy_cidrs: ["10.20.0.0/16"],
  forwarded: :x_forwarded,
  forwarded_hops: 1,
  security_headers: true,
  content_security_policy: "default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
  hsts: true)
```

The edge removes client `Forwarded`/`X-Forwarded-*` values and writes exactly
one canonical `X-Forwarded-For`, `X-Forwarded-Host`, and
`X-Forwarded-Proto`. `forwarded_hops` counts the trusted values reaching Ember;
it is not an estimate. Trust-all and an empty host allowlist are invalid
production choices. IPv6 networks broader than `/128` are unsupported.

## Browser and parsing controls

- Keep default security headers and enable HSTS only behind validated HTTPS.
- Secrets for sessions, signed cookies, and CSRF contain at least 32 random
  bytes and come from the platform secret manager, never environment dumps,
  manifests, command arguments, or logs.
- Set `max_body_bytes <= MultipartLimits#max_total_bytes`; endpoint-specific
  file/type/quota/scanning rules remain mandatory.
- CORS uses exact origins/methods/headers. CSRF protects every
  cookie-authenticated unsafe browser route.
- `RequestIdMiddleware` accepts only the documented bounded ASCII grammar;
  production telemetry may generate IDs at the `App` boundary instead.

## Telemetry and operational endpoints

Use `Telemetry` with a production JSON sink/exporter, the default bounded
`MetricsRegistry(max_series: 8192)` or a smaller reviewed bound, and a
`Tracer`. Raw path capture remains disabled unless a privacy review explicitly
allows it. Never add cookies, authorization, bodies, query strings, exception
messages, or arbitrary headers to events.

Expose liveness, readiness, and metrics through static application routes on
an edge-authorized administrative listener/path. Readiness must return 503
during startup and drain. Alert at minimum on sustained 5xx, overload
rejections, forced shutdown, readiness failure, pool waiting/exhaustion,
duration-budget breach, and unexpected metric-series overflow.

## Cross-layer timing invariant

For a normal rollout:

```text
edge readiness removal propagation
  + Ember shutdown_timeout
  + integration stop overhead
  < platform termination grace

Ember read/write timeout < edge upstream timeout < client-visible timeout
Ember idle_timeout < edge upstream keep-alive timeout
```

The reviewed starting point for the supplied examples is 5 seconds readiness
propagation, 30 seconds Ember shutdown, and 45 seconds platform grace. Streaming
applications increase the inner/outer write deadlines together and test
disconnect propagation before deployment.
