package orbit.session

import orbit
from orbit.security import CookieJar, CookieLimits, SetCookie, SessionCodec, CookieError
from orbit.security import SessionError as CodecError
from orbit.session._state import Session, Entry, SessionError, InvalidTokenError, SessionScopeError
from orbit.session._state import SessionConflictError, SessionStoreError, SessionOverflowError
from orbit.session._stores import CookieStore, MemoryStore

export Session, Entry, SessionError, InvalidTokenError, SessionScopeError
export SessionConflictError, SessionStoreError, SessionOverflowError
export CookieStore, MemoryStore, Middleware, Controller, ControllerSession, current

class _Clock:
  def now(): Time.now.unix_seconds

def current(request, name: :session): request.service(name)

mixin ControllerSession:
  def session(): service(:session)

class Controller < orbit.Controller:
  include ControllerSession

def _secret(material, purpose):
  bytes = case material:
    when Str: Bytes.new(material)
    when Bytes: material
    else: raise ArgumentError("session secrets must be strings or bytes")
  if bytes.count < 32:
    raise ArgumentError("session secrets must contain at least 32 bytes")
  Digest.hmac_sha256(bytes, Bytes.new(purpose))

class Middleware:
  attr store

  def init(
    @store:,
    secret:,
    old_secrets: [],
    @name: "orbit-session",
    @service: :session,
    @ttl: 3600,
    @absolute_ttl: 86400,
    @secure: true,
    @path: "/",
    @domain: null,
    @same_site: :lax,
    @max_cookie_bytes: 4096,
    @max_data_bytes: 65536,
    max_header_bytes: 8192,
    clock: null
  ):
    unless Int === @ttl and @ttl > 0 and Int === @absolute_ttl and @absolute_ttl >= @ttl:
      raise ArgumentError("session lifetimes must be positive seconds; absolute_ttl must cover ttl")
    unless Array === old_secrets and old_secrets.count <= 8:
      raise ArgumentError("old_secrets must contain at most eight previous keys")
    unless Int === @max_cookie_bytes and @max_cookie_bytes >= 256 and @max_cookie_bytes <= 4096:
      raise ArgumentError("max_cookie_bytes must be between 256 and 4096")
    unless Int === @max_data_bytes and @max_data_bytes > 0 and @max_data_bytes <= 1048576:
      raise ArgumentError("max_data_bytes must be between 1 and 1048576")
    unless Symbol === @service or Str === @service:
      raise ArgumentError("session service name must be a string or symbol")
    @clock = clock or _Clock()
    # Validate cookie policy at boot, including __Host-/SameSite constraints.
    _cookie("", 0)
    @limits = CookieLimits(max_header_bytes: max_header_bytes, max_value_bytes: @max_cookie_bytes)
    purpose = "orbit-session.v1|" + @store.kind + "|" + @name + "|" + @path + "|" + (@domain or "")
    keys = old_secrets.map |key|: _secret(key, purpose)
    @codec = SessionCodec(secret: _secret(secret, purpose), old_secrets: keys,
      ttl: @ttl, clock_skew: 0, max_payload_bytes: 4096)

  def now():
    value = @clock.now
    raise SessionError("session clock must return nonnegative Unix seconds") unless Int === value and value >= 0
    value

  def load(token, now):
    payload = try:
      @codec.decode(token, now: now)
    rescue CodecError |error|:
      raise InvalidTokenError("invalid session cookie", source: error)
    entry = @store.load(payload, now: now)
    if entry:
      return null if entry.expires_at <= now or entry.created_at + @absolute_ttl <= now
      raise InvalidTokenError("session timestamps are in the future") if entry.updated_at > now
      raise SessionOverflowError("stored session data exceeds max_data_bytes") if Json.generate(entry.data).bytesize > @max_data_bytes
    entry

  def _cookie(token, max_age):
    SetCookie(@name, token, path: @path, domain: @domain, secure: @secure,
      http_only: true, same_site: @same_site, max_age: max_age).header_value

  def _save(previous, entry, now):
    if Json.generate(entry.data).bytesize > @max_data_bytes:
      raise SessionOverflowError("session data exceeds max_data_bytes")
    token = try:
      @codec.encode(@store.dump(entry), now: now)
    rescue CodecError |error|:
      raise SessionOverflowError("session does not fit its cookie", source: error)
    header = try:
      _cookie(token, entry.expires_at - now)
    rescue CookieError |error|:
      raise SessionOverflowError("session does not fit its cookie", source: error)
    if header.bytesize > @max_cookie_bytes:
      raise SessionOverflowError("Set-Cookie exceeds max_cookie_bytes")
    # All serialization/header checks precede side effects in the store.
    @store.commit(previous, entry, now: now)
    header

  def _private(response):
    protected = response.with_header("cache-control", "private, no-store")
    varied = response.headers.all("vary").any? |value|:
      value.split(",").any? |name|: ["cookie", "*"].include?(name.trim.downcase)
    return protected if varied
    protected.with_header("vary", "Cookie", append: true)

  def _finish(session, response):
    return response unless session._loaded?
    protected = _private(response)
    return protected if response.status >= 500
    owned_cookie = response.headers.all("set-cookie").any? |value|: value.starts_with?(@name + "=")
    if owned_cookie:
      raise SessionError("session cookie is owned by orbit-session middleware")
    stamp = now()
    header = null
    if session._destroyed?:
      @store.destroy(session._original, now: stamp)
      header = _cookie("", 0)
    else:
      entry = session._next_entry(stamp, @ttl, @absolute_ttl)
      if entry:
        header = _save(session._original, entry, stamp)
      elif session._discard_cookie?:
        header = _cookie("", 0)
    if header then protected.with_header("set-cookie", header, append: true) else protected

  def call(request, next):
    # Orbit has already validated direct/proxy provenance before middleware.
    if @secure and not request.secure?:
      return orbit.render(text: "secure session requires HTTPS", status: 400)
    if request.services.has_key?(@service):
      raise SessionScopeError("request already has a session service")
    if request.headers.all("cookie").count > 1:
      return orbit.render(text: "bad request", status: 400)
    jar = try:
      CookieJar.parse(request.header("cookie"), limits: @limits)
    rescue CookieError:
      null
    return orbit.render(text: "bad request", status: 400) unless jar
    session = Session(self, jar.get(@name))
    try:
      session._within:
        response = orbit.normalize_response(next(request.with_service(@service, session)))
        _finish(session, response)
    rescue SessionConflictError:
      _private(orbit.render(text: "session changed; retry request", status: 409))
    rescue SessionStoreError:
      _private(orbit.render(text: "session store unavailable", status: 503))
