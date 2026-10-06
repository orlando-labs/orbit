# OWASP ASVS 5.0.0 framework mapping

Status: reviewed framework-relevant profile, 2026-07-22.

The reference is the official, stable
[OWASP ASVS v5.0.0](https://github.com/OWASP/ASVS/tree/v5.0.0/5.0/en).
Identifiers include the version as recommended by the ASVS project. This is a
control/evidence map for Ember's supported framework and trusted-edge profile;
it is not an OWASP certification and does not make an application compliant by
itself.

Status meanings:

- **F** — supplied and regression-tested by the framework;
- **D** — mandatory deployment/edge configuration documented by Ember;
- **A** — application-specific control that Ember supports but cannot satisfy;
- **P** — partial framework coverage with an explicitly owned residual risk.

## Framework-relevant controls

| ASVS requirement | Status | Ember control and evidence |
|---|---|---|
| v5.0.0-1.1.2, 1.2.1 | F | Final context-aware encoding in `ember.html`; text/quoted attributes escape and unsupported template contexts fail compilation. `stage3_selftest` plus both HTML compile-fail fixtures. |
| v5.0.0-1.2.2 | F | `url(...)` requires approved schemes and rejects `javascript:`, `data:`, protocol-relative, control/backslash, whitespace, and ambiguous list input; URL attributes require the wrapper. |
| v5.0.0-1.2.3 | F/A | JSON rendering uses the JSON encoder. Dynamic script interpolation is rejected unless application code crosses the explicit `trusted_script` review boundary. |
| v5.0.0-1.2.4 | A | ORM-neutral Ember does not construct SQL. Applications must use parameterized ORM/query APIs; strong parameters do not replace query parameterization. |
| v5.0.0-1.3.1, 1.3.4, 1.3.5 | A | Ember does not claim to sanitize user HTML/SVG/Markdown/CSS. `raw` and trusted wrappers are explicit review points; applications select a maintained sanitizer. |
| v5.0.0-1.3.7 | F/A | Templates are compiler source, never loaded from request data. Explicit raw/trusted values remain application responsibility. |
| v5.0.0-1.4.1..1.4.3 | D/P | Ember is Sputnik source; the C++ compiler/runtime boundary is reviewed and exercised by native suites. Sanitizer/hardening CI and immutable runtime provenance are gate-5/RC evidence. |
| v5.0.0-1.5.2, 1.5.3 | F/A | No generic client-selected object deserializer exists. JSON and multipart produce bounded data values; application schemas remain required. |
| v5.0.0-3.1.1 | D | Browser requirements, HTTPS behavior, HSTS/CSP defaults, and unsupported clients/configurations are documented in `SECURITY.md` and `DEPLOYMENT.md`. |
| v5.0.0-3.2.1, 3.2.2 | F/A | Correct content types, `nosniff`, CSP, and escaped HTML/text renderers. Serving user uploads and active content remains application policy. |
| v5.0.0-3.3.1..3.3.5 | F/D | `SetCookie` safe defaults, prefix invariants, SameSite/HttpOnly/Secure controls, injection rejection, and 4096-byte name+value bound. Production must choose `__Host-` names on validated HTTPS. |
| v5.0.0-3.4.1 | F/D | HSTS is emitted on every response only after validated HTTPS provenance when explicitly enabled; production policy requires `hsts: true`. TLS termination remains at the edge. |
| v5.0.0-3.4.2 | F | CORS uses exact allowlists, rejects credentialed wildcard configuration and disallowed preflights, and emits `Vary: Origin`. |
| v5.0.0-3.4.3, 3.4.4, 3.4.5, 3.4.6, 3.4.8 | F/D | Default CSP includes `object-src 'none'`, `base-uri 'none'`, and `frame-ancestors 'none'`; nosniff, referrer policy, COOP, and defense-in-depth XFO are applied to success/error responses. Applications may tighten CSP. |
| v5.0.0-3.5.1, 3.5.2, 3.5.3 | F/A | Signed double-submit CSRF, exact effective Origin, custom header, and Sec-Fetch-Site rejection; safe methods are not treated as state-changing by the middleware. Applications must install it on cookie-authenticated unsafe routes. |
| v5.0.0-3.7.2 | F | `ember.redirect` rejects unsafe/external destinations unless application code explicitly supplies an allowed origin policy. |
| v5.0.0-4.1.1 | F | Response normalization and render helpers set content types/charset; stage-0/2 contract tests cover status/body semantics. |
| v5.0.0-4.1.3 | F/D | Forwarded fields are ignored from untrusted peers and strictly parsed only for configured CIDRs/hops. Edge must remove/overwrite client forwarding fields. |
| v5.0.0-4.1.4 | F | Deterministic method routing, 405/Allow, automatic OPTIONS, and no TRACE route unless explicitly declared. |
| v5.0.0-4.2.1, 4.2.2 | F/D | Native HTTP parser rejects Host/CL-TE/obs-fold ambiguity; response framing rules are covered by the stage-2 raw-socket corpus. Edge must enforce compatible framing rules. |
| v5.0.0-4.2.5 | F/D | Finite header, body, cookie, session, multipart, route, and forwarding bounds. Outbound client policy is outside core Ember. |
| v5.0.0-5.1.1 | A | Each upload endpoint documents allowed type, extension, size, scanning, and download behavior. Ember documents parser defaults only. |
| v5.0.0-5.2.1 | F/A | Aggregate and per-file multipart limits are enforced. Application-specific processability, type/content checks, quotas, and archives are application controls. |
| v5.0.0-5.2.2..5.2.6 | A | Content/magic validation, archive and image limits, and user quotas are deliberately not inferred by a transport parser. |
| v5.0.0-5.3.1, 5.3.2 | F/A | Multipart rejects traversal-style filenames and performs no storage. Applications generate a server-side name outside executable/public roots. |
| v5.0.0-7.1.1..7.1.3 | A | Session lifetime, concurrency, federation, and re-authentication policy are application documentation. `SessionCodec(ttl:)` supplies an absolute envelope lifetime. |
| v5.0.0-7.2.1, 7.2.2 | F/A | The backend authenticates and decrypts every self-contained session token. Authentication-time issuance/renewal belongs to the application. |
| v5.0.0-7.3.1, 7.3.2 | P/A | Absolute expiry is enforced by `SessionCodec`; inactivity timeout requires state or application policy. |
| v5.0.0-7.4.1..7.4.5 | A | Stateless expiry alone is not immediate revocation. Applications use a stateful store, revocation epoch/list, key rotation, and logout/admin flows as required. |
| v5.0.0-11.1.1, 11.1.2 | D | `SECURITY.md` inventories HMAC-SHA-256, SHA-256, ChaCha20-Poly1305, nonces, purposes, minimum key material, and rotation. Deployment maintains actual key inventory/access. |
| v5.0.0-11.2.1 | P | The implementation follows RFC 8439 and passes its AEAD vector, but lacks independent validation. Tracked Medium risk must close before 1.0 RC. |
| v5.0.0-11.2.2, 11.2.3 | F/P | Versioned token formats, current/old key rotation, 256-bit key material, and separated AAD support migration. Algorithm replacement needs a format/version change. |
| v5.0.0-11.2.4 | F | Fixed-size authentication tags are compared without content short-circuit; malformed lengths fail before comparison. Timing-sensitive paths are regression-reviewed. |
| v5.0.0-12.1.1, 12.1.2, 12.2.1, 12.2.2 | D | TLS versions, ciphers, and public certificates are mandatory trusted-edge responsibilities; Ember's direct plaintext public exposure is unsupported. |
| v5.0.0-12.3.1..12.3.5 | D/A | Edge-to-app and backend links crossing trust boundaries require encrypted authenticated transport/service identity. Concrete mesh/database policy is deployment-specific. |
| v5.0.0-13.1.4, 13.3.1, 13.3.2, 13.3.4 | D/A | No production secret in source/build/logs; use a least-privilege secret manager and documented rotation. Stage-3 secret scan is evidence, not a replacement for release CI. |
| v5.0.0-13.4.2, 13.4.4 | F/D | `expose_exceptions` defaults false and production forbids enabling it. TRACE is absent unless explicitly routed and should also be blocked at the edge. |

## Chapters outside the framework profile

Authentication (V6), authorization (V8), OAuth/OIDC and self-contained identity
tokens (V9–V10), business-specific data protection (V14), and WebRTC (V17) are
application/product concerns. Ember primitives neither satisfy nor waive them.
Security architecture and secure coding (V15) are represented by the threat
model and review. Gate 4 supplies the framework-relevant V16 structured,
redacted route-template telemetry contract and regression tests. Release
evidence must still reassess those chapters for the actual application.

## Evidence index

- `test/stage3_selftest.s`: positive and negative Host/proxy, request ID,
  RFC 8439, tamper/expiry, cookies, CORS, CSRF, multipart, and HTML cases.
- `test/stage4_selftest.s` and `docs/OBSERVABILITY.md`: structured logging,
  configured redaction, trusted trace context, bounded metrics, and probes.
- `test/stage3_html_unquoted_rejected.*` and
  `test/stage3_html_comment_rejected.*`: expected macro-expansion failures.
- `test/stage2_selftest.s` and Sputnik runtime native HTTP tests: framing,
  connection, overload, disconnect, and lifecycle boundary.
- [THREAT_MODEL.md](THREAT_MODEL.md), [SECURITY.md](SECURITY.md), and
  [SECURITY_REVIEW.md](SECURITY_REVIEW.md): design, operations, scans, findings,
  and residual-risk ownership.
