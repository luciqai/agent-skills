# App Launch — Android

Read `references/metrics/preamble.md` first. It carries the units, the aggregation rules, and what the
MCP actually returns for launch.

> **Verified against:** Luciq Android SDK 19.2.0. §5 describes current limitations, several of which are
> expected to be fixed — treat it as the most version-sensitive section here.

## Version differences

No behavioural differences are documented within the verified version range — the facts below apply to
the version in the header. Read the app's SDK version from `build.gradle` / `build.gradle.kts` before
relying on §5, and if it falls outside the verified range, say so rather than applying those
limitations as though they still hold. **A limitation that has since been fixed will make you discount
valid data.**

Note for hybrid apps: React Native and Flutter pin their own native SDK versions, which can be
substantially older than the standalone version above. Check the pinned version rather than assuming.

## 0. Gating — what must be enabled

Launch capture is controlled at **two layers**. There is no build-time configuration.

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Account** | Luciq server-side provisioning | **No** — ask Luciq support |
| **Runtime** | `APM.setCold/Warm/HotAppLaunchEnabled(boolean)` | **Yes** |

Account-provisioned capabilities, **each defaulting to off**:

| Capability | Effect when not enabled |
|---|---|
| APM | No launch data at all |
| Cold launch | No `cold` launch groups |
| Warm launch | No `warm` launch groups |
| Hot launch | No `hot` launch groups |
| **`endAppLaunch()` — per launch type** | **The API call is rejected.** No `endAppLaunch` stage, and the total stays at time-to-resume |

> ⚠️ **`endAppLaunch()` requires its own account capability, separately per launch type.** This matters
> because instrumenting `endAppLaunch()` is the primary recommendation for making launch data reflect
> user-perceived startup — and the call silently does nothing if the capability is not provisioned. If
> no `endAppLaunch` stage appears **and** the code does call `APM.endAppLaunch()`, this is the cause,
> and it is not fixable in the app.

Three behaviours of the account layer:

- **Configuration arrives asynchronously.** The first run after install captures nothing.
- **Disabling is retroactive** — turning a launch type off removes already-stored launches of that type.
  "It was there yesterday" can be an account change.
- Capabilities may roll out gradually, so the same app version can behave differently across installs.

## 1. What is measured

| Type | Start anchor | End anchor |
|---|---|---|
| `cold` | Early in process startup, before `Application.onCreate` | First `Activity.onResume` |
| `warm` | First `Activity.onCreate` | `Activity.onResume` |
| `hot` | First `Activity.onStart` | `Activity.onResume` |

**Cold launch does not begin at process creation.** It begins when the SDK initializes, which is before
`Application.onCreate` but after the process has been created and classes loaded. Work preceding that
point — process fork, `Application` class loading, `attachBaseContext`, and other libraries' automatic
initializers that run earlier — is **outside** the measurement. Cold totals therefore under-report true
time-to-display by that margin. Use Macrobenchmark or `am start -W` if you need the full span.

**The window closes at `Activity.onResume`, which is before the first frame is drawn.** View
measure/layout/draw, the first frame, Compose's first composition, RecyclerView's first bind pass, image
decoding, and any asynchronous first-screen loading all happen after that point and are **not** in the
total.

One useful asymmetry with iOS: your own `Activity.onResume()` body runs to completion *before* the
framework reports the activity as resumed, so **code in `onResume()` is inside the window.** Code in a
`post()` or coroutine launched from `onResume()` generally is not.

If a group has no `endAppLaunch` stage, do not treat its total as time-to-interactive. It is
time-to-resume. To measure the part users actually perceive, call `APM.endAppLaunch()` at the app's real
interactive moment; the interval from `onResume` to that call is then reported as the `endAppLaunch`
stage and added to the total.

Android reports all three launch types. iOS has no `warm` — it classifies the same situation as `hot` —
so do not compare launch-type volumes or durations across platforms.

