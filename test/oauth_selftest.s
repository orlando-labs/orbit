package orbit.oauth_selftest

import orbit
import orbit.testing
import orbit.telemetry
import orbit.session as sessions
import orbit.oauth as oauth
import orbit.oauth.github as github

export main

SECRET = "0123456789abcdef0123456789abcdef"
CALLBACK = "http://localhost/auth/github/callback"
VERIFIER = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

class Clock:
  def init(@stamp = 1000)
  def now(): @stamp
  def advance(seconds): @stamp += seconds

def check(value, message):
  raise ValueError("OAuth: " + message) unless value

def fails(type, &block):
  caught = false
  try:
    block()
  rescue Exception |error|:
    raise error unless type === error
    caught = true
  check(caught, "expected " + type.to_str)

class FakeTransport:
  attr requests
  attr replies
  def init():
    @requests = []
    @replies = []
  def add(data, status: 200): @replies.push!(oauth.Reply(status, Json.generate(data)))
  def request(method, url, headers: {}, body: null, limit: 65536):
    @requests.push!({method: method, url: url, headers: headers, body: body, limit: limit})
    raise oauth.TransportError("fake transport exhausted") if @replies.empty?
    @replies.shift!

# The protocol layer accepts any [] / []= session, without importing a store.
def provider(transport, clock, **options):
  oauth.Provider(name: :example, authorize_url: "https://provider.example/authorize",
    token_url: "https://provider.example/token", client_id: "client: id",
    client_secret: "secret&value", redirect_uri: CALLBACK,
    transport: transport, clock: clock, allow_http_loopback: true, **options)

def token_data():
  {access_token: "token-123", token_type: "bearer", refresh_token: "refresh-123", expires_in: 60,
    refresh_token_expires_in: 120, scope: "read write"}

def request(query, path: "/auth/github/callback", method: "GET"):
  testing.request(method, path, query: query)._with_provenance("http", "localhost", "127.0.0.1", false)

def begin_flow(flow, session, return_to: "/book?chapter=1"):
  url = flow.start(session, return_to: return_to)
  Url.parse(url)[:query_map]

