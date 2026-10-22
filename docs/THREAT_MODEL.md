# Orbit threat model

Version: 1.0  
Review date: 2026-07-22  
Scope: Orbit source at roadmap gates 0–5 and the supported trusted-edge profile.

This is the framework threat model required by roadmap stage 3. Application
teams must extend it with their identities, authorization model, data classes,
external services, business abuse cases, and deployment topology.

## Assets and security objectives

Protected assets are request routing integrity, validated origin/client
provenance, session confidentiality and integrity, CSRF tokens, application
data carried in bodies and responses, uploaded bytes, secrets and keys,
service/ORM resources, logs and error events, availability, and the integrity
of the Sputnik compiler/runtime and native HTTP boundary.

The baseline aims to prevent an untrusted peer from changing HTTP message
boundaries, selecting an unauthorized host/origin, injecting active content or
headers, forging browser requests, reading or modifying session state, causing
unbounded allocation/work, choosing server-side file paths, or placing secrets
in responses/logs. It fails closed on ambiguous request metadata.

## Trust boundaries

```text
untrusted browser/client
        |
        | HTTPS, public limits, normalization
        v
trusted TLS edge / ingress
        |
        | private or authenticated HTTP/1.1 hop
        v
Sputnik native HTTP parser ---> Orbit SecurityPolicy ---> router/middleware/app
                                      |                         |
                                      | validated provenance    | explicit APIs
                                      v                         v
                              sessions/CSRF/HTML          DB/files/services
```

The edge is trusted only when the socket peer is inside the configured CIDR
set. Header presence never establishes trust. The runtime HTTP parser and
Orbit both enforce message/header limits. Application code is trusted to use
explicit unsafe wrappers only after validation or sanitization. Databases,
filesystems, service meshes, secret managers, scanners, and TLS configuration
remain deployment/application boundaries.

## Assumptions

- Public traffic reaches Orbit through the edge contract in
  [DEPLOYMENT.md](DEPLOYMENT.md); direct Internet exposure is unsupported.
- The edge removes user-supplied forwarding fields and writes its own values.
- Production disables exception exposure, keeps all documented limits finite,
  and supplies unpredictable secrets through a secret manager.
- The supported Sputnik compiler/runtime revision and native build chain are
  reviewed release inputs. Versioned packages, exact revision/tree locks,
  clean-room resolution, reproducible package comparison, checksums, and
  release provenance enforce this assumption.
- Authentication and authorization are application concerns; the framework
  session envelope does not grant identity or permissions by itself.

## Threats and mitigations

