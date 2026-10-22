# Security policy

## Supported versions

Until Orbit 1.0 is released, only the latest release candidate receives
security fixes. After 1.0, the support window in
[the compatibility policy](docs/COMPATIBILITY.md) applies.

| Release | Security support |
|---|---|
| `1.0.0-rc.x` | Latest RC only |
| Unversioned previews | No |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub private
vulnerability reporting for the Orbit repository. If that route is
unavailable, contact `security@orlando-labs.com` with:

- affected version and platform;
- minimal reproduction or request bytes;
- expected and observed impact;
- whether the issue is already being exploited or disclosed elsewhere;
- a safe way to contact the reporter.

Maintainers acknowledge a report within three business days, provide an
initial severity assessment within seven business days, and coordinate a fix,
advisory, CVE where appropriate, and disclosure date. Please allow 90 days for
coordinated disclosure unless exploitation or ecosystem risk requires a
different timeline.

The implementation threat model and security primitives are documented in
[docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) and
[docs/SECURITY.md](docs/SECURITY.md). Authentication, authorization, secret
management, uploaded-file policy, and edge TLS configuration remain
application/deployment responsibilities.
