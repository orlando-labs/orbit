# orbit-session

Request-scoped sessions for Orbit, independent of application models and storage
drivers. The package provides `CookieStore`, `MemoryStore`, session middleware,
and controller helpers. Model-backed storage lives in
[`orbit-session-orm`](../orbit-session-orm/README.md).

```sputnik
import orbit
import orbit.session as sessions

class Pages < sessions.Controller:
  def visit():
    session[:visits] = (session[:visits] or 0) + 1
    render(json: {visits: session[:visits]})

routes = orbit.routes:
  post "/visit", to: &Pages#visit

# Supply the same persistent secret, at least 32 bytes, to every instance.
def application(secret):
  orbit.App(routes: routes, middleware: [sessions.Middleware(
    store: sessions.CookieStore(), secret: secret)])
```

The default cookie is `orbit-session`, `Secure`, `HttpOnly`, `SameSite=Lax`,
`Path=/`, with no Domain. HTTPS is required; Orbit's validated proxy policy
determines whether a request is secure. For local plaintext development, pass
`secure: false` explicitly. `__Host-` names and `SameSite=None` follow the same
policy validation as `orbit.security.SetCookie`.

`sessions.Controller` includes `ControllerSession`. An existing base controller
can instead `include sessions.ControllerSession`. Function handlers use
`sessions.current(request)` or `request.service(:session)`. A custom middleware
`service:` name is available through `sessions.current(request, name: ...)`;
the controller helper uses `:session`.

## Session operations

| Operation | Behavior |
| --- | --- |
| `session[key]`, `include?`, `to_map` | Lazy read; missing keys return Null. `to_map` returns a deep copy. |
| `session[key] = value`, `delete`, `clear` | Change data; nested array/map mutations obtained through `[]` are tracked too. |
| `session.id` | Return the random 256-bit ID; allocate and persist a new anonymous session if needed. |
| `loaded?`, `new?`, `changed?` | Inspect lifecycle/change state; `new?` and `changed?` load the session. |
| `touch` | Renew the idle lifetime, bounded by the absolute lifetime. |
| `regenerate` | Rotate the ID while preserving data and absolute lifetime. |
| `reset` | Rotate the ID, clear data, and start a new absolute lifetime. |
| `destroy` | Clear the browser cookie and revoke the presented ID in a server store. Further writes/renewal fail. |

Untouched requests do not load storage. Anonymous reads allocate no cookie;
unchanged reads perform no store write or cookie renewal. Changes are saved once
after the handler returns. Exceptions, cancellation, and responses with status
500 or higher discard changes. Ordinary redirects and other statuses save
changes. Session-dependent responses carry `Cache-Control: private, no-store`
and `Vary: Cookie`.

The session belongs to the active request task. Child tasks and streaming
producers cannot access it. Capture `session.to_map` or the needed values in the
action before returning a streaming response. Persistence finishes before body
production, so a later transport/producer failure cannot undo a completed save.
Application database changes and session saves are separate transaction boundaries.

Values must be JSON data: Null, Bool, Int, finite Float, Str, arrays, and maps
with string/symbol keys. Keys normalize to strings; ambiguous StrictMap keys
are rejected. Arbitrary objects, bytes, cycles, and nesting beyond 32 levels
are rejected. Assignments copy their input, and storage receives isolated
snapshots.

## Store selection

| Store | Persistence and concurrency |
| --- | --- |
| `CookieStore()` | The entire session is encrypted/authenticated in the cookie; no database or server-side session state. |
| `MemoryStore(max_entries: 10000)` | Volatile, process-local entries; mutex-protected compare-and-swap, rotation, and revocation. |
| `orbit.session.orm.ORMStore(model)` | Shared model-backed entries; atomic revision checks, rotation, and revocation through ORM adapters. |

Cookies use Orbit's existing ChaCha20-Poly1305 `SessionCodec`. Encryption keys
are derived for the store kind, cookie name, Path, and Domain. Previous keys
can be accepted with `old_secrets: [...]` (at most eight); mutation or `touch`
reissues using the active key. Stable keys are required across restarts.