| Threat | Attack and impact | Framework/edge control | Residual responsibility |
|---|---|---|---|
| Request smuggling and response splitting | Conflicting CL/TE, duplicate Host, obs-fold, CR/LF, or invalid framing desynchronizes edge and app | Native HTTP conformance checks, immutable validated `Headers`, duplicate Host rejection, body/header bounds, stage-2 raw corpus | Edge must apply compatible RFC 9110/9112 normalization and never forward an ambiguous message |
| Proxy and Host spoofing | Raw Host or X-Forwarded fields change routing, origin, HTTPS/cookie decisions, or client identity | Pre-routing Host allowlist, explicit CIDRs/hops, trusted-intermediate checks, singleton forwarded host/proto, validated effective provenance | Configure exact hosts/CIDRs; use IPv4 or exact IPv6 `/128` edge entries |
| Header/log injection | Control characters in headers or request IDs forge response/log records | `Headers` rejects invalid names/values; request ID validation; structured JSON events use route templates and configured redaction | Exporters must preserve JSON structure and must not append raw request fields |
| Injection and unsafe deserialization | Untrusted values become SQL, commands, templates, objects, or headers | Strong-parameter schemas, typed routes, immutable values, no generic object deserializer, header validation | Applications use parameterized ORM/query APIs and explicit data schemas; no untrusted template source or dynamic code |
| XSS and active content | Interpolation changes HTML/URL/JS/CSS structure or uploaded content executes | Context-aware HTML macro, typed URL/script/style wrappers, forbidden ambiguous contexts, CSP/nosniff/frame controls | Unsafe wrappers require review; user-authored active content needs a maintained sanitizer; uploaded files need safe serving policy |
| CSRF and cross-origin abuse | Browser credentials authorize attacker-originated state changes | Exact-origin CORS, signed session-bound double submit, Origin and Sec-Fetch-Site checks, SameSite-capable cookies | Install middleware on all cookie-authenticated unsafe routes; CORS never replaces authorization |
| Session/cookie theft or tampering | Client reads, forges, replays, or extends session state | Secure/HttpOnly/SameSite defaults, prefix invariants, HMAC signing, ChaCha20-Poly1305, expiry, key rotation, constant-time tag checks | TLS/HSTS and `__Host-` production cookies; application renewal, inactivity, and revocation; keys in secret manager |
| Resource exhaustion | Huge headers, bodies, cookies, multipart parts/files, connections, or slow streams exhaust memory/workers | Finite transport timeouts/capacity, immediate overload rejection, bounded cookies/tokens/multipart, hop count and route bounds | Align transport/multipart limits; edge rate/slow-client policy; application file/user quotas and expensive-operation limits |
| Path confusion and file traversal | Encoded route segments or uploaded filenames choose unintended resources | Single percent-decode path pipeline, strict trailing slash, typed routes, filename separator/dot rejection | Generate server-side storage names; canonicalize under a fixed root; never use client filename as a path |
| Secrets and sensitive logs | Keys, cookies, bodies, raw URLs, errors, or versions leak through source/logs/responses | Production-safe 500 body, structured route-template logs, configured field redaction, privacy-safe traces | Secret manager/rotation; keep application/exporter extensions free of cookie/session/body values |
| Dependency/compiler/native compromise | Unpinned or vulnerable compiler/runtime/ORM/SQLite code changes security behavior | Versioned core/companion packages, exact revision/tree locks, clean-room build, platform/integration CI, reproducible signed release artifacts and provenance | Registry/hosting and signing-key protection; dependency review and rebuild for every changed row |
| Crypto misuse | Nonce reuse, weak keys, unauthenticated ciphertext, timing leakage | Secure random 96-bit nonce, minimum 32-byte secrets, RFC 8439 vector, encrypt-then-authenticate AEAD semantics, fixed-size constant-time tag checks, versioned rotation | Independent cryptographic review remains required before 1.0; inventory and rotate keys; do not reuse secrets across purposes |

## Abuse cases that must remain regression tests

- Missing, repeated, malformed, and unauthorized Host values never reach a
  route.
- Forwarding fields from an untrusted peer are ignored; excessive or
  untrusted proxy chains are rejected.
- Invalid request IDs cannot be reflected into headers or logs.
- Modified signed cookies, encrypted sessions, CSRF tokens, and expired
  sessions fail closed.
- Credentialed wildcard CORS configuration is rejected and disallowed
  preflights return 403.
- Oversized/duplicate cookies and aggregate/part/file multipart overflows are
  rejected; traversal filenames are rejected.
- JavaScript URLs, URL-list ambiguity, unwrapped script/style data, comment
  interpolation, and unquoted-attribute interpolation do not render.
- CL/TE ambiguity, duplicate Host, obs-fold, invalid status-body combinations,
  disconnects, overload, and shutdown cancellation retain stage-2 coverage.

## Residual risks and owners

There are no open critical or high findings in this stage-3 review. Accepted
lower-severity risks are tracked here and in [SECURITY_REVIEW.md](SECURITY_REVIEW.md):

| Severity | Risk | Owner / closure gate |
|---|---|---|
| Medium | ChaCha20-Poly1305 is a standards-conformant source implementation with an RFC vector but has not received independent cryptographic validation | Security/release owner; independent review or vetted runtime primitive before 1.0 RC |
| Resolved | Dependencies were sibling source paths without a lock/provenance manifest | Gate 5 introduced versioned packages, revision/tree locks, internal clean-room checkouts, reproducibility, CI, checksums, and provenance |
| Resolved | Preview access logging included the raw path and lacked redaction | Gate 4 introduced the structured route-template telemetry boundary and schema tests |
| Low | Trusted-proxy IPv6 networks support exact `/128` entries only | Runtime/security owner; retain safe rejection or add canonical IPv6 CIDR parsing before broader IPv6 deployment |
| Low | Multipart parsing buffers within the transport body bound before applying finer part limits | Framework owner; keep transport `max_body_bytes <= max_total_bytes`, add streaming parser only with equivalent invariant tests |

Any new high/critical finding reopens roadmap gate 3. Changes to proxy trust,
HTML contexts, cookie/session formats, cryptography, parsing, or native HTTP
framing require threat-model and regression-suite review.
