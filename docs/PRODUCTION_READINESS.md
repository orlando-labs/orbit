# Definition of production-ready for Ember 1.0

Status: normative release gate, accepted 2026-07-19 by
[ADR-0001](adr/0001-ember-1-0-contract.md).

Ember is production-ready only for the profile defined here: HTTP/API and
server-rendered applications behind the trusted edge described in
[DEPLOYMENT.md](DEPLOYMENT.md). “Production-ready” is a release claim supported
by evidence, not a synonym for compiling, passing smoke tests, or being used by
one application.

The current preview is **not production-ready**. Every gate below is required
for the 1.0 release unless an accepted ADR narrows the release profile. A waiver
cannot turn a failed mandatory gate green.

## Gate 0: contract — complete

- [x] HEAD fallback, strict trailing-slash identity, method selection, and
  status/content semantics are normative and testable.
- [x] The public API boundary and private/exported distinction are documented.
- [x] Edge deployment and trust boundaries are explicit.
- [x] Version, deprecation, Amber/runtime, platform, and support policies are
  explicit.
- [x] This production-ready definition has objective release evidence.

Evidence: [ADR-0001](adr/0001-ember-1-0-contract.md),
[HTTP_CONTRACT.md](HTTP_CONTRACT.md), [PUBLIC_API.md](PUBLIC_API.md),
[DEPLOYMENT.md](DEPLOYMENT.md), and [COMPATIBILITY.md](COMPATIBILITY.md).

## Gate 1: correctness and lifecycle invariants — complete

- [x] Request-id/access-log/error middleware preserves buffered and streaming
  response kinds and multi-value headers.
- [x] Cancellation, shutdown, client disconnect, fatal runtime failures, and
  policy/isolation errors are never converted to application `500` responses.
- [x] Routes, request metadata, strong-parameter results, and exposed snapshots
  are deeply immutable under concurrent access.
- [x] Headers preserve ordered repeated fields where required, including
  separate `Set-Cookie` values, with validated names/values and no CL/TE
  ambiguity.
- [x] A documented error hook observes uncaught application failures with
  redaction and cannot replace cancellation semantics.
- [x] All server limits, timeouts, backlog, and concurrency settings used by the
  production profile are explicit, finite, validated, and test-covered.

Required evidence: unit and property tests for every invariant, including both
buffered and streaming middleware paths and negative validation cases.

Evidence: `test/stage1_selftest.am`, the core/strong-params/HTTP/ORM self-tests,
[PUBLIC_API.md](PUBLIC_API.md), and the server configuration reference in
[TRANSPORT.md](TRANSPORT.md).

## Gate 2: production transport — complete

- [x] A public server handle implements readiness, stop-accepting, in-flight
  accounting, graceful drain, deadline cancellation, and idempotent shutdown.
- [x] Start hooks run before readiness; stop hooks run in reverse order after
  drain/cancellation. Failed startup unwinds already-started integrations.
- [x] HTTP/1.1 keep-alive supports multiple bounded requests per trusted edge
  connection with correct close/error behavior.
- [x] Overload behavior is bounded and documented; excess work is rejected
  predictably without unbounded tasks, queues, or memory.
- [x] HEAD, 1xx, 204, 205, and 304 plus `Content-Length`, `Transfer-Encoding`,
  trailers, `Expect: 100-continue`, and disconnect behavior conform to
  [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html) and
  [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112.html).
- [x] Shutdown/disconnect tests show no lost ORM leases, unfinished integration
  hooks, orphan tasks, or hung request/response streams.

Required evidence: deterministic lifecycle tests, raw-socket HTTP conformance
corpus, and loopback integration tests for buffered, streaming, slow, malformed,
and cancelled requests.

Evidence: `test/stage2_selftest.am`, [TRANSPORT.md](TRANSPORT.md), and the
`amber-lang` runtime suites `tests/vm_net_http_tests.cpp` (691 checks) and
`tests/stdlib_task_tests.cpp`.

## Gate 3: security baseline

- [ ] Host authorization rejects missing/duplicate/invalid/unauthorized
  authorities before routing.
- [ ] Trusted-proxy policy is explicit, bounded by CIDR/hops, ignores untrusted
  forwarding fields, and drives effective origin/client address safely.
- [ ] Request IDs are generated securely or accepted only after length/charset
  validation; control characters cannot enter headers or logs.
- [ ] Security headers, explicit CORS, bounded cookies, signed/encrypted
  sessions, CSRF defenses, and multipart parsing with hard aggregate/part/file
  limits have safe defaults and negative tests.
