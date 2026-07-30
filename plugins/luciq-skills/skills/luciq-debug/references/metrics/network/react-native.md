# Network — React Native

Read `references/metrics/preamble.md` and `references/metrics/network/overview.md` first, then **also
read the native platform file** — `references/metrics/network/ios.md` or
`references/metrics/network/android.md`. This file is a supplement, never a replacement: the account
gating, the privacy model, and (in native interception mode) the stage anchors all come from the native
platform.

> **Verified against:** `instabug-reactnative` 16.0.4, pinning iOS SDK 16.0.3 and Android SDK 16.0.0.

## Version differences

The wrapper and the native SDKs version independently — a wrapper upgrade can change the pinned native
version and with it the platform behaviour. Read the wrapper version from `package.json`.

| Behaviour | Applies to | Effect |
|---|---|---|
| Pinned Android SDK is **16.0.0** | wrapper 16.0.4 | This is **before the 19.0.0 unified-interception change**. `network/android.md` documents 19.2.0, so its §1 coverage requirements and §2 anchors do **not** describe what this app runs. Treat that file's Android specifics as forward-looking here, and confirm anchors with Luciq support before reasoning about a pre-19.0.0 native path. |
| Pinned iOS SDK is 16.0.3 | wrapper 16.0.4 | Within `network/ios.md`'s verified range. |

## 1. Coverage

**Capture is automatic and happens in JavaScript.** `Instabug.init()` patches
`XMLHttpRequest.prototype`, which covers `fetch` and axios because both route through XHR in React
Native. No setup, no code changes.

| Traffic | Captured? |
|---|---|
| `fetch`, `XMLHttpRequest`, `axios` | Yes |
| Requests from native modules or third-party native networking libraries | **No** |
| WebSockets | **No** |

**Automatic capture does not mean data appears.** The JS layer forwards records to the native SDK, which
is still subject to account-level gating — so wrapper-side capture working and APM data existing are two
different things.

### Gating layers

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Wrapper** | JS API calls and `Instabug.init()` config | **Yes** — see §2 and §5 |
| **Build** (Android only) | The Luciq Gradle plugin | **Yes** — only matters for native interception mode |
| **Account** | Luciq server-side provisioning | **No** — ask Luciq support |
| **Runtime** | Native SDK APIs | Yes |

Account capabilities and their consequences are identical to the native platform — read that file's
gating section. The ones that bite hardest on React Native:

- **Network capture** — off by default. JS captures and forwards; nothing is stored.
- **Stage breakdown** — see §2; unavailable in the default mode regardless.
- **Native interception mode** — separately provisioned. When not enabled the SDK logs a line about
  disabling native interception to avoid data loss, and falls back to JS interception.

### Native interception mode

An alternative mode routes capture through the native SDK
(`networkInterceptionMode: NetworkInterceptionMode.native` in `Instabug.init()`):

- On Android it requires the Luciq Gradle plugin. Without it the SDK logs an error and falls back.
- The mode is re-evaluated when the app foregrounds, so **it can change mid-session**.
- The SDK logs which path it took — a line naming the Android plugin as detected and native interception
  as switched on, or a line naming it as absent and native interception as disabled. Ask the customer for
  their console output when the mode is in question; **the mode is not present in the metric data.**

## 2. How a request is measured

### The total duration

| Anchor | Event |
|---|---|
| **Start** | Inside the patched `XMLHttpRequest.send()`, **before the request is dispatched** |
| **End** | The XHR reaches `readyState === DONE` and the SDK's `readystatechange` handler runs on the JS thread |

Both timestamps are taken with `Date.now()` **on the JS thread**. That single fact drives everything
below.

| Inside the window | Outside the window |
|---|---|
| The native HTTP stack — connection, TLS, server time, download | Building the request or the `fetch` options |
| **JS thread contention** — time the `readystatechange` callback waits for a busy JS thread | The app's own `await response.json()` / `JSON.parse` |
| SDK pre-dispatch work, including a feature-flag check | Promise resolution back to the caller, React state updates and re-render |
| All redirects and retries | Anything in native modules |

**Two consequences, both important:**

- **The number conflates network time with JS thread health.** A blocked JS thread — a heavy render, a
  large synchronous parse, a long list diff — delays the completion callback and inflates the reported
  duration of every request in flight. **A latency regression on React Native is not necessarily a
  network regression.** Cross-check against JS thread frame rate (the `frame_drop` metric) or native
  platform data before concluding.
- **The window opens before dispatch**, so a small amount of SDK-side setup is included. It is largest on
  the first request of a session, when the feature-flag check is not yet warm.

**This is materially different from both native platforms.** iOS anchors at `URLSessionTask.resume()` and
Android before its HTTP interceptors, neither of which includes JS event-loop delay. So the same request
measured on React Native reads higher than the same request measured natively — never compare a wrapper
number against a native one.

### Stages

**There is no timing breakdown in the default JS interception mode.** Stages come from the native layer,
so they require native interception mode — and on Android that additionally requires the Gradle plugin,
and on both platforms the account capability.

Since JS mode is the default, most React Native apps have no DNS/TLS/server-processing decomposition at
all. Latency is the only signal, and it is the least precise of any platform.

When stages *are* present, read the native platform file for their anchors — they map onto
`okhttp3.EventListener` callbacks on Android and `URLSessionTaskTransactionMetrics` on iOS.

## 3. Optimization targets

