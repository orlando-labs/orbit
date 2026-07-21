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

The repository is currently a pre-1.0 framework preview. Preview source/API may
still change to satisfy ADR-0001, but every intentional contract change must be
recorded in the changelog and, for a decision in ADR-0001, in a superseding ADR.
The compatibility guarantees above become release guarantees at `1.0.0`.

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

### Preview baseline

The stage 0 contract was verified against:

| Component | Baseline |
|---|---|
| Ember | repository `main` at ADR acceptance |
| Amber compiler/runtime | `amberc 0.1.0-dev`, source revision `9c79ca61eea9110c665f48c246b4d4ad38e23c09` |
| Build profiles | required `core.v1`, `macro.v1`; no optional profiles in core |
| Production status | unsupported preview |

This table records the reproducible decision baseline; it is not a release
support promise. Stage 5 replaces sibling source paths with versioned,
locked dependencies and publishes the release matrix.

## Optional integrations

Core Ember remains ORM-neutral. Each optional integration has an independent
matrix in the Ember release notes. An integration is supported only when Ember,
Amber, the integration package, its native client/library, and the target
platform all appear in one tested row.

For the ORM integration, the 1.0 release must pin compatible `amber-orm` and
`sqlite3-amber` versions. Updating either outside its declared compatible range
requires at least an Ember patch plus the full ORM integration suite. Core
applications do not inherit native/SQLite dependencies merely because those
integrations exist.

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