- [ ] HTML rendering is context-aware for supported contexts and rejects or
  requires explicit trusted wrappers for unsafe URL/JavaScript/CSS contexts.
- [ ] A reviewed threat model covers request smuggling, proxy trust, injection,
  XSS, CSRF, session/cookie theft, resource exhaustion, path confusion,
  deserialization, secrets, logs, and dependency/native boundaries.
- [ ] The framework-relevant profile of
  [OWASP ASVS 5.0](https://owasp.org/www-project-application-security-verification-standard/)
  is mapped to controls/tests; release scanning and review have zero open
  critical/high findings.

Required evidence: versioned threat model and ASVS mapping, dependency/native
scan, secret scan, security regression suite, and documented resolution or
accepted lower-severity risk ownership.

## Gate 4: observability and performance

- [ ] Structured access/error logs include request ID, method, route template
  (not raw sensitive path), status, duration, bytes, and outcome; secrets and
  configured fields are redacted.
- [ ] Metrics cover requests, in-flight work, duration, bytes, errors,
  rejections, connection/stream state, shutdown drain, and integration pools
  without unbounded labels.
- [ ] Tracing follows current OpenTelemetry HTTP semantic conventions and
  propagates only validated context across the trusted edge.
- [ ] Liveness and readiness implement the lifecycle semantics in the
  deployment contract.
- [ ] Reproducible benchmarks cover small JSON, 1K/4K routes, buffered HTML,
  full-duplex streaming, keep-alive, and ORM pool exhaustion on named hardware.
- [ ] The release publishes p50/p95/p99 latency, throughput, memory, and CPU
  budgets plus an automated regression threshold. No required workload regresses
  by more than 10% from the approved baseline without an accepted performance
  report.

Required evidence: machine-readable benchmark results, environment manifest,
dashboards/telemetry schema tests, and regression-gate output.

## Gate 5: release engineering and developer experience

- [ ] CI runs formatting/static checks, all self-tests, unit/property tests,
  raw HTTP conformance, fuzz smoke tests, native builds, integrations, examples,
  and the supported compatibility/platform matrix.
- [ ] Dependencies are versioned and locked; a clean supported environment can
  install and build Ember with one documented command and no sibling checkout.
- [ ] Release has a SemVer tag, license, changelog, security policy/reporting
  route, checksums, compatibility matrix, and reproducible dependency manifest.
- [ ] API reference covers every public name and has compile-tested examples.
- [ ] Deployment guide, proxy/platform examples, configuration reference,
  operations runbook, incident/shutdown/backup guidance, and migration guide
  are complete and tested by someone other than the author.
- [ ] Unsupported preview features are clearly separated from the 1.0 contract.

Required evidence: clean-room build log, release checklist, artifact/source
checksums, documentation link checker/example compilation, and compatibility CI.

## Release-candidate validation

- [ ] A representative application runs behind the supported reverse proxy in
  a canary environment with production-equivalent limits and telemetry.
- [ ] A 72-hour constant/mixed-load soak has no leaked tasks/connections/ORM
  leases and no unbounded memory, queue, label-cardinality, or descriptor growth.
  The run records heap/RSS and resource slopes, not only start/end values.
- [ ] At least 24 cumulative hours of coverage-guided fuzzing across percent
  decoding, query, JSON, multipart, and HTTP framing completes with no crash,
  hang, sanitizer finding, or unbounded allocation. Every prior crash remains a
  regression corpus case.
- [ ] Slowloris, slow reader/writer, premature EOF, client disconnect, timeout,
  cancellation, pool exhaustion, dependency failure, signal, and hard-kill
  tests meet documented outcomes.
- [ ] Canary promotion and rollback are rehearsed. Rollback preserves compatible
  configuration/data/session formats and completes inside the published
  recovery objective.
- [ ] There are zero open release-blocking defects, critical/high security
  findings, conformance failures, or unexplained benchmark regressions.

## Evidence index and decision rule

Before RC, the release manager creates a versioned evidence index linking each
checkbox to an immutable CI run, report, test, benchmark, or runbook exercise.
Evidence must state the Ember/Amber revisions, dependency lock, target triple,
and configuration digest.

The 1.0 release is production-ready only when every checkbox is green and the
evidence index is reviewed. Any later discovery that invalidates a mandatory
gate triggers a security/correctness release process and temporarily narrows or
withdraws the affected production claim in release documentation.
