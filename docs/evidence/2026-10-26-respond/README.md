# Orbit respond — 2026-10-26

Uncommitted development snapshot. No package publication or remote deployment.

- Sputnik parser tests passed for adjacent bare inline blocks, map payloads and
  source expression position. The source/path dependency regression passed.
- Respond VM/native semantics cover weighted Accept, specific q=0 exclusions,
  wildcards, repeated field lines, quoted parameters, defaults, malformed/bounded
  headers, JSON null/false, vendor JSON, raw binary, lazy branch selection,
  explicit responses, 204/redirects, controller headers/status, merged Vary,
  streaming response preservation and double-render errors.
- DSL shape diagnostics and caller expression bindings passed.
- Respond selftest: 809/809 native code objects, no fallback or bridge.
- Vue fixture and normal production main: 1214/1214 native, VM independent.
- Vue frontend type check/production build passed.
- Four browser tests passed in each mode: production VM, Vite development VM,
  production full-native. They cover one-URL HTML/JSON/vendor MIME, 400/406,
  HTML login/logout redirects, JSON session and logout 204, CSRF and assets.
- Stage-3 security/HTML checks passed with respond checks integrated.
- Public API export inventory and API reference agree; new documentation links
  exist, spec/cheat-sheet website copies are synchronized, git diff checks pass.

Browser OAuth uses the local Sputnik GitHub fixture. Real GitHub.com was not
exercised. Published package locks and package versions were not refreshed.