**CookieStore cannot revoke an already copied cookie or reject concurrent
updates to old snapshots.** Logout clears the browser's cookie; an old copy
remains valid until expiry. Parallel cookie writes use the last cookie retained
by the browser. Choose a server store when revocation or compare-and-swap is
required. MemoryStore is suitable only when requests share one process; it
does not synchronize replicas or survive restart.

Server stores reject stale updates with `SessionConflictError`; middleware
returns `409` without a new cookie. It does not replay handlers. Clients should
refresh state before deciding whether to repeat an operation. Storage failures
return `503` without replacing the session cookie. A missing/expired entry or
invalid token becomes an anonymous session with a fresh ID; the old cookie is
cleared unless a new session is saved. Malformed/duplicate Cookie headers
return `400`.

Default idle TTL is 3600 seconds; absolute TTL is 86400 seconds from creation.
Neither extends on read. `ttl:` and `absolute_ttl:` take positive integer
seconds; absolute TTL must cover idle TTL. Expiry is checked on every load and
save. `MemoryStore.prune(now: unix_seconds)` removes expired entries; capacity
cleanup also runs before inserting into a full store. Capacity exhaustion
returns `503` rather than evicting a live session.

`max_data_bytes:` defaults to 65536 (maximum 1048576). `max_cookie_bytes:`
defaults to 4096 and bounds the complete Set-Cookie value, including flags.
CookieStore therefore supports substantially less than 4096 bytes of session
data because metadata, encryption, and encoding share that budget. Server
cookies contain only an encrypted ID. All serialization/size checks happen
before committing to a store; overflow raises `SessionOverflowError` and the
request becomes `500`. Incoming Cookie headers default to an 8192-byte limit.
The middleware owns its cookie name; handlers must not set it themselves.

## CSRF integration

Use the session ID rather than the encrypted cookie text as the CSRF identity:

```sputnik
from orbit.security import CsrfMiddleware

def browser_middleware(session_secret, csrf_secret):
  [sessions.Middleware(store: sessions.CookieStore(), secret: session_secret),
    CsrfMiddleware(secret: csrf_secret, session_service: :session)]
```

Order matters: sessions wrap CSRF. A safe request creates a session and CSRF
cookie when needed; unsafe requests must pass Orbit's origin and double-submit
checks. Cookie data changes keep the same CSRF identity, while ID rotation
refreshes the CSRF token. Vue reads `orbit-csrf` and echoes it as `X-CSRF-Token`.
Authentication, OAuth results, User lookup, and authorization remain application
layers; applications can store their own stable account identifier here.

## Custom stores

Implement the following methods without inheriting from a package class:

```sputnik
kind()                            # stable string for encryption-key separation
load(payload, now:)               # Entry or Null
dump(entry)                       # JSON payload placed in the encrypted cookie
commit(previous, entry, now:)     # previous is Null for creation
destroy(previous, now:)           # idempotent revocation; previous may be Null
```

`Entry(id, revision, data, created_at, updated_at, expires_at)` is the shared
snapshot value. Reference stores can dump `{id: entry.id}` and use
`reference_id` from `orbit.session._state` to validate it. Core helpers in that
internal module are used by the ORM companion and may evolve together with it.

A server store must atomically verify that the previous ID exists, is unexpired,
and has the expected revision before update. Rotation must check that the new ID
is absent and delete/create in the same boundary. New IDs start at revision 1;
same-ID updates increment by one. Deletion must revoke the current entry for
that ID even if the supplied snapshot is stale. A stale writer must never
recreate a deleted/rotated ID. Return independent snapshots and raise
`SessionConflictError` for a failed revision check or `SessionStoreError` for
backend failures. Cleanup is an optional store-specific maintenance method.

## Local development

The working packages are not published. From the Orbit checkout, tests resolve
local sources through the build graph, with no registry downloads:

```sh
../sputnik-lang/build/sputnik run test/session_selftest.build.yaml \
  --grant random.secure --grant time.now
```

For strict native coverage, replace `run` with `build`, add `--target native
--require-full-native --out-dir build/session --cache-dir build/session-cache`,
then run `build/session/orbit.session_selftest`. The local SDK supports the
encoder's BigInt arithmetic and ByteBuffer operations directly. Tests include
the RFC 8439 ChaCha20-Poly1305 vector in addition to session lifecycle checks.
A real application should copy the source-module entries from this manifest
into its local development graph.
