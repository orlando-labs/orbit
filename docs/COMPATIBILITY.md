# Ember compatibility policy

Status: normative 1.0 policy, accepted 2026-07-19 by
[ADR-0001](adr/0001-ember-1-0-contract.md).

## Versioning

Ember releases use [Semantic Versioning 2.0.0](https://semver.org/). The public
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
tool-supported warning when Amber supports it. A deprecated public API remains
available for the rest of the current Ember major and is removed only in the
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
- the supported Ember/Amber/dependency/platform matrix.

It does not cover private/`__*` names, undocumented object attributes, exact
error strings, plain-text log formatting, source locations, generated C++ or
bytecode, cache/artifact layout, performance outside published budgets, or
behavior that the contracts identify as invalid/undefined.

Header field order is compatible only where HTTP makes order significant.
Multi-value field preservation, including repeated `Set-Cookie`, is semantic
behavior and is covered.

## Amber compiler and runtime

Amber source, compiler, standard library, runtime, and `net.http` form one
compatibility unit for Ember. A release is supported only on combinations
listed in its release matrix and exercised in CI.

Rules for Ember 1.x:

- While Amber is below 1.0, an Ember minor supports one Amber minor line (for
  example `0.a.*`) with an explicit minimum patch. A new Amber minor requires a
  new Ember minor; Ember patch releases do not silently move Amber minor lines.
- Once Amber is 1.0 or newer, an Ember minor supports the current Amber minor at
  release time and the immediately previous Amber minor, subject to a listed
  minimum patch for each.
- The native target, stdlib, runtime, and compiler must use the same Amber
  release. Mixed compiler/runtime artifacts are unsupported.
- A newly published Amber patch enters the matrix only after all Ember unit,
  conformance, native, integration, and smoke tests pass. “It compiles” is not
  sufficient.
- Supported platform triples are listed per release. Ember 1.0 must at minimum
  test Linux x86_64 and Linux arm64 for production and macOS arm64 as a
  development platform. Other targets are best effort unless listed.

Unsupported combinations may happen to build but receive no compatibility or
security guarantee.

### `1.0.0-rc.1` release matrix

| Component | Supported candidate row |
|---|---|
| Ember core package | `ember 1.0.0-rc.1` |
| Amber compiler/runtime/stdlib | `amberc 0.1.0-dev`, revision `8402f4f8102f71157ec736c24b2f0d250f26f18a`, tree `c6a06d241d0adafc0505e0f14f664a40b1235c98` |
| Build profiles | required `core.v1`, `macro.v1`; no optional core profile |
| Linux production targets | x86_64 and arm64, native target, required CI rows |
| Development target | macOS arm64, native target, required CI row |
| Other targets | unsupported unless added by a later release matrix |
| Production claim | not yet: the separate RC validation gates remain open |

The compiler, standard library, runtime, and `net.http` always come from the
single locked Amber revision. `release/dependencies.lock.json` is the
source/provenance lock; `amber.lock` is the deterministic package lock. The
three platform jobs run core/property/security/telemetry, native HTTP
conformance, fuzz smoke, examples, and API-example compilation. A matrix row is
publishable only when its immutable tag CI job is green.

## Optional integrations

Core Ember remains ORM-neutral. Each optional integration has an independent
matrix in the Ember release notes. An integration is supported only when Ember,
Amber, the integration package, its native client/library, and the target
platform all appear in one tested row.

The tested `1.0.0-rc.1` ORM row is:

| Component | Exact row |
|---|---|
| Integration package | `ember-orm 1.0.0-rc.1` |
| Ember | `1.0.0-rc.1` |
| Amber ORM | `0.1.0-dev`, revision `1e64d37859f7e1b6f92ebcebb01df9c4f599ff86`, tree `69fd72f6a0262d99b4ceeaa7734dcd24a44615df` |
| SQLite adapter | `sqlite3-amber 0.1.0-dev`, revision `8ffb543bf7678e3011dce8e8e58276b6d9725f88`, tree `ec8429f8dd09e729673ba6a972944de348ac71c7` |
| Bundled SQLite | `3.51.0`, source ID `fb2c931ae597f8d00a37574ff67aeed3eced4e5547f9120744ae4bfa8e74527b` |
| Tested platform | Linux x86_64 native integration CI; other platform rows are unsupported for this optional package until listed |

Updating any entry requires at least an Ember patch plus the full integration
suite. Core applications do not inherit native/SQLite dependencies merely
because the companion package exists.

## Support window

For Ember 1.x, security and correctness fixes are produced for the latest minor
release. The immediately previous minor receives critical/high security fixes
for six months after the next minor is released. Older minors and all preview
snapshots are unsupported.

A release line may be ended early only with a published advisory when an
upstream Amber/runtime dependency cannot be secured. The notice identifies the
last affected version, the supported upgrade target, and any mitigation.

## Required release evidence

Every release publishes:

- Ember version and source tag;
- exact dependency lock and supported Amber/platform/integration matrix;
- changelog with additions, fixes, deprecations, security/standards changes,
  and migrations;
- CI links for all required matrix rows and conformance suites;
- known limitations and production profile;
- checksums/signatures for distributed artifacts when artifacts are provided.

A combination absent from this evidence is not supported.
