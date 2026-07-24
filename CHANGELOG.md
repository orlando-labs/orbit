# Changelog

All notable changes are recorded here. Ember follows
[Semantic Versioning](https://semver.org/) and the compatibility rules in
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## [Unreleased]

- Added a representative controller-based catalog REST service, an Amber
  CRUD/strict-4xx client, and a reproducible 72-hour resource/metrics soak
  runner.
- Locked Amber to the lexical-first implicit-self bare-send implementation, so
  controller methods can use inherited `params`, `request`, `render`, and
  included nullary helpers without explicit `self`.

## [1.0.0-rc.1] - 2026-07-22

This is the first release candidate for the trusted-edge Ember 1.0 contract.
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
- Versioned `ember` and `ember-orm` packages, deterministic lock files,
  clean-room build tooling, platform CI, release provenance/checksums, API
  reference, deployment examples, runbook, and migration guide.

### Changed from preview

- `HEAD` falls back to `GET` by default; explicit `HEAD` still wins.
- Valid response status codes are limited to `100..599`; final `1xx` is
  rejected and `204`/`205`/`304` framing follows the HTTP contract.
- Headers are immutable ordered multi-value values rather than mutable maps.
- Host authorization runs before routing; origin and client identity use only
  validated proxy provenance.
- ORM support is distributed as the separate `ember-orm` companion package,
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

[Unreleased]: https://github.com/orlando-labs/ember/compare/v1.0.0-rc.1...HEAD
[1.0.0-rc.1]: https://github.com/orlando-labs/ember/releases/tag/v1.0.0-rc.1
