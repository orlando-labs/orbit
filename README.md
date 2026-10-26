# Orbit

Orbit is a source-first web framework for Sputnik. It implements the contract in
`sputnik-lang/DESIGN-web-framework-2026-07-13.md` over the existing
`net.http.Server`; it does not add another scheduler or socket layer.

The `1.0.0-rc.1` release candidate includes:

- central, immutable route tables built by `orbit.routes`;
- function, class-side, and per-request controller targets through Sputnik
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
- optional request-scoped `orm` pool integration backed by
  `sqlite3`.

Core Orbit is source-only and ORM-neutral. Importing `orbit` does not pull in
SQLite, FFI, sessions, or a filesystem template loader.
## Web notebook development

The next application milestone is a Sputnik-rendered `.html.sv` shell with a
Vue/Vite client. See the [active plan](docs/WEB_NOTEBOOK_PLAN.md): `orbit-vite`,
safe bootstrap data, session/GitHub auth with project ACL, then the first
notebook Run/reconnect slice. Packages remain local source dependencies until
the full agreed flow is complete.


## Small application

```sputnik
package hello

import orbit

export main

def hello(request, name):
  orbit.render(json: {message: "hello " + name})

routes = orbit.routes:
  get "/hello/:name", to: &hello, as: :hello

def main():
  orbit.App(routes: routes).run(port: 3000)
```

Resolve the exact Sputnik revision, build and install the reproducible Orbit
package, compile the API example, and compile this server with one command:

```sh
./script/clean-room-build
./.build/clean-room/hello/orbit.example.hello
```

The resolver uses `release/dependencies.lock.json`; it does not require a
sibling checkout. Core is the versioned `orbit` package. ORM support is the
separate `orbit-orm` companion package, so core applications do not inherit
ORM, SQLite, or FFI dependencies.

`App#call` is the primary boundary. Most tests should avoid sockets:

```sputnik
import orbit.testing

response = app.call(testing.get("/hello/Sputnik"))
testing.assert_status(response, :ok)
testing.assert_header(response, "content-type", "application/json; charset=utf-8")
```

## Routes

```sputnik
routes = orbit.routes:
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

The normative Orbit 1.0 routing and response rules, including `HEAD`, trailing
slashes, status/content combinations, 404/405, and automatic `OPTIONS`, are in
the [HTTP contract](docs/HTTP_CONTRACT.md).

Use `routes.path(:post, id: 42)`,
`routes.url(:post, id: 42, origin: "https://example.test")`, and
`routes.describe()` for reverse paths and deterministic introspection.

## Controllers and responses

Controllers are constructed once per request:

```sputnik
class Posts < orbit.Controller:
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

Supported normalized return values are `orbit.Response`, `orbit.Html`, `Str`,
`Bytes`, `orbit.StreamingResponse`, and `null`. Other values must be passed
explicitly to `render`, for example `orbit.render(json: value)`.

## Strong parameters

Parameter sources stay explicit: use `request.params.json` for a JSON request
body and `request.params.query` for the parsed query string. A schema filters
every undeclared key and checks the declared transport shape before returning
a deeply immutable `Map`.

```sputnik
create_user_params = orbit.params(root: :user):
  field(:name, required: true)
  field(:age, type: Int)
  array(:tags, of: Str)
  object(:profile):
    field(:bio)

def create_user(request):
  attrs = request.params.json.expect(create_user_params)
  orbit.render(json: attrs, status: :created)
```

`Str` is the default field type, so `field(:name)` is equivalent to
`field(:name, type: Str)`. Fields are optional and non-null by default; use
`required: true` and `nullable: true` explicitly. Arrays accept either a scalar
element type through `of:` or a block describing each object. A schema with
`root:` requires and unwraps that object.

Unknown keys are dropped recursively. Use
`orbit.params(root: :user, unknown: :reject): ...` when an endpoint should
reject them instead. `check` returns `Result[Map, ParamsShapeError]`; `expect`
raises the structured error and lets `App` return a safe 400 response. Missing
or non-JSON content types return 415. Parsing a JSON body after manual
`request.body_stream` consumption returns 400.

Strong parameters do not normalize strings, sanitize HTML, coerce query
values, or replace domain/ORM validation. See `examples/strong_params.s` for
a complete server.

## Streaming

Selecting a streaming response freezes its status, headers, and declared
trailer names. By default Orbit supplies `Transfer-Encoding: chunked`; every `write` is
one HTTP chunk and may carry an ordered list of extension pairs. Close the body
before writing declared trailers, then finish the trailer section. Returning
from the producer also closes and finishes an open stream safely.

```sputnik
def echo(request):
  orbit.stream(trailers: ["x-state"]) |response|:
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

Use `orbit.stream(length: size)` (also available in `Controller#stream`) when
the byte count is known. The transport emits `Content-Length` and writes each
part directly without chunk framing or whole-body buffering:

