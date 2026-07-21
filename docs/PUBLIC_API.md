# Ember 1.0 public API boundary

Status: normative 1.0 target, accepted 2026-07-19 by
[ADR-0001](adr/0001-ember-1-0-contract.md).

An Ember name is public only when it is listed here or in a versioned API
reference shipped with a release. Export visibility alone is insufficient:
Amber macros require a few implementation helpers to be exported. Undocumented
attributes, concrete collection classes, generated code, exception message
text, and names beginning with `__` or `_` are internal.

This document fixes the supported surface and extension protocols. Later
roadmap work may add public names and optional keyword arguments. Before the
1.0 RC it may also replace the two explicitly provisional concrete surfaces
listed below; no other current public surface may be removed without
superseding the contract ADR.

## `ember`

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
  head_fallback: true, automatic_options: true, expose_exceptions: false)`;
- read-only `routes`;
- `call(request)` as the primary deterministic test/adapter boundary;
- blocking `run(host: "127.0.0.1", port: 3000, workers: 1,
  max_concurrent_per_worker: 32, max_requests: null)`.

Server limit/timeout keywords may be added to `run`. The lifecycle stage will
add a public server handle without changing `call` or the meaning of existing
keywords. `expose_exceptions: true` is a development/test option and MUST NOT be
used in production.

`App#call` accepts `ember.Request` or `net.http.ServerRequest` and returns a
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
- `header(name)`, `body_text()`, `body_bytes()`, and `body_stream`;
- `path_param(name)`, `path_params()`, `query(name)`, `query_params()`, and
  `params()`;
- routed request metadata `routes` and `selected_route`;
- `service(name)` and `origin()`.

The concrete type of `headers` is provisional: stage 1 replaces the current
single-value map with a case-insensitive, ordered multi-value header value.
Applications must use `header(name)` for a single combined/selected value until
that API lands. Direct map mutation is not public.

`origin()` is also security-sensitive: its public meaning for 1.0 is the
validated effective origin after host authorization and trusted-proxy
processing. The preview's direct `Host` interpretation is not the 1.0 contract.

`RequestBodyStream` public operations are `framing`, `read_chunk(max_bytes:
null)`, `each_chunk(max_bytes: null)`, `trailers()`, `closed?()`, and
`started?()`. `RequestChunk` exposes `bytes`, `text`, and ordered `extensions`.
A body may be claimed by streaming code or strong-parameter parsing, never
both.

### Responses and rendering

The following are public:

- `Response(status: 200, headers: {}, body: "")`, with `status`, read-only
  `body`, `header(name)`, `body_text()`, and `body_bytes()`;
- `StreamingResponse(status: 200, headers: {}, trailers: [], &producer)`, with
  read-only `status`, `headers`, and `trailers`;
- `StreamBody#write(data, extensions: null)`, `close()`, `trailer(name, value)`,
  `finish()`, and `closed?()`;
- `render`, `redirect`, `stream`, `normalize_response`, and `status_code`;
- `Html`, including `Html.escape`, `Html.raw`, `Html.join`, `to_str`, and `+`.

The concrete type and mutation behavior of `Response#headers` is provisional
for the same multi-value migration as request headers. Header reads through
`header(name)` and values passed through constructors/helpers are stable.
`to_server_response()` is a public adapter bridge for server integrations, but
the concrete `net.http` value it returns follows the supported Amber version.

### Controllers and extension protocols

`Controller` is public. Subclasses may use `request`, `status`, `header`,
`render`, `redirect`, `stream`, `path`, `service`, `path_param`, `query`, and
`params`. Status/header mutations after response commit and a second render are
public errors.

Middleware is the callable protocol `(Request, next) -> response-like value`.
`next(request)` may be called once. Application middleware wraps route
middleware in declaration order.

An integration supplied to `App(integrations:)` implements
`around_controller(request, next)`. It applies only to controller targets.
Bare handlers use route/application middleware for equivalent behavior.

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

- `EmberError`, `RouteError`, `InvalidRouteError`, `DuplicateRouteError`,
  `DuplicateRouteNameError`, `InvalidPathError`, `RouteParamError`,
  `RouteNotFoundError`, `UnknownRouteNameError`, `PathGenerationError`;
- `InvalidResponseError`, `DoubleRenderError`, `ResponseCommittedError`,
  `UnknownStatusError`, `UnknownServiceError`, `UnsafeRedirectError`;
- `RequestParamsError`, `ParamsParseError`, `ParamsShapeError`,
  `ParamsUnsupportedMediaTypeError`, and `ParamsBodyConsumedError`.

## Supporting modules

### `ember.html`

Public API: `html"""..."""`, `escape`, `raw`, and `join`. The return value is
`ember.Html`. `raw` is an explicit trust boundary. Context-specific escaping or
rejection rules may become stricter before 1.0; accepting unsafe JavaScript,
CSS, or URL interpolation is not a compatibility promise.

### `ember.middleware`

Public API: `before`, `request_id`, `access_log`, `RequestIdMiddleware`, and
`AccessLogMiddleware`. Constructor keyword additions for policy, validation,
redaction, and sinks are compatible. Log formatting from the preview is not a
stable wire/data format; the 1.0 structured event schema will be documented
when introduced.

### `ember.testing`

Public API: `request`, `get`, `query`, `post`, `put`, `patch`, `delete`, `head`,
`options`, `assert_status`, `assert_header`, and `assert_body`. Test helpers
follow the same HTTP contract as `App#call`.

### `ember.integrations.orm`

Public API: `pool`, `connection`, `PoolIntegration`, and
`ConnectionMiddleware`. Ember core remains ORM-neutral. The integration's
request-scoped lease behavior and safe `503` mapping for pool timeout/closed/
lease failures are stable; ORM model/query APIs belong to `amber-orm`.

## Explicitly out of scope

No compatibility is promised for private methods, `__*` helpers, generated
macro AST, header ordering where HTTP says order is insignificant, access-log
text, default error body wording, compiler diagnostics other than documented
diagnostic identifiers, build artifacts, cache layout, or direct imports of
transitive Amber/ORM/SQLite implementation modules.