| Signal | Where to look |
|---|---|
| Broadly elevated latency across all endpoints | Suspect **JS thread contention** before the network. Profile the JS thread during the affected flow |
| One endpoint slow, others fine | Genuine — backend or payload. Check the `response_payload_size` dimension |
| Large `response_payload_size` | Trim payloads, paginate, enable compression server-side |
| Repeated identical patterns in one session | Missing caching or request de-duplication in the data layer |
| Slow first request of a session | Partly SDK warm-up inside the window; discount it |
| Screen slow but requests fast | Response parsing and re-render, neither of which is in this metric |
| Latency correlated with `radio` = cellular | Expected; segment on the `radio` dimension before comparing |

## 4. Validation checks

Work the layers in order — wrapper config is visible in the codebase, so start there.

| Check | How | If it fires |
|---|---|---|
| No data at all | `apm_list_groups` returns no groups | Check for `NetworkLogger.setEnabled(false)` and for a filter expression (§5). If neither applies, it is the **account layer** or a first-run install — not fixable in code |
| Missing requests | `occurrences` below expected volume | Check `setRequestFilterExpression` (§5), then whether the traffic originates in native modules, which are never captured |
| Logging stopped entirely | Groups exist historically, then stop | A malformed filter expression breaks logging outright — see §5. Check this before the account layer |
| No stage detail anywhere | No `spans_table` row matches a stage, and occurrence rows carry none | **Expected in the default JS mode.** Needs native interception mode plus, on Android, the Gradle plugin, plus the account capability. Not a finding on its own |
| Dev-server traffic present | Patterns on `localhost:8081` | In DEV builds, traffic to the Metro port is excluded. If Metro runs on a non-default port the app must call `Instabug.setMetroDevServerPort(port)` |
| Duplicate records in bug reports | Same request twice, Android | Expected when the Gradle plugin is installed — APM data is de-duplicated, bug-report logs are not |
| Filter not matching as expected | Filter keys off `method`, duration, or sizes | In native interception mode those snapshot fields are empty, so the expression silently stops matching |
| Latency broadly high | | JS thread contention, not necessarily the network. See §2 |
| Record shape inconsistent within one session | Stage detail present on some records, absent on others | The interception mode is re-evaluated on foreground and can change mid-session |
| Which interception mode produced the data | **Not in the metric data** | Read `Instabug.init()` in the codebase, then confirm against the console log lines in §1. Stage detail present implies native mode; absent implies JS mode or an ungated account, which are not distinguishable from the data alone |

## 5. `setRequestFilterExpression` — three traps

```ts
NetworkLogger.setRequestFilterExpression('network.url.includes("/health")');
```

1. **It takes a string of JavaScript source, not a function.** Compiled and evaluated at runtime.
2. **Returning `true` omits the request.** The name suggests a filter that keeps matches; it does the
   opposite.
3. **A malformed expression breaks network logging entirely.** The compile and call happen outside the
   error-handling path, so a syntax or runtime error throws out of the XHR handler and logging stops. If
   records stopped appearing after a release, check this first.

For anything non-trivial prefer `setNetworkDataObfuscationHandler` — a real function — and drop records
by returning modified data rather than relying on the expression.

## 6. What is available in APM

APM network records carry: URL, method, status, duration, payload **sizes**, content types, error, radio,
carrier, background flag, and custom attributes. Stage detail only in native interception mode.

**Neither bodies nor headers are available.** Body and header content appears only in bug reports,
crashes, and Session Replay — a separate store on a separate access path.

**Client failure detail is coarse.** All JS-side client failures use one numeric code, with the domain
distinguishing only a generic client error from a timeout, and the domain may be overwritten by the
response text when it is descriptive. **Do not build a failure taxonomy on the `failure_name` dimension
here** — it is far less informative than either native platform's.

Timeouts and network failures **are** captured — unlike Flutter, which drops them. So
`failure_rate.client_side` is meaningful on React Native, subject to the coarseness above.

## 7. Privacy — the URL is the surface that matters

Because APM carries no bodies or headers, the **URL** is the only field in an APM network record that can
contain application data.

The native platform's auto-masking applies to query parameters and its coverage gaps carry over — read
the native file's privacy section, in particular that **URL path segments are never masked**.

For JS-captured traffic the complete remedy is wrapper-side:

```ts
NetworkLogger.setNetworkDataObfuscationHandler(async (data) => {
  data.url = redact(data.url);
  return data;
});
```

**Ordering matters:** the filter expression sees **raw, un-obfuscated** data, and the obfuscation handler
runs **before** size and content-type replacement. So the filter expression sees values the handler would
have removed.

## 8. Distributed tracing and GraphQL

**Tracing:** the SDK injects a `Traceparent` header when the account has the capability enabled, or
records an existing one. Correlate with Datadog or New Relic on that header.

**GraphQL requires wiring.** Operation names are not extracted automatically. For Apollo:

```ts
import { ApolloLink } from '@apollo/client';
import { apolloLinkRequestHandler } from 'instabug-reactnative';

const link = new ApolloLink(apolloLinkRequestHandler).concat(httpLink);
```

For non-Apollo clients, set the `ibg-graphql-header` request header to the operation name manually.
Without either, every GraphQL request groups as an undifferentiated POST to one `/graphql` pattern. This
is not covered in the SDK README — if a customer's GraphQL traffic is ungrouped, this is why.