## 2. Stages

Stage durations come from `apm_group_view`'s `stages_breakdown` view. Match the stage names you receive
against the boundaries below — that mapping is the point of this section.

Stages are disjoint and **sum to the total**. There is no nesting and no self-versus-total distinction,
unlike iOS.

| Stage | Boundaries | Present for |
|---|---|---|
| `applicationInit` | SDK initialization point → first `Activity.onCreate` | `cold` |
| `activityCreate` | First `Activity.onCreate` → first `Activity.onStart` | `cold`, `warm` |
| `activityStart` | `Activity.onStart` → `Activity.onResume` | `cold`, `warm`, `hot` |
| `endAppLaunch` | `Activity.onResume` → your `endAppLaunch()` call | any, opt-in |

Totals by type:

- `cold` — start of `applicationInit` through end of `activityStart`
- `warm` — start of `activityCreate` through end of `activityStart`
- `hot` — `activityStart` alone (`onStart` → `onResume`), normally near-zero unless work happens in
  `onStart` or `onResume`

There is no separate stage for `Application.onCreate` itself; its cost is contained within
`applicationInit`.

## 3. Optimization targets by stage

| Stage | Where to look in the codebase |
|---|---|
| `applicationInit` | `Application.onCreate`; dependency-injection graph construction (Hilt, Dagger, Koin); third-party SDK initialization; `System.loadLibrary`; main-thread `SharedPreferences`, file, or database reads; `WorkManager` initialization; any AndroidX Startup initializer or `ContentProvider` that runs after ours. |
| `activityCreate` | The launcher `Activity.onCreate`: `setContentView` and layout inflation depth, view binding, splash-screen setup, synchronous data loads, initial `Fragment` transactions, `WorkManager` enqueues. |
| `activityStart` | `onStart` bodies, `ProcessLifecycleOwner` and `LifecycleEventObserver` callbacks, `onRestoreInstanceState`, `BroadcastReceiver` registration. |
| `endAppLaunch` | Everything after the framework considers the activity resumed: first frame and Compose first composition, feature-flag resolution, first-screen data fetch, splash dismissal, and on hybrid apps the JS or Dart startup path. |

## 4. Validation checks to run before interpreting

Each check uses data the MCP returns plus the customer's codebase. Run them before drawing any
conclusion.

| Check | How | If it fires |
|---|---|---|
| Missing cold launches | No `cold` group in `apm_list_groups`, or `app_insights` shows no cold data, while warm/hot are present | Grep the manifest for `android:process` on `<application>` or on the launcher activity. If found, cold data is absent by design — report an instrumentation finding, not a performance one. Then check §0 gating. |
| Implausible cold coverage | Cold `occurrences_count` far below expectation relative to app usage | Check for background entry points (FCM `onMessageReceived`, `WorkManager`, `BroadcastReceiver`, widget providers). Those starts are classified `warm`, not `cold`. |
| Warm volume inflated | Warm `occurrences_count` substantially exceeds cold | Check whether the app allows rotation and does not declare `configChanges`. Each configuration change fabricates a warm record. Discount before treating warm counts as launches. |
| Total is not time-to-interactive | No `endAppLaunch` stage in `stages_breakdown` | Grep for `endAppLaunch`. **Absent from the code** → recommend instrumenting it. **Present in the code** → the account capability is not provisioned (§0); recommend contacting Luciq support, not a code change. |
| Unmeasurable end call | `endAppLaunch` stage present but zero | Locate the `endAppLaunch()` call site; it runs too early to measure an interval. |
| Stage sum mismatch | Stage sum in `stages_breakdown` ≠ the group total, excluding `endAppLaunch` | Unexpected on Android — stages are disjoint and should sum. Treat the data as suspect rather than reasoning over the difference. |
| Pre-SDK window | Always, for `cold` | Read `Application.attachBaseContext`, the `Application` constructor, and any `ContentProvider` or AndroidX Startup initializer. Cost there is real but invisible to this metric. |
| Hot outliers | Hot `latency_p95_ms` far above its own `latency_p50_ms` | Hot is normally near-zero. Verify against a second signal before calling it a regression. |
| Apdex target misconfigured | `threshold_ms` below `50th_percentile_ms` | A low or falling `apdex_score` is a target-config problem, not a code defect. Weigh the target against what a launch should plausibly cost before attributing it to code. |

