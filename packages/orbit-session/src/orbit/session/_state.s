package orbit.session._state

import task

export Session, Entry, SessionError, InvalidTokenError, SessionScopeError
export SessionConflictError, SessionStoreError, SessionOverflowError
export json_copy, session_key, valid_id?, reference_id, copy_entry, check_transition

class SessionError < Exception:
  attr message
  attr source

  def init(@message, @source: null)

class InvalidTokenError < SessionError
class SessionScopeError < SessionError
class SessionConflictError < SessionError
class SessionStoreError < SessionError
class SessionOverflowError < SessionError

def session_key(key):
  case key:
    when (Str | Symbol): key.to_str
    else: raise SessionError("session keys must be strings or symbols")

def json_copy(value, depth = 0):
  raise SessionError("session data exceeds 32 nesting levels") if depth > 32
  case value:
    when (Null | Bool | Int | Str): value
    when Float:
      # The JSON encoder rejects non-finite numbers.
      Json.parse(Json.generate(value))
    when Array:
      value.map |child|: json_copy(child, depth + 1)
    when (Map | StrictMap):
      source = if StrictMap === value then Map(value.entries) else value
      copied = source.transformed |key, child|: (session_key(key), json_copy(child, depth + 1))
      raise SessionError("duplicate normalized session key") if copied.count != value.count
      copied
    else: raise SessionError("session values must be JSON data")

def valid_id?(id):
  Str === id and id.length == 64 and id.contains_only?("0123456789abcdef")

def reference_id(payload):
  unless (Map === payload or StrictMap === payload) and valid_id?(payload[?"id"]):
    raise InvalidTokenError("invalid session reference")
  payload["id"]

class Entry:
  attr id
  attr revision
  attr data
  attr created_at
  attr updated_at
  attr expires_at

  def init(@id, @revision, data, @created_at, @updated_at, @expires_at):
    valid = valid_id?(@id) and Int === @revision and @revision > 0
    valid = valid and Int === @created_at and Int === @updated_at and Int === @expires_at
    valid = valid and @created_at >= 0 and @updated_at >= @created_at and @expires_at > @updated_at
    unless valid and (Map === data or StrictMap === data):
      raise InvalidTokenError("invalid session entry")
    @data = json_copy(data)

  def to_map():
    {"id": @id, "revision": @revision, "data": json_copy(@data),
      "created_at": @created_at, "updated_at": @updated_at, "expires_at": @expires_at}

def copy_entry(entry):
  Entry(entry.id, entry.revision, entry.data, entry.created_at, entry.updated_at, entry.expires_at)

def check_transition(previous, entry, now):
  raise SessionConflictError("session expired before it could be saved") if entry.expires_at <= now
  expected = 1
  expected = previous.revision + 1 if previous and previous.id == entry.id
  raise SessionConflictError("invalid session revision transition") unless entry.revision == expected

class Session:
  def init(@manager, @token):
    @owner = task.local(inherit: false)
    @loaded = false
    @closed = false
    @destroyed = false
    @force = false
    @discard_cookie = false
    @original = null
    @data = {}

  def _within(&blk):
    try:
      @owner.with(true): blk()
    ensure:
      @closed = true

  def _check_scope!():
    if @closed or not @owner.bound?():
      raise SessionScopeError("session belongs to the active request task")

  def _load!():
    _check_scope!
    return if @loaded
    now = @manager.now
    if @token:
      try:
        @original = @manager.load(@token, now)
      rescue InvalidTokenError:
        @discard_cookie = true
      @discard_cookie = true unless @original
    @id = if @original then @original.id else SecureRandom.hex(32)
    @created_at = if @original then @original.created_at else now
    @data = if @original then json_copy(@original.data) else {}
    @baseline = Json.generate(@data)
    @loaded = true

  def [](key):
    _load!
    @data[?session_key(key)]

  def []=(key, value):
    _load!
    raise SessionScopeError("destroyed session cannot be modified") if @destroyed
    @data[session_key(key)] = json_copy(value)
    value

  def include?(key):
    _load!
    @data.has_key?(session_key(key))

  def delete(key):
    _load!
    name = session_key(key)
    value = @data[?name]
    @data.delete!(name)
    value

  def clear():
    _load!
    @data = {}
    self

  def to_map():
    _load!
    json_copy(@data)

  def id():
    _load!
    @force = true unless @original or @destroyed
    if @destroyed then null else @id

  def loaded?():
    _check_scope!
    @loaded

  def new?():
    _load!
    @original == null

  def changed?():
    _load!
    @force or @destroyed or Json.generate(json_copy(@data)) != @baseline

  def touch():
    _load!
    raise SessionScopeError("destroyed session cannot be renewed") if @destroyed
    @force = true
    self

  def regenerate():
    touch()
    @id = SecureRandom.hex(32)
    self

  def reset():
    regenerate()
    @data = {}
    @created_at = @manager.now
    self

  def destroy():
    _load!
    @data = {}
    @destroyed = true
    self

  def _original(): @original
  def _destroyed?(): @destroyed
  def _loaded?(): @loaded
  def _discard_cookie?(): @discard_cookie

  def _next_entry(now, ttl, absolute_ttl):
    _check_scope!
    return null unless @loaded
    return null if @destroyed
    return null unless changed?
    expires = now + ttl
    absolute = @created_at + absolute_ttl
    expires = absolute if expires > absolute
    raise SessionConflictError("session reached its absolute lifetime") if expires <= now
    revision = 1
    revision = @original.revision + 1 if @original and @original.id == @id
    Entry(@id, revision, @data, @created_at, now, expires)
