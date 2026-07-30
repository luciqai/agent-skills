# App Launch — React Native

Read `references/metrics/preamble.md` and `references/metrics/app-launch/overview.md` first, then
**also read the native platform file** —
`references/metrics/app-launch/ios.md` or `references/metrics/app-launch/android.md`. This file is a
supplement, never a replacement: the React Native layer adds no timing of its own.

> **Verified against:** `instabug-reactnative` 16.0.4, pinning iOS SDK 16.0.3 and Android SDK 16.0.0.
> The wrapper and native SDKs version independently — a wrapper upgrade can change the pinned native
> version and with it the behaviour described in the native files.

## Version differences

Read the wrapper version from `package.json` and the pinned native versions from `Podfile.lock` and the
Android build files. The pinned Android version above is substantially older than the standalone Android
SDK, so do not assume the standalone Android file's version header applies here.

No wrapper-level behavioural differences are documented within the verified range.

## 0. Gating — what must be enabled

Three layers apply. Read the native platform file's gating section too; its account capabilities govern
this data.

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Wrapper** | `Instabug.init()` config and JS API calls | **Yes** |
| **Account** | Luciq server-side provisioning | **No** — ask Luciq support |
| **Runtime** | Native SDK APIs | Yes |

Two things specific to React Native:

- **Hot launch is disabled by the wrapper** on both platforms, independently of any account setting.
  Expect zero `hot` launch groups regardless of provisioning.
- **`endAppLaunch()` needs an account capability** (per launch type, defaulting to off) *in addition* to
  being called. Since it is the only way to bring JS startup into the measurement, an unprovisioned
  capability means the metric cannot be made meaningful for this app at all. If no `endAppLaunch` stage
  appears while the code calls `APM.endAppLaunch()`, that is the cause — contact Luciq support rather
  than changing code.

## 1. What is measured

**Launch is timed entirely by the native SDK.** The React Native layer takes no timestamps of its own.
Read the native platform file for the anchors, stages, and data characteristics that actually govern
this data — this file only covers what the React Native layer adds or removes.

What that means for the window:

| Startup work | Inside the window? |
|---|---|
| Native process start, pre-`main` library loading (iOS) | Yes |
| `AppDelegate` / `MainApplication` setup | Yes |
| Bridge, TurboModule, or Hermes runtime creation | Partially — whatever finishes before the native end anchor |
| **JS bundle evaluation** | Usually no |
| **First React render, `componentDidMount`** | No |
| **First RN frame on screen** | No |
| Async data fetch on the first screen | No |

So a cold-launch total measures the **native shell coming up**. It says very little about JS startup
cost, which is where most React Native startup time goes.

**`APM.endAppLaunch()` is the only way to bring JS startup into the measurement.** Without it, JS
optimizations will not move the metric and a regression in JS startup will not appear in this data. Call
it at the app's real interactive moment — typically once the first screen has content, not in `App`'s
constructor.

**Only cold launches exist.** Hot launch capture is disabled in the React Native SDK on both platforms,
so expect no `hot` groups. On Android, `warm` groups can still appear.

## 2. Stages

No React Native stages exist. Stage names and boundaries come from the native platform — see the native
platform file's §2.

The one stage the React Native layer can influence is `endAppLaunch`, which spans from the native end
anchor to your `APM.endAppLaunch()` call. On a hybrid app this stage typically contains the entire JS
startup path, which makes it the most actionable value in `stages_breakdown` when present.

## 3. Public API

```ts
import { APM } from 'instabug-reactnative';

APM.endAppLaunch();                 // ends the current cold launch at this moment
APM.setAppLaunchEnabled(bool);      // toggles cold launch capture
```

Launch data is also readable from JS via the Session Replay sync callback:

```ts
SessionReplay.setSyncCallback((data) => {
  data.launchType;      // LaunchType.cold | warm | unknown
  data.launchDuration;  // microseconds
  return true;
});
```

`LaunchType` has no `hot` member, consistent with hot capture being disabled. Note that
`launchDuration` here is **microseconds** — the raw SDK unit — while the MCP surface reports
milliseconds.

**Timestamp accuracy of `endAppLaunch()`.** The call crosses the JS-to-native boundary asynchronously,
and the recorded moment is when the native call executes — not when JS invoked it. During startup the
main thread is contended, so the recorded end skews later than the JS moment. Treat `endAppLaunch` as an
upper bound and do not chase small deltas in it.

## 4. Validation checks to run before interpreting

| Check | How | If it fires |
|---|---|---|
| JS startup not measured | No `endAppLaunch` stage in `stages_breakdown` | Grep for `endAppLaunch`. If absent from the code, do not attribute the total to JS code, and recommend instrumenting it as the first action. If present, see §0 — the capability is unprovisioned. |
| Late SDK initialization | Find the `Instabug.init` call | If it is in a component body, `useEffect`, or `componentDidMount`, the SDK starts after the first React render. On Android this can suppress cold-launch capture entirely; on iOS it drops the scene and view-lifecycle stages. Check `AppDelegate` / `MainApplication` for a native init before concluding. |
| Missing native init | Grep `AppDelegate.mm` and `MainApplication.kt` for Instabug | If neither initializes the SDK, recommend `RNInstabug.initWithToken` (iOS) or `RNInstabug.Builder` (Android). This is the highest-value change for startup coverage on Android. |
| Unexpected launch types | A `hot` group appears in `apm_list_groups` | Unexpected — hot capture is disabled. Verify the wrapper version in `package.json` before interpreting. |
| Native-side attribution | A native stage dominates `stages_breakdown` | Switch to the native platform file's optimization targets; the cause is not in JS. |

Then run the native platform's validation table — it still applies in full.

## 5. Data characteristics

**No wrapper-side timing exists.** There is no bundle-load, `RCTContentDidAppear`, `ReactMarker`, or TTI
hook feeding launch data. Nothing in this data reflects JS execution unless `endAppLaunch()` is
instrumented.

**No screen-loading metric.** Unlike the Flutter SDK, the React Native SDK has no per-screen loading
API. Navigation listeners feed reproduction steps, not APM. The only JS-timed APM signals available are
manual UI traces (`APM.startUITrace` / `endUITrace`), App Flows, and network logging — and UI traces are
timed natively too.

**`warm` groups on Android** carry all the Android caveats, including configuration-change relaunches.
See the Android file's §5.

## 6. Getting a true JS startup number

This SDK does not measure JS startup. Use Hermes bundle profiling, `react-native-performance` or
`RCTContentDidAppear` markers, a Perfetto or Instruments trace, or an App Flow spanning the JS startup
path. Then use `endAppLaunch()` so the same interval is visible in launch data.

Standard levers once you know the cost is on the JS side: Hermes with precompiled bytecode, inline
requires, lazy `require` of heavy modules, reducing top-level module side effects, trimming the initial
component tree, deferring non-critical native module registration, and avoiding synchronous storage
reads during startup.
