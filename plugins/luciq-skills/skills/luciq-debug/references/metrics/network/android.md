# Network — Android

Read `references/metrics/preamble.md` and `references/metrics/network/overview.md` first. They carry the
units, the aggregation rules, the measured window, and what the MCP returns for network.

> **Verified against:** Luciq Android SDK 19.2.0. §5 describes current limitations, several of which are
> expected to be fixed — treat it as the most version-sensitive section here.

## Version differences

Read the app's SDK version from `build.gradle` / `build.gradle.kts` before relying on anything below.

| Behaviour | Applies to | Effect |
|---|---|---|
| Unified network interception | **19.0.0 and later** | Landed as a **breaking change** in 19.0.0. On earlier versions the coverage requirements in §1 and the anchors in §2 both differ — do not apply this file to a pre-19.0.0 app without confirming, and expect a step change in the data across that upgrade rather than a regression. |

Note for hybrid apps: React Native and Flutter pin their own native SDK versions, which can be
substantially older than the version above. React Native 16.0.4 and Flutter 16.0.4 both pin Android
**16.0.0** — well before the 19.0.0 change. Check the pinned version rather than assuming.

## 1. Coverage — read this first

Network capture is controlled at **three independent layers**. A capability is unavailable if *any*
applicable layer disables it, and the diagnostic action differs per layer — so identify the layer before
proposing anything.

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Build** | The Gradle plugin and its DSL | **Yes** — check `build.gradle` |
| **Account** | Luciq server-side provisioning | **No** — ask Luciq support |
| **Runtime** | SDK APIs the app calls | **Yes** — check for the calls in §8 |

### Account-level gating

These capabilities are provisioned per account and **default to off**. None can be enabled from
application code, and none are discoverable from the codebase:

| Capability | Effect when not enabled |
|---|---|
| APM | No APM data at all |
| Network capture | No network records |
| Stage breakdown | Records carry a total duration but **no stage detail** |
| GraphQL operation names | GraphQL requests group as undifferentiated POSTs to one `pattern` |
| gRPC capture | No gRPC records |
| URL and header masking | Nothing is masked — values are stored as sent |
| Distributed tracing (`traceparent`) | No trace correlation with Datadog / New Relic |

Three behaviours of this layer that matter for diagnosis:

- **Configuration arrives asynchronously.** On the first run after install none of it has been fetched,
  so nothing is captured. Expect the first session of any install to be absent.
- **Disabling is retroactive.** Turning off network capture or the stage breakdown removes
  already-stored data for it. "The data was there yesterday and is gone today" is a plausible outcome of
  an account change, not necessarily a bug.
- **Some capabilities roll out gradually**, so the same app version can have a capability active on some
  installs and not others — which shows up as coverage that differs across users.

### Build-level gating

**Network capture is off by default here too.** Two build conditions must both hold:

```kotlin
// build.gradle — the Luciq Gradle plugin must be applied, and:
luciq {
  networkInterception {
    enabled = true          // ← defaults to FALSE. Nothing is captured without this.
    okHttp { enabled = true; eventListenerEnabled = true }
    urlConnection { enabled = true; excludeFirebase = true }
    grpc { enabled = true } // ← also defaults to FALSE, independently of the above
    excludeUrlPatterns = []
  }
}
```

If network data is absent or far below expected volume, check these before anything else. **There is no
runtime API to enable capture** — it cannot be turned on from application code.

### What is instrumented

| Stack | Captured? | Notes |
|---|---|---|
| **OkHttp 4.x** | Yes, automatic | The only stack with a timing breakdown |
| **Retrofit** | Yes | Runs on OkHttp |
| **`HttpURLConnection`** | Yes, automatic | No timing breakdown |
| **Volley** | Yes, incidentally | Default `HurlStack` uses `URL.openConnection()` |
| **Ktor** | Depends on the engine | OkHttp and Android engines are captured — the Android engine runs on `HttpURLConnection`. CIO is not captured |
| **gRPC** | Manual + build flag | Add the Luciq gRPC interceptor to the channel **and** set `grpc { enabled = true }`. No bodies. Excluded from bug reports — APM only |
| **Cronet, Apache HttpClient** | **No** | Not captured at all |
| **WebView traffic** | **No** | Not functional in current releases |
| **WebSockets** | **No** | No WebSocket support exists — message traffic is never captured |

