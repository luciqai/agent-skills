# Network — all platforms

Read `references/metrics/preamble.md` first for units, aggregation rules, and the aggregates-not-records
model. Then read the platform file: `references/metrics/network/<platform>.md`.

> **Verified against:** Android SDK 19.2.0 · iOS SDK 16.x · React Native 16.0.4 · Flutter 16.0.4
> (`instabug_http_client` 2.7.1 / `instabug_dio_interceptor` 2.6.1). Read the app's SDK version from the
> project before relying on the limitations below — measurement anchors change rarely, stated
> limitations change often, and **a limitation that has since been fixed will make you discount valid
> data.**

On React Native or Flutter, read the wrapper file **and** the native platform file it names. Unlike
launch, the wrapper does its own timing here — the duration is taken on the JS thread or Dart isolate,
not by the native SDK — so the wrapper file governs the number and the native file governs the account
gating and the privacy model.

## Coverage is not automatic on every platform

Check this before concluding anything from missing requests.

| Platform | Automatic in code? | Required setup |
|---|---|---|
| **iOS** | Yes | None in code — but capture is account-gated, see below |
| **React Native** | Yes | None — the SDK patches `XMLHttpRequest`, covering `fetch` and axios |
| **Android** | **No** | The Luciq Gradle plugin **and** `networkInterception { enabled = true }` — the flag defaults to **false**. gRPC needs its own build flag, also defaulting to false |
| **Flutter** | **No** | Install `instabug_http_client` or `instabug_dio_interceptor` **and** change every call site to use them |

**A total absence of network data almost always means setup, not a performance problem.** Read the
platform file's coverage section before investigating anything else.

Capture is also gated **per account**, independently of anything in the codebase, and **the defaults
differ by platform**:

| Capability | iOS default | Android default |
|---|---|---|
| Network capture | off | off |
| gRPC | off | off |
| Masking | off | off |
| Distributed tracing | off | off |
| **GraphQL operation names** | **on** | **off** |
| **Stage breakdown** | **on** | **off** |

So a capability can be missing with correct code, and **the same account configuration produces
different coverage on the two platforms** — expect stages and GraphQL grouping on iOS where Android has
neither. Do not carry an assumption from one platform to the other.

Disabling a capability **removes already-stored data** for it — a full delete for network capture and
gRPC, a field clear for operation names and tracing. When the code is right and the data still isn't
there, that is the layer to check, and it is not fixable in the app.

## What the MCP returns for network

| Source | What you get |
|---|---|
| `apm_list_groups(metric: 'network')` | One row per URL-pattern group: `uuid`, `pattern`, `method` (null for gRPC), `type`, `key_metric`, `threshold_ms`, `failure_rate`, `latency_p95_ms`, `apdex_score`. Default sort is `failure_rate`, worst-first |
| `apm_group_view(metric: 'network')` | `summary`, `apdex_chart`, `throughput_chart`, **`failure_rate`**, `spans_table`, `dimensions`, `outliers`. Panels that don't apply come back in `ignored_views` |
| `apm_occurrence(metric: 'network')` | Individual requests via `selector: worst \| by_token \| list`; identify the group by `group_uuid`, or by `group_url` **plus `method`** when the URL is ambiguous |
| `app_insights` | App-level network key metrics in the `apm` section |

**The network list row carries no p50 and no occurrence count.** It gives you `latency_p95_ms` and
`failure_rate` only. Get p50 and volume from `summary` (`latency.p50_ms`, `occurrences`,
`throughput_per_min`) or per cohort from `dimensions`.

`summary` is the richest single call for one group:

```jsonc
"group":        { "uuid", "name", "method", "type", "key_metric", "threshold_ms", "protocol" },
"occurrences":  91230,
"apdex":        { "score", "satisfying", "tolerable", "frustrating" },
"latency":      { "p50_ms", "p95_ms" },
"failure_rate": { "total", "client_side", "server_side",
                  "client_side_failures", "server_side_failures" },
"throughput_per_min": 1520.5,
"comparisons":  { "apdex_change", "p95_change_ms" }
```

**`failure_rate` splits client-side from server-side, and the split is the most valuable thing on this
metric.** A server-side rate is a backend finding. A client-side rate is timeouts, DNS, TLS, and
connection errors — and **each platform corrupts the client-side number in its own direction**, which
the platform files describe. Never quote `failure_rate.total` without checking which side moved.

