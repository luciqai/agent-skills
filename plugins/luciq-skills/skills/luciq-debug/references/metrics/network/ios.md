# Network — iOS

Read `references/metrics/preamble.md` and `references/metrics/network/overview.md` first. They carry the
units, the aggregation rules, the measured window, and what the MCP returns for network.

> **Verified against:** Luciq iOS SDK 16.x. §5 describes current limitations, several of which are
> expected to be fixed — treat it as the most version-sensitive section here.

## Version differences

Read the app's SDK version from `Podfile.lock` or the SPM resolution before relying on anything below.

| Behaviour | Applies to | Effect |
|---|---|---|
| Client failures reported as successes when body capture is off | 16.x | **This is a defect, not a design decision, and it is expected to be fixed.** If the version under analysis has the fix, `failure_rate.client_side` is trustworthy and you must not discount it on the strength of §5. There is no version number for the fix yet — confirm with Luciq support before applying or dismissing this. |

**A limitation that has since been fixed will make you discount valid data.** If the app's version is
outside the verified range, say so rather than applying §5 as though it still holds.

## 1. Coverage — read this first

Network capture is controlled at **two layers** on iOS. Unlike Android there is no build-time
configuration — instrumentation installs automatically when the SDK starts.

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Account** | Luciq server-side provisioning | Mostly **no** — see the exception below |
| **Runtime** | SDK APIs the app calls | **Yes** — check for the calls in §8 |

### Account-level gating

These capabilities are provisioned per account. None can be turned **on** from application code:

| Capability | Default | Effect when not enabled |
|---|---|---|
| APM | off | No APM data at all |
| Network capture | **off** | No network records |
| Stage breakdown | on where capture is on | Records carry a total duration but **no stage detail** |
| GraphQL operation names | on | GraphQL requests group as undifferentiated POSTs to one `pattern` |
| gRPC capture | off | No gRPC records |
| URL masking | **off** | Nothing is masked — values are stored as sent |
| Distributed tracing (`traceparent`) | off | No trace correlation with Datadog / New Relic |
| Modern-concurrency capture | on | `async`/`await` requests are **still recorded**, with correct status and duration but a **0 response payload size** |
| Body-size limit | 10 KB | Governs the placeholder-size and trimmed-body symptoms in §5 |

**One exception to codebase-invisibility, and it matters for diagnosis:** URL masking is also exposed as a
public property the app can set. Application code cannot enable masking beyond what the account allows,
but it **can switch masking off** even when the account has it on — and unlike the rest of this layer,
that call is greppable. Before concluding that unmasked URLs are an account issue, check whether the app
sets `autoMaskingEnabled = false`. The APM master switch is public in the same way, so app code can
suppress all APM data.

**The stage breakdown is on by default wherever it can apply — the opposite of Android.** Any account with
network capture enabled gets stages unless the breakdown was explicitly turned off for it. So records
carrying a total duration but no stage detail mean a **deliberate account-level disable**, not a missing
configuration. Do not carry the Android assumption across platforms. Which state applies is not
determinable from the data — if the per-record causes in §2 are all excluded, the account is the only
remaining answer and only Luciq support can confirm it.

Three behaviours of this layer that matter for diagnosis:

- **Configuration arrives asynchronously.** On the first run after install, network capture begins only
  once the configuration lands mid-session, so that session holds **partial** data: requests that
  completed earlier are absent, later ones are recorded. The configuration is cached afterwards, so later
  launches are unaffected. Bug-report network logs work immediately — that divergence is expected, not a
  defect.
- **Disabling is retroactive.** Turning off network capture removes stored traces, and turning off gRPC
  removes gRPC traces. Turning off GraphQL or tracing *clears those fields* on existing records rather
  than deleting them. "It was there yesterday" can be an account change.