Instrumentation gaps worth checking in the codebase:

- **Only the no-argument `URL.openConnection()` is instrumented.** `openConnection(Proxy)`,
  `URL.openStream()`, and connections from a custom `URLStreamHandler` are not captured. Note
  `openStream()` reaches `openConnection()` internally, but that happens inside the JDK rather than in
  application bytecode, so those call sites are not covered.
- **Firebase, Google Play Services, Play Core, and Google DataTransport are excluded by default**
  (`excludeFirebase`). Exclusion is by **calling-class package, not by host**, and it applies only to the
  `HttpURLConnection` and gRPC paths — traffic those libraries send over OkHttp **is** still captured. So
  "Firebase traffic is missing" and "some Firebase traffic is present" are both expected.
- **Custom `Call.Factory` implementations are not captured** — instrumentation attaches when an
  `OkHttpClient` is constructed.
- **The SDK's own telemetry traffic is captured** on `*.instabug.com` hosts. Only the SDK's control-plane
  requests are self-excluded; the rest of Luciq's own traffic appears in the data. Filter those patterns
  out before computing endpoint statistics.

## 2. How a request is measured

### The total duration

Effective anchors:

- **Start** = the call reaching Luciq's interceptor. Luciq's interceptor is the **innermost** application
  interceptor, so the app's own interceptors wrap it and are **not** in the window; an application
  interceptor also runs only after the dispatcher has dequeued the call, so client-side queueing is
  **not** in the window either.
- **End** = the later of the call completing, or the SDK finishing its body read.

**The body-read end anchor is the part that surprises people.** OkHttp's `chain.proceed()` returns as
soon as response *headers* arrive — the body is still a stream at that point. The SDK forces the whole
body to be read before it stops the clock. So for a large download the reported duration covers the
**entire transfer**, even if the app streams the response and never blocks on it. An app-side interceptor
measuring around its own `chain.proceed()` would report a much smaller number for the same request; both
are correct, they measure different things.

On failure the clock stops when the throwable reaches the Luciq interceptor, so the duration includes the
timeout period for timeouts.

| Inside the window | Outside the window |
|---|---|
| Connection acquisition from the pool | Building the `Request` object |
| All redirects and all OkHttp-level retries | **The app's own OkHttp interceptors**, including auth/token-refresh, signing, caching, and retry interceptors |
| **The full response body transfer**, including for streamed responses the app never blocks on | Dispatcher queueing — time waiting for a slot |
| | Response deserialization by Retrofit, Moshi, Gson, or `kotlinx.serialization` |
| | Dispatching the result back to the caller (callback, coroutine resume, `LiveData` post) |
| | Anything in a `Call.Factory` wrapper the app supplies |
| | UI work triggered by the response |

Two consequences to act on:

- **A long duration with small stages does *not* implicate the app's own interceptors** — those sit
  outside the window, so a token-refresh interceptor that blocks for a second cannot inflate the request
  it delayed, and tuning `Dispatcher.maxRequests` / `maxRequestsPerHost` will not move these numbers.
  Look instead at connection acquisition, discarded redirect legs, and the response-body transfer.
- **Deserialization is never in the number.** If a screen feels slow but the duration is fine, look at
  JSON parsing and main-thread work after the response, which this metric cannot see.

### The stages

Stages come from `okhttp3.EventListener` callbacks, and each boundary is the callback of the same name.
If the app already registers its own `EventListener`, these are the identical events:

| Stage | `EventListener` callbacks |
|---|---|
| `dnsLookup` | `dnsStart` → `dnsEnd` |
| `tcpConnect` | `connectStart` → `secureConnectStart`, or `connectEnd` when there is no TLS |
| `tlsHandshake` | `secureConnectStart` → `secureConnectEnd` |
| `requestUpload` | `requestHeadersStart` → `requestBodyEnd` (or `requestHeadersEnd` when there is no body) |
| `serverProcessing` | `requestBodyEnd` / `requestHeadersEnd` → `responseHeadersStart` |
| `responseDownload` | `responseHeadersStart` → `responseBodyEnd` |

A stage is marked failed when its end event never arrived because the call failed inside it — so a
`failed` marker on `tlsHandshake` localises a certificate or handshake problem. The specific failing
phase is **inferred rather than recorded**, so treat it as a strong hint, not proof.

