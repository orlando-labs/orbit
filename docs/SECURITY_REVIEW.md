# Stage 3 security review and scan record

Review date: 2026-07-22  
Ember base revision: `35f492bb0d2aec40a7849bb327929eb85061b582` plus the stage-3 working-tree change set  
Compiler: `amberc 0.1.0-dev` from the sibling `amber-lang` source tree  
Verdict: **zero open critical/high findings** in the reviewed stage-3 scope.

This is an internal source/configuration review and regression record, not a
penetration test, independent cryptographic certification, or dependency
attestation. Those stronger artifacts remain release/RC gates.

## Reviewed scope

- `src/ember.am`: HTTP values, Host authorization, proxy trust, provenance,
  security headers, application error boundary, and transport configuration;
- `src/ember/html.am`: context tracking, escaping, typed trusted wrappers, and
  compile-time rejection;
- `src/ember/security.am`: cookie parsing/serialization, HMAC, AEAD session
  envelope, CORS, and CSRF;
- `src/ember/multipart.am`: media type, framing, headers, limits, and filename
  handling;
- request-id middleware, testing helpers, manifests, stage-0..3 regression
  tests, edge documentation, and relevant sibling Amber native HTTP/digest
  runtime code.

## Executed checks

| Check | Command/evidence | Result |
|---|---|---|
| Whitespace/patch integrity | `git diff --check` | Clean |
| Production-source secret pattern scan | `rg` for password/secret/token/API/private-key assignments outside tests/docs | No candidates |
| Dangerous source primitive scan | `rg` for eval/system/exec/popen/unsafe/raw in `src` | Only documented `Html.raw` trust-boundary calls |
| Build dependency inventory | Manifest path inventory across YAML/TOML | Core stage-3 graph contains Ember source modules only; optional ORM example/test uses sibling `amber-orm` and `sqlite3-amber` |
| Native boundary primitive scan | Targeted search for unsafe C string/process primitives in relevant Amber HTTP runtime paths | No candidate in the searched HTTP paths |
| Local documentation links | Resolve relative Markdown targets in README, roadmap, and `docs/` | All targets resolve |
| Fresh stage-3 build | Native `--no-cache --grant random.secure` build and executable | Passed; executable returned `true` |
| Security regression | `test/stage3_selftest.am` | Host/proxy/request-id/AEAD/cookies/session/CORS/CSRF/multipart/HTML pass |
| HTML compile-fail | Both `stage3_html_*_rejected.build.yaml` builds | Fail with expected `EMBER_HTML_CONTEXT` |
| Prior conformance | Stage 0, 1, 2, core, strong-params, HTTP, and ORM self-tests | Passed; every executable returned `true` |

These command results come from a fresh no-cache verification pass over this
working tree. A release must replace local evidence with immutable CI artifacts
and exact Ember/Amber/package provenance.

## Review findings

No critical or high issue remains open. The review found and fixed the
following before closure:

- raw `Host`/forwarded provenance was trusted: replaced with pre-routing host
  authorization and explicit bounded proxy CIDRs/hops;
- invalid incoming request IDs could reach response/log fields: replaced with
  strict acceptance and secure regeneration;
- the HTML macro treated interpreter contexts alike: replaced with contextual
  escaping, typed URL/script/style boundaries, and compile-time rejection;
- browser/session primitives and multipart limits were absent: added strict,
  bounded implementations and negative tests;
- Set-Cookie domain/size and CORS-origin configuration received additional
  injection/ambiguity validation during review;
- default CSP `base-uri` was tightened to `'none'`.

## Accepted lower-severity findings

| ID | Severity | Finding | Compensating control | Owner / deadline |
|---|---|---|---|---|
| S3-01 | Medium | The source ChaCha20-Poly1305 implementation is standards-vector tested but not independently validated | RFC 8439 vector, authenticated decrypt-before-use, fixed-size tag check, minimum 256-bit material, bounded tokens | Security/release owner; vetted runtime primitive or independent review before 1.0 RC |
| S3-02 | Medium | Sibling source dependencies are not version-locked or attested | Core stage-3 graph is source-only; optional dependency paths inventoried; compatibility documented | Release engineering; gate 5 locked clean-room build and dependency/provenance scan |
| S3-03 | Medium | Preview access log writes the raw path and lacks structured redaction | Error events are redacted; request IDs are safe; operators may omit preview access middleware | Observability owner; gate 4 structured route-template log schema |
| S3-04 | Low | Trusted-proxy IPv6 networks accept exact `/128` entries only | Unsupported broader prefixes fail configuration; IPv4 CIDR is complete | Runtime/security; retain restriction or add canonical parser before broader IPv6 deployment |
| S3-05 | Low | Multipart is bounded but buffered rather than streaming | Default parser and transport aggregate limits are both 1 MiB; strict part/file limits | Framework/application; require `max_body_bytes <= max_total_bytes`, reconsider with streaming parser work |

## Verification record

The reviewer updates this section only from a fresh, no-cache pass. On
2026-07-22:

- stage 3 native regression built without cache and returned `true`;
- both HTML negative fixtures failed with the expected
  `EMBER_HTML_CONTEXT` diagnostic;
- contract/stage 0, stage 1, stage 2, core, strong-params, HTTP loopback, and
  ORM/sqlite native self-tests built without cache and returned `true`;
- stage 2 and HTTP loopback executables ran with only local socket access;
- final source/secret/native-boundary scans and `git diff --check` are recorded
  in the executed-checks table above.

Any failure, newly discovered critical/high issue, or change to a security
boundary reopens the review and roadmap gate 3.
