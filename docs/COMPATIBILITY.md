# Orbit compatibility policy

Status: normative 1.0 policy, accepted 2026-07-19 by
[ADR-0001](adr/0001-orbit-1-0-contract.md).

## Versioning

Orbit releases use [Semantic Versioning 2.0.0](https://semver.org/). The public
API is the surface defined in [PUBLIC_API.md](PUBLIC_API.md) and the observable
behavior defined by the accepted contracts and ADRs.

- A patch release fixes defects without intentionally changing a valid public
  program or compliant HTTP behavior.
- A minor release may add public names, optional keywords, status symbols, and
  opt-in behavior. Existing defaults and accepted inputs remain compatible.
- Removing or renaming public API, changing a default, narrowing accepted valid
  input, changing route selection, changing response status/content semantics,
  or changing a public error classification requires a major release.
- A security or standards defect may force a behavior change in a patch. Such a
  change requires a security advisory or release-note entry, a migration path
  when safe, and a conformance test.

Deprecation is documented in API reference and release notes and emits a
tool-supported warning when Sputnik supports it. A deprecated public API remains
available for the rest of the current Orbit major and is removed only in the
next major. Vulnerable behavior may be disabled earlier under the security
exception above.

`1.0.0-rc.1` freezes the candidate public surface. A release-blocking defect
may still require an RC change, recorded in the changelog and migration guide;
a decision in ADR-0001 requires a superseding ADR. The compatibility guarantees
above become final release guarantees at `1.0.0`.

## What compatibility includes

Compatibility covers:

- documented imports, names, call signatures, defaults, and extension
  protocols;
- route matching/reverse routing and the `App#call` contract;
- documented status, headers, content, streaming, and error classification;
- strong-parameter filtering, types, issue codes, and immutable result shape;
- public test helpers and their assertions;
- documented configuration keys and environment-independent behavior;
- the supported Orbit/Sputnik/dependency/platform matrix.

It does not cover private/`__*` names, undocumented object attributes, exact
error strings, plain-text log formatting, source locations, generated C++ or
bytecode, cache/artifact layout, performance outside published budgets, or
behavior that the contracts identify as invalid/undefined.

Header field order is compatible only where HTTP makes order significant.
Multi-value field preservation, including repeated `Set-Cookie`, is semantic
behavior and is covered.

## Sputnik compiler and runtime

Sputnik source, compiler, standard library, runtime, and `net.http` form one
compatibility unit for Orbit. A release is supported only on combinations
listed in its release matrix and exercised in CI.

The unreleased fixed-length response API requires the matching Sputnik runtime
with `net.http.ServerResponse.stream(length:)`. The locked older RC dependency
is not evidence for this extension: update the release pin/matrix after the
runtime change is committed and repeat the fixed-length VM/native conformance lane.

Rules for Orbit 1.x:

- While Sputnik is below 1.0, an Orbit minor supports one Sputnik minor line (for
  example `0.a.*`) with an explicit minimum patch. A new Sputnik minor requires a
  new Orbit minor; Orbit patch releases do not silently move Sputnik minor lines.
- Once Sputnik is 1.0 or newer, an Orbit minor supports the current Sputnik minor at
  release time and the immediately previous Sputnik minor, subject to a listed
  minimum patch for each.
- The native target, stdlib, runtime, and compiler must use the same Sputnik
  release. Mixed compiler/runtime artifacts are unsupported.
- A newly published Sputnik patch enters the matrix only after all Orbit unit,
  conformance, native, integration, and smoke tests pass. “It compiles” is not
  sufficient.
- Supported platform triples are listed per release. Orbit 1.0 must at minimum
  test Linux x86_64 and Linux arm64 for production and macOS arm64 as a
  development platform. Other targets are best effort unless listed.

Unsupported combinations may happen to build but receive no compatibility or
security guarantee.

### `1.0.0-rc.1` release matrix

The Sputnik migration inputs below are local technical-preview commits.
Hosted release validation follows publication of the dependency commits.

| Component | Supported candidate row |
|---|---|
| Orbit core package | `orbit 1.0.0-rc.1` |
| Sputnik compiler/runtime/stdlib | `sputnik 0.1.0-dev`, revision `3383a5eecb4466077dd7ba580698a22ae40dbd3d`, tree `1db8817cc8d195f999605806975bb1572b198f07` |
| Build profiles | required `core.v1`, `macro.v1`; no optional core profile |
| Linux production targets | x86_64 and arm64, native target, required CI rows |
| Development target | macOS arm64, native target, required CI row |
| Other targets | unsupported unless added by a later release matrix |
| Production claim | not yet: the separate RC validation gates remain open |

The compiler, standard library, runtime, and `net.http` always come from the
single locked Sputnik revision. `release/dependencies.lock.json` is the
source/provenance lock; `sputnik.lock` is the deterministic package lock. The
three platform jobs run core/property/security/telemetry, native HTTP
conformance, fuzz smoke, examples, and API-example compilation. A matrix row is
publishable only when its immutable tag CI job is green.

## Optional integrations

Core Orbit remains ORM-neutral. Each optional integration has an independent
matrix in the Orbit release notes. An integration is supported only when Orbit,
Sputnik, the integration package, its native client/library, and the target
platform all appear in one tested row.

The tested `1.0.0-rc.1` ORM row is:

| Component | Exact row |
|---|---|
| Integration package | `orbit-orm 1.0.0-rc.1` |
| Orbit | `1.0.0-rc.1` |
| Sputnik ORM | `0.1.0-dev`, revision `3575602c2f03a3337dec5685eafecbe9d918597f`, tree `7e2e098a8547f79f2c82754d8be60f13ebce479a` |
| SQLite adapter | `sqlite3-sputnik 0.1.0-dev`, revision `96f3a62a19f448fc231268fcac33fddf9958e83e`, tree `d8bc6685ea7405c3a6aed9c70381a623326affef` |
| Bundled SQLite | `3.51.0`, source ID `fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b` |
| Tested platform | Linux x86_64 native integration CI; other platform rows are unsupported for this optional package until listed |

Updating any entry requires at least an Orbit patch plus the full integration
suite. Core applications do not inherit native/SQLite dependencies merely
because the companion package exists.

## Support window

For Orbit 1.x, security and correctness fixes are produced for the latest minor
release. The immediately previous minor receives critical/high security fixes
for six months after the next minor is released. Older minors and all preview
snapshots are unsupported.

A release line may be ended early only with a published advisory when an
upstream Sputnik/runtime dependency cannot be secured. The notice identifies the
last affected version, the supported upgrade target, and any mitigation.

## Required release evidence

Every release publishes:

- Orbit version and source tag;
- exact dependency lock and supported Sputnik/platform/integration matrix;
- changelog with additions, fixes, deprecations, security/standards changes,
  and migrations;
- CI links for all required matrix rows and conformance suites;
- known limitations and production profile;
- checksums/signatures for distributed artifacts when artifacts are provided.

A combination absent from this evidence is not supported.
