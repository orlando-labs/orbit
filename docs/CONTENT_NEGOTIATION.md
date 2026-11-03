# Content negotiation with `respond`

Import the Orbit macro into a controller module:

```sputnik
import orbit
from orbit import respond

class Accounts < orbit.Controller:
  def current():
    data = snapshot()
    respond:
      html: account_page(data)
      json: data
      text: data[:login]
      format("text/csv"): account_csv(data)
      format("application/vnd.example.account+json", encode: :json): data
```

`respond` is an expression. It gathers the offered formats, negotiates against
all `Accept` header field lines, and executes exactly one branch. Branch bodies
keep their lexical controller and caller bindings. Descriptor expressions are
evaluated once before negotiation; unselected branch bodies do not run.
Work shared between representations belongs before `respond`.

This is an Orbit macro over ordinary Sputnik blocks. Labels are scoped to the
macro body; no `html`, `json`, `text` or `format` methods are installed on the
controller. Standard branches take no arguments. Each branch needs a nonempty
block without parameters. Invalid branch shapes produce `ORBIT_RESPOND_*`
macro diagnostics. The outer body contains only representation declarations.

## Representations

| Branch | Response Content-Type | Branch value |
| --- | --- | --- |
| `html` | `text/html; charset=utf-8` | `orbit.Html` |
| `json` | `application/json; charset=utf-8` | JSON-compatible data, including `null` and `false` |
| `text` | `text/plain; charset=utf-8` | `Str` |
| `format(mime)` | declared MIME | ready `Str` or `Bytes` body |
| `format(mime, encode: :json)` | declared MIME | JSON-compatible data |

Custom MIME strings require no registry. `encode:` accepts `:body` (the default),
`:html`, `:json` and `:text`. The MIME and encoder are independent: a `+json`
suffix does not implicitly serialize a Map. Type/subtype and parameter names are
case-insensitive; charset values are normalized, other parameter values retain
their case. MIME parameters can be quoted and contain escaped separators.
Offered wildcards, quality parameters, duplicate parameters and invalid MIME
values are configuration errors (`ArgumentError`).

A reusable `Format(mime, encode: :body)` descriptor can be passed to `format`:

```sputnik
vendor = orbit.Format("application/vnd.example.account+json", encode: :json)
respond:
  html: account_page(data)
  format(vendor): data
```

Descriptors expose read-only `mime`, `type`, `subtype`, `params`, `encoder` and
canonical `identity`. Their parameter map is frozen. Supplying `encode:` to
`format(descriptor, ...)` explicitly overrides its encoder. Equivalent duplicate
MIME offers are rejected even when their spelling or parameter order differs.

Any branch can return a `Response` or `StreamingResponse`. It keeps its status,
headers and body/producer. A missing Content-Type is filled from the selected
format, except for bodyless statuses and empty redirects. A supplied
Content-Type must agree with the selected type and its parameters. `render`,
`redirect` and `stream` remain available inside branches:

```sputnik
def logout():
  session.destroy
  respond:
    html: redirect("/", status: 303)
    json: render(status: :no_content)
```

Controller status/header settings apply to encoded payloads. Ready responses
retain their explicit status. The response is committed once; subsequent
rendering/header mutations retain the normal controller errors. Stream
producers stay deferred until transport consumption.

## Selection and errors

Selection follows HTTP media ranges: `q` weights, exact types, `type/*`, `*/*`,
and matching MIME parameters. The most specific matching range determines an
offer's weight, including a specific `q=0` exclusion. Choose the highest
positive weight. Equal weights use declaration order, with `default:` as an
optional server preference. An absent Accept means no preference; an empty
Accept offers no acceptable types. Unsupported types are not silently converted.

```sputnik
respond(default: :json):
  html: account_page(data)
  json: data
```

`default:` accepts `:html`, `:json`, `:text`, a MIME string, or an offered Format
descriptor. A string matches the type and supplied parameters; a descriptor
matches its canonical identity. The default must be offered. It never overrides
a client's higher preference or a `q=0` exclusion.

No acceptable representation returns **406 Not Acceptable**, without executing
any branch. Malformed Accept returns **400 Bad Request**. Quality values use
integer thousandths (0–1, at most three decimal digits); malformed values and
duplicate parameters are rejected. Parsing is bounded to 8192 bytes and 128
ranges. A response can offer at most 64 representations.

All negotiated responses, including 400/406, contain `Vary: Accept`. Existing
Vary tokens from both controller and returned response are merged and
deduplicated case-insensitively; `Vary: *` remains `*`.

`Request#negotiate(formats, default: null)` exposes the same selection mechanism
to bare handlers and adapters. It accepts Format descriptors and returns the
selected original descriptor or `null`. Malformed Accept raises the public
`InvalidAcceptError`; invalid offers/defaults raise `ArgumentError`.
This lower-level method does not render or add headers.

Frontend requests expecting JSON must send `Accept: application/json`. Neither
`fetch`, a URL suffix nor a query parameter implicitly changes the format.

## Verification

`node test/respond_test.mjs --native` runs the Sputnik VM/native semantics suite,
macro diagnostics and expression-scope checks. Native coverage must be complete,
with zero fallback and no VM runtime bridge. The Vue shell browser suite checks
HTML/JSON/vendor MIME on one URL, 400/406, HTML redirects and JSON logout 204 in
production VM, Vite development and production full-native modes.

HTTP selection follows [RFC 9110 §12.5.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-12.5.1);
cache variance follows [§12.5.5](https://www.rfc-editor.org/rfc/rfc9110.html#section-12.5.5).
