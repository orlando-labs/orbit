# Ember 1.0 edge deployment model

Status: normative 1.0 target, accepted 2026-07-19 by
[ADR-0001](adr/0001-ember-1-0-contract.md).

Ember 1.0 is a production application server deployed behind a TLS-terminating
reverse proxy or managed ingress. Direct public-Internet exposure is outside
the supported 1.0 profile.

```text
client -- HTTPS / HTTP2+ --> trusted edge -- HTTP/1.1 keep-alive --> Ember
                                  |                                  |
                      public protocol policy              application lifecycle
                      TLS and certificates                 routing and rendering
                      request normalization                bounded concurrency
                      coarse overload limits               graceful drain
```

The edge-to-Ember hop MUST be loopback, a private network protected from
untrusted peers, or an authenticated service-mesh channel. If that hop crosses
a trust boundary, it MUST be encrypted and authenticated by the platform.

## Responsibility boundary

| Concern | Edge/ingress | Ember 1.0 |
|---|---|---|
| TLS certificates, ALPN, HTTP/2 and HTTP/3 | required | out of process |
| HTTP/1 message validity and smuggling defense | required before forwarding | required again at parser boundary |
| public request/header/body limits and slow-client defense | required | bounded inner limits and timeouts required |
| host allowlist | may reject early | authoritative application policy required |
| client IP/scheme/host forwarding | sanitize and overwrite | trust only configured proxy CIDRs/hops |
| compression/static assets/WAF/rate limits | deployment policy | not required framework behavior |
| routing, auth, CSRF/session policy, response safety | may add coarse policy | authoritative application behavior |
| graceful shutdown and request drain | stop routing new traffic | stop accept, drain, cancel at deadline |
| access logs/metrics/traces | edge hop telemetry | application hop telemetry with correlation |

Defense at the edge does not allow Ember limits, parsing checks, or host policy
to be disabled.

## Effective request provenance

The socket peer is untrusted unless it matches the configured trusted-proxy
policy. Ember 1.0 MUST apply these rules in order:

1. Validate the HTTP authority/`Host` syntax and reject missing, duplicate, or
   unauthorized hosts before application routing.
2. Ignore forwarded client/scheme/host fields from an untrusted peer.
3. For a trusted peer, process only the configured forwarding convention and
   bounded hop/CIDR chain. Ambiguous or malformed values are rejected, never
   guessed.
4. Derive `request.origin`, client address, and secure-cookie/redirect decisions
   from the validated effective scheme and authority.

The edge MUST remove client-supplied forwarding fields and set its own values.
Trust-all, trust-the-leftmost-address, and implicit trust based only on a header
being present are forbidden production configurations. The exact header names
and CIDRs/hop count are explicit application configuration.

## Required server configuration

A production deployment MUST set finite, reviewed values for:

- request line, header count/bytes, body bytes, trailer count/bytes, and stream
  buffering;
- header/read/write/idle timeouts and total request deadline where applicable;
- listen backlog, workers, per-worker concurrency, and global in-flight work;
- overload behavior (bounded queue or immediate `503`) and ORM/resource-pool
  acquisition deadlines;
- graceful shutdown deadline and the shorter readiness-removal propagation
  delay;
- host allowlist and trusted proxy CIDRs/hops;
- accepted request-id format/length and log-field redaction.

Framework defaults are safe for development, not a substitute for a reviewed
production configuration. Configuration and its non-secret digest must be
visible in startup telemetry. Secrets never appear in command output or logs.

The concrete stage-3 configuration uses `ember.SecurityPolicy`:

```sputnik
security = ember.SecurityPolicy(
  allowed_hosts: ["app.example.test"],
  trusted_proxy_cidrs: ["10.20.0.0/16"],
  forwarded: :x_forwarded,
  forwarded_hops: 2,
  hsts: true)

app = ember.App(routes: routes, security: security)
```

The edge removes client-supplied `X-Forwarded-*` fields and writes one
canonical set. Ember supports arbitrary IPv4 CIDR prefixes and exact IPv6
`/128` entries. A configuration requiring a broader IPv6 proxy network must
keep the edge hop on a private IPv4 address or wait for canonical IPv6 CIDR
support; trust-all is not a fallback. See [SECURITY.md](SECURITY.md) for the
cookie/session/CORS/CSRF, multipart, HTML, HSTS/CSP, and secret-rotation
contract.

