# Changelog

All notable changes are recorded here. Orbit follows
[Semantic Versioning](https://semver.org/) and the compatibility rules in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## [Unreleased]

- Added local-source `orbit-session`, `orbit-session-orm`, `orbit-oauth` and
  `orbit-oauth-github` companions with storage/User-neutral controller APIs.
- Added runtime HTML template loops, external `.html.sv` support via the SDK
  source-format registry, and explicit runtime helper references immune to
  caller-name shadowing. The web notebook plan now prioritizes Vue/Vite assets,
  a safe bootstrap and an authenticated SSR shell.

- Added `stream(length: N)`/`StreamingResponse(length: N)` with fixed-length
  response streaming in VM/native `net.http`, exact byte enforcement,
  known-length HEAD metadata, and preservation through middleware/telemetry.
  The default remains chunked; raw framing headers stay transport-owned.
- Fixed native HTTP response producers treating an unused final expression
  (such as a StreamBody or telemetry event) as a handler result and aborting
  otherwise complete keep-alive responses.
- Renamed the framework to Orbit, including the `orbit` and `orbit-orm`
  packages, module paths, `OrbitError`, `ORBIT_*` diagnostics and configuration,
  telemetry schemas, deployment examples, and benchmark commands.
- Added a representative controller-based catalog REST service, an Sputnik
  CRUD/strict-4xx client, and a reproducible 72-hour resource/metrics soak
  runner.
- Locked Sputnik to the lexical-first implicit-self bare-send implementation, so
  controller methods can use inherited `params`, `request`, `render`, and
  included nullary helpers without explicit `self`.

## [1.0.0-rc.1] - 2026-07-22

This is the first release candidate for the trusted-edge Orbit 1.0 contract.
It is not a production-ready declaration: the separate RC soak, fuzz, canary,
rollback, and independent security-review gates remain mandatory.

### Added

- Deterministic routing, typed captures, reverse routing, strong parameters,
  controller and middleware protocols, context-aware HTML, and test helpers.
- Bounded HTTP/1.1 keep-alive, full-duplex streaming, overload rejection,
  graceful drain/deadline cancellation, and lifecycle-aware integrations.
- Host/trusted-proxy enforcement, response security headers, cookies, signed
  values, encrypted sessions, exact CORS, CSRF, and bounded multipart parsing.
- Structured redacted logs, bounded metrics, W3C trace-context handling,
  health/readiness probes, and performance budgets.
- Versioned `orbit` and `orbit-orm` packages, deterministic lock files,
  clean-room build tooling, platform CI, release provenance/checksums, API
  reference, deployment examples, runbook, and migration guide.

### Changed from preview

- `HEAD` falls back to `GET` by default; explicit `HEAD` still wins.
- Valid response status codes are limited to `100..599`; final `1xx` is
  rejected and `204`/`205`/`304` framing follows the HTTP contract.
- Headers are immutable ordered multi-value values rather than mutable maps.
- Host authorization runs before routing; origin and client identity use only
  validated proxy provenance.
- ORM support is distributed as the separate `orbit-orm` companion package,
  so importing core never brings in ORM, SQLite, or FFI.

### Security

- Exception details, raw paths, queries, request bodies, credentials, cookie
  values, and arbitrary headers are excluded from the production telemetry
  schema by default.
- Ambiguous HTTP framing, header injection, invalid request IDs, unsafe HTML
  contexts, forged session/CSRF data, and multipart path-like filenames fail
  closed.

### Known limitations

- TLS and HTTP/2/3 require a trusted reverse proxy; direct public exposure is
  unsupported.
- WebSocket, direct TLS, hot reload, generators/resources, `.amv`, and an asset
  pipeline are outside the 1.0 contract.
- Trusted-proxy IPv6 networks support exact `/128` entries only.
- Independent cryptographic review and the full RC validation campaign remain
  open release gates.

[Unreleased]: https://github.com/orlando-labs/orbit/compare/v1.0.0-rc.1...HEAD
[1.0.0-rc.1]: https://github.com/orlando-labs/orbit/releases/tag/v1.0.0-rc.1