**Stages require both of:** the account having the stage breakdown enabled, and `eventListenerEnabled`
left on. The account layer removes stages *retroactively* — they are captured either way, then cleared
from storage if the account lacks the capability, so that state is **not distinguishable** from never
having been captured.

Stages are also **absent** for `HttpURLConnection` and gRPC regardless of any of the above — those
records only ever carry a total.

On a reused connection `dnsLookup`, `tcpConnect`, and `tlsHandshake` are **absent, not zero** — those
callbacks simply never fire.

### Reading the gap between total and stages

`duration − Σ(stages)` is real and often large. It contains, in rough order of likelihood:

1. The response-body transfer beyond time-to-headers
2. Connection-pool acquisition not covered by a connect stage
3. Redirect hops other than the last, whose stages are discarded

Compute it explicitly on an occurrence row. A gap dominating the total is a client-side finding even
though no stage names it — but it does **not** point at the app's own interceptor chain, which is outside
the window.

## 3. Optimization targets

| Signal | Where to look |
|---|---|
| High `dnsLookup` across hosts | Too many distinct hosts; consider consolidating domains |
| High `tcpConnect` + `tlsHandshake` share, repeatedly to one host | Connection reuse is failing. Check that one shared `OkHttpClient` is reused rather than constructed per request, and inspect `ConnectionPool` settings |
| High `serverProcessing` | **Backend.** Not fixable client-side. Report as such |
| High `responseDownload` with a large `response_payload_size` | Enable gzip/brotli, trim response payloads, paginate |
| High `requestUpload` with a large `request_payload_size` | Compress or shrink request bodies; avoid sending unused fields |
| Total ≫ stage sum | The response-body transfer first, then connection-pool acquisition, then discarded redirect legs. **Not** the app's own interceptors — they are outside the window |
| Large downloads look slow | Expected — the duration covers the full body transfer, not time-to-headers. Compare against `response_payload_size` before treating it as a regression, and consider `excludeUrlPatterns` for streaming endpoints |
| Stage carries a `failed` marker | Narrows the failure — a failed `tlsHandshake` suggests a certificate or pinning problem, a failed `dnsLookup` suggests resolution |
| Repeated identical patterns in one session | Missing caching or de-duplication |
| Latency correlated with `radio` = cellular | Expected; segment on the `radio` dimension before comparing |

## 4. Validation checks

Work the three layers in order — build config first, because it is the only one visible in the codebase,
then account, then runtime.

| Check | How | If it fires |
|---|---|---|
| No data at all | `apm_list_groups` returns no groups, or `summary`'s `occurrences` is implausibly low | **Build layer first**: is the Gradle plugin applied and `networkInterception.enabled = true`? This is the most common cause by a wide margin. If the build config is correct, it is the account layer or a first-run install — neither is fixable in code |
| Stage detail missing everywhere | No `spans_table` row matches a §2 stage, and occurrence rows carry no stage detail | If `eventListenerEnabled` is on, this is the **account layer** — the stage breakdown is not provisioned. Recommend contacting Luciq support rather than changing code |
| Stage detail missing on some records | Records with stage detail coexist with records without | Expected — the ones without came from `HttpURLConnection` or gRPC, which never carry stages. Also expected on a reused connection for the three connection stages |
| Volume plateaus in busy sessions | `occurrences` stops scaling with traffic | Expected — counts are capped per session. See §5; this is neither a setup nor a performance finding, and it invalidates per-endpoint frequency arithmetic |
| Failure rate inflated by cancellations | `failure_name` dimension dominated by a bare `IOException` | Cancellations are recorded as failures with status 0 (§5). A genuine failure names its cause — `SocketTimeoutException`, `UnknownHostException`, `SSLHandshakeException`. Exclude bare `IOException` before treating `failure_rate.client_side` as a reliability signal |
| Client failures with no detail | `failure_name` values are bare exception class names | Expected for HTTP — the exception message is dropped on the APM path and no numeric code is set. Correlate with the bug-report network log for the same request to recover the message |
| Data present, then stopped | Groups exist historically but not recently | Possible account-level change; disabling a capability removes stored data retroactively |
| Coverage inconsistent across users | Same app version, some installs have data | Gradual rollout at the account layer |
| GraphQL requests ungrouped | All GraphQL traffic on one `pattern` | Account layer — operation-name extraction is off by default on Android. The app can also supply the name itself; see §8 |
| Luciq's own traffic present | Patterns on `*.instabug.com` | Filter before computing endpoint statistics |
| Firebase traffic partially absent | Some expected Google-host requests missing, others present | Excluded by default via `excludeFirebase` — but only on the `HttpURLConnection` and gRPC paths |
| Duplicate-looking records | Same pattern, near-identical timestamps | If the app is React Native, this is the Android Gradle plugin double-recording |
| Secrets visible in records | Tokens or identifiers in URL paths | See §7 — auto-masking covers query parameters by exact key match, never paths |
| Header-level question | Need to see request or response headers | Not available in APM. Use the bug-report network log for the same request |
| Multi-process app | `android:process` used for services or activities | Network numbers are unreliable — no cross-process deduplication exists |
| Apdex target misconfigured | `threshold_ms` below `latency.p50_ms` | A low or falling `apdex_score` is a target-config problem, not a code defect |

