# Public application files

```sputnik
from orbit.assets import StaticFiles

app = orbit.App(routes: routes, middleware: [StaticFiles()])
```

The default root is `./assets`, relative to the application working directory.
For example, `assets/favicon.svg` is served at `/favicon.svg`; no controller
action or source string is needed. To mount elsewhere, use
`StaticFiles(root: "./assets", at: "/static")` and request `/static/favicon.svg`.
Place the middleware before session/CSRF processing so public files do not
allocate sessions or set cookies. Orbit still validates request provenance and
applies its response security headers.

Only GET and HEAD are handled. A matching regular file becomes a fixed-length
`orbit.StreamingResponse`: the producer opens it with scoped `fs.File.open`,
reads with `each_chunk`, and writes each chunk to the HTTP body before reading
the next one. No complete-file buffer is built. The default chunk size is
64 KiB, configurable from one byte to 1 MiB. Scoped file cleanup runs on normal
completion, callback errors and transport cancellation. HEAD returns the same
Content-Length without starting the file producer or opening a file handle.

Common SVG/image, stylesheet, JavaScript, JSON, text, font and PDF extensions
receive MIME types; unknown extensions use `application/octet-stream`.
`cache_control` defaults to `public, max-age=3600`, suitable for unhashed public
files rather than an immutable hashed-asset policy. Conditional requests,
ETags and byte ranges are not implemented in this initial helper.

Paths are decoded once, bounded and checked by component. Dot-prefixed names,
dot/parent components, decoded separators, drive separators, nested percent
encoding and control characters are not served. Symlinks are rejected in the
configured root and descendants; directory listings are never generated.
Missing files and paths unsuitable for static delivery fall through to the
application, which retains its normal route and URL-error behavior.

The public directory belongs to the trusted application release. It must not
contain credentials, source files or private uploads; path checks are not an
atomic filesystem sandbox for a tree concurrently writable by an attacker.
Files remain unchanged while their responses are produced, so metadata length
and streamed bytes describe the same release file. The HTTP layer rejects
short or overlong transfers if that contract is violated.

Consumers grant `fs.read` and `fs.metadata` explicitly. No Python, Node or
external web server is required for this delivery path. A trusted production
edge can still serve Vite's hashed `frontend/dist/assets` directly; the example
keeps those under `/assets/`, independently of Orbit's application assets.

Verification uses `node test/assets_test.mjs --native` for fixture creation and
Sputnik VM/direct-native HTTP checks. The file handler itself is Sputnik.
