# Orbit 1.0 public API boundary

Status: normative `1.0.0-rc.1` candidate, accepted 2026-07-19 by
[ADR-0001](adr/0001-orbit-1-0-contract.md).

An Orbit name is public only when it is listed here or in a versioned API
reference shipped with a release. Export visibility alone is insufficient:
Sputnik macros require a few implementation helpers to be exported. Undocumented
attributes, concrete collection classes, generated code, exception message
text, and names beginning with `__` or `_` are internal.

This document fixes the supported surface and extension protocols. Later
roadmap work may add public names and optional keyword arguments. Before the
1.0 RC it may also replace the two explicitly provisional concrete surfaces
listed below; no other current public surface may be removed without
superseding the contract ADR.

## `orbit`

### Route declarations

Public macros:

- `routes`, `get`, `query`, `post`, `put`, `patch`, `delete`, `head`,
  `options`, `scope`, and `mount`;
- `params`, `field`, `object`, and `array` for strong-parameter schemas.

The route options `to:`, `as:`, `params:`, and `before:` and the scope/mount
options shown in the README are public. Function targets receive `Request`
first; controller targets create one `Controller` instance per request.

`__route`, `__scope`, `__mount`, and `__before` are exported macro plumbing and
are not public application APIs.

### Application

`App` is public with:

- `App(routes:, middleware: [], integrations: [], services: {},
  security: null, head_fallback: true, automatic_options: true,
  expose_exceptions: false, on_error: null, telemetry: null)`; a null security
  value constructs the default `SecurityPolicy`;
- read-only `routes` and `telemetry`;
- `call(request)` as the primary deterministic test/adapter boundary;
- `server(**options)` returning an unstarted `ServerHandle`;
- asynchronous `start(max_requests: null, **options)`;
- blocking `run(**options, max_requests: null)`.

The shared server options are `host`, `port`, `workers`,
`max_concurrent_per_worker`, `backlog`, `reuse_addr`, `max_header_bytes`,
`max_body_bytes`, `read_timeout`, `write_timeout`, `idle_timeout`,
`max_requests_per_connection`, `shutdown_timeout`, and `overload`. Their
defaults and units are normative in [TRANSPORT.md](TRANSPORT.md).
`expose_exceptions: true` is a development/test option and MUST NOT be used in
production.

`ServerHandle` is public with `start(max_requests: null)`,
`serve(max_requests: null)`, `wait()`, `ready?()`, `accepting?()`,
`stop_accepting()`, `shutdown(timeout: null)`, `in_flight()`, `stats()`,
`port()`, `local_endpoint()`, and read-only `app`. A handle starts at most once;
shutdown and stop-accepting are idempotent. `shutdown` returns whether the
drain was clean. Stats use the stable Symbol keys `accepted`, `completed`,
`failed`, `rejected`, `active`, `requests`, `active_requests`,
`keepalive_requests`, `forced_shutdowns`, and `capacity`.

`App#call` accepts `orbit.Request` or `net.http.ServerRequest` and returns a
normalized `Response` or `StreamingResponse` subject to the
[HTTP contract](HTTP_CONTRACT.md).

### Request

`Request` has a public in-memory constructor with `method:`, `target:`, `path:`,
`raw_query:`, `headers:`, `body_text:`, `body_bytes:`, `body_stream:`,
`remote_endpoint:`, and `local_endpoint:`. The server/routing injection
keywords used by `App` are internal. Stable read-only request data and
operations are:

- `method`, `target`, `path`, `raw_query`, `remote_endpoint`, and
  `local_endpoint`;
- validated provenance `effective_scheme`, `effective_authority`, `client_ip`,
  `trusted_proxy`, `origin()`, and `secure?()` after `App` authorization;
- `header(name)`, `body_text()`, `body_bytes()`, and `body_stream`;
- `path_param(name)`, `path_params()`, `query(name)`, `query_params()`, and
  `params()`;
- routed request metadata `routes` and `selected_route`;
- `service(name)`.

Requests adapted from `net.http.ServerRequest` expose remote and local
endpoints as canonical endpoint text. In-memory constructor values are retained
as supplied and should be treated as diagnostic metadata, not authority.

Request headers are exposed as the immutable `Headers` value described below.
Applications may use `header(name)` for the first/selected value or
`headers.all(name)` when repeated fields matter. Direct mutation is not public.

`origin()` is security-sensitive and is the validated effective origin after
host authorization and trusted-proxy processing. Applications must not derive
origin or client identity from raw forwarding fields.

`SecurityPolicy` is public with `allowed_hosts`, `trusted_proxy_cidrs`,
`forwarded`, `forwarded_hops`, `security_headers`,
`content_security_policy`, and `hsts` constructor keywords. Supported
forwarding modes are `:none` and `:x_forwarded`. IPv4 CIDR and exact IPv6
`/128` proxy entries are supported. Policy defaults and the production
configuration contract are normative in [SECURITY.md](SECURITY.md).