```sputnik
orbit.stream(length: 6) |response|:
  response.write("one")
  response.write("two")
```

`length` is a nonnegative `Int`, or `null` for chunked mode. Fixed-length
streams reject trailers/chunk extensions. Overflow raises `BodyLengthError`
before excess bytes are sent; a short close/producer also fails and closes
the connection. HEAD preserves the declared length without invoking the
producer. Framing headers remain transport-owned in either mode.

## Middleware and `before`

Middleware follows `(Request, Next) -> Response`. Application middleware wraps
scope/mount middleware, which wraps route middleware and then the target.

```sputnik
from orbit.middleware import before

before [&request_id, &authenticate]
def create(request):
  orbit.render(text: request.query(:name), status: :created)
```

`before` preserves the public function name and signature and applies to direct
calls as well as routed calls. It accepts a middleware value or one ordered
list. Route-dependent policy belongs in the central route declaration.

## HTML and views

Views are ordinary typed Sputnik modules. Interpolation in `html"""..."""` is
escaped by default and returns `orbit.Html`; trusted output requires explicit
`raw(...)`.

```sputnik
from orbit.html import escape, html, join

def page(title as Str):
  html"""
    <h1>#{title}</h1>
    """
```

Template regions can repeat at runtime with ordinary Sputnik iteration:

```sputnik
from orbit.html import html, escape

def list(items):
  html"""
    <ul>
    %for item with_index index in items:
      <li data-index="#{index}">#{item.name}</li>
    </ul>
    """
```

The iterable evaluates once; patterns, Map key/value arguments and nested loops
work as in `for`. Directive lines emit no newline, extra body indent is stripped,
and an empty loop emits nothing. `%#` comments are omitted and `%%` emits `%`.
Only `%for` is implemented. Escaping and typed trust rules apply to every
iteration. Loops must begin and end in HTML text context: placing one inside an
attribute, tag, comment, script or style, or leaving such a context open in its
body, fails with `ORBIT_HTML_CONTROL_CONTEXT`.

External `.html.sv` bodies are supported through the compiler source-format
registry. Declare inputs/imports in ordinary Sputnik:

```sputnik
package app.views.posts
export index

@template("./posts/index.html.sv")
def index(posts, title: "Posts")
```

The external file contains only template text, `#{...}` and `%for` controls.
Register `source_formats: [{suffix: .html.sv, module: orbit.html, macro: html}]`
in the project build manifest and include the provider modules/dependencies.
Call `index(posts, title: "Latest")` normally. Helpers for escaping are resolved
by the provider, so external HTML declarations need no `escape` import. Source
errors point to `.sv`; template/provider changes invalidate compiled output.
The executable embeds rendering code and needs no template files at runtime.
See [`test/external_templates_selftest.s`](test/external_templates_selftest.s)
and the [SDK contract](../sputnik-lang/docs/engineering/external-templates-v1.md).

The macro tracks the output interpreter context. Text and ordinary quoted
attributes escape automatically; URL attributes require `url(...)`, script or
event-handler data requires `trusted_script(...)`, style data requires
`trusted_style(...)`, and `srcdoc` requires explicit `raw(...)`. Interpolation
inside comments, tag syntax, or unquoted attributes is a compile-time
`ORBIT_HTML_CONTEXT` error.

```sputnik
from orbit.html import html, escape, url

def item_link(label, id):
  destination = url("/items/" + id.to_str)
  html"""
    <a href="#{destination}">#{label}</a>
    """
```

`raw` and the trusted wrappers are review boundaries, not sanitizers. See the
[security baseline](docs/SECURITY.md) for the complete context contract.

## Security baseline

Every application has an `orbit.SecurityPolicy`. Its development default
accepts only localhost authorities, ignores forwarding headers, and adds CSP,
nosniff, frame, referrer, permissions, and opener policies. Production must
configure exact hosts and its trusted edge explicitly:

```sputnik
security = orbit.SecurityPolicy(
  allowed_hosts: ["app.example.test"],
  trusted_proxy_cidrs: ["10.20.0.0/16"],
  forwarded: :x_forwarded,
  forwarded_hops: 2,
  hsts: true)

app = orbit.App(routes: routes, security: security)
```

Host authorization happens before routing. Untrusted forwarding fields are
ignored; trusted chains are bounded and validated before they drive
`request.origin()`, `request.client_ip`, or secure-cookie/HSTS decisions.

Import `orbit.security` for `CookieJar`, `SetCookie`, `SignedCookieCodec`,
`SessionCodec`, `CorsMiddleware`, and `CsrfMiddleware`. Import
`orbit.multipart` for the strict parser and `MultipartLimits`. These APIs do
not turn authentication, authorization, upload content validation/storage,
key management, or CORS policy into implicit framework behavior. The
[threat model](docs/THREAT_MODEL.md), [ASVS map](docs/ASVS_5_MAPPING.md), and
[review record](docs/SECURITY_REVIEW.md) define the exact responsibility split.

