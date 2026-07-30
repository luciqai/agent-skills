# Network — Flutter

Read `references/metrics/preamble.md` and `references/metrics/network/overview.md` first, then **also
read the native platform file** — `references/metrics/network/ios.md` or
`references/metrics/network/android.md`. This file is a supplement, never a replacement: the account
gating and the privacy model both come from the native platform.

> **Verified against:** `instabug_flutter` 16.0.4 pinning iOS SDK 16.0.3 and Android SDK 16.0.0, with
> `instabug_http_client` 2.7.1 and `instabug_dio_interceptor` 2.6.1.

## Version differences

**Four independently versioned components.** The add-on packages upgrade separately from the core plugin,
which upgrades separately from the pinned native SDKs. If capture changed behaviour after an upgrade,
check which of the four moved — read them from `pubspec.yaml` and `pubspec.lock`.

| Behaviour | Applies to | Effect |
|---|---|---|
| Pinned Android SDK is **16.0.0** | plugin 16.0.4 | This is **before the 19.0.0 unified-interception change**. `network/android.md` documents 19.2.0, so its §1 coverage requirements and §2 anchors do **not** describe what this app runs. Less consequential than on React Native, because Flutter traffic is timed in Dart rather than by the native interceptor — but do not quote that file's Android anchors for a Flutter app. |
| Pinned iOS SDK is 16.0.3 | plugin 16.0.4 | Within `network/ios.md`'s verified range. |
| Add-on package versions | independent | A mismatched add-on constraint against the core plugin can stop capture outright. Check the constraint before investigating data loss. |

## 1. Coverage — nothing is captured by default

**The core `instabug_flutter` package does not intercept network traffic.** Capture requires a separate
add-on package **and a code change at every call site.** This is the single most common cause of missing
Flutter network data — check it before anything else.

| HTTP client | Captured? | What is required |
|---|---|---|
| `http` package | Only via `InstabugHttpClient` | Add `instabug_http_client`, replace every `http.Client()` with `InstabugHttpClient()` |
| `dio` | Only with the interceptor | Add `instabug_dio_interceptor`, then `dio.interceptors.add(InstabugDioInterceptor())` on **every** `Dio` instance |
| `dart:io` `HttpClient` | Only via a separate package | Requires `instabug-dart-io-http-client`, a distinct repository |
| Top-level `http.get(...)` etc. | **No** | Those functions create their own client internally |
| `client.read()` / `client.readBytes()` | **No** | Not logged even on `InstabugHttpClient` |
| `cupertino_http` | **No** | On iOS, native capture is disabled, so nothing records these |
| Chopper, `graphql_flutter`'s own link, Firebase SDKs, Flutter image loading | **No** | |
| WebSockets | **No** | |

### Setup

```yaml
dependencies:
  instabug_http_client:        # for the http package
  instabug_dio_interceptor:    # for dio
```

```dart
final client = InstabugHttpClient();
final response = await client.get(Uri.parse(url));

final dio = Dio();
dio.interceptors.add(InstabugDioInterceptor());
```

### Gating layers

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Package** | Add-on package installed *and used at each call site* | **Yes** — `pubspec.yaml` and every client construction |
| **Account** | Luciq server-side provisioning | **No** — ask Luciq support |
| **Runtime** | `omitLog` / `obfuscateLog` callbacks | Yes — see §6 |

There is **no build layer** — no Gradle plugin involvement, and no native-interception concept at all.

**Installing the package does not mean data appears.** The Dart layer forwards records to the native SDK,
which is still subject to account gating. Account capabilities match the native platform — read that
file's gating section. Most relevant here: network capture is off by default, the first session after
install has nothing, and disabling removes stored data retroactively.

### Codebase checks when data is missing

1. Is either add-on package in `pubspec.yaml` at all?
2. Is the app calling top-level `http.get(...)` instead of an `InstabugHttpClient` instance?
3. Is the Dio interceptor added to **every** `Dio` instance — including those built inside repositories,
   DI containers, and third-party packages?
4. Is the app using `client.read()` / `client.readBytes()`?
5. Is traffic going through `dart:io HttpClient`, `cupertino_http`, or a native plugin?

