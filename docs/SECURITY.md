# Ember security baseline

Status: normative stage-3 security contract, version 1.0, 2026-07-22.

This document defines the secure deployment and application contract for the
Ember 1.0 target. It complements the trusted-edge boundary in
[DEPLOYMENT.md](DEPLOYMENT.md), the versioned [threat model](THREAT_MODEL.md),
and the [OWASP ASVS 5.0.0 mapping](ASVS_5_MAPPING.md).

## Request boundary

Every `App` has an `ember.SecurityPolicy`. The default policy accepts only
`localhost`, `127.0.0.1`, and `[::1]`, ignores all forwarding headers, and adds
the default security headers. An in-memory request passed to `App#call` must
therefore contain exactly one valid `Host` header; `ember.testing` supplies
`Host: localhost` unless the test overrides it.

Production must construct the policy explicitly:

```amber
policy = ember.SecurityPolicy(
  allowed_hosts: ["app.example.test"],
  trusted_proxy_cidrs: ["10.20.0.0/16"],
  forwarded: :x_forwarded,
  forwarded_hops: 2,
  hsts: true)

app = ember.App(routes: routes, security: policy)
```

Host syntax and authorization are checked before routing. A missing,
duplicated, or malformed authority returns 400; a syntactically valid but
unauthorized host returns 403. Exact host names are preferred. A `*.` entry is
an explicit subdomain-suffix policy and never authorizes the bare suffix.

`:x_forwarded` is the only supported forwarding convention. It is disabled
unless at least one trusted proxy CIDR and a positive hop bound are configured.
Forwarding fields from an untrusted socket peer are ignored. For a trusted
peer, `X-Forwarded-Host` and `X-Forwarded-Proto` must each contain one value,
`X-Forwarded-For` must not be repeated or exceed the configured hop count, and
every intermediate address must also be trusted. Ambiguity is rejected.

Arbitrary IPv4 CIDR prefixes and exact IPv6 `/128` proxy entries are supported.
Broader IPv6 proxy networks are intentionally rejected until a canonical IPv6
CIDR parser is part of the supported Amber runtime. Deployments that require a
broader IPv6 range must use an IPv4/private edge hop or enumerate exact IPv6
addresses.

After authorization, `request.effective_scheme`,
`request.effective_authority`, `request.client_ip`, `request.trusted_proxy`,
`request.origin()`, and `request.secure?()` are safe provenance values. Cookie,
CSRF, redirect, and application origin decisions must use these values rather
than raw forwarding headers.

## Response headers and request IDs

The default policy adds these headers to success and error responses:

- `Content-Security-Policy: default-src 'self'; object-src 'none'; base-uri
  'none'; frame-ancestors 'none'`;
- `X-Content-Type-Options: nosniff` and defense-in-depth
  `X-Frame-Options: DENY`;
- `Referrer-Policy: strict-origin-when-cross-origin`;
- restrictive `Permissions-Policy` for geolocation, microphone, and camera;
- `Cross-Origin-Opener-Policy: same-origin`.

HSTS is opt-in because the development listener is plaintext. With `hsts:
true`, it is emitted only when the effective scheme is validated as HTTPS. A
production browser deployment must enable HSTS and may replace the CSP with a
stricter application-specific policy. Disabling `security_headers` is not a
supported production configuration.

`RequestIdMiddleware` accepts an incoming identifier only when
`accept_incoming` is true and the value is non-empty, within the configured
16..256 byte bound, and consists solely of ASCII letters, digits, `.`, `_`, or
`-`. Otherwise it generates a 144-bit secure random Base64URL identifier. Raw
invalid values are never reflected. Stage 4 will replace the preview access-log
text format with structured, redacted events.

## Cookies and sessions

`ember.security` exposes strict bounded primitives:

- `CookieJar.parse` rejects malformed, duplicate, invalid, oversized, or
  over-count request cookies;
- `SetCookie` defaults to `Secure`, `HttpOnly`, `SameSite=Lax`, and `Path=/`,
  enforces `__Secure-`/`__Host-` invariants, rejects attribute injection, and
  keeps the name plus value within 4096 bytes;
- `SignedCookieCodec` provides versioned HMAC-SHA-256 authenticity with
  constant-time tag comparison, payload bounds, and read-side key rotation;
