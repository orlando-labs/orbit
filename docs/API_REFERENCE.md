# Orbit 1.0 API reference

Version: `1.0.0-rc.1`. This is the callable reference for the public surface
defined by [PUBLIC_API.md](PUBLIC_API.md). The machine-readable allowlist is
`release/public-api.json`; CI rejects an undocumented public export or a stale
entry. Examples are compiled by `test/api_reference_selftest.build.yaml`, HTML
macro contexts by `test/stage3_selftest.build.yaml`, and the ORM section by
`test/orm_selftest.build.yaml`.
Origin/CSP checks also have a standalone full-native fixture,
`test/security_policy_selftest.build.json`, included by the stage-3 suite.

Exact error message text and names listed as internal exports are not API.
Arguments shown with defaults retain those defaults for Orbit 1.x.

Working authentication companions are documented separately:
[`orbit-oauth`](../packages/orbit-oauth/README.md) provides protocol flows and
controller results; [`orbit-oauth-github`](../packages/orbit-oauth-github/README.md)
adds GitHub identity resolution. They are local development packages, outside
the root package's 1.0 export allowlist, and depend on no User/ORM model.

## `orbit`

### Routing macros

- `routes(&block) -> Routes` builds an immutable route table.
- `get`, `query`, `post`, `put`, `patch`, `delete`, `head`, and `options`
  declare a route with `to:`, optional `as:`, `params:`, and `before:`.
- `scope(prefix, before: [], &block)` and `mount(routes, at: "/", before: [])`
  compose tables without a mutable global registry.
- `params(root: null, unknown: :drop, &block)`, `field`, `object`, and `array`
  construct strong-parameter schemas.

### Application and lifecycle

- `App(routes:, middleware: [], integrations: [], services: {}, security:
  null, head_fallback: true, automatic_options: true, expose_exceptions:
  false, on_error: null, telemetry: null)`.
- `App#call(request)`, `server(**options)`, `start(max_requests: null,
  **options)`, and `run(**options, max_requests: null)`.
- `ServerHandle#start`, `serve`, `wait`, `ready?`, `accepting?`,
  `stop_accepting`, `shutdown`, `in_flight`, `stats`, `port`, and
  `local_endpoint` implement the lifecycle in [TRANSPORT.md](TRANSPORT.md).
- `Integration` supplies `start`, `attach_server`, `ready?`, `stop`, and the
  `around_controller(request, next)` extension protocol.
- `ErrorEvent` exposes redacted `error_type`, `request_method`,
  `route_pattern`, and `request_id` to the configured error hook.

### Requests, responses, and headers

- `Request(method:, target:, path:, raw_query:, headers:, body_text:,
  body_bytes:, body_stream:, remote_endpoint:, local_endpoint:)` is the
  in-memory constructor. Reads include method/target/path/query, immutable
  `Headers`, body accessors, path/query params, services, route metadata,
  validated origin/scheme/authority/client IP, and `secure?`.
- `RequestBodyStream#framing`, `read_chunk`, `each_chunk`, `trailers`,
  `closed?`, and `started?`; `RequestChunk#bytes`, `text`, and `extensions`.
- `Response(status: 200, headers: {}, body: "")`; reads are `status`,
  `headers`, `body`, `header`, `body_text`, and `body_bytes`.
- `StreamingResponse(status: 200, headers: {}, trailers: [], length: null, &producer)` and
  `StreamBody#write`, `close`, `trailer`, `finish`, and `closed?`.
  `stream`/`Controller#stream` accept `length:`; response `length` is read-only.
  `null` selects chunked; a nonnegative `Int` selects fixed-length framing with
  exact byte enforcement and without trailers/chunk extensions. HEAD advertises
  known length without starting the producer. Direct framing headers are rejected.
- `Headers(source = null)` reads with `first`, `all`, `include?`, `size`,
  `empty?`, `keys`, `each`, and `to_pairs`; persistent updates are `add`,
  `set`, `delete`, `without`, and `merge`.
- `render`, `redirect`, `stream`, `normalize_response`, and `status_code`
  create or normalize responses. `Html` provides `escape`, `raw`, `join`,
  `to_str`, and concatenation.

### Content negotiation

- `respond(default: null, &block)` is a controller macro with lazy `html`,
  `json`, `text` and `format(mime, encode: :body)` branches. It negotiates
  Accept, returns 406 when no offer matches and 400 for malformed Accept, and
  merges `Vary: Accept` with existing variance. `status_code(:not_acceptable)`
  is 406. Standard branches return payloads; ready buffered/streaming responses
  retain their explicit status and lifecycle.
