# Migrating from the Orbit preview to 1.0 RC

This guide covers intentional contract changes between the unversioned preview
and `1.0.0-rc.1`. Upgrade the compiler/runtime and Orbit together; mixed Sputnik
artifacts are unsupported.

## Framework naming

Use `orbit` for the core package and imports, `orbit.*` for submodules, and
`orbit-orm` for the optional ORM companion. The base exception is `OrbitError`.
Update environment variables and CI secrets to the `ORBIT_*` prefix, diagnostic
codes to `ORBIT_*`, and telemetry event names, metric keys, and evidence schemas
to `orbit.*`. Deployments use `orbit.service` and `deploy/kubernetes/orbit.yaml`;
HTTP benchmarks select the framework with `--stack orbit`. Regenerate package
locks and rebuild applications after updating these names.

## 1. Install the locked packages

Replace source paths outside the application checkout with exact package
versions. Core applications depend only on `orbit = 1.0.0-rc.1`. ORM
applications additionally use `orbit-orm = 1.0.0-rc.1`, the tested
`orm = 0.1.0-dev` revision, and a tested adapter such as
`sqlite3 = 0.1.0-dev`. Commit the generated `sputnik.lock`.

Use the exact Sputnik compiler/runtime row in
[COMPATIBILITY.md](COMPATIBILITY.md); rebuild every native/bytecode artifact.

## 2. Adopt HTTP response rules

- `HEAD` now falls back to `GET` by default. Set `head_fallback: false` only if
  the application intentionally requires explicit HEAD routes.
- Status codes outside `100..599` are rejected. Final `1xx` responses are
  invalid; `204`, `205`, and `304` have strict content/framing rules.
- Application `Content-Length` must match buffered content. Transfer-Encoding
  and trailers remain transport-owned.
- `/path` and `/path/` remain distinct; add explicit redirects/routes rather
  than relying on normalization.

Run the raw HTTP/conformance tests after changing custom middleware or response
adapters.

## 3. Replace mutable/map header assumptions

`Response#headers` and request headers are immutable ordered `Headers` values.
Use `first`, `all`, `to_pairs`, `add`, `set`, `delete`, `without`, or `merge`.
Do not join repeated `Set-Cookie`; preserve each field separately. Middleware
must preserve buffered versus streaming response kind.

## 4. Configure request provenance

Every application has a `SecurityPolicy`; the development default accepts only
localhost. Production must set exact allowed hosts, trusted proxy CIDRs,
forwarding mode/hop count, HSTS, and CSP. Stop reading raw `Host` or
`X-Forwarded-*` headers for redirects, cookies, tenant selection, scheme, or
client identity; use `request.origin()`, `effective_authority`,
`effective_scheme`, `client_ip`, and `secure?`.

## 5. Install browser and parsing controls explicitly

Import `orbit.security` for cookies/session/CORS/CSRF and `orbit.multipart` for
multipart. Configure 32-byte-or-longer secret-manager keys, exact CORS
allowlists, CSRF on cookie-authenticated unsafe routes, and upload
type/quota/storage/scanning rules. Replace unsafe template interpolation with
the `url`, `trusted_script`, or `trusted_style` boundaries; ambiguous contexts
now fail compilation.

## 6. Move ORM integration to its companion package

Change the dependency graph, not the import:

```sputnik
from orbit.integrations.orm import pool as orm_pool
```

The package now participates in start/readiness/drain/stop. Do not close the
pool independently during a normal shutdown. Bare handlers still require
explicit connection middleware; controller integrations are not applied to
bare functions.

## 7. Adopt the lifecycle and telemetry boundary

Use `App#start`/`ServerHandle` in the process signal adapter. Remove readiness
before `stop_accepting`, drain with a finite deadline, then `wait`. Configure
`Telemetry` at `App` rather than relying only on access-log middleware, and
update dashboards to route-template fields from
[OBSERVABILITY.md](OBSERVABILITY.md). Raw path/query/body/error text is no
longer a supported log schema.

## 8. Verify before promotion

Run the one-command clean build, CI suites, compile-fail HTML fixtures,
integration test, proxy smoke, and migration/rollback rehearsal. Review the
unsupported list in [API_REFERENCE.md](API_REFERENCE.md); preview-only direct
TLS, HTTP/2/3, WebSocket, generators/resources, asset pipeline, hot
reload, and dynamic route replacement must not be assumed by the application.