## 5. Data characteristics

**Requests before SDK initialization are not recorded.** APM begins receiving records only after the SDK
finishes starting; earlier completions are not queued and are lost. On the first run after install, APM
records nothing until the first configuration fetch succeeds.

**Record counts are capped per session.** Beyond the cap, further requests are not stored. Treat
`occurrences` as a **sample, not a census**: do not infer broken coverage from counts that plateau
instead of scaling with traffic, and do not compute per-endpoint request frequencies from a session that
hit the cap without accounting for it.

**Client failure detail depends on the source, and is coarser in APM than elsewhere.**

| Source | What the failure name contains |
|---|---|
| Automatically intercepted HTTP failure | The **exception class name** — `IOException`, `SSLHandshakeException`, `SocketTimeoutException`. The message is dropped on the APM path, and no numeric code is set |
| gRPC client-side failure | The gRPC **status name** — `DEADLINE_EXCEEDED`, `UNAVAILABLE` — plus the numeric status value. Genuinely informative |

So for HTTP you can tell a TLS failure from a timeout, but not *which* host failed to resolve or what the
socket reported. **The message does exist** — the same failure recorded into a bug report carries
`throwable.message` — so correlating the APM record with the bug-report network log for the same request
recovers it.

**Cancelled requests are recorded as failures**, with status 0. Worth knowing before quoting a failure
rate: **a user-cancelled request is not a failure**, but it is counted as one, so
`failure_rate.client_side` is **inflated** on this platform. They are usually distinguishable by the
failure name — a cancellation surfaces as a plain `IOException`, a genuine failure names its cause.

**Records with neither a status code nor an error are discarded** during maintenance.

**Redirects and retries collapse into one record.** The URL recorded is the **original** request URL; the
total covers the whole chain; the stages describe only the **last** hop. A redirect chain is therefore
invisible as a chain, and the stage sum will be far below the total.

**Background requests are marked** and are attached to the following session rather than the one during
which they ran. Session-scoped request counts will not tie out exactly.

**gRPC records carry no bodies and no stages**, and do not appear in bug reports. Their group also has no
`method` — that field is null for gRPC.

**The HTTP protocol version, connection reuse, and cache-hit status are never recorded**, so HTTP/2 and
HTTP/3 cannot be distinguished from HTTP/1.1 in the data.

**Response-body buffering can inflate the very durations you are analysing.** The OkHttp interceptor
buffers the entire response body into memory before the app receives it, for responses that pass the
SDK's capture checks. For large downloads or streaming responses that is a real memory and latency cost.
Adding those URL patterns to `excludeUrlPatterns` skips body buffering while still producing the APM
record — but the exclusion list reaches only the OkHttp path, and only the response body.

**Per-request event collection is capped at 50.** A request that exceeds the cap ships with **no stages
at all** — they are dropped rather than truncated — and its duration falls back to the interceptor
measurement alone.

**Timestamps and durations come from different clocks** — durations are measured monotonically, start
timestamps are wall-clock and can drift. Never derive a duration by subtracting timestamps.

## 6. What is available in APM

APM network records carry: URL, method, status, duration, stages, payload **sizes**, content types,
failure name, radio, carrier, background flag, and custom attributes.