## Session companions

The working [`orbit-session`](packages/orbit-session/README.md) package adds
request-scoped sessions, controller helpers, encrypted cookie storage, and
bounded process-local memory storage. It has no User or ORM dependency.
[`orbit-session-orm`](packages/orbit-session-orm/README.md) adds atomic,
model-backed persistence through the existing ORM adapters, with no dependency
on a particular database driver. Development build graphs use local sources;
these companions have not been published.

Cookie storage avoids database writes but cannot revoke copied cookies or
detect concurrent updates. Memory/ORM stores enforce revision checks and
revocation; conflicting saves return 409. For browser applications, place
`CsrfMiddleware(session_service: :session, secret: ...)` after the session
middleware so CSRF uses the stable session ID rather than changing ciphertext.
See the package READMEs for lifecycle, limits, schema, and local test commands.

## OAuth companions

[`orbit-oauth`](packages/orbit-oauth/README.md) implements Authorization Code
with PKCE S256, refresh tokens, Client Credentials, bounded browser state, and
controller helpers. [`orbit-oauth-github`](packages/orbit-oauth-github/README.md)
adds GitHub endpoints, authenticated profiles, and verified primary email.
The controller receives an explicit `Result`; account lookup, session rotation,
and optional User persistence remain application decisions. Neither package
depends on ORM or a session store. Development graphs resolve local sources;
these packages have not been published.

## ORM integration

Models bind to one shareable pool during startup. Installing
`orbit.integrations.orm.pool(database)` gives every controller target one
request-scoped lease; nested ORM calls reuse it and spawned child tasks acquire
their own lease.

```sputnik
import orm
from orbit.integrations.orm import pool as orm_pool

class Person:
  use orm.model(table: :people)

database.bind!(Person).or_raise

app = orbit.App(
  routes: routes,
  integrations: [orm_pool(database)])
```

Bare handlers have no hidden controller lifecycle. Use route middleware
`before: [orbit_orm.connection(database)]` or the `before` annotation.
Pool timeout, closed, and lease failures become a safe 503 response.
Transactions remain explicit business boundaries through the ORM model/pool.
The pool integration participates in server startup/readiness/shutdown, so a
deadline cancellation unwinds request leases before the pool closes.
Custom lifecycle-aware controller integrations subclass `orbit.Integration`;
its default `start`, `attach_server`, `ready?`, and `stop` methods are safe no-ops.

See `examples/sqlite_users.s` and `test/orm_selftest.s` for complete graphs.
The ORM test/example/soak graphs load the sibling `../orm` and `../sqlite3`
working directories directly, including native SQLite sources. During web
notebook development, rebuild against these local sources; package release
locks and published archives are not updated by these graphs.

## Production transport lifecycle

Use `App#start` when the process adapter needs readiness and graceful shutdown:

```sputnik
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

# Representative controller CRUD service + Sputnik client smoke
./script/soak smoke

# Constant/mixed-load run; 72h is the default and required evidence duration
./script/soak run --duration 72h --artifacts /durable/orbit-soak-evidence
```

CI runs the core lane on Linux x86_64, Linux arm64, and macOS arm64 against the
exact Sputnik compiler/runtime revision. The release workflow accepts only an
annotated `v$VERSION` tag, rebuilds the signed package twice, compares bytes,
and publishes checksums plus provenance. See the
[release process](docs/RELEASING.md), [API reference](docs/API_REFERENCE.md),
[configuration reference](docs/CONFIGURATION.md), and
[operations runbook](docs/RUNBOOK.md). The controller-based catalog service,
Sputnik CRUD/4xx client, resource thresholds, and evidence format are documented
in the [72-hour soak test](docs/SOAK_TEST.md).

## Orbit 1.0 contract

The accepted [Orbit 1.0 contract ADR](docs/adr/0001-orbit-1-0-contract.md)
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
cancellation, and idempotent shutdown. Orbit now provides strict multipart,
cookie/session, CSRF/CORS, Host, and proxy-trust primitives. It still does not
claim direct TLS, HTTP/2/3, WebSocket, user authentication/authorization,
uploaded-file storage/scanning, or complete application security; those remain
explicit edge or application layers, not hidden behavior.

The unsupported 1.0 surface also includes WebSocket, hot reload,
generators/resources, an asset pipeline, and dynamically replaceable
route snapshots. The complete supported/unsupported boundary is in the
[versioned API reference](docs/API_REFERENCE.md).

Dynamic slugs and CMS paths remain database data behind static parameter or
lowest-precedence wildcard routes. Normalization, history, tenant/locale
scope, reserved root names, uniqueness, and cache invalidation are application
repository policy; they never mutate `Routes`.
