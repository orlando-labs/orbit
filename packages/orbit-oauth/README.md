# orbit-oauth

OAuth 2.0 protocol and Orbit controller integration, independent of User models,
ORM, and session storage. Provider-specific profile APIs belong in companions
such as [`orbit-oauth-github`](../orbit-oauth-github/README.md).

The first scope implements Authorization Code with mandatory PKCE S256,
refresh tokens, and Client Credentials. Only Bearer tokens and JSON token
responses are accepted. Device Authorization, OIDC/ID-token verification,
discovery, implicit grants, and password grants are outside this scope.
OAuth token exchange alone does not establish an identity; a provider companion
must validate identity through its authenticated API.

## Layers

| API | Responsibility |
| --- | --- |
| `Provider` | Fixed endpoints, credentials, authorization parameters, exchange, refresh, and optional identity resolution. |
| `Token` | Explicit access/refresh tokens, granted scopes, and expiry timestamps. |
| `Flow` | Browser state, PKCE verifier, callback validation, and return path. |
| `Result` | `provider`, `token`, `identity` (possibly Null), and `return_to`. |
| `Registry` | Named flows and distinct callback URLs for providers. |
| `ControllerOAuth` / `Controller` | `oauth_authorize`, `oauth_callback`, and `oauth_result`. |

The package depends only on Orbit. `Flow` accepts any session object with
`[]` and `[]=`, including `orbit-session`; it imports no session store. The
controller helper reads request services `:oauth` and `:session`. Applications
register `Registry` as an ordinary Orbit service and install session middleware
separately. No routes, users, account links, or authenticated sessions are
created implicitly.

## Generic provider

```sputnik
import orbit.oauth as oauth

provider = oauth.Provider(
  name: :example,
  authorize_url: "https://identity.example/oauth/authorize",
  token_url: "https://identity.example/oauth/token",
  client_id: client_id,
  client_secret: client_secret,
  redirect_uri: "https://notebook.example/auth/example/callback",
  scopes: ["profile"],
  authorization_params: {prompt: "consent"})

flow = oauth.Flow(provider)
# session is supplied by the application, not by the protocol client.
url = flow.start(session, return_to: "/notebook")
result = flow.finish(session, request)
```

`token_auth:` is `:basic` by default when a secret is supplied and `:none` for
public clients. `:post` supports providers requiring credentials in the token
form. Basic credentials are individually form-encoded before Base64 encoding.
Public clients still use PKCE; they cannot use Client Credentials. Authorization
parameters cannot override state, PKCE, callback, client ID, response type,
scopes, or secret/token fields. Reserved and duplicate normalized keys fail at
startup. Generic scopes are space-delimited; a comma is a valid character
inside one scope. Provider addons can configure `scope_separator: ","` for
nonstandard token responses.

All URLs are configured at startup, with HTTPS required. URLs cannot contain
userinfo, fragments, or existing queries; use `authorization_params` for
provider options. `redirect_uri` is fixed and sent unchanged in both requests;
it is never derived from Host or client parameters. The explicit development
option `allow_http_loopback: true` permits HTTP only for `localhost`,
`127.0.0.1`, and `::1`. It applies to provider endpoints too, enabling local
HTTP fixtures. Custom `site_url`/API endpoints are trusted configuration.

For a provider returning the RFC 9207 `iss` callback parameter, configure
`issuer:`. The callback then requires an exact match, including presence.
`Registry` rejects providers sharing the same callback URL, including equivalent
host casing/default ports, to avoid cross-provider response mix-up. Use a
separate callback path for every provider.

## Browser flow and controller

```sputnik
class Login < oauth.Controller:
  def start(): oauth_authorize(:example, return_to: "/notebook")

  def callback():
    try:
      result = oauth_callback(:example)
      # result == oauth_result; inspect identity/token here.
      # Application-specific account lookup and session changes go here.
      redirect(result.return_to, status: 303)
    rescue oauth.OAuthError:
      render(text: "Authorization failed; start again", status: 400)
```

An existing controller can `include oauth.ControllerOAuth`. Function handlers
use `oauth.current(request).flow(name)` and explicitly pass their session and
request. The controller's OAuth result remains local to that controller instance.

Use a CSRF-protected POST for the start route and a GET callback route. The
start helper returns 303 to the provider. Both helpers set `Cache-Control:
no-store` and `Referrer-Policy: no-referrer`; Orbit preserves the stricter
referrer policy. Render no third-party resources on a callback page, and
redirect after completion so the code does not remain in the visible URL.
Exclude callback query strings, token bodies, and Authorization headers from
application/proxy logs.

State contains 256 random bits; the PKCE verifier is 32 secure random bytes,
Base64url encoded without padding. Only state/challenge go to the provider.
The verifier remains in the application's protected session. A pending entry
is bound to provider/client/endpoints/callback/scopes/configuration and retains
a local return path. Return paths reject external/protocol-relative targets,
backslashes, and control characters.

