# Vue account shell verification

The account preview uses `./frontend`, an external `.html.sv` view, CookieStore
and the existing GitHub OAuth provider. Both the application and the offline
GitHub HTTP fixture are Sputnik. Frontend/build/test orchestration is Node;
no Python dependency is added.

- `summary.json`: check results and working-source hashes.
- `assets-vm-native.log`, `assets-native-build.json`: manifest/asset/JSON tests
  in VM and strict full-native, with no fallback/bridge.
- `browser-development.log`, `browser-production.log`, `browser-native.log`:
  two browser tests in each configuration. Coverage includes login, session/CSRF
  rotation, reload, logout, a separate anonymous browser context, large string
  UID, denied/invalid callbacks, CSRF/origin failures, missing assets and CSP.
- `backend-native-build.json`: strict native backend graph, VM independent.
- `frontend-build.log`: pinned Vue/Vite production build and Vue type checking.
- `vue-account.png`: synthetic account displayed after the fixture flow.

Run commands are in `examples/vue_shell/README.md` and
`packages/orbit-vite/README.md`. Real github.com consent was not exercised:
it requires a configured OAuth App and its credentials. The fixture entry point
is separate from the normal application and does not create a real GitHub account.

The related language correction replaces the erroneous `@template` special
case with sigil-less `template` annotation syntax. `@template` remains an instance
variable. Parser regression tests cover ivar/local/module bindings and imports;
VS Code/Vim/notebook highlighting and the external-template VM fixture pass.
