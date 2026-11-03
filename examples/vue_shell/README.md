# Orbit + Vue: GitHub account preview

Sputnik/Orbit renders a page into an explicitly selected document layout. Vue
mounts inside the account page's `#notebook-app` and displays the session/account.
`./frontend` is the Vite project and the default `orbit-vite` root.

The backend, session management and OAuth integration are Sputnik. Development,
frontend builds and browser testing use Node (22.12+; verified with Node 26).
There are no Python dependencies. Sputnik packages resolve from local source
directories through `dependencies: {name: {path: ...}}`. Run the entry directly:

```sh
../../../sputnik-lang/build/sputnik run backend/main.s
../../../sputnik-lang/build/sputnik build backend/main.s -o build/notebook
../../../sputnik-lang/build/sputnik pkg lock backend/main.s
```

The optional root `sputnik.build.json` contains local package overrides and
external template formats. It lists no application sources or entry. Local
modules are found by imports. With installed packages and no custom settings,
the configuration file is unnecessary. No Sputnik package is downloaded here.

Local `.s`/`.sv` edits invalidate compilation caches without rewriting the
lock. Package identity or dependency graph changes require a lock update.

## Application modules

The application's modules are `main`, `app`, `views` and `layouts`. Their names
belong to this application's build graph; the repository's `examples/vue_shell`
path is not part of their namespace. Application code uses `import views`,
`import layouts` and `from app import application`. Library imports use their
own module names, such as `orbit`, `orbit.session` and `orbit.vite`.

Imports find sibling `.s` files under `backend/` and follow their imports.
The compiler discovers the graph independently of the process working directory.
Package file inventories belong to the packages themselves.

## Response representations

Pages use `respond` from Orbit. Both `/` and `/api/session` offer HTML and JSON;
`/api/session` also offers `application/vnd.orbit.session+json`. Opening the
session URL in a browser renders the Vue account page. API reads send explicit
`Accept: application/json`. Login start and logout offer HTML redirects while
the Vue JSON flow retains authorize_url and logout 204. Unsupported formats
return 406; malformed Accept returns 400. All negotiated responses vary on
Accept and preserve the existing private/no-store session policy.

## Security configuration

The application delegates CSP and origin checks to Orbit:

```sputnik
security = orbit.SecurityPolicy(origin: origin,
  content_security_policy: assets.csp)
```

`Assets.csp` selects development permissions for Vite scripts, styles and HMR,
or production defaults with no development origins. Extend individual source
lists with `assets.csp.with(...)` when the application needs external resources.
`SecurityPolicy(origin:)` checks the validated effective scheme, host and port
before dispatch. The example has no custom origin middleware or hand-built CSP
header. Trusted edge configuration remains explicit under `--behind-proxy`.
Controller session access uses the package's `ControllerSession` mixin; the
session middleware supplies private/no-store headers on session responses.

## Layouts and pages

```text
backend/layouts.s                           layout function declarations
backend/views/layouts/application.html.sv    document/head/header/footer
backend/views.s                             page function declarations
backend/views/account/show.html.sv           account page fragment / Vue mount
backend/app.s                               controller selects page and layout
```

A page view returns `orbit.Html`, which a layout accepts as `content` and renders
at `#{content}`. The layout owns the complete document and shared chrome. The
page owns its page markup and Vue mount point. These are ordinary template
functions; an application can declare any number of layouts in `layouts.s` (or
separate modules) and choose the desired function in each action. The account
action currently selects `layouts.application` explicitly:

```sputnik
content = views.account()
render(html: layouts.application(content,
  title: "Orbit · Account", assets: service(:assets), bootstrap: snapshot()))
```

`render` receives the finished document. A second layout gets its own `.html.sv`
file and declaration; its action calls that layout function around its page.
Layout arguments are explicit, so a plain SSR layout can accept only
`content`/`title`, while a Vue layout also accepts assets and bootstrap data.
The example's layout choice is entirely in application code.

## Public files

Put application files in `./assets`. The application installs
`orbit.assets.StaticFiles()` before session/CSRF middleware; for example,
`assets/favicon.svg` is streamed by Sputnik at `/favicon.svg`. There is no
favicon controller action or embedded SVG source. GET uses scoped file reads
and a fixed-length stream; HEAD returns the same length without reading the
body. Public-file responses do not create session/CSRF cookies.

These files are deployed alongside the backend as part of its release. Vite's
hashed files remain in `frontend/dist/assets` and are served under `/assets/`
by the edge. See [StaticFiles](../../docs/STATIC_FILES.md) for MIME, caching and
path handling.

## Where JavaScript enters the document

`backend/main.s` creates `orbit.vite.Assets`; the app registers it as the
`:assets` service. The controller passes this object into the selected layout.
The layout's `<head>` contains the actual insertion point:

```sputnik-view
<title>#{title}</title>
#{json_script(bootstrap, id: "orbit-bootstrap")}
#{assets.tags(entry: entry)}
```

`entry` defaults to `src/main.ts`. `Assets.tags` returns an `orbit.Html` fragment:

- Development: module scripts for the configured Vite origin's `@vite/client`
  and `/src/main.ts`.
- Production: stylesheet links, a module script for the hashed JS file selected
  by `frontend/dist/.vite/manifest.json`, and applicable modulepreload links.