- `Format(mime, encode: :body)` is a reusable MIME/encoder descriptor with
  read-only `mime`, `type`, `subtype`, `params`, `encoder` and `identity`.
- `Request#negotiate(formats, default: null)` returns the selected Format or
  null and raises `InvalidAcceptError` for malformed Accept.
- See [content negotiation](CONTENT_NEGOTIATION.md) for selection, defaults,
  arbitrary MIME parameters, encoders, limits and response preservation.

### Controllers, targets, and routing values

- `Controller` helpers are `request`, `status`, `header`, `render`,
  `redirect`, `stream`, `path`, `service`, `path_param`, `query`, and
  `params`.
- `Target.function(callable)`, `Target.controller(action)`, and
  `Target#invoke` are the adapter/DSL target boundary.
- `Routes#lookup`, `match`, `path`, `url`, and `describe`; immutable values are
  `Route`, `RouteMatch`, and `RouteLookup` with the fields specified in
  [PUBLIC_API.md](PUBLIC_API.md).

### Strong parameters and security provenance

- Values: `ParamSchema`, `ParamField`, `ParamObject`, `ParamArray`,
  `ParamIssue`, `RequestParams`, and `RequestParamSource`. Sources expose
  `check` and `expect`; request sources are `json` and `query`.
- `Origin(value)` validates an HTTP(S) origin. Read-only fields are `scheme`,
  `host`, `port` (effective integer port), and `authority`; `to_str`/`str`
  return its canonical spelling, `secure?` identifies HTTPS, and `websocket`
  derives the WS(S) origin. Host case, default ports and an optional trailing
  slash normalize; credentials, paths, query/fragment, ambiguous numeric IPs,
  malformed authorities and out-of-range ports are rejected.
- `ContentSecurityPolicy(**directives)` builds a bounded CSP header from source
  lists. `.with(**directives)` returns a new policy, replacing the specified
  lists and preserving other directives; it never mutates the original.
  Keyword names use underscores (`script_src`, `img_src`, `connect_src`, etc.).
  Sources are arrays of exact HTTP(S)/WS(S) origins, `"*"`, or explicit keywords
  `:self`, `:none`, `:data`, `:blob`, `:unsafe_inline`, `:unsafe_eval`,
  `:strict_dynamic`, `:unsafe_hashes`, `:report_sample`, `:wasm_unsafe_eval`.
  An empty list serializes as `'none'`; `'none'` cannot mix with other sources.
  `to_str`/`str` return the serialized header. See [SECURITY.md](SECURITY.md).
- `SecurityPolicy(origin: null, allowed_hosts: null, trusted_proxy_cidrs: [], forwarded: :none,
  forwarded_hops: 0, security_headers: true, content_security_policy: ...,
  hsts: false)` authorizes request provenance before routing.
  `origin` accepts an `Origin` or string, defaults the allowed hosts to that
  origin's host, and checks the effective scheme/host/port after trusted-proxy
  processing. Without it, the previous localhost host defaults apply.
  `content_security_policy` accepts `ContentSecurityPolicy`, the existing raw
  header string, or explicit `null`. The default is `ContentSecurityPolicy()`.

### Public errors

The stable semantic error classes are `OrbitError`, `RouteError`,
`InvalidRouteError`, `DuplicateRouteError`, `DuplicateRouteNameError`,
`InvalidPathError`, `RouteParamError`, `RouteNotFoundError`,
`UnknownRouteNameError`, `PathGenerationError`, `InvalidResponseError`,
`DoubleRenderError`, `ResponseCommittedError`, `ServerLifecycleError`,
`UnknownStatusError`, `UnknownServiceError`, `UnsafeRedirectError`,
`RequestParamsError`, `ParamsParseError`, `ParamsShapeError`,
`ParamsUnsupportedMediaTypeError`, `ParamsBodyConsumedError`,
`RequestSecurityError`, `InvalidAuthorityError`, `UnauthorizedHostError`,
`InvalidForwardedRequestError`, and `UnauthorizedOriginError`.

## `orbit.assets`

`StaticFiles(root: "./assets", at: "/", chunk_size: 65536,
cache_control: "public, max-age=3600")` is an optional middleware serving public
application files. Add `StaticFiles()` before session/CSRF middleware. It streams
GET responses through scoped `fs.File.open` / `each_chunk` and `orbit.stream`
with known length; HEAD returns metadata without opening the producer. Missing
or unsupported paths fall through to application routing. Requires `fs.read`
and `fs.metadata` grants. See [static files](STATIC_FILES.md).