**Partial coverage is the normal failure mode**: one `Dio` instance instrumented and three not. Do not
treat endpoint volumes as complete without verifying every client construction site.

## 2. Failed requests are not recorded

**Timeouts, DNS failures, and connection-refused produce no record at all.** `instabug_http_client` logs
only on a successful response; `InstabugDioInterceptor` logs an error only when the error carries a
response, so `DioException`s without one are dropped.

Consequences for analysis, and this is the most important section in this file:

- **`failure_rate.client_side` is structurally under-reported.** An app with a connectivity problem looks
  healthy. This is not the iOS body-capture defect — it is unconditional on Flutter, and no setting
  changes it.
- **Timeout latency is invisible**, so latency percentiles are biased **low** — the slowest requests are
  exactly the ones missing. A flattering p95 on Flutter is not evidence of a fast network.
- Client failure detail is **never populated** on either platform, so an empty `failure_name` dimension
  carries no information at all.
- **Never conclude "the network is fine" from Flutter network data alone.** Cross-check against crash
  data, user reports, or backend metrics.

This is a genuine difference from React Native, which does capture client failures.

## 3. How a request is measured

### The total duration

| Anchor | Event |
|---|---|
| **Start** | Inside the Instabug client or interceptor, **before delegating to the real HTTP client** |
| **End** | The Dart `Future` completes and the logging callback runs — `.then(...)` for `InstabugHttpClient`, `onResponse` for the Dio interceptor |

Both timestamps are taken **on the Dart isolate**. That drives everything below.

| Inside the window | Outside the window |
|---|---|
| The native HTTP stack — connection, TLS, server time, download | Building the request or `RequestOptions` |
| **Dart event-loop contention** — time the completion callback waits | The app's own `jsonDecode` / `fromJson` |
| Other Dio interceptors in the chain, depending on registration order | `setState` / rebuild, and any `FutureBuilder` work |
| All redirects and retries | Anything in native plugins |

**Two consequences:**

- **The number conflates network time with Dart event-loop health.** A busy isolate — a large synchronous
  decode, heavy widget building — delays the completion callback and inflates the reported duration. **A
  latency regression on Flutter is not necessarily a network regression.**
- **Other Dio interceptors may be inside the window.** If the app has an auth-refresh or retry interceptor
  registered alongside Instabug's, its time may be attributed to the request depending on ordering. Check
  `dio.interceptors` order when latency looks inflated. **Note this is the opposite of native Android**,
  where the app's own interceptors sit outside the window.

**This differs from both native platforms.** iOS anchors at `URLSessionTask.resume()`, Android before its
HTTP interceptors — neither includes Dart event-loop delay. The same request measured through Flutter
reads higher than measured natively, so never compare a Flutter number against a native one.

### Stages

**There is no timing breakdown on Flutter — none, on either platform.** No DNS, TLS, server-processing, or
download decomposition exists for Dart-captured traffic, and there is no configuration or account
capability that enables it.

Latency is the only signal. That makes attribution harder than on any other platform: a slow request
cannot be split into connection setup versus backend time from this data at all. For attribution,
recommend the DevTools network view during investigation, or backend-side tracing correlated on the
`traceparent` header.

## 4. Optimization targets

| Signal | Where to look |
|---|---|
| Broadly elevated latency across all endpoints | Suspect **Dart event-loop contention** before the network. Profile with DevTools during the affected flow |
| One endpoint slow, others fine | Genuine — backend or payload. Check the `response_payload_size` dimension |
| Large `response_payload_size` | Trim payloads, paginate, enable compression server-side |
| Latency inflated on traffic from one client | Other interceptors on that `Dio` instance may be inside the window |
| Repeated identical patterns in one session | Missing caching or de-duplication in the data layer |
| Screen slow but requests fast | Decoding and rebuild, neither of which is in this metric |
| Latency correlated with `radio` = cellular | Expected; segment on the `radio` dimension before comparing |
| p95 implausibly low | Timeouts are missing entirely — see §2 |

## 5. Validation checks