- **URL masking and distributed tracing roll out gradually**, so the same app version can behave
  differently across installs — including a partially-enabled account where some devices mask and others
  do not. The remaining capabilities are plain on/off. **The capture mechanism itself is also gradually
  rolled out**: an install that does not receive it gets no automatic capture at all.

### What is instrumented

| Stack | Captured? | Notes |
|---|---|---|
| **`URLSession`** — data, upload, download tasks | Yes | Completion-handler, delegate, `async`/`await`, and Combine paths |
| **Alamofire, Moya, Apollo** | Yes | They use `URLSession`; no library-specific code exists |
| **`WKWebView`** | Opt-in | Requires `webViewNetworkTrackingEnabled = true`, set **after** SDK start (earlier assignments are ignored), plus `webViewMonitoringEnabled`. The account flag defaults to **on**, so the account can only disable it — the code opt-in is the real gate |
| **gRPC** | Manual only | Requires an explicit call per request, see §8 |
| **`NSURLConnection`** | **No** | |
| **Raw CFNetwork, `Network.framework`, BSD sockets** | **No** | Includes custom HTTP/3 clients built on those |
| **WebSockets** (`URLSessionWebSocketTask`) | **No** | |
| **`URLSessionStreamTask`** | **No** | |
| **App extensions** | Not unless the extension starts the SDK itself | Capture is in-process with no cross-process channel |

**Records have a source, and several characteristics below apply to only one of them.** Natively captured
`URLSession` traffic, WebView-sourced entries, and manually added entries (including gRPC) reach the store
by different paths, and the occurrence row carries a log-source field identifying which. §2's measurement
model, and the body-capture blind spot and upload-size defects in §5, describe **native capture only** —
WebView and manual entries do not share them. Check the log source before applying any of those to a
record.

Coverage traps worth checking in the codebase:

- **Requests whose `User-Agent` contains `AppleWebKit` are dropped.** The test is a case-sensitive
  substring match on the request header, and it drops the request from **both** APM records and
  bug-report/crash network logs. An app setting a browser-like User-Agent on its API client loses **all**
  of its traffic. WebView-sourced entries deliberately skip this test.
- **Only `http` and `https` schemes are captured.** Custom schemes, `file://`, and `ws://` are dropped.
  Manually added gRPC traces use `grpc://` URLs and bypass this filter, as they bypass all of the filters
  in this list.
- **Non-standard HTTP verbs are not filtered on the automatic `URLSession` path.** `PROPFIND`, `MKCOL`,
  `LOCK`, `REPORT`, `SEARCH` and any other verb are recorded verbatim. The
  `GET, HEAD, POST, PUT, PATCH, DELETE, CONNECT, OPTIONS, TRACE` allow-list applies **only** to manually
  added logs, WebView-sourced logs, and gRPC traces; verbs outside it are silently discarded on those
  paths alone.
- **Requests already in flight when the SDK starts are invisible.** There is no buffer for them.
- **A `URLSession` built with a custom delegate before the SDK starts stays invisible for the whole
  launch.** Delegate-based capture attaches to the delegate *class* at session construction, so a session
  created before SDK start is never instrumented — not just for one request. Relevant to Alamofire and
  Apollo apps that build their session at app-launch time. Conversely, such a session begins reporting if
  any later session is built with the same delegate class.
- **Both capture kill-switches only take effect before SDK start** and neither is total. See §8: their
  presence in the code does not prove capture was off, and their absence does not explain a true zero.

## 2. How a request is measured

Everything in this section describes **natively captured `URLSession` traffic**. WebView and manually
added entries carry a duration supplied by their own source and have no stages.

### The total duration

| Anchor | Event |
|---|---|
| **Start** | `URLSessionTask.resume()` |
| **End** | The task's completion callback — `didCompleteWithError` for delegate-based tasks, the completion handler for closure-based data and upload tasks, `didFinishDownloadingTo` for delegate-based downloads, or the equivalent for `async`/`await` |

Because `URLSession` delivers completion only after the response has been fully received, the window
naturally covers the entire body transfer.