## `orbit.html`

`html"""..."""` returns `orbit.Html`. `escape`, `escape_text`,
`escape_attribute`, `raw`, and `join` handle normal HTML values. URL and active
contexts require `url`/`HtmlUrl`, `trusted_script`/`TrustedScript`, or
`trusted_style`/`TrustedStyle` as described in
[SECURITY.md](SECURITY.md). These trust wrappers are not sanitizers.

## `orbit.middleware`

`before`, `request_id`, `access_log`, `RequestIdMiddleware`, and
`AccessLogMiddleware` are public. Middleware follows `(Request, next) ->
response`; `next` may be called once. Production request observation should use
the application telemetry boundary to include framework errors.

## `orbit.telemetry`

- Sinks/events: `RedactionPolicy`, `JsonLogSink`, `MemorySink`, `AccessEvent`,
  and `ErrorLogEvent`.
- Tracing: `TraceContext`, `ServerSpan`, and `Tracer`.
- Operations: `MetricsRegistry`, `HealthProbe`, and aggregate `Telemetry`.

The stable schema, cardinality bounds, methods, and lifecycle timing are in
[OBSERVABILITY.md](OBSERVABILITY.md).

## `orbit.security`

- Cookies and envelopes: `CookieLimits`, `CookieJar`, `SetCookie`, `Aead`,
  `SignedCookieCodec`, and `SessionCodec`.
- Browser boundary: `CorsMiddleware`, `CsrfProtection`, and `CsrfMiddleware`.
- Catchable errors: `SecurityError`, `CookieError`, `SessionError`, and
  `CsrfError`.

Constructor limits, key rotation, expiry, safe cookie defaults, and
application obligations are normative in [SECURITY.md](SECURITY.md).
`CsrfMiddleware(session_service: :session, secret: ...)` integrates with the
optional [orbit-session companion](../packages/orbit-session/README.md);
otherwise CSRF retains its `session_cookie:` identity source.

## `orbit.multipart`

`parse(request, limits: MultipartLimits()) -> MultipartForm` returns bounded
`MultipartPart` values. Public types are `MultipartLimits`, `MultipartPart`,
`MultipartForm`, and `MultipartError`. Parts expose name, filename,
content-type, headers, bytes, text, and `file?`; forms expose `parts`, `first`,
`all`, `fields`, and `files`.

## `orbit.testing`

`request`, `get`, `query`, `post`, `put`, `patch`, `delete`, `head`, and
`options` create in-memory requests. `assert_status`, `assert_header`, and
`assert_body` verify normalized responses.

## `orbit.integrations.orm` companion package

Install the separate `orbit-orm` package to use `pool`, `connection`,
`PoolIntegration`, and `ConnectionMiddleware`. It pins `orbit` and
`orm`; applications that use the SQLite adapter additionally pin the
tested `sqlite3` row from [COMPATIBILITY.md](COMPATIBILITY.md). Core
Orbit has no ORM, SQLite, or FFI dependency.

## Unsupported preview surface

The following are intentionally not part of this reference: direct public
TLS, HTTP/2/3, WebSocket, hot reload, generators/resources, asset
pipeline in core, dynamic route replacement, exported `__*` macro plumbing, exported
single-underscore HTML macro helpers, log text formatting, generated code,
cache paths, and concrete transitive Sputnik/ORM/SQLite implementation details.

## External view bodies

`template("./page.html.sv")` on a declaration-only module function uses its
ordinary input signature and lexical imports. Build-manifest `source_formats`
selects the `orbit.html` / `html` provider. See the README and
`test/external_templates_selftest.build.yaml`. Runtime rendering uses compiled
code; source files are compiler inputs, not runtime filesystem templates.

## JSON bootstrap and Vite companion

`orbit.html.json_script(data, id:, nonce: null) -> orbit.Html` encodes a
non-executable JSON island with escaped HTML-sensitive characters, separators
and attributes. Read it using DOM `textContent` and `JSON.parse`; application
wire schemas carry large IDs as strings and exclude credentials/session bearers.

The separate [`orbit-vite`](../packages/orbit-vite/README.md) package exports
`Assets` and `ManifestError`. `Assets` defaults to `./frontend`, production mode,
and `src/main.ts`; `tags(entry: null, nonce: null, preload: true)` returns an
HTML asset fragment. See [`examples/vue_shell`](../examples/vue_shell/README.md)
for `.html.sv`, dev/HMR, production manifest/assets and GitHub/session integration.
