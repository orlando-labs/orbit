package orbit.oauth._protocol

from net.http import Client as HttpClient

export OAuthError, StateError, CallbackError, ProviderError, ProtocolError, TransportError
export Token, Identity, Reply, Transport, Provider
export endpoint, local_path, text, normalize_scopes, pkce_challenge, clock_now, Clock, callback_key

class OAuthError < Exception:
  attr message
  def init(@message)

class StateError < OAuthError
class CallbackError < OAuthError
class ProtocolError < OAuthError
class TransportError < OAuthError

class ProviderError < OAuthError:
  attr code
  attr status
  def init(code, @status: null):
    @code = if Str === code and code.length <= 80 and code.contains_only?("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.") then code else "provider_error"
    super("OAuth provider rejected the request: " + @code)

class Clock:
  def now(): Time.now.unix_seconds

def clock_now(clock):
  stamp = clock.now
  raise ArgumentError("OAuth clock must return nonnegative Unix seconds") unless Int === stamp and stamp >= 0
  stamp

def _controls?(value):
  bytes = value.bytes
  index = 0
  while index < bytes.count:
    return true if bytes[index] < 32 or bytes[index] == 127
    index += 1
  false

def text(value, label, limit = 8192):
  unless Str === value and value.present? and value.bytesize <= limit:
    raise ArgumentError(label + " must be a nonempty bounded string")
  raise ArgumentError(label + " contains control characters") if _controls?(value)
  value

def endpoint(value, allow_http_loopback: false, query: false):
  text(value, "OAuth URL", 2048)
  raise ArgumentError("OAuth URLs cannot contain backslashes or whitespace") if value.contains?("\\") or value.contains?(" ")
  parsed = Url.parse(value)
  valid = parsed[:scheme] == "https"
  if allow_http_loopback and parsed[:scheme] == "http":
    valid = ["localhost", "127.0.0.1", "::1"].include?(parsed[:host])
  unless valid and parsed[:host] and parsed[:userinfo] == null and parsed[:fragment] == null:
    raise ArgumentError("OAuth URLs require HTTPS without credentials or fragments")
  raise ArgumentError("OAuth URL cannot contain a query") if not query and parsed[:query] != null
  parsed

def local_path(value):
  text(value, "OAuth return path", 1024)
  unless value.starts_with?("/") and not value.starts_with?("//") and not value.contains?("\\"):
    raise ArgumentError("OAuth return path must be an absolute application path")
  value

def callback_key(value):
  parsed = Url.parse(value)
  port = parsed[:port] or (if parsed[:scheme] == "https" then 443 else 80)
  [parsed[:scheme], parsed[:host], port, parsed[:path]]

def normalize_scopes(values, separator: " "):
  source = if Str === values then values.split(separator) else values
  raise ArgumentError("OAuth scopes must be an array or string") unless Array === source
  result = []
  source.each |scope|:
    next if scope == ""
    text(scope, "OAuth scope", 256)
    valid = scope.contains_only?("!#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~")
    raise ArgumentError("invalid OAuth scope") unless valid
    result.push!(scope) unless result.include?(scope)
  raise ArgumentError("too many OAuth scopes") if result.count > 64
  result.freeze

def pkce_challenge(verifier): Base64Url.encode(Digest.sha256(verifier.bytes))

class Token:
  attr access_token
  attr token_type
  attr refresh_token
  attr expires_at
  attr refresh_expires_at
  attr scopes

  def init(@access_token, @token_type, @refresh_token, @expires_at, @refresh_expires_at, @scopes)
  def expired?(now: Time.now.unix_seconds): @expires_at != null and @expires_at <= now
  def authorization(): "Bearer " + @access_token
  def to_str(): "<orbit.oauth.Token redacted>"

class Identity:
  attr provider
  attr uid
  attr info
  attr raw
  def init(@provider, @uid, @info: {}, @raw: {})

class Reply:
  attr status
  attr body
  attr content_type
  def init(@status, @body, @content_type = "application/json")