**One difference from Android worth internalising:** the clock starts at `resume()`, not at task creation.
If the app creates tasks and resumes them later — a manual upload queue, a throttler, a dependency-ordered
chain — that waiting time is **not** in the duration. If a task is suspended and resumed again, the clock
restarts from the last `resume()`.

| Inside the window | Outside the window |
|---|---|
| Connection setup, TLS, request, server time, response transfer | Building the `URLRequest` |
| All redirects and transport-level retries | Time between creating a task and calling `resume()` |
| The full response body transfer | Response decoding — `JSONDecoder`, `Codable`, third-party parsers |
| Reading a download to its destination file | Dispatching the result back (completion queue hop, `await` resumption, Combine downstream) |
| | UI work triggered by the response |

**One exception, and it inverts the rule:** for a `downloadTask(with:completionHandler:)` the clock stops
only *after* the app's completion handler returns. That handler is exactly where an app must synchronously
move the temp file off its delete-on-return URL, and often decodes it — so for closure-based downloads,
that file work and any decoding done there **are** inside the number.

Two consequences to act on:

- **Decoding is not in the number** for data tasks, upload tasks, delegate-based tasks and `async`/`await`.
  A screen that feels slow while its requests look fast is usually spending the time in `JSONDecoder` or
  main-thread work after the response. Closure-based downloads are the exception above.
- **The window has no client-side queueing component.** If requests appear fast individually but the
  screen is slow, look for app-level serialization — an `OperationQueue` with
  `maxConcurrentOperationCount = 1`, or an actor funnelling requests — none of which this metric sees.

### The stages

Stages come from `URLSessionTaskTransactionMetrics`, and each boundary is the property of the same name.
If the app already implements `urlSession(_:task:didFinishCollecting:)`, these are the identical values:

| Stage | `URLSessionTaskTransactionMetrics` properties |
|---|---|
| `dnsLookup` | `domainLookupStartDate` → `domainLookupEndDate` |
| `tcpConnect` | `connectStartDate` → `secureConnectionStartDate`, or `connectEndDate` when there is no TLS |
| `tlsHandshake` | `secureConnectionStartDate` → `secureConnectionEndDate` |
| `requestUpload` | `requestStartDate` → `requestEndDate` |
| `serverProcessing` | request end → `responseStartDate` |
| `responseDownload` | `responseStartDate` → `responseEndDate` |

A stage is marked failed when it began but its end date never arrived — so a `failed` marker on
`tlsHandshake` localises a certificate or pinning problem precisely. **A failed stage reports a duration
of 0, not null:** its real elapsed time is lost and lands in the gap described below, so a large gap on a
record carrying any `failed` stage means that stage, not redirects. `serverProcessing` is derived from the
request-end boundary, so a missing `requestEndDate` yields no `serverProcessing` stage at all rather than
a failed one. Stage durations are not clamped, so a non-monotonic pair of dates can produce a negative
value.

**The causes when stages are missing entirely.** This list is exhaustive; rule all of them out before
attributing to the account:

1. **Not enabled for the account** — see §1. Only this one needs support rather than a code change.
2. **The transaction was served from `URLCache`, or reported an unknown fetch type.** Only
   `resourceFetchType` values of `.networkLoad` and `.serverPush` are kept; `.localCache` and `.unknown`
   are both dropped. The record keeps its duration and loses its stages.
3. **`URLSession.shared`, or a session whose delegate class was never instrumented.** Metrics arrive
   through the session delegate, which the SDK installs on any session built with
   `URLSession(configuration:delegate:delegateQueue:)` — passing `nil` there is fine, the SDK supplies a
   delegate. `URLSession.shared` has no delegate at all, and a session built before the SDK started was
   never instrumented; both still report a total.
4. **The request was mutated between `resume()` and the metrics callback.** Stages are attached by matching
   the transaction against the request as captured at `resume()`; a mismatch drops the stages silently and
   leaves a total-only record.

