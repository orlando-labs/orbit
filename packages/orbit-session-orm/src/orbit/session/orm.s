package orbit.session.orm

import orm
from orbit.session._state import Entry, SessionError, SessionConflictError, SessionStoreError
from orbit.session._state import reference_id, check_transition

export ORMStore

class ORMStore:
  def init(model, columns: {}):
    @model = if orm.ModelType === model then model else model.model
    raise ArgumentError("bind the session model before creating ORMStore") unless @model.bound?
    @columns = {id: :id, payload: :payload, revision: :revision,
      created_at: :created_at, updated_at: :updated_at, expires_at: :expires_at}
    columns.each |name, column|:
      raise ArgumentError("unknown session column mapping") unless @columns.has_key?(name)
      @columns[name] = column
    selected = {}
    @columns.each |name, column|:
      unless Str === column or Symbol === column:
        raise ArgumentError("session column names must be strings or symbols")
      raise ArgumentError("session column mappings must be distinct") if selected.has_key?(column.to_str)
      selected[column.to_str] = true
      spec = @model.config.attribute(column)
      raise ArgumentError("session model is missing column: " + column.to_str) unless spec
      expected = if ["id", "payload"].include?(name.to_str) then :text else :integer
      raise ArgumentError("invalid session column type: " + column.to_str) unless spec.type == expected
    pk = @model.config.primary_key
    unless pk and pk.name.to_str == @columns[:id].to_str and not pk.generated?:
      raise ArgumentError("session id column must be the non-generated text primary key")

  def kind(): "orm"
  def dump(entry): {"id": entry.id}

  def _find(id):
    result = @model.find(id)
    return result.value if result.ok?
    return null if orm.NotFoundError === result.error
    raise SessionStoreError("session lookup failed", source: result.error)

  def _entry(record):
    unless Str === record[@columns[:payload]]:
      raise SessionStoreError("stored session payload must be JSON text")
    try:
      data = Json.parse(record[@columns[:payload]], duplicate_keys: :reject)
      Entry(record[@columns[:id]], record[@columns[:revision]], data,
        record[@columns[:created_at]], record[@columns[:updated_at]], record[@columns[:expires_at]])
    rescue JsonParseError |error|:
      raise SessionStoreError("stored session payload is malformed", source: error)
    rescue SessionError |error|:
      raise SessionStoreError("stored session metadata is malformed", source: error)

  def load(payload, now:):
    record = _find(reference_id(payload))
    return null unless record
    entry = _entry(record)
    if entry.expires_at <= now then null else entry

  def _attributes(entry):
    values = {}
    values[@columns[:id]] = entry.id
    values[@columns[:payload]] = Json.generate(entry.data)
    values[@columns[:revision]] = entry.revision
    values[@columns[:created_at]] = entry.created_at
    values[@columns[:updated_at]] = entry.updated_at
    values[@columns[:expires_at]] = entry.expires_at
    values

  def commit(previous, entry, now:):
    check_transition(previous, entry, now)
    try:
      @model.with_lock:
        record = null
        if previous:
          record = _find(previous.id)
          unless record and record[@columns[:expires_at]] > now and record[@columns[:revision]] == previous.revision:
            raise SessionConflictError("session changed or was revoked")
        if not previous or previous.id != entry.id:
          raise SessionConflictError("session identifier collision") if _find(entry.id)
          # Rotation deletes and creates inside the same database boundary.
          record.delete.or_raise if record
          @model.create(_attributes(entry)).or_raise
        else:
          record.assign!(_attributes(entry))
          record.save.or_raise
    rescue orm.OrmError |error|:
      raise SessionStoreError("session save failed", source: error)
    null

  def destroy(previous, now:):
    return null unless previous
    try:
      @model.with_lock:
        record = _find(previous.id)
        record.delete.or_raise if record
    rescue orm.OrmError |error|:
      raise SessionStoreError("session deletion failed", source: error)
    null

  def prune(now:, limit: 100):
    raise ArgumentError("prune limit must be a positive Int") unless Int === limit and limit > 0
    removed = 0
    try:
      @model.with_lock:
        while removed < limit:
          expired = @model.where |query|: query.field(@columns[:expires_at]) <= now
          result = expired.first
          if result.err?:
            raise SessionStoreError("session prune lookup failed", source: result.error) unless orm.NotFoundError === result.error
            break
          result.value.delete.or_raise
          removed += 1
    rescue orm.OrmError |error|:
      raise SessionStoreError("session prune failed", source: error)
    removed
