# orbit-session-orm

`ORMStore` implements the [orbit-session store contract](../orbit-session/README.md)
using a bound ORM model. It depends on `orm`, not a database driver or a User
model. Database selection, migration/schema creation, pool setup, and model
binding remain application responsibilities.

```sputnik
import orm
import orbit.session as sessions
from orbit.session.orm import ORMStore

class BrowserSession:
  use orm.model(table: :browser_sessions):
    expect_schema:
      column(:id, type: :text, nullable: false, primary_key: true, generated: false)
      column(:payload, type: :text, nullable: false)
      column(:revision, type: :integer, nullable: false)
      column(:created_at, type: :integer, nullable: false)
      column(:updated_at, type: :integer, nullable: false)
      column(:expires_at, type: :integer, nullable: false)

def session_middleware(database, secret):
  database.bind!(BrowserSession).or_raise
  sessions.Middleware(store: ORMStore(BrowserSession), secret: secret)
```

The table must exist before binding; `expect_schema` validates the database
schema and does not create it. All six fields are required. The ID must be a
non-generated text primary key. Payload is JSON text; revision and timestamps
are integers (Unix seconds for timestamps). An index on the expiry column is
recommended for cleanup. Extra fields need defaults/nullability if the store
does not supply them.

Both an ORM model class and its `orm.ModelType` descriptor are accepted. Bind
once at startup, then share the store/middleware. The constructor validates
field types, distinct mappings, and the primary key. Existing column names can
be mapped without changing the storage protocol:

```sputnik
store = ORMStore(BrowserSession, columns: {
  id: :sid, payload: :body, revision: :rev,
  created_at: :born, updated_at: :seen, expires_at: :expires_s})
```

## Atomic persistence

Reads use ordinary model lookup and ignore expired entries without deleting
them. A read-only request performs no write, and the store holds no database
transaction across application code or OAuth/network calls.

Commits enter `Model.with_lock:` before re-reading the row. They check expiry
and revision, then update atomically. Rotation checks the target ID and
deletes/creates in the same boundary; failure rolls back both changes. Logout
deletes the presented ID under the same lock even if its revision has changed.
A stale request cannot overwrite a newer revision or resurrect a deleted ID.
Conflicts become `409`; storage/model validation failures become `503` through
the session middleware. Callbacks are not retried.

The adapter must implement the ORM
[atomicity contract](../../../orm/docs/atomicity.md), including absent-row
protection. The current SQLite adapter reserves the writer with `BEGIN
IMMEDIATE` before reading. Use a shareable ORM pool for concurrent requests;
the direct database adapter is intended for one logical task at a time. Keep
the short save boundary outside an unrelated deferred transaction, which the
SQLite adapter cannot safely upgrade. Other databases belong in ORM adapters,
without separate `orbit-session-pg`/`orbit-session-mysql` packages.

Model validations should be deterministic and free of external side effects:
they run inside the store's short transaction. Session persistence does not
enclose the controller's business transaction. If a business action succeeds
and the final session save conflicts, the action itself is not rolled back.

```sputnik
removed = store.prune(now: Time.now.unix_seconds, limit: 100)
```

Cleanup deletes at most `limit` expired rows per call under a write boundary;
it does not materialize the entire table. Schedule it at the application level.
Expiry/revocation correctness does not depend on cleanup having run.

## Local checks

The test graph loads sibling `../orm` and `../sqlite3` directories and the
working `orbit-session` sources. SQLite is the test adapter, not a dependency
of this package. From the Orbit checkout:

```sh
../sputnik-lang/build/sputnik run test/session_orm_selftest.build.yaml \
  --grant ffi --grant random.secure --grant time.now \
  --grant fs.read --grant fs.write --grant fs.metadata
```

For strict native coverage, replace `run` with `build`, add `--target native
--require-full-native --out-dir build/session-orm --cache-dir
build/session-orm-cache`, then run `build/session-orm/orbit.session_orm_selftest`.
Tests use a temporary file-backed WAL database and multiple connections to
check competing writes, logout races, cancellation, rotation rollback, custom
column mappings, expiration, and lease cleanup. No archives are built or
published by these checks.