On a reused connection `dnsLookup`, `tcpConnect`, and `tlsHandshake` are **absent, not zero** — those
dates are simply nil. This is per-record and expected on HTTP/2 and HTTP/3, and it is **not** evidence of
caching.

### Reading the gap between total and stages

`duration − Σ(stages)` contains, in rough order of likelihood:

1. Any `failed` stage's real elapsed time, which is reported as 0
2. Redirect hops other than the first — the matched transaction is the one whose request matches the
   request as it was at `resume()`, so every later hop's metrics are discarded
3. Time between the transaction completing and the completion callback being delivered, including
   delegate-queue hops
4. Body writing for download tasks, and for closure-based downloads the app's own completion handler

## 3. Optimization targets

| Signal | Where to look |
|---|---|
| High `dnsLookup` across hosts | Too many distinct hosts; consolidate domains |
| High `tcpConnect` + `tlsHandshake` share, repeatedly to one host | Connection reuse failing. Check whether the app creates a new `URLSession` per request instead of reusing one; verify `httpMaximumConnectionsPerHost` |
| High `serverProcessing` | **Backend.** Not fixable client-side |
| High `responseDownload` with a large `response_payload_size` | Enable compression, trim payloads, paginate |
| High `requestUpload` with a large `request_payload_size` | Compress or shrink request bodies |
| Total high, all stages low | A `failed` stage reporting 0, redirect chains, a mismatched transaction, or delegate-queue delivery delay — see §2's gap list |
| Many stage-less short records | Inconclusive on its own. `URLCache` serving is one cause; connection reuse, an unknown fetch type and a mutated request produce the same shape. **Do not report cache health from stage absence** |
| Repeated identical patterns in one session | Missing caching or de-duplication |
| Requests fast but screen slow | Decoding or app-level request serialization — neither is in this metric |
| Latency correlated with `radio` = cellular | Expected; segment on the `radio` dimension before comparing |
| Records marked background or background-transitioned | Treat as unreliable for user-perceived latency; see §5 for what each marker means |
| Stage carries a `failed` marker | Localises the failure — failed `tlsHandshake` is certificate or pinning, failed `dnsLookup` is resolution |

## 4. Validation checks

Work the layers in order: runtime API calls first, because they are visible in the codebase, then account.
Check the log source before applying any native-only row.