The `failure_rate` view adds a time series plus a breakdown by `failure_type`:

```jsonc
"rate":      { "series": [{ "ts", "rate" }] },
"breakdown": [{ "failure_type", "count", "rate" }]
```

`dimensions` accepts `pattern_key` of `platform`, `app_version`, `device`, `os_version`, `country`,
`radio`, `carrier`, `failure_name`, `experiment`, `request_payload_size`, `response_payload_size`, and
`custom_attribute_1`…`custom_attribute_20`. Each row carries `occurrences_count`, `apdex_score`,
`dissat_count`, `p50_ms`, `p95_ms`.

`failure_name` is the dimension that names *what* failed — the platform files tell you what those values
look like, and Android's are much coarser than iOS's.

Network-only filters: `country`, `carrier`, `radio`, `failure_name`, `failure_type`,
`response_time_ms`, `request_payload_size`, `response_payload_size`, `custom_attributes`. On the list
surface: `total_failure_rate`, `client_failure_rate`, `server_failure_rate`, each `{gt, lt}` on a
0.0–1.0 rate.

**There is no `stages_breakdown` view for network.** That view exists for `launch` and
`screen_loading` only. The per-request timing breakdown described below is **not available as an
aggregate panel** — see the next section for what to do instead.

## The timing breakdown, and where to find it

When captured, a request's timing decomposes into these stages. This table is a **boundary reference**:
use it to interpret whatever stage or span names you receive, not as a list of keys to expect.

| Stage | What it measures | What a high value points at |
|---|---|---|
| `dnsLookup` | DNS resolution | DNS provider, missing preconnect |
| `tcpConnect` | TCP connection | network latency, no connection reuse |
| `tlsHandshake` | TLS negotiation | certificate chain, no session resumption |
| `requestUpload` | sending headers and body | request payload size, upstream bandwidth |
| `serverProcessing` | time to first response byte | **backend** — not a client problem |
| `responseDownload` | receiving the body | response payload size, compression |

Two routes reach this data, and neither is a stages panel:

- **`spans_table`** on `apm_group_view` returns rows of `type`, `name`, `average_calls`, `frequency`,
  `p50_ms`, `p95_ms`, `p50_change`, `p95_change`. Span names are pass-through — match them against the
  table above rather than assuming them. Note `span_name` is **not** an accepted filter for network.
- **`apm_occurrence`** returns one request's full row, including its stage detail where present. This is
  the only per-request view. Use `selector: 'worst'`, or `latency_percentile` /
  `poor_occurrences: true` to target slow requests.

**Missing `dnsLookup`/`tcpConnect`/`tlsHandshake` on a single request usually means the connection was
reused** — expected on HTTP/2 and HTTP/3 for every request after the first to a host, and not a defect.
Stages can also be absent for several other reasons that are **not** interchangeable with an
account-level disable; the platform files enumerate them exhaustively. Rule those out before blaming the
account.

## What the measured window covers

The total duration spans the request lifecycle as the SDK observes it, and always includes connection
setup, all redirects, transport-level retries, and the full response transfer.

It excludes, on every platform, building the request object, deserializing the response (Retrofit,
Moshi, `Codable`, `json_serializable`), and dispatching the result back to the caller.

**Anchors differ per platform in ways that change findings:**

- **Android** starts *inside* the app's own HTTP interceptors and **after client-side queueing**, and
  ends once the SDK has read the response body. So **neither queueing nor the app's interceptor chain is
  inside the window**, while the SDK's own body read is.
- **iOS** starts at `URLSessionTask.resume()` and ends at the task's completion callback, so time a task
  spent waiting to be resumed is excluded.
- **React Native and Flutter** time on the JS thread / Dart isolate, so **runtime-thread contention is
  inside the window**. A busy JS thread or isolate inflates every in-flight request. On hybrid apps,
  broadly elevated latency is as likely to be thread health as network health — and the same request
  reads higher through a wrapper than measured natively.

Two consequences hold everywhere. A screen that feels slow while its requests look fast is probably
spending the time in deserialization, which this metric cannot see. And because client-side queueing
sits outside the window on both native platforms, **an app that serializes or throttles its own requests
will not show that cost here at all** — look for it in the app's own dispatcher or queue configuration.

## Facts you must apply

