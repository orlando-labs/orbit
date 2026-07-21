# Ember

Ember is a source-first web framework for Amber. It implements the contract in
`amber-lang/DESIGN-web-framework-2026-07-13.md` over the existing
`net.http.Server`; it does not add another scheduler or socket layer.

The current preview includes:

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
- inline escaped `html"""..."""` templates and ordinary typed Amber view
  modules;
- in-memory request builders and response assertions;
- optional request-id/access-log middleware and the function-intrinsic
  `before` annotation macro;
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

Build a server with an explicit listen grant:

```sh
../amber-lang/build/amberc build examples/hello.build.yaml \
  --target native --out-dir out-example --cache-dir cache-example \
  --grant net.listen --grant random.secure
./out-example/ember.example.hello
```

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

See `examples/sqlite_users.am` and `test/orm_selftest.am` for complete graphs.

## Verification

```sh
# Stage 0 HTTP/routing contract
../amber-lang/build/amberc build test/contract_selftest.build.yaml \
  --target native --out-dir out-contract-native \
  --cache-dir cache-contract-native --no-cache
./out-contract-native/ember.contract_selftest

# Source-only framework behavior
../amber-lang/build/amberc build test/core_selftest.build.yaml \
  --target native --out-dir out-native --cache-dir cache-native --no-cache
./out-native/ember.core_selftest

# Strong-parameter schemas and request sources
../amber-lang/build/amberc build test/strong_params_selftest.build.yaml \
  --target native --out-dir out-params-native \
  --cache-dir cache-params-native --no-cache
./out-params-native/ember.strong_params_selftest

# Real amber-orm + sqlite3-amber integration
../amber-lang/build/amberc build test/orm_selftest.build.yaml \
  --target native --out-dir out-orm-native --cache-dir cache-orm-native --no-cache
./out-orm-native/ember.orm_selftest

# Real loopback HTTP adapter
../amber-lang/build/amberc build test/http_selftest.build.yaml \
  --target native --out-dir out-http-native --cache-dir cache-http-native \
  --grant net.listen --grant net.connect
./out-http-native/ember.http_selftest
```

## Ember 1.0 contract

The accepted [Ember 1.0 contract ADR](docs/adr/0001-ember-1-0-contract.md)
closes the semantic decisions from roadmap stage 0. Its supporting documents
define the [public API boundary](docs/PUBLIC_API.md),
[edge deployment model](docs/DEPLOYMENT.md),
[compatibility policy](docs/COMPATIBILITY.md), and measurable
[production-readiness gates](docs/PRODUCTION_READINESS.md). These documents are
the target contract; the current preview does not yet satisfy the production
gates.

## Current transport boundary

The low-level server is plaintext HTTP/1.1 with one request per accepted
connection and explicit `Connection: close`. Buffered and chunked full-duplex
bodies are supported, including `Expect: 100-continue`, chunk extensions, and
trailers. Ember does not yet claim TLS, HTTP/2, keep-alive, WebSocket,
multipart, sessions, cookies, CSRF, or production-ready proxy trust. Those are
later layers, not hidden behavior in the preview.

Dynamic slugs and CMS paths remain database data behind static parameter or
lowest-precedence wildcard routes. Normalization, history, tenant/locale
scope, reserved root names, uniqueness, and cache invalidation are application
repository policy; they never mutate `Routes`.