| Check | How | If it fires |
|---|---|---|
| No data at all | `apm_list_groups` returns no groups | Check §8's kill switches — but both only take effect before SDK start, so a call that is present may have done nothing, and neither stops WebView or manual/gRPC logs, so their absence cannot explain a true zero. Also check the masking/APM properties in §1. If none apply, it is the account layer, a lost gradual rollout, or a first-run install |
| Suspiciously few records | `occurrences` below expected traffic volume | Browser-like `User-Agent`, a non-`URLSession` stack, or a session whose delegate class predates SDK start. **Not** non-standard verbs — those are recorded on the automatic path |
| **Client failure rate implausibly low or zero** | `failure_rate.client_side` near 0 while `server_side` is normal | See §5 — with body capture disabled, client failures on **natively captured** requests are reported as successes, so this number is **deflated, not healthy**. WebView-sourced records keep their error detail and remain trustworthy. Verify body capture, below, before concluding the network is healthy |
| Verifying body capture | Not visible in the data — grep the app for `logBodyEnabled` (Swift `NetworkLogger.logBodyEnabled`, ObjC `LCQNetworkLogger.logBodyEnabled`) | Absent means the default applies; an explicit `false` confirms the blind spot above |
| Cancelled requests absent | | Expected for tasks cancelled before completion. A task cancelled *after* completion keeps its record, and a request that fails with `NSURLErrorCancelled` without `cancel()` being called on the task appears as an ordinary client failure |
| Upload sizes implausible | `request_payload_size` implausibly small against a known-large payload, or 0 | See §5 — file-based and streamed uploads report wrong sizes. Do not test for an exact magnitude: the placeholder length tracks the account's body-size limit |
| Stage detail missing everywhere | No `spans_table` row matches a §2 stage, and occurrence rows carry no stage detail | See §2's four causes. Exclude all four before concluding the account layer; only that one needs support rather than a code change |
| Stage detail missing on some records | Coexists with records that have it | Inconclusive. Connection reuse, `URLCache`, an unknown fetch type, and a mutated request all produce this — see §2 |
| Data present, then stopped | Groups exist historically but not recently | Possible account-level change; disabling removes network and gRPC traces retroactively and clears GraphQL/tracing fields |
| Coverage inconsistent across users | Same app version | Gradual rollout — applies to masking, tracing, and the capture mechanism itself |
| Response sizes 0 on 2xx endpoints | `response_payload_size` of 0 on endpoints known to return a body | **Two causes, check the cheaper one first.** Body capture disabled zeroes the response size for delegate-based and `async`/`await` requests — a one-line code fix. Otherwise modern-concurrency capture is not enabled for the account. Either way the records are **present and otherwise correct**, so do not read this as missing traffic |
| Requests missing at launch | | Already in flight at SDK start; not buffered |
| No background-session downloads | | Expected — effectively never reported |
| Filter unexpectedly removing data | App calls the filter-predicate API | **Semantics are inverted** — a predicate that *matches* omits the request. A predicate that throws is treated as non-matching, so the request is kept |
| Apdex target misconfigured | `threshold_ms` below `latency.p50_ms` | A low or falling `apdex_score` is a target-config problem, not a code defect |

## 5. Data characteristics

Unless a paragraph says otherwise, these describe **natively captured** requests. Check the log source.

**With body capture disabled, client-side failures are reported as successes.** When body logging is off,
the error object is discarded along with the bodies, so timeouts, TLS failures, and connection errors
arrive as records with status 0, no error detail, and no response present. **This is the most consequential
characteristic on this platform** — it makes `failure_rate.client_side` structurally too low, and an agent
computing a failure rate from such a dataset will conclude the network is healthy when it is not. It
applies to native capture only: WebView-sourced records keep their error detail even with body capture off.
Confirm body capture (§4) before trusting client-side failure counts.

**Client failure detail is an `NSError` domain and code**, so `NSURLErrorDomain` with `-1001` is a timeout
and `-1009` is offline. More specific than Android's exception class name, and it surfaces on the
`failure_name` dimension.

**Cancelling a task erases its record, if it has not yet completed.** The trigger is the `cancel()` call
on the task, not a cancellation error. Three consequences: a user navigating away mid-request produces no
data; cancelling after completion leaves the record intact; and a request that fails with
`NSURLErrorCancelled` without `cancel()` being called on the task — session `invalidateAndCancel()`, for
instance — is recorded as an ordinary client failure. **Note this is the opposite of Android**, where
cancellations are recorded and inflate the client-side failure rate.

**Upload sizes are unreliable for two cases.** A file-based upload at or above the account's body-size
limit (10 KB by default) reports the length of an internal placeholder message — tens of bytes — rather
than the file size, and that length tracks the configured limit. A streamed upload reports 0. Multipart is
correct only when built from in-memory data. Exclude these before computing upload bandwidth; the only
handle is implausibility against a known payload size.

**Redirects and transport-level retries collapse into one record.** A retry issued by the app or its
networking library is a new task, so it produces a **separate** record — and no field distinguishes the
two cases, so retry volume cannot be measured from this data. Within one record, the URL and method are
the **final** hop's, while the request size and the stages are the **first** hop's. (Android records the
*original* URL and the *last* hop's stages — the two platforms are inverted here, so never compare
redirect-heavy endpoints across them.)

**In-flight requests at app termination are erased**, not reported as timeouts, so timeout rates are
under-reported.