class Transport:
  def init(timeout: 10.0):
    @client = HttpClient(timeout: timeout, redirects: :off)

  def request(method, url, headers: {}, body: null, limit: 65536):
    response = null
    try:
      response = if method == :get:
        @client.get(url, headers: headers)
      elif method == :post:
        @client.post(url, headers: headers, body: body)
      else:
        raise ArgumentError("unsupported OAuth HTTP method")
      Reply(response.status, response.body_text(limit: limit), response.headers.first("content-type"))
    rescue HttpError:
      # Transport exception messages may contain URLs or request credentials.
      raise TransportError("OAuth HTTP exchange failed")
    ensure:
      response.close! if response

  def close!(): @client.close!

class Provider:
  attr name
  attr authorize_url
  attr token_url
  attr client_id
  attr redirect_uri
  attr issuer
  attr requested_scopes
  attr binding

  def init(
    name:,
    authorize_url:,
    token_url:,
    client_id:,
    redirect_uri:,
    client_secret: null,
    scopes: [],
    token_auth: null,
    scope_separator: " ",
    issuer: null,
    authorization_params: {},
    transport: null,
    clock: null,
    allow_http_loopback: false
  ):
    @name = text(name.to_str, "OAuth provider name", 64)
    @authorize_url = authorize_url
    @token_url = token_url
    @redirect_uri = redirect_uri
    endpoint(@authorize_url, allow_http_loopback: allow_http_loopback)
    endpoint(@token_url, allow_http_loopback: allow_http_loopback)
    endpoint(@redirect_uri, allow_http_loopback: allow_http_loopback)
    @issuer = issuer
    endpoint(@issuer, allow_http_loopback: allow_http_loopback) if @issuer
    @client_id = text(client_id, "OAuth client ID", 512)
    @client_secret = client_secret
    text(@client_secret, "OAuth client secret", 4096) if @client_secret != null
    @token_auth = token_auth or (if @client_secret then :basic else :none)
    unless [:basic, :post, :none].include?(@token_auth):
      raise ArgumentError("token_auth must be :basic, :post or :none")
    raise ArgumentError("client authentication requires a secret") if @token_auth != :none and not @client_secret
    @requested_scopes = normalize_scopes(scopes)
    unless [" ", ","].include?(scope_separator):
      raise ArgumentError("scope_separator must be a space or comma")
    @scope_separator = scope_separator
    unless Map === authorization_params or StrictMap === authorization_params:
      raise ArgumentError("authorization_params must be a map")
    source = if StrictMap === authorization_params then Map(authorization_params.entries) else authorization_params
    @authorization_params = source.transformed |key, value|:
      name = text(key.to_str, "OAuth authorization parameter", 80)
      if ["client_id", "redirect_uri", "response_type", "scope", "state", "code_challenge", "code_challenge_method", "client_secret", "access_token"].include?(name):
        raise ArgumentError("reserved OAuth authorization parameter: " + name)
      (name, text(value, "OAuth authorization value", 1024))
    if @authorization_params.count != authorization_params.count:
      raise ArgumentError("duplicate normalized OAuth authorization parameter")
    @authorization_params.freeze
    @transport = transport or Transport()
    @owned_transport = transport == null
    @clock = clock or Clock()
    @binding = Digest.sha256(Json.generate([@name, @client_id, @authorize_url, @token_url,
      @redirect_uri, @issuer, @requested_scopes, @token_auth, @scope_separator, @authorization_params]).bytes).hex

  def now(): clock_now(@clock)

  def authorization_url(state, verifier):
    params = @authorization_params.copy
    params.merge!({response_type: "code", client_id: @client_id, redirect_uri: @redirect_uri,
      state: state, code_challenge: pkce_challenge(verifier), code_challenge_method: "S256"})
    params[:scope] = @requested_scopes.join(" ") unless @requested_scopes.empty?
    @authorize_url + "?" + Url.build_query(params)

  def json_request(method, url, headers: {}, body: null, limit: 65536):
    reply = @transport.request(method, url, headers: headers, body: body, limit: limit)
    raise TransportError("OAuth endpoint returned a redirect") if reply.status >= 300 and reply.status < 400
    unless Str === reply.body and reply.body.bytesize <= limit:
      raise ProtocolError("OAuth response exceeds the size limit")
    media = if reply.content_type then reply.content_type.split(";")[0].trim.downcase else ""
    unless media == "application/json" or (media.starts_with?("application/") and media.ends_with?("+json")):
      raise ProtocolError("OAuth endpoint must return JSON")
    data = try:
      Json.parse(reply.body, duplicate_keys: :reject)
    rescue JsonParseError:
      raise ProtocolError("OAuth endpoint returned invalid JSON")
    if Map === data and data[?:error]:
      raise ProviderError(data[:error], status: reply.status)
    unless reply.status >= 200 and reply.status < 300:
      raise TransportError("OAuth endpoint returned an unsuccessful status")
    data

  def _lifetime(data, name, stamp):
    value = data[?name]
    return null if value == null
    unless Int === value and value >= 0 and value <= 315360000:
      raise ProtocolError("invalid OAuth token lifetime")
    stamp + value

  def _token(params, requested, previous = null):
    headers = {accept: "application/json", "content-type": "application/x-www-form-urlencoded"}
    params[:client_id] = @client_id
    if @token_auth == :basic:
      # RFC 6749 section 2.3.1: encode each credential before Basic encoding.
      encoded_id = Url.build_query({x: @client_id})
      encoded_secret = Url.build_query({x: @client_secret})
      pair = encoded_id.slice(2..-1) + ":" + encoded_secret.slice(2..-1)
      headers[:authorization] = "Basic " + Base64.encode(pair.bytes)
      params.delete!(:client_id)
    elif @token_auth == :post:
      params[:client_secret] = @client_secret
    data = json_request(:post, @token_url, headers: headers, body: Url.build_query(params), limit: 16384)
    raise ProtocolError("OAuth token response must be an object") unless Map === data
    access = data[?:access_token]
    unless Str === access and access.present? and access.bytesize <= 8192 and access.contains_only?("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/="):
      raise ProtocolError("invalid OAuth access token")
    type = data[?:token_type]
    raise ProtocolError("only OAuth Bearer tokens are supported") unless Str === type and type.downcase == "bearer"
    refresh = data[?:refresh_token]
    refresh = previous.refresh_token if refresh == null and previous
    if refresh != null:
      valid = Str === refresh and refresh.present? and refresh.bytesize <= 8192
      raise ProtocolError("invalid OAuth refresh token") unless valid
      raise ProtocolError("invalid OAuth refresh token") if _controls?(refresh)
    granted = requested
    if data.has_key?(:scope):
      raise ProtocolError("invalid OAuth token scope") unless Str === data[:scope]
      granted = try:
        normalize_scopes(data[:scope], separator: @scope_separator)
      rescue ArgumentError:
        raise ProtocolError("invalid OAuth token scope")
    stamp = now()
    refresh_expiry = _lifetime(data, :refresh_token_expires_in, stamp)
    if previous and not data.has_key?(:refresh_token) and not data.has_key?(:refresh_token_expires_in):
      refresh_expiry = previous.refresh_expires_at
    Token(access, "Bearer", refresh, _lifetime(data, :expires_in, stamp), refresh_expiry, granted)

  def exchange(code, verifier):
    text(code, "OAuth authorization code")
    unless Str === verifier and verifier.length >= 43 and verifier.length <= 128 and verifier.contains_only?("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"):
      raise ArgumentError("invalid PKCE verifier")
    _token({grant_type: "authorization_code", code: code, redirect_uri: @redirect_uri, code_verifier: verifier}, @requested_scopes)

  def refresh(token, scopes: null):
    raise ArgumentError("refresh expects an OAuth Token with a refresh token") unless Token === token and token.refresh_token
    raise ArgumentError("OAuth refresh token has expired") if token.refresh_expires_at != null and token.refresh_expires_at <= now()
    requested = if scopes == null then token.scopes else normalize_scopes(scopes)
    escalated = requested.any? |scope|: not token.scopes.include?(scope)
    if escalated:
      raise ArgumentError("refresh scopes cannot exceed the original grant")
    params = {grant_type: "refresh_token", refresh_token: token.refresh_token}
    params[:scope] = requested.join(" ") if scopes != null
    _token(params, requested, token)

  def client_credentials(scopes: @requested_scopes):
    raise ArgumentError("client credentials requires client authentication") if @token_auth == :none
    requested = normalize_scopes(scopes)
    params = {grant_type: "client_credentials"}
    params[:scope] = requested.join(" ") unless requested.empty?
    _token(params, requested)

  def identity(token): null
  def close!(): @transport.close! if @owned_transport
  def to_str(): "<orbit.oauth.Provider " + @name + ">"