def protocol_checks():
  check(oauth.pkce_challenge(VERIFIER) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 S256 vector")
  transport = FakeTransport()
  clock = Clock()
  client = provider(transport, clock, scopes: ["read", "write"], authorization_params: {prompt: "consent"})
  flow = oauth.Flow(client, clock: clock)
  session = {}
  auth = begin_flow(flow, session)
  check(auth[:response_type] == "code" and auth[:client_id] == "client: id", "authorization request")
  check(auth[:redirect_uri] == CALLBACK and auth[:scope] == "read write", "fixed callback and scopes")
  check(auth[:prompt] == "consent" and auth[:code_challenge_method] == "S256", "provider authorization options")
  check(auth[:state].length == 64 and auth[:code_challenge].length == 43, "state and challenge entropy")
  pending = session[:_orbit_oauth][auth[:state]]
  check(oauth.pkce_challenge(pending[:verifier]) == auth[:code_challenge], "verifier retained only in session")
  transport.add(token_data)
  result = flow.finish(session, request({state: auth[:state], code: "code&123"}))
  check(result.provider == "example" and result.identity == null and result.return_to == "/book?chapter=1", "controller-independent result")
  check(result.token.access_token == "token-123" and result.token.expires_at == 1060, "token normalization and lifetime")
  check(result.token.scopes == ["read", "write"] and not result.token.expired?(now: 1059) and result.token.expired?(now: 1060), "scope and expiry")
  check(result.token.authorization == "Bearer token-123" and not result.token.to_str.contains?("token-123"), "explicit token access and safe display")
  sent = transport.requests[0]
  form = Url.parse_query(sent[:body])
  check(form[:code] == "code&123" and form[:grant_type] == "authorization_code" and form[:redirect_uri] == CALLBACK, "token exchange form encoding")
  check(form[:code_verifier] == pending[:verifier] and not form.has_key?(:client_secret) and not form.has_key?(:client_id), "PKCE and Basic client authentication")
  basic = Base64.decode(sent[:headers][:authorization].slice(6..-1)).to_str
  check(basic == "client%3A+id:secret%26value", "RFC 6749 encoded Basic credentials")
  fails(oauth.StateError): flow.finish(session, request({state: auth[:state], code: "replay"}))
  check(transport.requests.count == 1, "replayed state never reaches token endpoint")
  transport.add({access_token: "token-new", token_type: "Bearer", expires_in: 10})
  refreshed = client.refresh(result.token, scopes: ["read"])
  check(refreshed.refresh_token == "refresh-123" and refreshed.scopes == ["read"], "refresh retains omitted refresh token and narrowed grant")
  check(refreshed.refresh_expires_at == 1120, "unchanged refresh token retains its expiration")
  refresh_form = Url.parse_query(transport.requests[1][:body])
  check(refresh_form[:grant_type] == "refresh_token" and refresh_form[:scope] == "read", "refresh request")
  fails(ArgumentError): client.refresh(result.token, scopes: ["admin"])
  transport.add({access_token: "service", token_type: "bearer"})
  service = client.client_credentials(scopes: ["jobs"])
  check(service.scopes == ["jobs"] and service.expires_at == null, "client credentials without expiry")
  check(Url.parse_query(transport.requests[2][:body])[:grant_type] == "client_credentials", "client credentials grant")
  public_client = provider(transport, clock, token_auth: :none)
  fails(ArgumentError): public_client.client_credentials
  client.close!

  post_client = provider(transport, clock, token_auth: :post)
  transport.add({access_token: "post", token_type: "bearer"})
  post_client.exchange("code", VERIFIER)
  form = Url.parse_query(transport.requests[-1][:body])
  check(form[:client_id] == "client: id" and form[:client_secret] == "secret&value", "client_secret_post")
  transport.add({access_token: "public", token_type: "bearer"})
  public_client.exchange("code", VERIFIER)
  form = Url.parse_query(transport.requests[-1][:body])
  check(form[:client_id] == "client: id" and not form.has_key?(:client_secret), "public PKCE client")
  transport.add({access_token: "comma", token_type: "bearer", scope: "read,write"})
  check(client.exchange("code", VERIFIER).scopes == ["read,write"], "generic OAuth permits commas within one scope")
  clock.advance(120)
  fails(ArgumentError): client.refresh(result.token)

def state_checks():
  transport = FakeTransport()
  clock = Clock()
  client = provider(transport, clock)
  flow = oauth.Flow(client, ttl: 30, max_pending: 2, clock: clock)
  session = {}
  first = begin_flow(flow, session)
  second = begin_flow(flow, session)
  check(first[:state] != second[:state], "parallel login attempts have distinct state")
  fails(oauth.StateError): flow.start(session)
  fails(oauth.StateError): flow.finish(session, request({code: "code"}))
  fails(oauth.StateError): flow.finish({}, request({state: first[:state], code: "code"}))
  fails(oauth.StateError): flow.finish(session, request({state: "f" * 64, code: "code"}))
  fails(oauth.CallbackError): flow.finish(session, request("state=" + first[:state] + "&state=" + first[:state] + "&code=code"))
  fails(oauth.CallbackError): flow.finish(session, request("state[x]=bad&code=code"))
  fails(oauth.CallbackError): flow.finish(session, request("state=%ZZ"))
  fails(oauth.CallbackError): flow.finish(session, request({state: first[:state], code: "code"}, path: "/other"))
  fails(oauth.CallbackError): flow.finish(session, request({state: first[:state], code: "code"}, method: "POST"))
  fails(oauth.CallbackError): flow.finish(session, request("code=" + "a" * 17000))
  check(transport.requests.empty? and session[:_orbit_oauth].count == 2, "invalid callbacks preserve unrelated attempts and make no network calls")
  fails(oauth.ProviderError): flow.finish(session, request({state: first[:state], error: "access_denied"}))
  check(session[:_orbit_oauth].count == 1, "provider denial consumes its state")
  transport.add({access_token: "parallel", token_type: "bearer"})
  flow.finish(session, request({state: second[:state], code: "code"}))
  check(session[:_orbit_oauth].empty?, "other tab can complete")
  expired = begin_flow(flow, session)
  clock.advance(30)
  fails(oauth.StateError): flow.finish(session, request({state: expired[:state], code: "code"}))
  begin_flow(flow, session)
  check(session[:_orbit_oauth].count == 1, "expired attempts pruned before login")
  ["https://evil.example", "//evil.example", "/\\evil.example", "/ok\r\nevil"].each |path|:
    fails(ArgumentError): flow.start({}, return_to: path)

  other = provider(transport, clock, issuer: "https://provider.example")
  isolated = oauth.Flow(other, clock: clock)
  pending = begin_flow(isolated, session)
  fails(oauth.StateError): flow.finish(session, request({state: pending[:state], code: "code"}))
  fails(oauth.CallbackError): isolated.finish(session, request({state: pending[:state], code: "code", iss: "https://evil.example"}))
  pending = begin_flow(isolated, session)
  fails(oauth.CallbackError): isolated.finish(session, request({state: pending[:state], code: "code"}))
  pending = begin_flow(isolated, session)
  transport.add({access_token: "issuer", token_type: "bearer"})
  isolated.finish(session, request({state: pending[:state], code: "code", iss: "https://provider.example"}))

def invalid_reply_checks():
  transport = FakeTransport()
  client = provider(transport, Clock())
  bad = [
    [], {token_type: "bearer"}, {access_token: "token", token_type: "mac"},
    {access_token: "token\r\ninjected", token_type: "bearer"},
    {access_token: "token", token_type: "bearer", expires_in: "60"},
    {access_token: "token", token_type: "bearer", scope: []},
    {access_token: "token", token_type: "bearer", refresh_token: 42}]
  bad.each |value|:
    transport.add(value)
    fails(oauth.ProtocolError): client.exchange("code", VERIFIER)
  transport.replies.push!(oauth.Reply(200, "{\"access_token\":\"a\",\"access_token\":\"b\",\"token_type\":\"bearer\"}"))
  fails(oauth.ProtocolError): client.exchange("code", VERIFIER)
  transport.replies.push!(oauth.Reply(200, "not json"))
  fails(oauth.ProtocolError): client.exchange("code", VERIFIER)
  transport.replies.push!(oauth.Reply(200, "{}", "text/html"))
  fails(oauth.ProtocolError): client.exchange("code", VERIFIER)
  transport.replies.push!(oauth.Reply(200, "x" * 16385))
  fails(oauth.ProtocolError): client.exchange("code", VERIFIER)
  transport.replies.push!(oauth.Reply(302, "{}"))
  fails(oauth.TransportError): client.exchange("code", VERIFIER)
  transport.add({message: "secret never copied"}, status: 500)
  fails(oauth.TransportError): client.exchange("code", VERIFIER)
  transport.add({error: "bad_verification_code", error_description: "echoed-secret"})
  try:
    client.exchange("code", VERIFIER)
  rescue oauth.ProviderError |error|:
    check(error.code == "bad_verification_code" and not error.message.contains?("echoed-secret"), "safe provider errors including HTTP 200")
  ["http://remote.example/auth", "https://user:pass@provider.example/auth", "https://provider.example/auth#fragment"].each |url|:
    fails(ArgumentError): provider(transport, Clock(), issuer: url)
  fails(ArgumentError): provider(transport, Clock(), authorization_params: {state: "fixed"})
  fails(ArgumentError): client.exchange("code", "short")
  fails(ArgumentError): oauth.Registry([oauth.Flow(client), oauth.Flow(client)])
  equivalent = oauth.Provider(name: :second, authorize_url: "https://provider.example/authorize",
    token_url: "https://provider.example/token", client_id: "other", redirect_uri: "http://LOCALHOST:80/auth/github/callback",
    transport: transport, allow_http_loopback: true)
  fails(ArgumentError): oauth.Registry([oauth.Flow(client), oauth.Flow(equivalent)])

def github_checks():
  transport = FakeTransport()
  client = github.Provider(client_id: "gh-client", client_secret: "gh-secret", redirect_uri: CALLBACK,
    transport: transport, clock: Clock(), allow_http_loopback: true)
  transport.add({access_token: "gho_token", token_type: "bearer", scope: "read:user,user:email"})
  transport.add({id: 12345, login: "octocat", name: "Octo", email: "untrusted-profile@example.com"})
  transport.add([{email: "unverified@example.com", primary: true, verified: false},
    {email: "secondary@example.com", primary: false, verified: true},
    {email: "verified@example.com", primary: true, verified: true}])
  session = {}
  flow = oauth.Flow(client, clock: Clock())
  auth = begin_flow(flow, session)
  result = flow.finish(session, request({state: auth[:state], code: "gh-code"}))
  identity = result.identity
  check(identity.provider == "github" and identity.uid == "12345", "stable GitHub numeric ID")
  check(identity.info[:login] == "octocat" and identity.info[:email] == "verified@example.com" and identity.info[:email_verified], "primary verified email only")
  check(identity.raw[:email] == "untrusted-profile@example.com", "explicit raw profile")
  check(result.token.scopes == ["read:user", "user:email"], "GitHub comma scopes")
  check(transport.requests[0][:url] == "https://github.com/login/oauth/access_token", "GitHub token endpoint")
  check(Url.parse_query(transport.requests[0][:body])[:client_secret] == "gh-secret", "GitHub POST credentials")
  profile_request = transport.requests[1]
  check(profile_request[:url] == "https://api.github.com/user" and profile_request[:headers][:authorization] == "Bearer gho_token", "authenticated GitHub profile")
  check(profile_request[:headers]["x-github-api-version"] == "2026-03-10", "versioned GitHub API")
  fails(ArgumentError): client.client_credentials
  transport.add({id: 9, login: "new-name"})
  transport.add([{email: "no@example.com", primary: true, verified: false}])
  check(client.identity(result.token).info[:email] == null, "unverified email is never an identity")
  transport.add({id: "123", login: "bad"})
  fails(oauth.ProtocolError): client.identity(result.token)
  profile_only = github.Provider(client_id: "gh-client", client_secret: "secret", redirect_uri: CALLBACK,
    fetch_emails: false, scopes: ["read:user"], transport: transport, allow_http_loopback: true)
  transport.add({id: 42, login: "profile-only"})
  check(profile_only.identity(result.token).uid == "42", "email endpoint is optional")

class LoginPages < oauth.Controller:
  def start(): oauth_authorize(:github, return_to: "/notebook")
  def callback():
    try:
      result = oauth_callback(:github)
      check(result == oauth_result, "result available in controller")
      session = service(:session)
      session.regenerate
      session[:account] = result.identity.uid
      redirect(result.return_to, status: 303)
    rescue oauth.OAuthError:
      render(text: "authorization failed", status: 400)
  def account(): render(text: service(:session)[:account] or "anonymous")

routes = orbit.routes:
  post "/auth/github", to: &LoginPages#start
  get "/auth/github/callback", to: &LoginPages#callback
  get "/account", to: &LoginPages#account

def cookie(response):
  header = response.header("set-cookie")
  if header then header.split(";")[0] else null

def integration_checks(store):
  clock = Clock()
  transport = FakeTransport()
  provider = github.Provider(client_id: "gh-client", client_secret: "secret", redirect_uri: CALLBACK,
    transport: transport, clock: clock, allow_http_loopback: true)
  app = orbit.App(routes: routes, expose_exceptions: true,
    services: {oauth: oauth.Registry([oauth.Flow(provider, clock: clock)])},
    middleware: [sessions.Middleware(store: store, secret: SECRET, secure: false, clock: clock)])
  anonymous = app.call(testing.get("/account"))
  check(anonymous.body_text == "anonymous" and cookie(anonymous) == null, "anonymous page remains lazy")
  started = app.call(testing.post("/auth/github"))
  check(started.status == 303 and cookie(started) != null, "controller starts flow and persists state: " + started.status.to_str + " " + started.body_text)
  check(started.header("referrer-policy") == "no-referrer", "authorization response privacy")
  auth = Url.parse(started.header("location"))[:query_map]
  token = cookie(started)
  denied = app.call(testing.get("/auth/github/callback", query: {state: auth[:state], error: "access_denied"}, headers: {cookie: token}))
  check(denied.status == 400 and cookie(denied) != null and transport.requests.empty?, "denial commits state consumption without network")
  replayed = app.call(testing.get("/auth/github/callback", query: {state: auth[:state], code: "replay"}, headers: {cookie: cookie(denied)}))
  check(replayed.status == 400 and transport.requests.empty?, "denied state cannot be replayed")
  started = app.call(testing.post("/auth/github", headers: {cookie: cookie(denied)}))
  auth = Url.parse(started.header("location"))[:query_map]
  transport.add({access_token: "gho_secret", token_type: "bearer"})
  transport.add({id: 777, login: "account"})
  transport.add([])
  finished = app.call(testing.get("/auth/github/callback", query: {state: auth[:state], code: "valid"}, headers: {cookie: cookie(started)}))
  check(finished.status == 303 and finished.header("location") == "/notebook", "controller consumes identity and redirects")
  check(finished.header("cache-control").contains?("no-store") and finished.header("referrer-policy") == "no-referrer", "callback response privacy")
  account = app.call(testing.get("/account", headers: {cookie: cookie(finished)}))
  check(account.body_text == "777", "application stores its own account identifier")
  check(not finished.header("set-cookie").contains?("gho_secret"), "access token absent from application cookie")

def main():
  protocol_checks
  state_checks
  invalid_reply_checks
  github_checks
  integration_checks(sessions.CookieStore())
  integration_checks(sessions.MemoryStore())
  print "PASS orbit OAuth and GitHub"
  true