The browser loads those script URLs. `frontend/src/main.ts` imports the Vue
component and CSS, reads the non-executable `orbit-bootstrap` JSON island, and
calls `createApp(...).mount('#notebook-app')`. The page fragment supplies that
element; the surrounding layout remains owned by Orbit. Production files are
served by the edge; dev files/HMR are served by Vite. The bootstrap contains data,
and the module tags connect the executable frontend.

## GitHub development login

Register a GitHub **OAuth App** with homepage `http://127.0.0.1:3000` and callback
`http://127.0.0.1:3000/auth/github/callback`. Use that exact host throughout.
From this example directory:

```sh
cd frontend
npm ci
cd ..
export GITHUB_CLIENT_ID=your_oauth_app_id
export GITHUB_CLIENT_SECRET=your_oauth_app_secret
node tools/dev.mjs
```

Open `http://127.0.0.1:3000`. The runner starts Vite and the real Sputnik app,
restarts the backend for local `.s`/`.sv` changes (including source packages),
and leaves Vue HMR to Vite. The watched package/template/native inputs come
from the compiler's resolved graph rather than an application-side file list.
Session/CSRF secrets are generated once in private `build/dev-secrets.json`;
explicit `ORBIT_SESSION_SECRET` / `ORBIT_CSRF_SECRET` environment values override
them. Keep secrets out of frontend files and `VITE_*` variables. The runner prints
no credential values. Use `ORBIT_ORIGIN`, `ORBIT_PORT`, `VITE_ORIGIN` for explicit
local configuration and register the matching callback at GitHub.

Login requests only `read:user`; no repository or email permissions are requested.
The CSRF-protected POST creates PKCE/state and returns the authorization URL.
Vue navigates there; the backend exchanges the callback code, loads GitHub's
authenticated profile, resets the session ID/data and stores a bounded public
account snapshot. The token is discarded. UID is a string, including values
above JavaScript's safe integer range. Neither provider tokens, secrets, session
IDs nor pending PKCE state are sent in the HTML/bootstrap or session API.

`GET /api/session` returns the public snapshot; `POST /auth/logout` clears the
browser session and returns `204 No Content`. Session responses are
private/no-store. Cookies are HttpOnly, SameSite=Lax and Secure on HTTPS;
plaintext loopback is explicit development
behavior. Origin/CSRF checks cover login/logout, and callback errors redirect
to a generic error state without echoing provider descriptions.

The first example deliberately uses CookieStore without User/ORM/database.
Logout clears the browser's cookie; a copied older cookie cannot be centrally
revoked. Concurrent OAuth callbacks also have no global one-use state store.
GitHub's PKCE/one-use code protection remains required. A production application
must choose shared revocation/state policy if those guarantees are required.
There are no project resources or project ACL in this account-only example.

## Production build

```sh
cd frontend
npm run build
cd ..
../../../sputnik-lang/build/sputnik build backend/main.s -o build/native/main \
  --target native --require-full-native \
  --grant net.listen --grant net.connect --grant random.secure --grant time.now \
  --grant fs.read --grant fs.metadata
```

Run `build/native/main --behind-proxy` **from this
application directory**, with `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`,
`ORBIT_SESSION_SECRET`, `ORBIT_CSRF_SECRET` (independent persistent values of at
least 32 bytes), and `ORBIT_ORIGIN=https://your-host` in the environment. Register
the exact HTTPS callback. The normal production entry does not allow fixture
endpoints or plaintext callbacks. The backend binds loopback; `--behind-proxy`
trusts one forwarding hop from loopback only. Adapt the supplied
[Nginx configuration](nginx.conf.example) in the existing TLS edge.

The edge serves hashed `frontend/dist/assets/` files and proxies pages/API to
Orbit. Deploy binary, dist and manifest as one immutable release. Stop Vite for
production verification; Node is not part of the production HTTP backend.

## Offline verification

The **test-only** `backend/fixture.s` selects a separate GitHub HTTP fixture,
implemented in `test/github_fixture.s` on Sputnik. It validates PKCE and consumes
authorization codes once, then returns a synthetic account with a large UID.
The normal application entry has no switch to select this fixture. Node only
orchestrates processes and provides a small static/reverse-proxy test edge.

```sh
cd frontend
npm run build
PLAYWRIGHT_BROWSERS_PATH=../../../build/playwright-browsers npx playwright install chromium
PLAYWRIGHT_BROWSERS_PATH=../../../build/playwright-browsers npm run test:browser
ORBIT_E2E_MODE=development PLAYWRIGHT_BROWSERS_PATH=../../../build/playwright-browsers npm run test:browser
```

Tests cover login/consent, UID precision, private bootstrap/API data, session
rotation/CSRF refresh, reload, refresh, logout, denied login, invalid callback,
CSRF/origin failures, missing assets and browser/CSP errors. Dev and production
use separate local test ports (4318/4317).

To check the same flow with a strict full-native application backend, from here:

```sh
../../../sputnik-lang/build/sputnik build backend/fixture.s -o build/fixture-native/fixture \
  --target native --require-full-native \
  --grant net.listen --grant net.connect --grant random.secure --grant time.now \
  --grant fs.read --grant fs.metadata
cd frontend
ORBIT_E2E_NATIVE=1 PLAYWRIGHT_BROWSERS_PATH=../../../build/playwright-browsers npm run test:browser
```

Manual offline preview from this directory:
`node tools/smoke_server.mjs --mode production --port 3010 --native-backend`.
The intermediary consent page explicitly identifies itself as a local fixture.
Automated checks use that fixture; real GitHub authorization additionally needs
the configured OAuth App credentials and a user consent run.
