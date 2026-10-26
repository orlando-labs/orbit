package orbit.oauth

import orbit
from orbit.oauth._protocol import OAuthError, StateError, CallbackError, ProviderError, ProtocolError, TransportError
from orbit.oauth._protocol import Token, Identity, Reply, Transport, Provider, pkce_challenge
from orbit.oauth._protocol import Clock, clock_now, local_path, callback_key, text

export OAuthError, StateError, CallbackError, ProviderError, ProtocolError, TransportError
export Token, Identity, Reply, Transport, Provider, Flow, Result, Registry
export ControllerOAuth, Controller, current, pkce_challenge

class Result:
  attr provider
  attr token
  attr identity
  attr return_to
  def init(@provider, @token, @identity, @return_to)
  def to_str(): "<orbit.oauth.Result " + @provider + ">"

class Flow:
  attr provider

  def init(@provider, @ttl: 600, @max_pending: 3, @session_key: "_orbit_oauth", clock: null):
    unless Int === @ttl and @ttl > 0 and @ttl <= 1800:
      raise ArgumentError("OAuth state TTL must be between 1 and 1800 seconds")
    unless Int === @max_pending and @max_pending > 0 and @max_pending <= 8:
      raise ArgumentError("OAuth max_pending must be between 1 and 8")
    unless Str === @session_key and @session_key.present?:
      raise ArgumentError("OAuth session_key must be a nonempty string")
    @clock = clock or Clock()

  def _pending(session, stamp):
    stored = session[@session_key] or {}
    raise StateError("invalid OAuth session state") unless Map === stored
    pending = {}
    stored.each |state, entry|:
      if Map === entry and Int === entry[?:issued_at] and Int === entry[?:expires_at] and entry[:issued_at] <= stamp and entry[:expires_at] > stamp:
        pending[state] = entry
    pending

  def start(session, return_to: "/"):
    local_path(return_to)
    stamp = clock_now(@clock)
    pending = _pending(session, stamp)
    raise StateError("too many pending OAuth authorizations") if pending.count >= @max_pending
    state = SecureRandom.hex(32)
    verifier = SecureRandom.base64url(32)
    pending[state] = {binding: @provider.binding, issued_at: stamp, expires_at: stamp + @ttl, verifier: verifier, return_to: return_to}
    session[@session_key] = pending
    @provider.authorization_url(state, verifier)

  def _callback(request):
    raise CallbackError("OAuth callback requires GET") unless request.method == "GET"
    unless request.origin and callback_key(request.origin + request.path) == callback_key(@provider.redirect_uri):
      raise CallbackError("OAuth callback URL does not match its configured redirect URI")
    raw = request.raw_query or ""
    raise CallbackError("OAuth callback query is too large") if raw.bytesize > 16384
    params = try:
      Url.parse_query(raw)
    rescue UrlDecodeError:
      raise CallbackError("malformed OAuth callback query")
    # Repeated and bracket-shaped protocol parameters must never be coerced.
    ["state", "code", "error", "error_description", "error_uri", "iss"].each |name|:
      value = params[?name]
      raise CallbackError("invalid OAuth callback parameter") if value != null and not Str === value
    params

  def finish(session, request):
    params = _callback(request)
    state = params[?:state]
    unless Str === state and state.length == 64 and state.contains_only?("0123456789abcdef"):
      raise StateError("missing or invalid OAuth state")
    pending = _pending(session, clock_now(@clock))
    entry = pending[?state]
    raise StateError("unknown or expired OAuth state") unless entry and entry[?:binding] == @provider.binding
    # Consume before any provider I/O; applications rescue failures into a 4xx
    # response so orbit-session persists consumption. Never hold a DB lock here.
    pending.delete!(state)
    session[@session_key] = pending
    issuer = params[?:iss]
    if @provider.issuer and issuer != @provider.issuer:
      raise CallbackError("OAuth issuer does not match the configured provider")
    if params[?:error]:
      raise CallbackError("OAuth callback contains both code and error") if params[?:code]
      raise ProviderError(params[:error])
    code = params[?:code]
    unless Str === code and code.present? and code.bytesize <= 8192:
      raise CallbackError("missing or invalid OAuth authorization code")
    try:
      text(code, "OAuth authorization code")
    rescue ArgumentError:
      raise CallbackError("invalid OAuth authorization code")
    token = @provider.exchange(code, entry[:verifier])
    Result(@provider.name, token, @provider.identity(token), local_path(entry[:return_to]))

class Registry:
  def init(flows):
    raise ArgumentError("OAuth registry requires an array of flows") unless Array === flows
    @flows = {}
    callbacks = []
    flows.each |flow|:
      raise ArgumentError("OAuth registry requires Flow values") unless Flow === flow
      name = flow.provider.name
      raise ArgumentError("duplicate OAuth provider name") if @flows.has_key?(name)
      callback = callback_key(flow.provider.redirect_uri)
      raise ArgumentError("OAuth providers require distinct callback URLs") if callbacks.include?(callback)
      callbacks.push!(callback)
      @flows[name] = flow
    @flows.freeze

  def flow(name):
    value = @flows[?name.to_str]
    raise ArgumentError("unknown OAuth provider") unless value
    value

def current(request, name: :oauth): request.service(name)

mixin ControllerOAuth:
  def oauth(): service(:oauth)
  def oauth_result(): @oauth_result

  def oauth_authorize(name, return_to: "/"):
    url = oauth.flow(name).start(service(:session), return_to: return_to)
    redirect(url, status: 303, external: true,
      headers: {"cache-control": "no-store", "referrer-policy": "no-referrer"})

  def oauth_callback(name):
    header("cache-control", "no-store")
    header("referrer-policy", "no-referrer")
    @oauth_result = oauth.flow(name).finish(service(:session), request)

class Controller < orbit.Controller:
  include ControllerOAuth
