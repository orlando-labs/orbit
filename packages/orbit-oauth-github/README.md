# orbit-oauth-github

GitHub OAuth App integration for [`orbit-oauth`](../orbit-oauth/README.md).
The companion configures GitHub endpoints and client authentication, then
resolves identity through the authenticated user API on every completed login.
It has no User, ORM, or database dependency.

```sputnik
import orbit
import orbit.oauth as oauth
import orbit.oauth.github as github
import orbit.session as sessions
from orbit.security import CsrfMiddleware

class Login < oauth.Controller:
  def start(): oauth_authorize(:github, return_to: "/notebook")

  def callback():
    try:
      result = oauth_callback(:github)
      session = service(:session)
      session.regenerate
      # Application policy can look up/link a User here, if needed.
      session[:account] = {provider: result.provider, uid: result.identity.uid}
      redirect(result.return_to, status: 303)
    rescue oauth.OAuthError:
      render(text: "GitHub authorization failed; start again", status: 400)

routes = orbit.routes:
  post "/auth/github", to: &Login#start
  get "/auth/github/callback", to: &Login#callback

def application(client_id, client_secret, session_secret, csrf_secret):
  provider = github.Provider(client_id: client_id, client_secret: client_secret,
    redirect_uri: "https://notebook.example/auth/github/callback")
  orbit.App(routes: routes,
    security: orbit.SecurityPolicy(allowed_hosts: ["notebook.example"]),
    services: {oauth: oauth.Registry([oauth.Flow(provider)])},
    middleware: [
      sessions.Middleware(store: sessions.CookieStore(), secret: session_secret),
      CsrfMiddleware(secret: csrf_secret, session_service: :session)])
```

Configure the exact callback URL in the GitHub OAuth App. Keep `client_secret`
on the Sputnik backend; the Vue/Electron renderer uses the same browser flow
and never receives it. The example assumes HTTPS reaches Orbit; when TLS
terminates at a proxy, configure Orbit's trusted proxy/forwarding policy too.
Use `SameSite=Lax` for the session cookie so a top-level GET callback carries
it. Vue first obtains a CSRF cookie on a safe request, then sends it in
`X-CSRF-Token` for the POST start request (or submits a suitably protected form).

Default endpoints are `https://github.com/login/oauth/authorize`,
`https://github.com/login/oauth/access_token`, and `https://api.github.com`.
PKCE S256 and state come from core. Token exchange uses `client_secret_post`
and requests JSON. GitHub's comma-separated granted scopes are normalized to
an array. Refresh uses core's explicit `refresh(token)` API when GitHub issues
refresh tokens. GitHub OAuth Apps do not support Client Credentials; calling
it raises `ArgumentError`.

The default scopes are `read:user` and `user:email`. On every completion the
provider requests `/user`, and by default `/user/emails?per_page=100`. Identity
uses GitHub's numeric `id`, converted to a string, rather than a renameable
login or email:

| Result field | Value |
| --- | --- |
| `identity.provider` | `"github"`, or the configured provider name. |
| `identity.uid` | Stable numeric GitHub account ID as a string. |
| `identity.info` | `login`, `name`, `email`, `email_verified`, `avatar_url`, `url`. |
| `identity.raw` | Explicit original `/user` JSON object. |
| `result.token` | Core Token; never implicitly persisted. |

Only a primary **and verified** entry from the email API populates normalized
`email`; otherwise it remains Null and `email_verified` is false. The public
profile's email is never treated as verified. Up to the first 100 email entries
are inspected; the result remains Null if no verified primary is in that page.
An email API failure fails the login rather than silently supplying an
incomplete identity. For profile-only login set `fetch_emails: false, scopes:
["read:user"]` to skip that endpoint. User lookup/linking and email/account
matching policies belong to the application.

API calls use `Accept: application/vnd.github+json`, a Bearer header,
`User-Agent: orbit-oauth-github`, and the explicit default API version
`2026-03-10`. Profile/email replies are each limited to 131072 bytes; unexpected
JSON shapes fail with `ProtocolError`. Responses never expose tokens by
default. The provider inherits core transport ownership and `close!` behavior.

Optional configuration:

- `name:` for a second GitHub installation (requires a distinct callback path).
- `site_url:` and `api_url:` for GitHub Enterprise Server; for example
  `https://github.company.example` and `https://github.company.example/api/v3`.
  Base URLs have no trailing slash. Pick `api_version:` supported by that server.
- `api_version:`, `user_agent:`, `scopes:`, and `fetch_emails:`.
- `authorization_params:` for options such as `login`, `allow_signup: "false"`,
  or `prompt: "select_account"`. Core reserved fields cannot be replaced.
- `transport:` / `clock:` for dependency injection;
  `allow_http_loopback: true` for local HTTP development fixtures only.

Run the core and loopback suites from the Orbit checkout as described in
[local checks](../orbit-oauth/README.md#local-checks). They resolve both packages
from local directories and exercise VM and full-native execution.

Official contracts: [GitHub OAuth web flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps),
[authenticated user](https://docs.github.com/en/rest/users/users#get-the-authenticated-user),
and [email addresses](https://docs.github.com/en/rest/users/emails#list-email-addresses-for-the-authenticated-user).