| Fact | Applies to |
|---|---|
| Stages come from OkHttp only — no breakdown for `HttpURLConnection` or gRPC | Android |
| Client-side queueing and the app's own interceptor chain are **outside** the duration | Android |
| The duration includes the SDK's own read of the response body, so large downloads look slow by design | Android |
| Cancelled requests are recorded as failures with status 0, inflating `failure_rate.client_side` | Android |
| Cancelling a task that has not yet completed erases its record; cancelling after completion leaves it | iOS |
| With body capture disabled, client-side failures on **natively captured** requests are reported as successes — deflating `failure_rate.client_side` | iOS |
| Upload sizes are wrong for streamed uploads, and for file-based uploads at or above the body-size limit | iOS |
| Timeouts, DNS failures, and connection-refused produce **no record at all** — failure rates are structurally under-reported | Flutter |
| Requests may appear twice in bug reports when the Gradle plugin is installed | React Native (Android) |
| WebSockets are never captured | all |
| Redirects and transport-level retries collapse into one record; a retry issued by the app or its networking library is a separate record, so retry volume is not measurable | all |
| The HTTP protocol version, connection reuse, and cache-hit status are never recorded | all |

`type` and `protocol` on the group describe the group's shape (for example `rest`, `https`), **not** the
HTTP version — HTTP/2 and HTTP/3 are indistinguishable from HTTP/1.1 in this data.

## Neither bodies nor headers are available

Not on any platform, in any APM network record. Payload **sizes** and content types are. Body and header
content appears only in bug reports, crashes, and Session Replay — a separate store on a separate access
path. For a header-level question, the same request in a bug report is the route.

So within APM, the fields that can carry application data are the **URL** and any **custom attributes**
the app attaches.

## Privacy — the URL is the main surface

Auto-masking replaces the values of ~20 known-sensitive keys with `*****`, matched against **query
parameter names**. It is **disabled until enabled for the account**, so assume URLs are stored as sent
unless you have confirmed otherwise. It does not cover:

- **URL path segments** — only query parameters are matched, so a token or identifier embedded in a
  path (`/v2/users/{token}/orders`) is stored verbatim. Common in REST APIs, and the main APM-relevant
  gap.
- **URL fragments** — a token after `#` (`/callback#access_token=…`) is stored verbatim. This is the
  OAuth implicit-flow redirect vector, worth checking specifically in any app that handles one.
- **Key variants** — a key must match the list exactly, so a query parameter named `X-Api-Key` or
  `sessionKey` is not covered on either platform.
- **Case sensitivity — iOS only.** On iOS the configured list is compared as stored, so an entry
  carrying an uppercase letter can never match. **Android is unaffected** — it matches
  case-insensitively, including account-level additions.
- **Custom attributes** — never masked, on any platform.

Redacting a URL path or fragment needs a code-level hook, and it differs per platform: the request
obfuscation handler on iOS, `Luciq.setNetworkLogListener` on Android. Both are **best-effort** — each
can be disabled account-side, and a failure inside the callback leaves the record unmodified. Full
detail in the platform file.

## Before interpreting — run in order

1. **Read the platform file** for this app: `references/metrics/network/<platform>.md`. It carries the
   coverage requirements, which stacks are instrumented, the stage gating, and the conditions under
   which this data misleads.
2. **Confirm coverage before reading absence as a measurement.** Compare `occurrences` and
   `throughput_per_min` against expected traffic, and check the codebase for the setup the coverage
   table above requires. On Android that is a build-config check; on Flutter it is a per-call-site one.
3. **Split the failure rate before attributing it.** Read `failure_rate.client_side` and
   `server_side` separately, then use the `failure_rate` view's `failure_type` breakdown and the
   `failure_name` dimension to name the failures. Apply the platform's client-side correction — iOS
   under-reports client failures, Android over-reports them.
4. **Attribute latency to a side.** High `serverProcessing` is a backend finding, not a client one.
   High connect and TLS share, repeatedly to one host, is connection reuse failing in the app.
5. **Segment before comparing.** Run `dimensions` on `radio` — cellular and Wi-Fi distributions are not
   comparable — and on `app_version`, `os_version`, `device`, and `country`. A change confined to one
   cohort has a different cause than one uniform across all of them.
6. **Exclude what the platform file marks unreliable** before aggregating.