**Background `URLSession` downloads are effectively never reported.** Completion arrives in a new process
after relaunch, by which point the pending record has been cleaned up. There is no background-session
support in the SDK.

**Two background markers exist, and they mean different things.** The background marker is
**session-derived** — true when either the session the request started in or the current session was
backgrounded — so it is coarser than "this request ran while backgrounded" and will catch foreground
requests that merely shared a session. The background-*transition* marker is per-request. On a prewarmed
launch, any request starting before the first run-loop idle is marked as having transitioned, regardless of
actual app state; the record carries no launch-relative timestamp, so prewarming cannot be identified from
the data. Treat both markers as reasons to distrust a record for user-perceived latency rather than as
precise filters.

**The HTTP protocol version, connection reuse, and cache-hit status are never recorded** — HTTP/2 and
HTTP/3 are indistinguishable from HTTP/1.1, and a `URLCache` hit is inferable only from the absence of
stages, which has other causes.

**Streaming and SSE responses produce nothing until the stream closes.** An open stream is an unfinished
record and is not reportable.

**Capture work runs on the main thread, once per capture event per consumer.** Persistence, the app's own
obfuscation and attribute handlers, and response-body disk IO all run **off** the main thread. Relevant if
the app issues many requests during a latency-sensitive phase — but it is capture overhead, not storage
cost.

## 6. What is available in APM

APM network records carry: URL, method, status, duration, stages, payload **sizes**, content types, error
domain and code, radio, carrier, background markers, log source, and custom attributes.

**Bodies are not available, and neither is host header content.** The only header-derived values on the
record are the two content types and the SDK's own `traceparent` correlation IDs. Body and header content
appears only in bug reports, crashes, and Session Replay — a separate store on a separate access path.

Content types and the request size are unaffected by the body-capture setting. **The response size is 0
when body capture is disabled** for delegate-based and `async`/`await` requests; completion-handler and
download tasks keep their size regardless.

So you can see that a request sent 512 KB and took 1.2 s, but not what it sent or which headers it
carried. For header-level debugging, the same request in a bug report is the route.

## 7. Privacy — the URL is the main surface

The **URL** is the field most likely to carry application data. **Custom attributes** are the other
surface: the app supplies them, and they are never masked.

Auto-masking replaces the values of these keys with `*****`, matched case-insensitively against **query
parameter names**:

```
authorization, authorization_token, auth_token, auth, access_token, token, oauth_token,
bearer_token, refresh_token, jwt_token, jwt, password, pwd, api_key, apikey, secret,
client_secret, app_secret, consumer_secret
```

Credentials embedded in the URL's userinfo component are also replaced, both user and password. Masking is
**disabled until enabled for the account**, and the account gate is a **gradual rollout** — a
partially-enabled account leaves some devices completely unmasked. The public `autoMaskingEnabled` property
cannot enable masking; it is an off-switch that ANDs with the account gate. Verify both before relying on
masking.

### Coverage gaps that affect APM

- **URL path segments are not masked** — only query parameters. A token or identifier embedded in a path
  (`/v2/users/{token}/orders`) is stored verbatim. Common in REST APIs, and the main APM-relevant gap.
- **URL fragments are not masked.** A token after `#` (`/callback#access_token=…`) is stored verbatim —
  the OAuth implicit-flow redirect vector.
- **Custom attributes are not masked.** Anything the app attaches is stored as supplied.
- **Matching is exact key equality after lowercasing.** No substring or prefix matching, so a query
  parameter named `X-Api-Key`, `sessionKey`, or `user_token` is not covered.
- **A configured key that is not all-lowercase can never match.** The lookup lowercases the incoming key
  but compares it against the configured list as stored, so an entry carrying an uppercase letter is dead
  at every casing. One default entry is dead for this reason — hence 19 effective keys above, not the 20
  configured — and account-level additions fail the same way. **Android is not affected by this**; it
  matches case-insensitively on both sides.

### The complete remedy

