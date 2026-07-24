# Ember

Ember is a source-first web framework for Amber. It implements the contract in
`amber-lang/DESIGN-web-framework-2026-07-13.md` over the existing
`net.http.Server`; it does not add another scheduler or socket layer.

The `1.0.0-rc.1` release candidate includes:

- central, immutable route tables built by `ember.routes`;
- function, class-side, and per-request controller targets through Amber
  callable references;
- literal, typed parameter, and terminal wildcard routes with deterministic
  precedence;
- named paths, scopes, mounts, route middleware, automatic OPTIONS, and
  HEAD-from-GET by default with an explicit opt-out;
- RFC 10008 `QUERY` routes with request content and mandatory `Content-Type`;
- declarative strong-parameter schemas for JSON bodies and query strings;
- request/response values, JSON/text/HTML rendering, safe redirects, and
  production-safe exception responses;
- cooperative full-duplex HTTP/1.1 request/response streams with chunk
  extensions and trailers;
- bounded HTTP/1.1 keep-alive, immediate overload rejection, and an explicit
  readiness/drain/deadline-shutdown server lifecycle;
- pre-routing Host authorization, explicit trusted-proxy CIDRs/hops, validated
  request provenance, and safe browser response headers;
- context-aware `html"""..."""` templates with typed URL/script/style trust
  boundaries and compile-time rejection of ambiguous contexts;
- bounded cookies, HMAC-signed values, encrypted authenticated sessions,
  exact CORS, CSRF protection, and strict multipart parsing in optional source
  modules;
- in-memory request builders and response assertions;
- optional request-id/access-log middleware and the function-intrinsic
  `before` annotation macro;
- structured redacted access/error/lifecycle telemetry, bounded metrics,
  trusted-edge W3C tracing, and lifecycle-aware health/readiness probes;
- optional request-scoped `amber-orm` pool integration backed by
  `sqlite3-amber`.

Core Ember is source-only and ORM-neutral. Importing `ember` does not pull in
SQLite, FFI, sessions, or a filesystem template loader.

## Small application

```amber
package hello

import ember

export main

def hello(request, name):
  ember.render(json: {message: "hello " + name})

routes = ember.routes:
  get "/hello/:name", to: &hello, as: :hello

def main():
  ember.App(routes: routes).run(port: 3000)
```

Resolve the exact Amber revision, build and install the reproducible Ember
package, compile the API example, and compile this server with one command:

```sh
./script/clean-room-build
./.build/clean-room/hello/ember.example.hello
```

The resolver uses `release/dependencies.lock.json`; it does not require a
sibling checkout. Core is the versioned `ember` package. ORM support is the
separate `ember-orm` companion package, so core applications do not inherit
ORM, SQLite, or FFI dependencies.

`App#call` is the primary boundary. Most tests should avoid sockets:

```amber
import ember.testing

response = app.call(testing.get("/hello/Amber"))
testing.assert_status(response, :ok)
testing.assert_header(response, "content-type", "application/json; charset=utf-8")
```

## Routes

```amber
routes = ember.routes:
  get "/posts/new", to: &new_post
  get "/posts/:id", to: &Posts#show,
    params: {id: Int}, as: :post
  query "/posts/search", to: &search_posts

  scope "/api", before: [&authenticate]:
    get "/profile", to: &Profiles#show

  mount AdminRoutes, at: "/admin"
```

Matching precedence is literal, then parameter, then wildcard. Paths are split
before percent decoding, malformed encodings are rejected, trailing slashes
match strictly, and route/path/segment sizes are bounded. A wildcard must be
terminal. Duplicate normalized shapes and duplicate names are rejected when a
`Routes` value is constructed.

The normative Ember 1.0 routing and response rules, including `HEAD`, trailing
slashes, status/content combinations, 404/405, and automatic `OPTIONS`, are in
the [HTTP contract](docs/HTTP_CONTRACT.md).

Use `routes.path(:post, id: 42)`,
`routes.url(:post, id: 42, origin: "https://example.test")`, and
`routes.describe()` for reverse paths and deterministic introspection.

## Controllers and responses

Controllers are constructed once per request:

```amber
class Posts < ember.Controller:
  def show(id as Int):
    status(:ok)
    header("cache-control", "private")
    render(json: {id: id})
```

Function handlers receive the request first. Controller actions receive route
captures; request, services, named paths, render, and redirect are inherited
helpers. Rendering twice or mutating status/headers after commit raises a
framework error.

Inside an object method, an unresolved bare identifier is a dynamic nullary
send to that method's `self`, so inherited or included helpers such as
`request`, `params`, and `render` remain concise. A lexical binding with the
same name always wins. Outside an object method there is no implicit receiver,
and an unresolved bare identifier is a compile-time error.

Supported normalized return values are `ember.Response`, `ember.Html`, `Str`,
`Bytes`, `ember.StreamingResponse`, and `null`. Other values must be passed
explicitly to `render`, for example `ember.render(json: value)`.

## Strong parameters

Parameter sources stay explicit: use `request.params.json` for a JSON request
body and `request.params.query` for the parsed query string. A schema filters
every undeclared key and checks the declared transport shape before returning
a deeply immutable `Map`.