## 5. Data characteristics that affect interpretation

Each entry states an observable property and the action to take. Where the platform provides no
distinguishing field, that is called out so you can filter instead of guess.

**Cold launches are not reported when the main process is renamed.** If `android:process` is set on the
`<application>` element, or the launcher activity runs in a named process, no cold launch is recorded
for that app — only `warm` and `hot` appear. Check the manifest first if cold volume is zero or near
zero; this is an instrumentation condition, not a performance finding.

**Activities in secondary processes do not report cold launches.** Only the app's default process
produces them.

**First run after install.** Cold launch data is not available on an app's very first run after
installation.

**Background-initiated process starts are classified `warm`, not `cold`.** When the process is started
by an FCM data message, `WorkManager` or `JobService`, a `BroadcastReceiver`, or a widget update, and the
user opens the app afterwards, the resulting record is `warm`. The duration is *not* inflated by the
waiting interval — it begins at `Activity.onCreate` — so the value is usable. But cold-launch volume
under-counts for apps with frequent background wake-ups, and warm volume is correspondingly inflated.

**Configuration changes produce `warm` launch records.** Rotation, dark-mode toggles, locale changes,
and font-scale changes each recreate the activity and are recorded as a warm launch. Warm volume
therefore does not correspond to user-initiated app starts. **Discount warm-launch counts by the app's
configuration-change rate before treating them as launches**, and be skeptical of warm-launch trends in
apps that support rotation.

**Durations are unclamped.** No upper bound is applied. Use percentiles, not means.

**Hot-launch outliers.** Hot durations are normally near-zero. Occasional large values occur when a
foreground transition spans more than one activity. Verify against a second signal before treating one
as a regression.

**Splash-then-redirect flows.** If a splash activity reaches `onResume`, the cold launch ends there and
the real first screen is never measured. The reported `first_screen` may name either the splash or the
activity that follows it, so it is not stable across records for this pattern. This is the canonical
case for `endAppLaunch()`.

**Launch-mode effects on classification.** With `singleTask`, `singleInstance`, or
`FLAG_ACTIVITY_REORDER_TO_FRONT`, a target activity that is not recreated produces a `hot` record rather
than `warm`. Launch mode is not otherwise reflected in the data.

**Deep links, notification taps, and launcher shortcuts are indistinguishable from icon launches.** No
field identifies the launch cause, and `first_screen` is whichever activity resumes first. If you need
to compare startup cost by entry point, instrument it yourself with App Flows.

**`endAppLaunch()` is reliable for a session's cold launch only.** Once a session contains more than one
launch record — a cold launch followed by a hot launch, for example — later calls are not applied.
Instrument the call for cold launch and do not expect `endAppLaunch` stages on hot or warm records.
Within a single launch, only the first call is honoured.

**`endAppLaunch` of exactly zero** means the call site runs too early to measure any interval. Move it
later in the startup path.

**`first_screen` values are fully-qualified activity class names** and are not truncated or omitted for
length — unlike iOS.

## 6. Getting a true first-frame number

The SDK does not measure time to first frame or fully-drawn. For those, use Macrobenchmark's
`StartupTimingMetric` (which reports timeToInitialDisplay and timeToFullDisplay), `am start -W`, or a
Perfetto trace. Treat the SDK's total as a complementary signal covering SDK initialization through
activity resume, and use `reportFullyDrawn()` in your app to make the fully-drawn metric meaningful.