```objc
[LCQNetworkLogger setRequestObfuscationHandler:^NSURLRequest *(NSURLRequest *request) { … }];
```

```swift
NetworkLogger.setRequestObfuscationHandler { request in … }
```

For APM specifically this is the only way to redact a URL path or fragment. Note the return value **also
changes what APM records** — the URL, method, content type and request body size APM stores all come from
the obfuscated request, so rewriting a URL there changes how requests group into patterns in the
dashboard, and stripping a body zeroes the recorded request size.

The filter-predicate API excludes requests, but **a predicate that matches causes the request to be
omitted** — the opposite of what the name suggests. A response-side match deletes an already-recorded APM
entry, and a predicate that throws is treated as non-matching, so the request is kept.

## 8. Public API

Objective-C:

```objc
LCQNetworkLogger.enabled                    // disabling also clears stored logs and stops APM network data; no-op before SDK init
LCQNetworkLogger.autoMaskingEnabled         // off-switch only — ANDs with the account gate, cannot enable masking
LCQNetworkLogger.logBodyEnabled             // see §5 before disabling — it suppresses client-failure detail on native capture
[LCQNetworkLogger setRequestObfuscationHandler:…]
[LCQNetworkLogger setResponseObfuscationHandler:…]
[LCQNetworkLogger setNetworkLoggingRequestFilterPredicate:…responseFilterPredicate:…]
[LCQNetworkLogger disableAutomaticCapturingOfNetworkLogs]
[LCQNetworkLogger addGrpcNetworkLogWithUrl:… gRPCMethod:… serverErrorMessage:…]   // manual gRPC entry point
[LCQAPM addNetworkTraceAttributesForURLMatchingPredicate:owner:usingHandler:]
[Luciq disableMethodSwizzling]
Luciq.webViewNetworkTrackingEnabled         // assign AFTER Luciq start; earlier assignments are ignored
```

Swift — the two classes are renamed, so the Objective-C spellings do not exist as Swift identifiers:

```swift
NetworkLogger.enabled
NetworkLogger.autoMaskingEnabled
NetworkLogger.logBodyEnabled
NetworkLogger.setRequestObfuscationHandler { … }
APM.addNetworkTraceAttributesForURL(matching:owner:usingHandler:)
Luciq.disableMethodSwizzling()
Luciq.webViewNetworkTrackingEnabled
```

`Luciq` keeps its name in both languages. When grepping a customer codebase, search for the spelling that
matches the app's language — the Objective-C class names are absent from Swift-first apps.

**Both kill-switches only take effect before SDK start, and neither is total.** `disableMethodSwizzling`
is ignored with a console error if called after start; when honoured it disables automatic `URLSession`
capture **and** WKWebView capture. `disableAutomaticCapturingOfNetworkLogs` must likewise precede start and
does not stop capture already running. Neither stops WebView network logs from a separately-enabled WebView
path, nor manually added / gRPC logs, both of which keep recording.

Attributes: **5 per record by default** (the account can change it); keys ≤30 characters and values ≤60 are
fixed. Over any limit the attribute is **dropped, not truncated**, and which ones survive the count limit
is **arbitrary** — never compare attribute sets across records. The cap is per record across all handlers
combined, and re-using a key already present overwrites it rather than counting against the cap. They
surface as the `custom_attribute_1`…`custom_attribute_20` dimension keys.

**Distributed tracing:** the SDK reads an existing `traceparent` header, or generates and injects one when
enabled for the account. Requests already carrying a client-generated `traceparent` are left untouched and
flagged as such. A malformed `traceparent` is also left untouched but produces no trace fields and is not
flagged.

**GraphQL:** operation names come from the `X-APOLLO-OPERATION-NAME` header, or from `ibg-graphql-header`
for non-Apollo clients. **The header lookup is case-sensitive** — a client sending
`x-apollo-operation-name` in lowercase gets no GraphQL classification and no GraphQL failure classification
either.
