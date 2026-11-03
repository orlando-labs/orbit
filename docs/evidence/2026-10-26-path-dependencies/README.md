# Source entries and path dependencies — 2026-10-26

Uncommitted development snapshot. No package release or remote deployment.

- SDK build, build/package/package-store unit tests passed.
- Path integration passed in VM and strict full-native: no-manifest local imports,
  transitive macros, installed imports without dependencies, source-entry settings,
  transitive relative path dependencies, live macro/template edits, stable graph
  lock, lock-only resolution, conflicting identities and rejected distributable paths.
- Additional VM cases passed: anonymous scripts with optional settings and
  ambiguous configuration formats. Unreachable invalid source files are ignored.
- All five remaining Orbit example manifests built from entry + dependencies,
  with no application/library source inventories.
- Vue production VM, development VM and production native: 3 browser tests each.
  Covers local GitHub fixture login, account/session, refresh/logout 204,
  CSRF/errors and streamed asset GET/HEAD. Real GitHub.com was not exercised.
- Vue strict native source build: 1160/1160 native, no bytecode fallback/bridge.
- ORM/SQLite strict native: 1909/1909 native, executable returned true.
- Optional protocol regression (including metrics/set_integration_pool) built
  strict native and returned native-open-protocol-ok.

The Vue settings file contains only local path dependencies and source formats.
Run/build/pkg lock use backend/main.s; imports discover layouts/views/app.
The fixture entry is backend/fixture.s, and the provider entry is test/github_fixture.s.
Development reload reads compiler inputs.json, including package and .sv sources.