`RequestBodyStream` public operations are `framing`, `read_chunk(max_bytes:
null)`, `each_chunk(max_bytes: null)`, `trailers()`, `closed?()`, and
`started?()`. `RequestChunk` exposes `bytes`, `text`, and ordered `extensions`.
A body may be claimed by streaming code or strong-parameter parsing, never
both.

### Responses and rendering

The following are public:

- `Response(status: 200, headers: {}, body: "")`, with `status`, read-only
  `body`, `header(name)`, `body_text()`, and `body_bytes()`;
- `StreamingResponse(status: 200, headers: {}, trailers: [], length: null, &producer)`, with
  read-only `status`, `headers`, `trailers`, and `length`;
- `StreamBody#write(data, extensions: null)`, `close()`, `trailer(name, value)`,
  `finish()`, and `closed?()`;
- `render`, `redirect`, `stream`, `normalize_response`, and `status_code`;
- `Html`, including `Html.escape`, `Html.raw`, `Html.join`, `to_str`, and `+`.

`Response#headers` and `StreamingResponse#headers` are immutable `Headers`
values. Header reads through `header(name)` and values passed through
constructors/helpers are stable.
`stream` and `Controller#stream` accept the same optional `length:`. A
nonnegative `Int` selects fixed-length transport framing; `null` keeps the
chunked default. Fixed-length writes must total exactly that many bytes;
trailers and chunk extensions are invalid. Header derivations, middleware and
telemetry preserve length. Framing headers cannot be supplied directly.
`to_server_response()` is a public adapter bridge for server integrations, but
the concrete `net.http` value it returns follows the supported Sputnik version.

`Headers(source = null)` is a public immutable, case-insensitive, ordered
multi-value collection. Supported reads are `first`, `all`, `include?`,
`size`, `empty?`, `keys`, `each`, and `to_pairs`; persistent updates are `add`,
`set`, `delete`, `without`, and `merge`. Source maps and ordered pairs are
validated and snapshotted. Header names are canonicalized to lowercase;
repeated values such as `Set-Cookie` remain separate and ordered.

### Controllers and extension protocols

`Controller` is public. Subclasses may use `request`, `status`, `header`,
`render`, `redirect`, `stream`, `path`, `service`, `path_param`, `query`, and
`params`. Status/header mutations after response commit and a second render are
public errors.

Middleware is the callable protocol `(Request, next) -> response-like value`.
`next(request)` may be called once. Application middleware wraps route
middleware in declaration order.

An integration supplied to `App(integrations:)` implements
`around_controller(request, next)`. A controller wrapper that needs server
lifecycle participation subclasses `Integration` and overrides `start()`,
`attach_server(server)`, `ready?()`, or `stop()`; their defaults are safe
no-ops as defined in [TRANSPORT.md](TRANSPORT.md). A duck-typed wrapper that does not subclass
`Integration` participates only in controller dispatch. Controller wrapping
applies only to controller targets. Bare handlers use route/application
middleware for equivalent behavior.

`Target` and its `function`/`controller` constructors are public for adapter and
DSL authors. `Target#invoke` is the supported invocation boundary. The helper
endpoint classes used internally are not public.

### Routing and introspection values

The public routing values are `Routes`, `Route`, `RouteLookup`, and
`RouteMatch`:

- `Routes#lookup(path, method, head_fallback: false,
  automatic_options: true)`, `match(path, method: "GET")`, `path(name,
  **params)`, `url(name, origin:, **params)`, and `describe()`;
- read-only `Routes#routes` as an immutable snapshot;
- read-only route metadata `method`, `pattern`, `target`, `name`, `middleware`,
  and `param_types`;
- lookup `kind`, `match`, and `allowed_methods`;
- match `route`, `path_params`, and ordered `captures`.

Route compiler segments, candidates, shapes, and matching helper methods are
internal even if reachable from an object.

### Strong-parameter values

`ParamSchema`, `ParamField`, `ParamObject`, `ParamArray`, `ParamIssue`,
`RequestParams`, and `RequestParamSource` are public values. The supported
operations are schema/source `check` and `expect`, request-source `json` and
`query`, issue fields `path`, `code`, `expected`, `actual`, and `data()`, plus
the read-only declaration metadata exposed by these values.

Returned maps and issue paths are deeply immutable snapshots. Unknown keys,
type rules, nullability, and error codes are behavioral compatibility surface.

### Public errors

Applications may catch these error types; their inheritance and semantic
classification are stable, but their exact message strings are not:

- `OrbitError`, `RouteError`, `InvalidRouteError`, `DuplicateRouteError`,
  `DuplicateRouteNameError`, `InvalidPathError`, `RouteParamError`,
  `RouteNotFoundError`, `UnknownRouteNameError`, `PathGenerationError`;
- `InvalidResponseError`, `DoubleRenderError`, `ResponseCommittedError`,
  `ServerLifecycleError`, `UnknownStatusError`, `UnknownServiceError`,
  `UnsafeRedirectError`;
