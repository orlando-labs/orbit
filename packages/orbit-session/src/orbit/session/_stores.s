package orbit.session._stores

from sync import Mutex
from orbit.session._state import Entry, InvalidTokenError, SessionConflictError, SessionStoreError
from orbit.session._state import reference_id, copy_entry, check_transition

export CookieStore, MemoryStore

class CookieStore:
  def kind(): "cookie"

  def load(payload, now:):
    unless Map === payload or StrictMap === payload:
      raise InvalidTokenError("invalid cookie session payload")
    entry = Entry(payload[?"id"], payload[?"revision"], payload[?"data"],
      payload[?"created_at"], payload[?"updated_at"], payload[?"expires_at"])
    if entry.expires_at <= now then null else entry

  def dump(entry): entry.to_map
  def commit(previous, entry, now:): check_transition(previous, entry, now)
  def destroy(previous, now:): null

class MemoryStore:
  def init(@max_entries: 10000):
    unless Int === @max_entries and @max_entries > 0:
      raise ArgumentError("max_entries must be a positive Int")
    @entries = {}
    @mutex = Mutex.new

  def kind(): "memory"
  def dump(entry): {"id": entry.id}

  def load(payload, now:):
    id = reference_id(payload)
    @mutex.synchronize:
      entry = @entries[?id]
      if entry and entry.expires_at <= now:
        @entries.delete!(id)
        entry = null
      if entry then copy_entry(entry) else null

  def commit(previous, entry, now:):
    check_transition(previous, entry, now)
    @mutex.synchronize:
      if previous:
        current = @entries[?previous.id]
        unless current and current.expires_at > now and current.revision == previous.revision:
          raise SessionConflictError("session changed or was revoked")
      if not previous or previous.id != entry.id:
        raise SessionConflictError("session identifier collision") if @entries.has_key?(entry.id)
        _prune(now) if @entries.count >= @max_entries
        if @entries.count >= @max_entries and not previous:
          raise SessionStoreError("memory session capacity exceeded")
      @entries.delete!(previous.id) if previous and previous.id != entry.id
      @entries[entry.id] = copy_entry(entry)
    null

  def destroy(previous, now:):
    if previous:
      @mutex.synchronize: @entries.delete!(previous.id)
    null

  def _prune(now):
    removed = 0
    @entries.keys.each |id|:
      if @entries[id].expires_at <= now:
        @entries.delete!(id)
        removed += 1
    removed

  def prune(now:):
    @mutex.synchronize: _prune(now)

  def size():
    @mutex.synchronize: @entries.count
