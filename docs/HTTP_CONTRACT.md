# Ember 1.0 HTTP contract

Status: normative 1.0 target, accepted 2026-07-19 by
[ADR-0001](adr/0001-ember-1-0-contract.md).

The key words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** have their usual
RFC meaning. This document defines Ember behavior at both `App#call` and the
network adapter. Where the preview implementation differs, this document wins
and the gap must be closed before 1.0.

## Request target and route identity

- Routing uses the decoded path only. The query string never participates in
  route selection.
- `/resource` and `/resource/` are different paths. Ember does not add or
  remove a trailing slash and does not generate an implicit redirect.
- The root path is `/`. Empty paths, non-origin-form paths at `App#call`,
  malformed percent encoding, paths over 8192 bytes, more than 128 segments,
  and decoded segments over 2048 bytes are rejected as `400 Bad Request`.
- Matching precedence is literal segment, parameter segment, then terminal
  wildcard. Declaration order does not change the winner.
- A scope or mount joins path boundaries once. A child `/` denotes the scope
  root without adding a slash: `scope "/api"` plus `get "/"` is `/api`. Use a
  prefix ending in `/` when `/api/` is intentionally the route identity.
- Reverse routing generates the same trailing-slash identity declared by the
  route. It percent-encodes each segment and never generates a canonicalization
  redirect.

## Method selection

Ember route declarations support `GET`, `QUERY`, `POST`, `PUT`, `PATCH`,
`DELETE`, `HEAD`, and `OPTIONS`. `QUERY` follows
[RFC 10008](https://www.rfc-editor.org/rfc/rfc10008.html); an Ember `QUERY`
request without `Content-Type` is rejected with `400 Bad Request` before its
handler runs.

Selection for an otherwise valid path is deterministic:

1. An exact method route wins.
2. By default, `HEAD` falls back to the selected `GET` route when there is no
   exact `HEAD` route. `App(head_fallback: false)` opts out.
3. By default, an unmatched `OPTIONS` request receives an automatic `204`.
   An explicit `OPTIONS` route wins. `App(automatic_options: false)` opts out.
4. A path with no candidate route returns `404`. A candidate path with no
   selected method returns `405`.

Every automatic `OPTIONS` and `405` response has a deterministic, sorted
`Allow` value. It includes `HEAD` when `GET` fallback is enabled and includes
`OPTIONS` when automatic `OPTIONS` is enabled.

## HEAD

`HEAD` has the semantics of `GET` without response content, as required by
[RFC 9110 section 9.3.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.3.2).

- An explicit `HEAD` route is selected before a `GET` fallback.
- The chosen handler and middleware chain run once with `request.method ==
  "HEAD"`. Application code MUST keep `GET`/`HEAD` handlers safe and must not
  depend on consuming a HEAD request body.
- `App#call` returns an empty body for every HEAD response, including errors.
- A buffered fallback preserves the headers and status that the GET route
  selected. The adapter computes `Content-Length` from the hypothetical GET
  content when it is known.
- A streaming producer is not started for HEAD. Headers that require producing
  stream content, including a computed length and late trailers, are omitted.
- The adapter never sends content or trailers and never adds
  `Transfer-Encoding` to a HEAD response.

These rules favor predictable metadata without running an unbounded producer
only to discard its output.

## Application return values

The normalized return-value contract is:

| Handler value | Result before method/status content rules |
|---|---|
| `Response` or `StreamingResponse` | used as the selected response |
| `Html` | `200`, `text/html; charset=utf-8` |
| `Str` | `200`, `text/plain; charset=utf-8` |
| `Bytes` | `200`, `application/octet-stream` |
| `null` | `204` with no content |
| any other value | `InvalidResponseError`, converted by `App` to safe `500` |

An empty `Str` or zero-length `Bytes` is still a `200` representation. Only
`null` selects `204` implicitly. `render` always uses its explicit/default
status and does not infer a status from body length.

Integer status codes are limited to `100..599`. Known symbols are conveniences,
not a closed set of HTTP status codes.

## Status and content rules

Ember applies these rules after the handler and middleware chain and before a
response reaches either `App#call` or the network adapter:

| Response | Application content | Framing and metadata |
|---|---|---|
| final `1xx` | forbidden | `1xx` is transport-only; returning it as the final application response is invalid |
| `204` | forbidden | no trailers, `Content-Length`, or `Transfer-Encoding` |
| `205` | forbidden | no trailers or `Transfer-Encoding`; the adapter may emit `Content-Length: 0` |
| `304` | forbidden | no trailers or `Transfer-Encoding`; only representation metadata allowed by RFC 9110 is retained |
| response to `HEAD` | always suppressed | follows the HEAD rules above |
| all other supported final statuses | allowed | normal buffered or streaming framing |

`1xx`, `204`, and `304` are header-terminated responses under
[RFC 9110 sections 15.2, 15.3.5, and 15.4.5](https://www.rfc-editor.org/rfc/rfc9110.html#section-15).
Ember additionally treats `205` as contentless per RFC 9110 section 15.3.6.

Supplying content, a stream, or trailers for a contentless status is a
programmer error. Ember raises `InvalidResponseError` before commit; the
top-level `App` error policy turns an uncaught instance into a safe `500`.
Silently changing the developer-selected status is not allowed.

## Framing fields

- `Transfer-Encoding` and `Trailer` are framework-owned. Streaming code
  declares trailer names through `stream(trailers: ...)` and does not set these
  fields directly.
- An application-supplied `Content-Length` on a buffered response MUST equal
  the exact body byte count. A mismatch is an invalid response.
- `Content-Length` on HEAD is permitted only when it describes the selected
  GET representation. On `304`, it is permitted only when it equals the size
  of the selected `200` representation. If Ember cannot prove the value, it
  omits the field.
- The adapter, not application middleware, makes the final framing decision.
  Conflicting `Content-Length`/`Transfer-Encoding` combinations never reach the
  wire.

## Error boundary

Malformed path/route captures and request-parameter parse failures become safe
`400` responses. Unsupported parameter media types become `415`. Missing routes
become `404`; method mismatches become `405`; uncaught ordinary application
errors become `500`. Production responses do not expose exception messages.

Cancellation, client disconnect, shutdown, process-fatal failures, and runtime
isolation/policy errors are control flow, not application failures. They MUST
propagate to the server lifecycle and MUST NOT be converted to `500`. The
`on_error` hook observes reportable failures without changing this
classification.

## Testable invariants

The in-memory and socket adapters must agree on status, method selection,
headers (apart from hop-by-hop framing), and visible body. Stage 0 routing is
covered by `test/contract_selftest.s`; stage 1 application invariants by
`test/stage1_selftest.s`; and stage 2 status/framing/lifecycle conformance by
`test/stage2_selftest.s` plus the Sputnik runtime HTTP regression suite. These
remain mandatory gates in
[the production-readiness definition](PRODUCTION_READINESS.md).
