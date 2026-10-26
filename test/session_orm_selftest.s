package orbit.session_orm_selftest

import orbit
import orbit.testing
import orbit.session as sessions
import orm
import task
from orm.sqlite3 import pool as sqlite_pool
from orbit.session.orm import ORMStore
from orbit.session_selftest import round_trip, check, server_store_checks, concurrent_requests

export main

class SessionRow:
  use orm.model(table: :web_sessions):
    validate:
      expect(:body, body.absent? or not body.contains?("reject-me"), message: "payload rejected")

def mapped_store():
  ORMStore(SessionRow, columns: {id: :sid, payload: :body, revision: :rev,
    created_at: :born, updated_at: :seen, expires_at: :expires_s})

def snapshot(id, revision, data, created = 1000, updated = 1000, expires = 1060):
  sessions.Entry(id, revision, data, created, updated, expires)

def store_checks(store):
  id = SecureRandom.hex(32)
  initial = snapshot(id, 1, {account: "42", nested: {value: 1}})
  store.commit(null, initial, now: 1000)
  loaded = store.load({"id": id}, now: 1000)
  check(loaded.data[:account] == "42" and loaded.revision == 1, "ORM load committed entry")
  loaded.data[:nested][:value] = 999
  check(store.load({"id": id}, now: 1000).data[:nested][:value] == 1, "loaded data is isolated")
  next = snapshot(id, 2, {account: "43"})
  store.commit(initial, next, now: 1000)
  caught = false
  try:
    store.commit(initial, snapshot(id, 2, {account: "stale"}), now: 1000)
  rescue sessions.SessionConflictError:
    caught = true
  check(caught and store.load({"id": id}, now: 1000).data[:account] == "43", "ORM rejects stale writes")
  target = SecureRandom.hex(32)
  caught = false
  try:
    store.commit(next, snapshot(target, 1, {account: "reject-me"}), now: 1000)
  rescue sessions.SessionStoreError:
    caught = true
  check(caught and store.load({"id": id}, now: 1000) != null and store.load({"id": target}, now: 1000) == null,
    "failed rotation rolls back both deletion and creation")
  rotated = snapshot(target, 1, {account: "44"})
  store.commit(next, rotated, now: 1000)
  check(store.load({"id": id}, now: 1000) == null and store.load({"id": target}, now: 1000) != null,
    "ORM rotation replaces identity atomically")
  store.destroy(rotated, now: 1000)
  caught = false
  try:
    store.commit(rotated, snapshot(target, 2, {account: "resurrected"}), now: 1000)
  rescue sessions.SessionConflictError:
    caught = true
  check(caught and store.load({"id": target}, now: 1000) == null, "logout cannot be undone by stale save")
  expired = snapshot(SecureRandom.hex(32), 1, {})
  store.commit(null, expired, now: 1000)
  check(store.load({"id": expired.id}, now: 1060) == null, "ORM expiry checked without cleanup")
  check(store.prune(now: 1060, limit: 1) == 1, "bounded ORM cleanup")

def parallel_writes(store):
  id = SecureRandom.hex(32)
  initial = snapshot(id, 1, {counter: 0})
  store.commit(null, initial, now: 1000)
  first = task.spawn:
    try:
      store.commit(initial, snapshot(id, 2, {counter: 1}), now: 1000)
      1
    rescue sessions.SessionConflictError:
      0
  second = task.spawn:
    try:
      store.commit(initial, snapshot(id, 2, {counter: 2}), now: 1000)
      1
    rescue sessions.SessionConflictError:
      0
  check(first.wait() + second.wait() == 1, "exactly one concurrent ORM CAS wins")
  check(store.load({"id": id}, now: 1000).revision == 2, "concurrent revision increments once")
  store.destroy(initial, now: 1000)

def main():
  path = "/tmp/orbit-session-" + SecureRandom.hex(8) + ".sqlite"
  database = sqlite_pool(path, max_size: 4, busy_timeout: 3.0, pragmas: {journal_mode: :wal})
  try:
    database.with_connection |db|:
      db.exec("create table web_sessions(sid text primary key not null, body text not null, rev integer not null, born integer not null, seen integer not null, expires_s integer not null)")
    database.bind!(SessionRow).or_raise
    store = mapped_store()
    round_trip(store)
    store_checks(store)
    server_store_checks(store)
    parallel_writes(store)
    concurrent_requests(store)
    # A separately constructed store sees the same model-backed session data.
    initial = snapshot(SecureRandom.hex(32), 1, {account: "persistent"})
    store.commit(null, initial, now: 1000)
    check(mapped_store().load({"id": initial.id}, now: 1000).data[:account] == "persistent", "ORM store survives recreation")
    check(database.stats[:leased] == 0, "ORM store returns all leases")
  ensure:
    database.close!
    for suffix in ["", "-wal", "-shm"]:
      fs.remove(path + suffix) if fs.exists?(path + suffix)
  print "PASS orbit ORM sessions"
  0