- `SessionCodec` provides bounded, versioned, authenticated encryption with
  ChaCha20-Poly1305, secure 96-bit nonces, absolute expiry, clock-skew bounds,
  and read-side key rotation.

All signing, encryption, and CSRF secrets must contain at least 32 bytes of
unpredictable material loaded from the platform secret manager. Never place
them in source, build manifests, command arguments, logs, or client-visible
configuration. Put the current secret first and previous secrets in
`old_secrets`; remove old keys after the longest token lifetime. Grant
`random.secure` to builds that generate tokens.

`SessionCodec` is a stateless envelope, not an authentication system. The
application remains responsible for login-time renewal, authorization,
inactivity policy, logout/account-disable revocation where required, and
choosing a production `__Host-` cookie name. A server-side session store or a
per-user revocation epoch is required when immediate revocation is a business
requirement.

## CORS and CSRF

No CORS headers are emitted unless `CorsMiddleware` is installed. Its origins,
methods, and request headers are exact allowlists. Credentialed CORS forbids a
wildcard origin. Preflight requests with a disallowed origin, method, or header
are rejected; allowed origin reflection is accompanied by `Vary: Origin`.
CORS is not authorization and must not replace endpoint authentication.

`CsrfMiddleware` implements a signed, session-bound double-submit token. Unsafe
methods require an exact validated `Origin`, identical cookie/header tokens, a
valid HMAC, and reject `Sec-Fetch-Site: cross-site`. Safe responses bootstrap a
token cookie. Pair it with an authenticated encrypted/signed session cookie;
use production names such as `__Host-ember-session` and
`__Host-ember-csrf` on HTTPS. Routes that intentionally accept cross-origin
state changes need a separately reviewed protocol rather than bypassing the
middleware.

## Multipart and uploaded files

`ember.multipart.parse(request, limits:)` claims the request body exactly once
and accepts only strict `multipart/form-data`. Defaults are 1 MiB aggregate,
64 parts, 8 KiB headers per part, 32 headers, 64 KiB fields, 512 KiB files,
128-byte field names, and 255-byte filenames. It requires CRLF framing,
one `Content-Disposition`, quoted parameters, no epilogue, and rejects path
separators and dot traversal filenames.

Align the server `max_body_bytes` with or below the endpoint multipart limit.
The parser returns bytes and metadata only: it does not persist, unpack,
execute, scan, or trust uploaded content. Each application must allowlist file
types, verify magic/content, impose user/storage quotas, generate its own
storage name outside executable/public roots, and scan files when its threat
model requires that.

## HTML rendering

`html"""..."""` determines the interpolation context at compile time:

- element text and ordinary quoted attributes are escaped automatically;
- URL attributes require `url(...)`, which rejects unapproved schemes,
  protocol-relative URLs, control characters, backslashes, whitespace, and
  ambiguous URL lists;
- script bodies and `on*` attributes require `trusted_script(...)`;
- style bodies and style attributes require `trusted_style(...)`;
- `srcdoc` requires an explicit `Html` value from `raw(...)`;
- interpolation in comments, tag syntax, and unquoted attributes fails macro
  expansion with `EMBER_HTML_CONTEXT`.

`raw`, `trusted_script`, and `trusted_style` are security-review boundaries,
not sanitizers. Never pass untrusted data to them. User-authored HTML, SVG,
Markdown, CSS, or JavaScript needs a separately selected, maintained sanitizer;
Ember deliberately does not pretend that escaping can sanitize active content.

## Production checklist

- Configure exact public hosts, edge CIDRs, hop count, HSTS, and an
  application-specific CSP before binding traffic.
- Ensure the edge removes client forwarding fields and overwrites them once;
  keep the edge-to-Ember hop private or mutually authenticated.
- Store and rotate 32-byte-or-longer session/CSRF secrets in a secret manager;
  use `__Host-` cookies on HTTPS.
- Install CORS only on routes/origins that require it and CSRF on all
  cookie-authenticated state-changing browser routes.
- Keep transport, cookie, session, and multipart limits finite and mutually
  consistent.
- Treat trusted HTML wrappers, redirect destinations, uploaded files, log
  fields, and deserialized application data as explicit review points.
- Run the stage-3 regression and compile-fail fixtures before release; review
  [SECURITY_REVIEW.md](SECURITY_REVIEW.md) for residual risks.