**Neither bodies nor headers are available.** Body and header content appears only in bug reports,
crashes, and Session Replay — a separate store on a separate access path. Payload *sizes* and content
types are in APM regardless of whether body capture is enabled, so size-based analysis is unaffected by
that setting.

The practical consequence: you can see that a request sent 512 KB and took 1.2 s, but not what it sent or
which headers it carried. For header-level debugging, the same request in a bug report is the route.

## 7. Privacy — the URL is the surface that matters

Because APM carries no bodies or headers, the **URL** is the only field in an APM network record that can
contain application data, alongside any custom attributes the app attaches.

Auto-masking replaces the values of these keys with `*****`, matched case-insensitively against **query
parameter names**:

```
authorization, authorization_token, auth_token, auth, access_token, token, oauth_token,
bearer_token, refresh_token, jwt_token, jwt, username, password, pwd, api_key, apikey, secret,
client_secret, app_secret, consumer_secret
```

`Luciq.setNetworkAutoMaskingState(Feature.State)` toggles it in the SDK, but it is **disabled until
enabled for the account** — verify it is active before relying on it. **The shipping default is therefore
unmasked**: assume URLs are stored as sent unless you have confirmed otherwise.

### Coverage gaps that affect APM

These are properties of how matching works, not configuration mistakes. Each requires
`Luciq.setNetworkLogListener` to address.

- **URL path segments are not masked** — only query parameters. A token or identifier embedded in a path
  (`/v2/users/{token}/orders`) is stored in APM verbatim. Path-embedded secrets are common in REST APIs,
  and this is the main APM-relevant gap.
- **URL fragments are not masked** — a token after `#` (`/callback#access_token=…`) is stored verbatim.
  Worth checking specifically in any app handling an OAuth implicit-flow redirect.
- **Matching is exact key equality.** No substring or prefix matching, so a query parameter named
  `X-Api-Key`, `sessionKey`, or `user_token` is not covered. Case does not matter — both the default list
  and any account-level additions are matched case-insensitively.
- **Custom attributes are never masked.**

### The complete remedy

`Luciq.setNetworkLogListener(listener)` receives each record before storage and can rewrite the URL and
headers, or return `null` to drop the record entirely. For APM specifically, it is the only way to redact
a URL path or fragment.

Constraints and failure modes worth stating plainly: the URL cannot be blanked (the edit is rejected and
the record is stored unmodified), and any modification marks the record as user-modified. The listener can
also be disabled account-side, in which case it is **never invoked** and records store unredacted; and an
exception thrown inside it is swallowed, leaving the unmodified record to proceed. Treat it as
best-effort rather than a guarantee.

There is **no per-URL opt-out** for the app's own endpoints. `excludeUrlPatterns` affects body capture
only — it does not remove the record from APM.

## 8. Public API

```java
Luciq.setNetworkLogListener(NetworkLogListener)   // sanitize, rewrite, or drop — affects APM records
Luciq.setNetworkAutoMaskingState(Feature.State)   // toggles URL + header masking
Luciq.setNetworkLogBodyEnabled(boolean)           // no effect on APM fields, except that disabling it
                                                  // also removes GraphQL server-error detection
APM.setEnabled(boolean)                           // gates all APM data, including network records
APM.addOnNetworkTraceListener(OnNetworkTraceListener)     // attach custom attributes
APM.removeOnNetworkTraceListener(OnNetworkTraceListener)
```

Use `APM.addOnNetworkTraceListener` with the listener type from the APM package. A same-named method
exists on `Luciq` taking a different listener type and is inert on the current architecture — do not use
it. If a customer's attributes are not appearing, check which overload they called.

Attributes: up to 5 per record (the count is account-configurable), keys ≤30 characters, values ≤60.
Violations are dropped, never truncated. They surface as the `custom_attribute_1`…`custom_attribute_20`
dimension keys.

**Distributed tracing:** the SDK reads an existing `traceparent` header, or generates and injects one when
the account has the feature enabled. Correlate with Datadog or New Relic on that header. `tracestate` is
not read or written. Note that **when a client error is present the trace fields are cleared, so failed
requests carry no trace id** — an absence of failed requests in a backend trace view is expected, not a
tracing defect.

**GraphQL:** operation names are extracted from Apollo requests when enabled for the account — off by
default on Android. Any client can also supply the name itself by setting an `ibg-graphql-header` request
header, which the SDK reads and strips before the request is sent.