```amber
create_user_params = ember.params(root: :user):
  field(:name, required: true)
  field(:age, type: Int)
  array(:tags, of: Str)
  object(:profile):
    field(:bio)

def create_user(request):
  attrs = request.params.json.expect(create_user_params)
  ember.render(json: attrs, status: :created)
```

`Str` is the default field type, so `field(:name)` is equivalent to
`field(:name, type: Str)`. Fields are optional and non-null by default; use
`required: true` and `nullable: true` explicitly. Arrays accept either a scalar
element type through `of:` or a block describing each object. A schema with
`root:` requires and unwraps that object.

Unknown keys are dropped recursively. Use
`ember.params(root: :user, unknown: :reject): ...` when an endpoint should
reject them instead. `check` returns `Result[Map, ParamsShapeError]`; `expect`
raises the structured error and lets `App` return a safe 400 response. Missing
or non-JSON content types return 415. Parsing a JSON body after manual
`request.body_stream` consumption returns 400.

Strong parameters do not normalize strings, sanitize HTML, coerce query
values, or replace domain/ORM validation. See `examples/strong_params.am` for
a complete server.

## Streaming

Selecting a streaming response freezes its status, headers, and declared
trailer names. Ember supplies `Transfer-Encoding: chunked`; every `write` is
one HTTP chunk and may carry an ordered list of extension pairs. Close the body
before writing declared trailers, then finish the trailer section. Returning
from the producer also closes and finishes an open stream safely.

```amber
def echo(request):
  ember.stream(trailers: ["x-state"]) |response|:
    request.body_stream.each_chunk |chunk|:
      response.write(chunk.bytes, extensions: chunk.extensions)
    response.close
    response.trailer("x-state", "complete")
    response.finish
```

`request.body_stream.framing` is `:chunked`, `:content_length`, or `:empty`.
Chunked requests preserve wire chunk boundaries, ordered/repeated extensions,
and trailers. Content-Length requests yield bounded application parts with no
extensions or trailers; an unframed request is immediately empty. The producer
runs cooperatively, so it may alternate request reads and response writes
without draining the request first.

## Middleware and `before`

Middleware follows `(Request, Next) -> Response`. Application middleware wraps
scope/mount middleware, which wraps route middleware and then the target.

```amber
from ember.middleware import before

before [&request_id, &authenticate]
def create(request):
  ember.render(text: request.query(:name), status: :created)
```

`before` preserves the public function name and signature and applies to direct
calls as well as routed calls. It accepts a middleware value or one ordered
list. Route-dependent policy belongs in the central route declaration.

## HTML and views

Views are ordinary typed Amber modules. Interpolation in `html"""..."""` is
escaped by default and returns `ember.Html`; trusted output requires explicit
`raw(...)`.

```amber
from ember.html import escape, html, join

def page(title as Str):
  html"""
    <h1>#{title}</h1>
    """
```

External `.amv` files are intentionally not advertised: they require the
compiler-level source-format registry described by the design. Ember does not
read templates from the filesystem during macro expansion.

The macro tracks the output interpreter context. Text and ordinary quoted
attributes escape automatically; URL attributes require `url(...)`, script or
event-handler data requires `trusted_script(...)`, style data requires
`trusted_style(...)`, and `srcdoc` requires explicit `raw(...)`. Interpolation
inside comments, tag syntax, or unquoted attributes is a compile-time
`EMBER_HTML_CONTEXT` error.

```amber
from ember.html import html, url

def item_link(label, id):
  destination = url("/items/" + id.to_str)
  html"""
    <a href="#{destination}">#{label}</a>
    """
```

`raw` and the trusted wrappers are review boundaries, not sanitizers. See the
[security baseline](docs/SECURITY.md) for the complete context contract.

## Security baseline

Every application has an `ember.SecurityPolicy`. Its development default
accepts only localhost authorities, ignores forwarding headers, and adds CSP,
nosniff, frame, referrer, permissions, and opener policies. Production must
configure exact hosts and its trusted edge explicitly:

```amber
security = ember.SecurityPolicy(
  allowed_hosts: ["app.example.test"],
  trusted_proxy_cidrs: ["10.20.0.0/16"],
  forwarded: :x_forwarded,
  forwarded_hops: 2,
  hsts: true)

app = ember.App(routes: routes, security: security)
```

Host authorization happens before routing. Untrusted forwarding fields are
ignored; trusted chains are bounded and validated before they drive
`request.origin()`, `request.client_ip`, or secure-cookie/HSTS decisions.

Import `ember.security` for `CookieJar`, `SetCookie`, `SignedCookieCodec`,
`SessionCodec`, `CorsMiddleware`, and `CsrfMiddleware`. Import
`ember.multipart` for the strict parser and `MultipartLimits`. These APIs do
not turn authentication, authorization, upload content validation/storage,
key management, or CORS policy into implicit framework behavior. The
[threat model](docs/THREAT_MODEL.md), [ASVS map](docs/ASVS_5_MAPPING.md), and
[review record](docs/SECURITY_REVIEW.md) define the exact responsibility split.

