# ADR-0001: Orbit 1.0 contract and production boundary

- Status: Accepted
- Date: 2026-07-19
- Owners: Orbit maintainers
- Decision scope: Orbit 1.0

## Context

Orbit already has a deterministic router, request/controller pipeline,
buffered and full-duplex streaming responses, strong parameters, HTML helpers,
testing helpers, and an optional ORM integration. The preview did not define a
single normative answer for HEAD fallback, trailing slashes, contentless HTTP
statuses, API stability, supported deployment topology, or the evidence needed
to call a release production-ready.

Leaving those choices until transport/security implementation would make tests
and APIs encode accidental behavior. Stage 0 therefore decides the target
contract before lifecycle, transport, security, observability, and release work.

## Decision

### HTTP and routing semantics

The normative behavior is [the Orbit 1.0 HTTP contract](../HTTP_CONTRACT.md):

- `/path` and `/path/` are distinct; Orbit never redirects or canonicalizes a
  trailing slash implicitly.
- `HEAD` uses an explicit HEAD route first and otherwise falls back to GET by
  default. `head_fallback: false` is the explicit exact-method mode.
- HEAD invokes the chosen request pipeline but emits no content; streaming
  producers are not started solely to answer HEAD.
- Explicit OPTIONS wins; otherwise automatic OPTIONS is enabled by default.
  404/405 and sorted `Allow` behavior are deterministic.
- `null` means `204`; an empty string/byte sequence remains an empty `200`
  representation. Integer HTTP statuses are `100..599`.
- Final application `1xx` is invalid. `204`, `205`, and `304` cannot carry
  application content or trailers. Framing fields are validated/owned by the
  adapter rather than passed through ambiguously.
- Cancellation, disconnect, shutdown, and fatal/policy runtime failures are
  control flow and never become application `500` responses.

### Public API

[The public API boundary](../PUBLIC_API.md) is allowlist-based: documented names
and behavior are public; export visibility, reachability, or an attribute in an
implementation class does not make a surface public. Macro helpers beginning
with `__` remain internal despite export visibility.

`App#call`, routing/rendering values, middleware/integration protocols, strong
parameters, HTML, testing, and the optional ORM integration are supported
surfaces. Concrete header collection types and the preview `Request#origin`
derivation are the only called-out pre-RC replacements because multi-value
headers and trusted-proxy processing are mandatory correctness/security work.
Additive lifecycle/configuration API remains permitted.

### Production topology

[The deployment contract](../DEPLOYMENT.md) defines Orbit 1.0 as an application
server behind a trusted TLS-terminating reverse proxy/ingress. The edge owns
public TLS and newer HTTP versions. Orbit still owns inner HTTP parsing and
limits, host authorization, explicit trusted-proxy interpretation, application
security, bounded concurrency, keep-alive on the inner HTTP/1.1 hop, readiness,
and graceful drain.

Direct public exposure, direct TLS, and HTTP/2/3 inside Orbit are not part of the
1.0 production claim.

### Compatibility and release claim

[The compatibility policy](../COMPATIBILITY.md) uses SemVer after 1.0, treats
documented semantics and extension protocols as API, and requires a tested
Orbit/Sputnik/runtime/platform matrix. While Sputnik is pre-1.0, an Orbit minor
supports one explicit Sputnik minor line. Preview builds have no production
support promise.

[The production-ready definition](../PRODUCTION_READINESS.md) is a mandatory
evidence-based gate spanning correctness/lifecycle, transport, security,
observability/performance, release engineering/DX, and RC validation. The edge
deployment profile is the only 1.0 production profile.

## Consequences

- `App` changes its preview default to `head_fallback: true`. Applications that
  require explicit HEAD routes can set `false`.
- Status validation narrows from the preview's `100..999` to HTTP's `100..599`.
- Existing strict trailing-slash behavior is retained and tested.
- Stage 1/2 implementation must centralize final response validation so
  in-memory and socket behavior cannot diverge for HEAD/contentless statuses or
  framing.
- Stage 1 must replace map headers without promising map mutation compatibility.
- Stage 2 must supply the lifecycle/keep-alive behaviors already fixed by the
  deployment contract.
- Stage 3 must replace direct Host-based origin derivation with validated host
  and proxy policy.
- Release work cannot label Orbit production-ready merely because self-tests or
  a sample deployment pass; every release gate needs durable evidence.

## Alternatives considered

### Keep HEAD fallback opt-in

Rejected. HEAD is defined as GET metadata without content, and default fallback
provides consistent discoverability and `Allow` behavior. An opt-out preserves
strict method applications.

### Normalize or redirect trailing slashes

Rejected. Redirect status/method preservation, proxy prefix rewriting, signed
URLs, and API clients make implicit canonicalization policy-dependent. An
application can declare both routes or an explicit redirect.

### Silently strip invalid status content everywhere

Rejected. The wire must always be compliant, but silently accepting a streamed
204/304 hides application defects. Orbit rejects invalid application responses
before commit; HEAD suppression is method semantics rather than such a defect.

### Support direct public TLS/HTTP2 in 1.0

Rejected. It expands certificate, ALPN, protocol, and operational scope without
removing the need for lifecycle, parsing defense, proxy trust, and observability.
The supported edge profile delivers a smaller verifiable boundary.

### Treat every exported symbol as stable

Rejected. Macro expansion requires exported plumbing, and implementation
attributes expose representation choices. An explicit documented allowlist
gives application authors a clear compatibility boundary.

### Claim broad Sputnik version compatibility

Rejected while Sputnik is `0.x`. Source-first framework behavior depends on the
compiler, stdlib, runtime, and `net.http`; only tested matrix rows are supported.

## Implementation and verification

Stage 0 immediately aligns the safe preview changes (HEAD default and numeric
status range), adds `test/contract_selftest.s`, and publishes all normative
documents. Remaining implementation gaps are deliberately assigned to roadmap
stages 1–5 and appear as unchecked production-readiness gates; they are decided
behavior, not open semantic questions.

This ADR may be changed only by a new ADR that explicitly supersedes it and
updates every affected contract, test, and migration note.
