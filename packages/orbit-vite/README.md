# orbit-vite

Vite assets for Orbit HTML views. Vue is an application dependency; this package
only depends on Orbit. The default frontend directory is `./frontend`, relative
to the application working directory.

```sputnik
from orbit.vite import Assets
from orbit.html import json_script
from orbit import SecurityPolicy

# Select the mode explicitly; never infer it from request headers.
assets = Assets(mode: :development, dev_origin: "http://127.0.0.1:5173")
# Production default: frontend/dist/.vite/manifest.json
assets = Assets()
security = SecurityPolicy(origin: "https://app.example.test",
  content_security_policy: assets.csp)
fragment = assets.tags()
# Pass both Html fragments to an ordinary view function.
bootstrap = json_script({schema: "app.v1", account: null}, id: "app-bootstrap")
```

`Assets` options:

| Option | Default | Meaning |
| --- | --- | --- |
| `mode` | `:production` | `:development` or `:production`. |
| `frontend` | `"./frontend"` | Application frontend directory. |
| `entries` | `["src/main.ts"]` | One to 32 configured manifest entry names. |
| `dev_origin` | `"http://127.0.0.1:5173"` | Trusted HTTP(S) origin; no path, credentials, query or fragment. |
| `hmr_origin` | `null` | Optional explicit WS(S) origin in development; defaults to the WS(S) equivalent of `dev_origin`. |
| `asset_base` | `"/"` | Same-origin URL prefix ending in `/`. |
| `dist` | `"dist"` | Relative build directory below frontend. |
| `manifest` | `".vite/manifest.json"` | Relative path below dist. |
| `max_manifest_bytes` | `1048576` | Startup manifest read limit; maximum 4 MiB. |
| `max_chunks` | `4096` | Manifest entry limit; maximum 16384. |

`csp` returns an immutable `orbit.ContentSecurityPolicy`, ready for
`SecurityPolicy(content_security_policy: assets.csp)`. Development automatically
allows the configured asset server for scripts/connections, the HMR endpoint
for connections, and inline styles for Vite CSS updates. Script inline/eval
permissions are not enabled. Production uses a same-origin policy and excludes
development origins and permissions. Both modes keep form actions on `'self'`.
No policy values are taken from requests.

Use `assets.csp.with(img_src: [:self, "https://images.example.test"])` for explicit
application extensions. `with` replaces the supplied directive's whole source
list and preserves all other directives. For a separate HMR endpoint, configure
both Vite's WebSocket endpoint and `hmr_origin` to the same origin; this option
describes the browser connection for CSP and does not reconfigure Vite itself.

`tags(entry: null, nonce: null, preload: true) -> orbit.Html` emits the default
entry or another configured entry. Dev emits `@vite/client` and the source
entry; no manifest/filesystem access is performed. Production emits entry CSS,
recursively imported CSS, the module script (or a CSS entry), and optional JS
modulepreloads. Manifest order is retained, CSS/preloads are deduplicated,
cycles terminate through a visited set, and dynamic imports remain lazy.
Imports are bounded to 128 levels. A nonce is applied to generated tags when
supplied; it must be a bounded CSP nonce string.

Production validates all referenced files and static/dynamic chunk references
at startup, including unused chunks. Absolute, parent, dot, encoded, control,
query and fragment paths are rejected, as are symlinks in directory/file
components. Duplicate JSON keys, missing/non-entry configured entries, malformed
lists, missing files and unknown imports fail startup. Configuration errors use
`ArgumentError`, manifest/path errors use `ManifestError`; filesystem/capability
and read-limit errors retain their SDK types. Use a physical, immutable release
directory and install its assets/manifest/backend together. `tags` does no
filesystem IO on requests. Recreate `Assets` to load a new release.

The package generates HTML; production `/assets/` delivery belongs to the trusted
edge/static server. It must provide proper MIME types, immutable caching for
hashed assets and actual 404 responses. Development requires matching Vite
CORS/origin/HMR configuration. See the complete
[Vue/GitHub example](../../examples/vue_shell/README.md).

In a document layout, call `#{assets.tags(entry: entry)}` inside `<head>`.
The action passes the `Assets` service explicitly to that layout. Render the
page's `Html` fragment separately at `#{content}` in the layout body; page/layout
selection uses ordinary function calls. The Vue example separates these files
under `backend/views/account/` and `backend/views/layouts/`.

`orbit.html.json_script(data, id:, nonce: null)` creates a non-executable JSON
island, escaping `<`, `>`, `&` and Unicode line separators plus HTML attributes.
Read it using DOM `textContent` and `JSON.parse`. Application wire schemas should
use strings for IDs/integers outside JavaScript's safe integer range; the helper
does not silently change JSON numeric types. Keep credentials and session bearer
material out of this public data.

Local VM and strict full-native checks, using Node already required by Vite:

```sh
node test/vite_test.mjs --native   # from the Orbit repository
```

These cover asset ordering, cycles, lazy chunks, nonce/attribute escaping,
malformed/oversized manifests, filesystem escapes/symlinks and hostile JSON
round trips. No Python or database dependency is added. Source packages remain
local; `.sputnikpkg` publication is deferred.

Manifest behavior follows [Vite backend integration](https://vite.dev/guide/backend-integration).
