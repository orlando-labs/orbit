package app

import orbit
from orbit import respond
import orbit.oauth as oauth
import orbit.session as sessions
from orbit.security import CsrfMiddleware
from orbit.assets import StaticFiles
import views
import layouts

export application

class Pages < oauth.Controller:
  include sessions.ControllerSession

  def snapshot():
    account = session[:account]
    {
      schema: "orbit.vue-shell.v1",
      account:,
      session: {
        authenticated: account != null,
        store: "cookie",
        ttl_seconds: 3600,
        authenticated_at: session[:authenticated_at]
      },
      auth_error: request.query("auth_error") == "1"
    }

  def account_page(data):
    layouts.application(
      views.account(),
      title: "Orbit · Account",
      assets: service(:assets),
      bootstrap: data
    )

  def home():
    data = snapshot()
    respond:
      html: account_page(data)
      json: data

  def current():
    data = snapshot()
    respond:
      html: account_page(data)
      json: data
      format("application/vnd.orbit.session+json", encode: :json): data

  def start():
    header("cache-control", "no-store")
    header("referrer-policy", "no-referrer")
    try:
      target = service(:oauth).flow(:github).start(session, return_to: "/")
      respond:
        html: redirect(target, status: 303, external: true)
        json: {authorize_url: target}
    rescue oauth.OAuthError:
      respond:
        html: redirect("/?auth_error=1", status: 303)
        json: render(json: {error: "Please reload the page and try signing in again."}, status: 400)

  def callback():
    try:
      result = oauth_callback(:github)
      session.reset
      identity = result.identity
      session[:account] = {
        provider: "github",
        uid: identity.uid,
        login: identity.info[:login],
        name: identity.info[:name],
      }
      session[:authenticated_at] = Time.now.unix_seconds
      redirect("/", status: 303)
    rescue oauth.OAuthError:
      redirect("/?auth_error=1", status: 303)

  def logout():
    session.destroy
    respond:
      html: redirect("/", status: 303)
      json: render(status: :no_content)

routes = orbit.routes:
  get "/", to: &Pages#home
  get "/api/session", to: &Pages#current
  post "/auth/github", to: &Pages#start
  get "/auth/github/callback", to: &Pages#callback
  post "/auth/logout", to: &Pages#logout

def application(provider, assets, session_secret:, csrf_secret:, origin:, behind_proxy: false, debug: false):
  security = orbit.SecurityPolicy(origin: origin, content_security_policy: assets.csp,
    trusted_proxy_cidrs: if behind_proxy then ["127.0.0.1/32", "::1/128"] else [],
    forwarded: if behind_proxy then :x_forwarded else :none,
    forwarded_hops: if behind_proxy then 1 else 0)

  orbit.App(routes: routes, security: security, expose_exceptions: debug,
    services: {assets: assets, oauth: oauth.Registry([oauth.Flow(provider, max_pending: 1)])},
    middleware: [StaticFiles(),
      sessions.Middleware(store: sessions.CookieStore(), secret: session_secret, secure: security.origin.secure?),
      CsrfMiddleware(secret: csrf_secret, session_service: :session)])
