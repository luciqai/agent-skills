# App Launch — Flutter

Read `references/metrics/preamble.md` first, then **also read the native platform file** —
`references/metrics/app-launch/ios.md` or `references/metrics/app-launch/android.md`. This file is a
supplement, never a replacement: the Flutter plugin adds no launch timing of its own.

> **Verified against:** `instabug_flutter` 16.0.4, pinning iOS SDK 16.0.3 and Android SDK 16.0.0.
> The plugin and native SDKs version independently — a plugin upgrade can change the pinned native
> version and with it the behaviour described in the native files.

## Version differences

Read the plugin version from `pubspec.yaml` / `pubspec.lock` and the pinned native versions from
`Podfile.lock` and the Android build files. The pinned Android version above is substantially older than
the standalone Android SDK, so do not assume the standalone Android file's version header applies here.

No plugin-level behavioural differences are documented within the verified range.

## 0. Gating — what must be enabled

Two layers apply. Read the native platform file's gating section too; its account capabilities govern
this data.

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Account** | Luciq server-side provisioning | **No** — ask Luciq support |
| **Runtime** | `APM.setColdAppLaunchEnabled(bool)` | **Yes** |

There is no wrapper-level launch gating — unlike React Native, the Flutter plugin does not disable any
launch type, so `hot` and (on Android) `warm` groups can appear.

**`endAppLaunch()` needs an account capability** (per launch type, defaulting to off) *in addition* to
being called. Since it is the only way to bring Dart startup into the measurement, an unprovisioned
capability means the metric cannot be made meaningful for this app at all. If no `endAppLaunch` stage
appears while the code calls `APM.endAppLaunch()`, that is the cause — contact Luciq support rather than
changing code.

Note this compounds with the Android coverage constraint in §6: on Android, Flutter apps already have
reduced cold-launch coverage because the SDK can only start from Dart `main()`. An unprovisioned
`endAppLaunch()` capability on top of that leaves very little usable launch signal.

## 1. What is measured

**Launch is timed entirely by the native SDK.** The Flutter plugin takes no timestamps of its own for app
launch. Read the native platform file for the anchors, stages, and data characteristics that actually
govern this data — this file only covers what the Flutter layer adds or removes.

What that means for the window:

| Startup work | Inside the window? |
|---|---|
| Native process start, pre-`main` library loading (iOS) | Yes |
| `AppDelegate` / `MainActivity` setup | Yes |
| Flutter engine creation, Dart VM startup | Partially — whatever finishes before the native end anchor |
| **`main()` and `WidgetsFlutterBinding.ensureInitialized()`** | Platform-dependent; often at or after the boundary |
| **`runApp()` and the first widget build** | Usually no |
| **First Flutter frame on screen** | No |
| Async data fetch on the first route | No |

So a cold-launch total measures the **native shell coming up**. It says very little about Dart startup
cost.

**`APM.endAppLaunch()` is the only way to bring Dart startup into the measurement.** The plugin never
calls it for you. Wire it to a post-frame callback after the first meaningful route renders:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) => APM.endAppLaunch());
```

Without it, Dart optimizations will not move the metric and a regression in Dart startup will not appear
in this data.

`hot` and — on Android — `warm` groups can both appear; the Flutter plugin does not disable any launch
type.

## 2. Stages

No Flutter stages exist. Stage names and boundaries come from the native platform — see the native
platform file's §2.

The one stage the Flutter layer can influence is `endAppLaunch`, which spans from the native end anchor
to your `APM.endAppLaunch()` call. On a hybrid app this stage typically contains the entire Dart startup
path, which makes it the most actionable value in `stages_breakdown` when present.

## 3. Public API

```dart
import 'package:instabug_flutter/instabug_flutter.dart';

await APM.endAppLaunch();                    // ends the current launch at this moment
await APM.setColdAppLaunchEnabled(bool);     // toggles cold launch capture
```

The `endAppLaunch` doc comment mentions cold and hot launches. On Android, expect it to apply to a
session's cold launch only — see the Android file's §5.

No launch data is readable from Dart. There is no launch type or duration exposed to app code, unlike the
React Native SDK.

**Timestamp accuracy of `endAppLaunch()`.** The call crosses the Dart-to-host boundary asynchronously and
the recorded moment is when the native handler runs, not when Dart invoked it. Treat `endAppLaunch` as an
upper bound.

## 4. Validation checks to run before interpreting

| Check | How | If it fires |
|---|---|---|
| Dart startup not measured | No `endAppLaunch` stage in `stages_breakdown` | Grep for `endAppLaunch`. If absent from the code, do not attribute the total to Dart code, and recommend the post-frame callback above as the first action. If present, see §0 — the capability is unprovisioned. |
| Android cold coverage | Cold groups absent or with low `occurrences_count` on Android | Expected to some degree: the SDK can only start from Dart `main()`, which is late in Android's startup. Confirm the manifest has no `android:process` first, then treat reduced coverage as a platform constraint rather than a defect in the app. |
| First-route cost not visible | Grep for `InstabugCaptureScreenLoading`, `APM.wrapRoutes`, `InstabugNavigatorObserver` | If none are present, there is no Dart-timed measurement of the first route at all. Recommend adding one — see §5. |
| iOS stage coverage | `sceneConnect` and view-lifecycle stages absent | Expected on Flutter, because the SDK starts from Dart `main()`. The total is still valid; do not read the absence as a defect. |
| Native-side attribution | A native stage dominates `stages_breakdown` | Switch to the native platform file's optimization targets; the cause is not in Dart. |

Then run the native platform's validation table — it still applies in full.

## 5. Screen loading is the Dart-side proxy

Unlike app launch, Flutter's screen-loading metrics **are** timed in Dart, so they include widget build
and the first frame of a route. That makes the first route's screen-loading duration the best available
measurement of Flutter-side startup cost — query it with `metric: 'screen_loading'`.

```dart
// Wrap the first route
InstabugCaptureScreenLoading(screenName: 'Home', child: HomeScreen())

// Or wrap a route table
APM.wrapRoutes(routes);

// Plus the navigator observer
navigatorObservers: [InstabugNavigatorObserver()]

// Optionally mark the interactive moment for a screen
await APM.endScreenLoading();
```

**Use the two metrics together:** cold app launch for the native shell, first-route screen loading for
the Dart side. They are separate metrics measuring different spans — do not add them or treat one as a
subset of the other.

## 6. Data characteristics

**No wrapper-side launch timing.** The plugin has post-frame hooks, but they feed screen loading and
reproduction steps only — nothing routes into app launch.

**The SDK can only be initialized from Dart `main()`.** There is no native `AppDelegate` or `Application`
initialization helper, so unlike React Native this is a **structural constraint the customer cannot work
around**. On Android it depresses cold-launch coverage; on iOS it removes the scene and view-lifecycle
stages. Report it as a platform characteristic, not a misconfiguration.

**Screen-loading diagnostics are quieter on Android.** Disabled-state warnings are logged on iOS only, so
missing screen-loading data on Android may come with no diagnostic signal.

## 7. Getting a true Dart startup number

This SDK does not measure Dart startup. Use `flutter run --trace-startup`, DevTools timeline, or a profile
build. Then use `endAppLaunch()` so the same interval is visible in launch data.

Standard levers once you know the cost is on the Dart side: avoid heavy synchronous work in `main()`
before `runApp`, defer plugin registration and preference reads, precache only what the first frame
needs, use `const` constructors and a shallower initial widget tree, avoid large synchronous asset or
JSON decodes during startup, and move deserialization to an isolate.