`Flow(provider, ttl: 600, max_pending: 3, session_key: "_orbit_oauth", clock:
null)` allows independent login attempts in multiple tabs. TTL must be 1–1800
seconds; the count must be 1–8. Expired entries are pruned on a new start;
capacity exhaustion raises `StateError`. The bound applies to the shared
session key, across providers. Configure the same clock on provider/flow when
testing. A custom clock implements `now()` returning nonnegative Unix seconds.
Do not overwrite the reserved session key with application data.

Callbacks require GET, matching validated request origin/path, scalar protocol
parameters, a known unexpired matching state, and a code or provider error.
Repeated/bracket-shaped parameters, invalid encoding, or an oversized query
are rejected before token exchange. Unrelated pending attempts survive a failed
callback. Each matched state is removed before provider I/O.

**Session persistence remains a separate boundary.** Catch OAuth errors in the
controller and return an ordinary failure response (as above) to persist state
consumption. With `orbit-session`, an uncaught exception or 5xx response discards
session changes; a retry may present the same state. No transaction/row lock is
held over provider HTTP calls. CookieStore cannot revoke/reject a copied older
cookie or synchronize concurrent callbacks. Provider-enforced PKCE and one-use
authorization codes remain required; state deletion alone is not a global
one-use guarantee. Memory/ORM stores additionally enforce their usual session
revision checks. A session conflict may require starting login again.

After successful identity/account validation, the application should rotate
its session ID before storing its own account identifier. Store tokens only
when the application actually needs provider API access; they are never copied
to sessions, responses, or User records by this package.

## Tokens and non-browser grants

```sputnik
token = provider.client_credentials(scopes: ["jobs"])
refreshed = provider.refresh(token)
# Optional subset, never a broader grant:
refreshed = provider.refresh(token, scopes: ["jobs"])
```

`Token` exposes `access_token`, `token_type` (normalized to `Bearer`),
`refresh_token`, `expires_at`, `refresh_expires_at`, and `scopes`.
`authorization()` explicitly builds a Bearer header; `expired?(now: ...)` checks
access expiry. Missing expiries remain Null; `expires_in` values must be integer
seconds from 0 through 315360000. A refresh response omitting its refresh token
retains the previous token and its known expiry. A new refresh token replaces
the old one; persist the returned token atomically in application storage if
needed. The library does not retry exchanges or schedule refreshes.
`to_str` redacts Token contents, but explicit attribute access is sensitive.

## Transport, errors, and extension points

`Transport(timeout: 10.0)` uses the SDK HTTP client with TLS verification and
redirects disabled. It consumes/closes every response, including body-limit
failures. Token responses are limited to 16384 bytes. JSON parsing rejects
duplicate keys. There are no automatic HTTP retries. The provider owns its
default transport; call `provider.close!` at application shutdown. A supplied
transport is owned by the caller (useful when sharing a pool).

A test/custom transport implements:

```sputnik
request(method, url, headers: {}, body: null, limit: 65536)
# Return oauth.Reply(status, body_text, content_type = "application/json").
```

It must enforce the limit while reading, verify TLS, avoid redirects/retries,
and propagate cancellation. Provider validation also checks the returned body's
size. `Provider#json_request` supports trusted provider-specific endpoints;
never pass an untrusted URL together with a Bearer token. Override
`identity(token)` to return `Identity(provider, uid, info: {}, raw: {})`; the
base provider returns Null. Keep provider-specific payloads outside core.

All runtime protocol failures inherit `OAuthError`: `StateError`,
`CallbackError`, `ProviderError`, `ProtocolError`, and `TransportError`.
`ProviderError` retains a bounded safe `code` and optional HTTP `status`; raw
provider descriptions/bodies are not included in error messages. Provider error
objects are recognized even with HTTP 200 (GitHub behavior). Transport errors
omit underlying URLs/credentials; cancellation propagates without wrapping.
Invalid application configuration raises `ArgumentError`.

## Local checks

Development graphs use local sources; these packages are not published:

```sh
../sputnik-lang/build/sputnik run test/oauth_selftest.build.yaml \
  --grant random.secure --grant time.now
../sputnik-lang/build/sputnik run test/oauth_http_selftest.build.yaml \
  --grant random.secure --grant time.now --grant net.listen --grant net.connect
```

Both also build with `--target native --require-full-native`, with separate
output/cache directories. The first suite covers the RFC 7636 vector, protocol
validation, refresh, provider identity, and real Orbit/session controller flow
with CookieStore and MemoryStore. The second uses a loopback HTTP server to
verify wire requests, profile/refresh, redirects, body limits, and lease cleanup.
No real GitHub credentials are required. Published deployment still requires
registering the exact callback URL and testing the configured OAuth App.

Protocol references: [RFC 6749](https://www.rfc-editor.org/rfc/rfc6749),
[PKCE RFC 7636](https://www.rfc-editor.org/rfc/rfc7636),
[OAuth security BCP RFC 9700](https://www.rfc-editor.org/rfc/rfc9700), and
[issuer identification RFC 9207](https://www.rfc-editor.org/rfc/rfc9207).