Work the layers in order — package installation and call sites are visible in the codebase.

| Check | How | If it fires |
|---|---|---|
| No data at all | `apm_list_groups` returns no groups | Neither add-on package installed, or no call site uses it. If both are correct, it is the **account layer** or a first-run install |
| Partial coverage | Some endpoints present, others absent | Uninstrumented client instances. Enumerate every `Dio()` and `http.Client()` construction — this is the normal failure mode, not an edge case |
| No client failures | `failure_rate.client_side` is 0 or the `failure_name` dimension is empty | **Expected, and not healthy** — failed requests are dropped and failure detail is never populated. See §2. Do not read as a reliability signal |
| Latency looks too good | p95 implausibly low for the endpoint | Timeouts are missing from the distribution entirely |
| No stage detail | No `spans_table` row matches a stage | Expected on all Flutter traffic, unconditionally. Not a finding |
| Latency broadly high | | Dart event-loop contention, or other Dio interceptors inside the window |
| iOS native traffic absent | `cupertino_http` or native plugin requests missing | Native capture is disabled on iOS; nothing records these |
| Records stopped after an upgrade | | One of four independently versioned components moved — check the add-on package constraint against `instabug_flutter` |
| Data present, then stopped | | Possible account-level change; disabling removes stored data retroactively |
| Which client path produced the data | **Not in the metric data** | Read `pubspec.yaml` and the call sites: `InstabugHttpClient`, the Dio interceptor, or neither |
| Payload sizes look low on non-ASCII payloads | | Sizes are computed as UTF-16 code units, not bytes — see §6 |

## 6. What is available in APM

APM network records carry: URL, method, status, duration, payload **sizes**, content types, radio,
carrier, background flag, and custom attributes. **No stages, and no client failure detail.**

**Neither bodies nor headers are available.** Body and header content appears only in bug reports,
crashes, and Session Replay — a separate store on a separate access path.

Payload sizes are computed in Dart as **UTF-16 code units, not bytes**, so multi-byte payloads
under-report. `content-length` is preferred when the header is present. Keep this in mind before using
`request_payload_size` / `response_payload_size` for bandwidth arithmetic on non-ASCII payloads.

## 7. Privacy — the URL is the surface that matters

Because APM carries no bodies or headers, the **URL** is the only field in an APM network record that can
contain application data.

The native platform's auto-masking applies to query parameters and its coverage gaps carry over — read
the native file's privacy section, in particular that **URL path segments are never masked**.

For Dart-captured traffic the complete remedy is package-side:

```dart
NetworkLogger.obfuscateLog((data) async => data.copyWith(url: redact(data.url)));
NetworkLogger.omitLog((data) async => data.url.startsWith('https://internal.example.com'));
```

`omitLog` returning `true` **omits** the record. `NetworkData` fields are `final`, so use `copyWith`.

**Ordering matters:** `omitLog` runs first, then size-limit replacement, then `obfuscateLog` — so an
obfuscation callback cannot rely on seeing original content.

There is **no off switch for Dart-layer capture** short of removing the client or interceptor.

## 8. Distributed tracing and GraphQL

**Tracing:** both add-on packages inject a `traceparent` header before the request is sent when the
account has the capability enabled. Correlate with Datadog or New Relic on that header.

**GraphQL is not supported.** No operation-name extraction, no equivalent of the React Native GraphQL
header, no GraphQL failure classification. Every GraphQL request groups as an undifferentiated POST to one
`/graphql` pattern. If a customer needs per-operation visibility, the only routes are encoding the
operation name into the URL or using custom attributes.

## 9. Two hazards that surface as gaps rather than bad data

1. **A response arriving without a matching recorded request fails hard on the Dio path.** An earlier
   interceptor short-circuiting the chain, or a resolved cached response, can trigger it. Requests that
   never complete also leave state behind, accumulating over a long session. If a customer reports
   intermittent crashes in the network path or unexplained gaps, check interceptor ordering and whether
   any interceptor resolves responses without passing through `onRequest`.
2. **On Android, a record with a null status code is discarded silently.** A request completing without an
   HTTP status produces nothing at all.