- `RequestParamsError`, `ParamsParseError`, `ParamsShapeError`,
  `ParamsUnsupportedMediaTypeError`, and `ParamsBodyConsumedError`;
- `RequestSecurityError`, `InvalidAuthorityError`,
  `UnauthorizedHostError`, and `InvalidForwardedRequestError`.

## Supporting modules

### `orbit.html`

Public API: `html"""..."""`, `escape`, `escape_text`, `escape_attribute`,
`raw`, `join`, `url`, `trusted_script`, `trusted_style`, `HtmlUrl`,
`TrustedScript`, and `TrustedStyle`. The macro return value is `orbit.Html`.
Text and ordinary quoted attributes are escaped automatically. URL, script,
style, event-handler, and srcdoc contexts require the explicit wrappers
documented in [SECURITY.md](SECURITY.md); comments, tag syntax, and unquoted
attributes reject interpolation. `raw` and trusted wrappers are explicit trust
boundaries, not sanitizers. Exported `_url_attribute`, `_script_body`,
`_style_body`, `_script_attribute`, `_style_attribute`, and
`_srcdoc_attribute` functions are macro plumbing and are not public APIs.

### `orbit.middleware`

Public API: `before`, `request_id`, `access_log`, `RequestIdMiddleware`, and
`AccessLogMiddleware`. Constructor keyword additions for policy, validation,
redaction, and sinks are compatible. Log formatting from the preview is not a
stable wire/data format; the 1.0 structured event schema is normative in
[OBSERVABILITY.md](OBSERVABILITY.md).

`RequestIdMiddleware(accept_incoming: true, max_length: 128)` validates
incoming values against the bounded ASCII identifier grammar in
[SECURITY.md](SECURITY.md), otherwise replacing them with a secure random ID.

### `orbit.telemetry`

Public event/sink API: `RedactionPolicy`, `JsonLogSink`, `MemorySink`,
`AccessEvent`, and `ErrorLogEvent`. Public tracing API: `TraceContext`,
`ServerSpan`, and `Tracer`. Public metrics/operations API: `MetricsRegistry`
with `snapshot`, `response`, and `set_integration_pool`, and `HealthProbe` with
`live?`, `ready?`, `liveness`, and `readiness`. `Telemetry` is the aggregate
observer accepted by `App(telemetry:)`; its public read-only components are
`sink`, `metrics`, `tracer`, and `health`.

Event fields, redaction, finite cardinality, trace trust, OTel compatibility,
and lifecycle semantics are normative in
[OBSERVABILITY.md](OBSERVABILITY.md). `MemorySink` is for tests and bounded
short-lived capture, not a production exporter. Event read-only attributes and
`fields()` maps follow the stable schema in the observability contract.

### `orbit.security`

The public cookie API is `CookieLimits`, `CookieJar`, `SetCookie`,
`CookieError`, `CookieJar.parse`, jar `get`/`include?`/`to_map`, and
`SetCookie#header_value`. Public cryptographic envelopes are `Aead`,
`SignedCookieCodec`, `SessionCodec`, and `SessionError`, with `seal`/`open`,
`seal_bytes`/`open_bytes`, and codec `encode`/`decode` operations. Public
browser middleware is `CorsMiddleware`, `CsrfProtection`, `CsrfMiddleware`,
and `CsrfError`. Constructor bounds, key requirements, safe defaults, rotation,
and application responsibilities are normative in [SECURITY.md](SECURITY.md).

### `orbit.multipart`

Public API: `parse`, `MultipartLimits`, `MultipartPart`, `MultipartForm`, and
`MultipartError`. Parts expose `name`, `filename`, `content_type`, `headers`,
`bytes`, `file?`, and field-only `text`. Forms expose immutable `parts` and
`first`, `all`, `fields`, and `files`. Parsing claims the body once and applies
the aggregate, count, header, field, file, name, and filename bounds documented
in [SECURITY.md](SECURITY.md). Storage and content validation are not part of
this transport parser.

### `orbit.testing`

Public API: `request`, `get`, `query`, `post`, `put`, `patch`, `delete`, `head`,
`options`, `assert_status`, `assert_header`, and `assert_body`. Test helpers
follow the same HTTP contract as `App#call`.

### `orbit.integrations.orm`

Public API: `pool`, `connection`, `PoolIntegration`, and
`ConnectionMiddleware`. This module is distributed by the separate versioned
`orbit-orm` companion package; Orbit core remains ORM-neutral. The integration's
request-scoped lease behavior and safe `503` mapping for pool timeout/closed/
lease failures are stable. `PoolIntegration` also implements the server
lifecycle: it rejects an already-closed pool at startup, reports readiness,
and closes the pool after drain/cancellation. ORM model/query APIs belong to
`sputnik-orm`.

## Explicitly out of scope

No compatibility is promised for private methods, `__*` helpers, generated
macro AST, header ordering where HTTP says order is insignificant, access-log
text, default error body wording, compiler diagnostics other than documented
diagnostic identifiers, build artifacts, cache layout, or direct imports of
transitive Sputnik/ORM/SQLite implementation modules.