## ORM integration

Models bind to one shareable pool during startup. Installing
`ember.integrations.orm.pool(database)` gives every controller target one
request-scoped lease; nested ORM calls reuse it and spawned child tasks acquire
their own lease.

```amber
import orm
from ember.integrations.orm import pool as orm_pool

class Person:
  use orm.model(table: :people)

database.bind!(Person).or_raise

app = ember.App(
  routes: routes,
  integrations: [orm_pool(database)])
```

Bare handlers have no hidden controller lifecycle. Use route middleware
`before: [ember_orm.connection(database)]` or the `before` annotation.
Pool timeout, closed, and lease failures become a safe 503 response.
Transactions remain explicit business boundaries through the ORM model/pool.
The pool integration participates in server startup/readiness/shutdown, so a
deadline cancellation unwinds request leases before the pool closes.
Custom lifecycle-aware controller integrations subclass `ember.Integration`;
its default `start`, `attach_server`, `ready?`, and `stop` methods are safe no-ops.

See `examples/sqlite_users.am` and `test/orm_selftest.am` for complete graphs.

## Production transport lifecycle

Use `App#start` when the process adapter needs readiness and graceful shutdown:

```amber
server = app.start(
  port: 3000,
  workers: 2,
  max_concurrent_per_worker: 64,
  idle_timeout: 15.0,
  max_requests_per_connection: 100,
  shutdown_timeout: 30.0,
  overload: :reject)

# In the signal/platform adapter:
server.stop_accepting()
clean = server.shutdown()
stats = server.wait()
```

`ready?`, `accepting?`, `in_flight`, and `stats` expose lifecycle state.
Shutdown first stops admission, drains buffered and streaming requests, then
closes streams and cooperatively cancels remaining tasks at the deadline.
Integration stop hooks run once, in reverse order, after all request `ensure`
scopes have unwound. See the complete [transport contract](docs/TRANSPORT.md)
and [edge deployment model](docs/DEPLOYMENT.md).

## Verification

```sh
# Package/install/API/server clean-room gate, without sibling checkouts
./script/clean-room-build

# Static/docs/locks, native self-tests, raw HTTP conformance, parser/framing
# fuzz smoke, examples, ORM/SQLite integration, and clean-room
./script/ci full

# Representative controller CRUD service + Amber client smoke
./script/soak smoke

# Constant/mixed-load run; 72h is the default and required evidence duration
./script/soak run --duration 72h --artifacts /durable/ember-soak-evidence
```

CI runs the core lane on Linux x86_64, Linux arm64, and macOS arm64 against the
exact Amber compiler/runtime revision. The release workflow accepts only an
annotated `v$VERSION` tag, rebuilds the signed package twice, compares bytes,
and publishes checksums plus provenance. See the
[release process](docs/RELEASING.md), [API reference](docs/API_REFERENCE.md),
[configuration reference](docs/CONFIGURATION.md), and
[operations runbook](docs/RUNBOOK.md). The controller-based catalog service,
Amber CRUD/4xx client, resource thresholds, and evidence format are documented
in the [72-hour soak test](docs/SOAK_TEST.md).

## Ember 1.0 contract

The accepted [Ember 1.0 contract ADR](docs/adr/0001-ember-1-0-contract.md)
closes the semantic decisions from roadmap stage 0. Its supporting documents
define the [public API boundary](docs/PUBLIC_API.md),
[edge deployment model](docs/DEPLOYMENT.md),
[compatibility policy](docs/COMPATIBILITY.md), and measurable
[production-readiness gates](docs/PRODUCTION_READINESS.md). Contract,
correctness, production-transport, security, observability/performance, and
release-engineering gates 0–5 are complete; RC canary/load/soak/fuzz/rollback
validation remains. See the
[observability contract](docs/OBSERVABILITY.md) and
[performance contract](docs/PERFORMANCE.md).

## Current transport boundary

The low-level server is plaintext HTTP/1.1 with bounded sequential keep-alive
and pipelining, finite idle/request limits, hard connection capacity, and
immediate `503` overload rejection. Buffered and chunked full-duplex bodies are
supported, including `Expect: 100-continue`, chunk extensions, and trailers.
The server handle implements stop-accepting, clean drain, deadline
cancellation, and idempotent shutdown. Ember now provides strict multipart,
cookie/session, CSRF/CORS, Host, and proxy-trust primitives. It still does not
claim direct TLS, HTTP/2/3, WebSocket, user authentication/authorization,
uploaded-file storage/scanning, or complete application security; those remain
explicit edge or application layers, not hidden behavior.

The unsupported 1.0 surface also includes WebSocket, hot reload,
generators/resources, `.amv`, an asset pipeline, and dynamically replaceable
route snapshots. The complete supported/unsupported boundary is in the
[versioned API reference](docs/API_REFERENCE.md).

Dynamic slugs and CMS paths remain database data behind static parameter or
lowest-precedence wildcard routes. Normalization, history, tenant/locale
scope, reserved root names, uniqueness, and cache invalidation are application
repository policy; they never mutate `Routes`.