## Lifecycle contract

Startup proceeds in this order:

1. Validate configuration and immutable routes.
2. Start integrations and verify required dependencies.
3. Bind the listener and start workers.
4. Mark ready only after all required start hooks succeed.

Shutdown proceeds in this order:

1. Mark unready and allow the platform's readiness change to propagate.
2. Stop accepting new connections/requests.
3. Drain in-flight buffered and streaming requests while propagating client
   disconnect and cancellation.
4. At the configured deadline, cancel remaining work and close connections.
5. Run integration stop hooks in reverse start order and release pools.

Readiness is false during startup, after shutdown begins, or when a required
integration reports it cannot serve traffic. Liveness indicates process/event
loop health and MUST NOT fail merely because a replaceable downstream is
temporarily unavailable.

The process exits successfully after a clean drain and non-zero after startup
failure, fatal runtime failure, or an exceeded shutdown deadline. Orchestrators
must allow at least the Ember drain deadline plus readiness propagation and
hook overhead before sending an unconditional kill.

Roadmap stage 2 implements this lifecycle through `App#server`, `App#start`,
and the public `ServerHandle`. A signal adapter should first make the instance
unready at the platform, call `stop_accepting()`, wait for the configured
propagation interval, and then call `shutdown()`. `shutdown` returns `false`
when its deadline forced cancellation, allowing the process adapter to select
the documented non-zero exit status. `wait()` joins the accept task and returns
final counters. See [TRANSPORT.md](TRANSPORT.md) for the exact API, defaults,
keep-alive bounds, overload policy, and stats.

Integration `start()` hooks run before listener bind, `attach_server()` binds
handle-aware telemetry after bind, `ready?()` participates
in handle readiness, and `stop()` runs in reverse order after clean drain or
forced cancellation. A startup error unwinds only integrations whose start
hook completed. Request-task cancellation resumes the persistent handler VM so
`ensure` scopes finish before resource-pool stop hooks.

## Streaming and proxy behavior

The edge MUST permit streaming without unbounded buffering, preserve response
backpressure, and use timeouts compatible with the application's longest
supported stream. Client disconnect must reach Ember as cancellation. A
deployment that buffers all responses or lets the edge timeout before Ember's
write deadline does not support Ember streaming, even if buffered endpoints
work.

Keep-alive is required on the trusted edge-to-Ember HTTP/1.1 hop for the 1.0
production profile. TLS, HTTP/2/3, WebSocket, and direct TLS inside Ember are
not 1.0 release requirements.

## Operational endpoints

Health, readiness, and metrics endpoints must be reachable by the platform but
not exposed publicly without edge authorization. They use dedicated static
routes, have strict timeouts, do not reveal secrets or exception messages, and
are excluded from noisy access logs only through explicit telemetry policy.

## Unsupported deployments

The following do not satisfy the Ember 1.0 production contract:

- binding Ember directly to a public interface without a trusted edge;
- deriving HTTPS or client identity from unchecked forwarding headers;
- infinite or absent request, concurrency, stream, or shutdown limits;
- marking ready before integrations start or remaining ready while draining;
- relying on process kill as the normal shutdown mechanism;
- claiming full-duplex streaming through a buffering proxy without an
  integration test.

The tracked [nginx example](../deploy/nginx.conf) overwrites forwarding fields,
uses HTTP/1.1 upstream keep-alive, and disables response/request buffering for
streaming. The [systemd unit](../deploy/systemd/ember.service) and
[Kubernetes deployment](../deploy/kubernetes/ember.yaml) reserve 45 seconds
for the documented 5-second readiness propagation plus 30-second Ember drain
and hook overhead. Adapt paths, addresses, resources, probes, and certificates
without weakening the boundary. Operational response, backup, restore, and
rollback procedures are in [RUNBOOK.md](RUNBOOK.md); the complete setting
matrix is in [CONFIGURATION.md](CONFIGURATION.md).
