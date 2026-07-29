# App Launch — iOS

Read `references/metrics/preamble.md` first. It carries the units, the aggregation rules, and what the
MCP actually returns for launch.

> **Verified against:** Luciq iOS SDK 16.x. §5 describes current limitations, several of which are
> expected to be fixed — treat it as the most version-sensitive section here.

## Version differences

Window boundaries and units change rarely but are not immutable. Read the app's SDK version from
`Podfile.lock` or the SPM resolution before relying on anything below.

| Behaviour | Applies to | Effect |
|---|---|---|
| Cold end anchor at the first `applicationDidBecomeActive` | 16.x | The anchor moved in a recent release. On an older SDK the window closed earlier, so cold totals are not comparable across that upgrade — confirm the boundary with Luciq support before reading a step change as a regression. |

**A limitation that has since been fixed will make you discount valid data.** If the app's version is
outside the verified range, say so rather than applying §5 as though it still holds.

## 0. Gating — what must be enabled

Launch capture is controlled at **two layers**. There is no build-time configuration.

| Layer | Controlled by | Visible in the codebase? |
|---|---|---|
| **Account** | Luciq server-side provisioning | **No** — ask Luciq support |
| **Runtime** | `LCQAPM.coldAppLaunchEnabled` / `hotAppLaunchEnabled` | **Yes** |

Account-provisioned capabilities, **each defaulting to off**:

| Capability | Effect when not enabled |
|---|---|
| APM | No launch data at all |
| Cold launch | No `cold` launch groups |
| Hot launch | No `hot` launch groups |
| **Detailed stage breakdown** | Only the two-stage form — `preMain` and `appStartup` |
| **`endAppLaunch()` — separately for cold and hot** | **The API call is rejected.** No `endAppLaunch` stage, and the total stays at time-to-activation |

> ⚠️ **`endAppLaunch()` requires its own account capability, separately for cold and hot.** This matters
> because instrumenting `endAppLaunch()` is the primary recommendation for making launch data reflect
> user-perceived startup — and the call is rejected if the capability is not provisioned. If no
> `endAppLaunch` stage appears **and** the code does call it, this is the cause, and it is not fixable
> in the app.

Three behaviours of the account layer:

- **Configuration arrives asynchronously.** The first run after install captures nothing — this is the
  mechanism behind the first-run gap in §5.
- **Disabling is retroactive** — turning a launch type off removes already-stored launches of that type.
- Capabilities may roll out gradually, so the same app version can behave differently across installs.

## 1. What is measured

| Type | Start anchor | End anchor |
|---|---|---|
| `cold` | Process creation | The **first** `applicationDidBecomeActive` of the process |
| `hot` | `applicationWillEnterForeground` | `applicationDidBecomeActive` |

**The window closes at activation, which is before the first frame is drawn.** UIKit and SwiftUI
consider the app active once the run loop is servicing it — view rendering, image decoding, and any
asynchronous first-screen loading happen *after* that point and are therefore **not** in the total.
Work inside your own `applicationDidBecomeActive(_:)` sits on the boundary: it runs after the
notification is posted, so it is largely excluded.

If a group has no `endAppLaunch` stage, do not treat its total as time-to-interactive. It is
time-to-activation. To measure the part users actually perceive, call `endAppLaunch()` at the app's
real interactive moment; the interval from activation to that call is then reported as the
`endAppLaunch` stage and added to the total.

There is **no warm launch on iOS.** A suspended-then-resumed app is reported as `hot`.

A hot launch is only recorded when the app genuinely entered the background first. Brief interruptions
that resign active without backgrounding — Control Center, a notification banner, an incoming call, an
app-switcher peek — produce no launch record. This is intended; do not read the absence as missing
data.

## 2. Stages

Stage durations come from `apm_group_view`'s `stages_breakdown` view, which returns a per-stage
breakdown plus a trend series. Match the stage names you receive against the boundaries below — that
mapping is the point of this section.

Every stage duration is **self-time**: work in nested stages is subtracted. Rank stages by self-time.
Where a stage contains others, a full-span figure may also be reported; use it only to understand
nesting, never to rank.

Cold launches report one of two stage sets. The detailed breakdown is an account capability; when it is
not enabled you receive only the two-stage form.

**Two-stage form** — `preMain` and `appStartup` are contiguous and together span process creation →
activation:

| Stage | Boundaries |
|---|---|
| `preMain` | Process creation → a point late in pre-`main()` initialization, after dynamic-library loading and most static initializers have run |
| `appStartup` | That point → `applicationDidBecomeActive` |

**Detailed form** — `appStartup` is not reported, and the stages **do not sum to the total**:

| Stage | Boundaries |
|---|---|
| `preMain` | Process creation → the same late pre-`main()` point |
| `appInit` | That point → `application(_:didFinishLaunchingWithOptions:)` completes |
| `sceneConnect` | Run loop begins processing the scene-connect event → `scene(_:willConnectTo:options:)` returns |
| `viewDidLoad` | First view controller's `viewDidLoad` |
| `viewWillAppear` | First view controller's `viewWillAppear` |
| `viewDidAppear` | First view controller's `viewDidAppear` |

**The unattributed remainder.** In the detailed form, no stage covers
`didFinishLaunching → applicationDidBecomeActive` beyond `sceneConnect` and the three view-lifecycle
stages. Root view-controller construction, view-hierarchy building, autolayout, the first render pass,
and `didBecomeActive` observers all fall into an unnamed remainder. Compute it as
`total − Σ(stage self-times)`. It is frequently the largest single contributor and is a legitimate
optimization target even though no stage names it.

**`endAppLaunch` — both forms.** Independent of the stage-breakdown capability: whenever the app calls
`endAppLaunch()` after the automatic launch end, that stage is appended and the total extends to the
call. Boundaries: automatic launch end → the call. Include it before comparing a two-stage group's
stages against its total — the two automatic stages alone stop at activation.

**Hot launches** report one automatic stage, `appStartup`, spanning the whole foreground-to-active
window. No breakdown is available; `endAppLaunch` applies as described above.

## 3. Optimization targets by stage

| Stage | Where to look in the codebase |
|---|---|
| `preMain` | Build configuration, not app logic: dynamic-library count, ObjC `+load` methods, C++ static initializers (`__attribute__((constructor))`), ObjC category count, binary size. Consolidate dylibs; convert `+load` work to lazy initialization. |
| `appStartup` / `appInit` | `application(_:didFinishLaunchingWithOptions:)`: third-party SDK initialization, keychain and `UserDefaults` access, Core Data / SwiftData stack setup, synchronous remote-config fetches, appearance-proxy configuration. |
| `sceneConnect` | `scene(_:willConnectTo:options:)`: window and root view-controller construction, storyboard instantiation, nib loading. |
| `viewDidLoad` / `viewWillAppear` / `viewDidAppear` | The first view controller's lifecycle bodies: synchronous network or disk fetches, heavy layout, image decoding, attributed-string construction. |
| Unattributed remainder | Root view hierarchy construction, autolayout solving, the first render pass, work triggered from `didBecomeActive` observers. |
| `endAppLaunch` | Whatever the app does after iOS considers it active: feature-flag resolution, first-screen data fetch, splash dismissal, and on hybrid apps the JS or Dart startup path. |

## 4. Validation checks to run before interpreting

Each check uses data the MCP returns plus the customer's codebase. Run them before drawing any
conclusion.

| Check | How | If it fires |
|---|---|---|
| Total is not time-to-interactive | No `endAppLaunch` stage in `stages_breakdown` | Grep for `endAppLaunch`. **Absent from the code** → recommend instrumenting it before optimizing anything post-activation. **Present in the code** → the account capability is not provisioned (§0); the fix is with Luciq support, not a code change. |
| Tail contamination | `latency_p95_ms` far above `latency_p50_ms`, or `outliers` dominated by multi-second values | Prewarmed and background-initiated launches are indistinguishable in this data and can run for minutes. Do not call it a regression on p95 alone — check `latency_p50_ms` and inspect `outliers`, and look for background entry points (`didReceiveRemoteNotification`, `performFetchWithCompletionHandler`, `BGTaskScheduler`). |
| Premature end call | Stage sum in `stages_breakdown` exceeds the group total | `endAppLaunch()` runs before activation. Reliable only in the two-stage form: in the detailed form the unattributed remainder absorbs the shortfall, so absence of this signal does not clear the call site — read it in the codebase instead. Locate and move it; treat the affected group as unreliable. |
| Unattributed remainder | `total − Σ(stage self-times)` on detailed groups | Expected, and often dominant. Attribute it to root view-controller construction, autolayout, and the first render pass — inspect `SceneDelegate`, the root VC's `loadView`/`viewDidLoad`, and `didBecomeActive` observers. |
| Breakdown unavailable | `appStartup` present, or `stages_breakdown` in `ignored_views` | Only coarse attribution is possible. Say so rather than over-reading two stages. |
| Late SDK initialization | `sceneConnect` and the view-lifecycle stages absent while `appInit` is present | Find where the SDK is started. Stage coverage is partial; the total is still valid. |
| SwiftUI first screen | View-lifecycle stages absent while `sceneConnect` is present | Expected — hosting controllers are not instrumented. Do not report as missing data; attribute that time to the remainder. |
| Missing screen name | `first_screen` absent in `dimensions` | Likely a name over 60 characters — common for SwiftUI hosting controllers. Do not infer the screen was unidentifiable. |
| Placeholder screen name | An `N/A` bucket in the `first_screen` `dimensions` breakdown | Hot-only fallback when nothing resolved. Exclude it from screen-level conclusions; it is not a real screen. |
| Cross-type screen grouping | Grouping on `first_screen` across `cold` and `hot` groups | Invalid — the two types resolve names differently. Segment by `type` first. |
| Apdex target misconfigured | `threshold_ms` below `50th_percentile_ms` | A low or falling `apdex_score` is a target-config problem, not a code defect. Weigh the target against what a launch should plausibly cost before attributing it to code. |

## 5. Data characteristics that affect interpretation

Each entry states an observable property and the action to take. Where the platform provides no
distinguishing field, that is called out so you can filter instead of guess.

**Prewarmed launches.** iOS 15 and later may create the process ahead of the user opening the app. The
duration then includes the idle interval, which can be minutes. **No field distinguishes these**, so
they surface only as tail inflation — treat p95 and `outliers` accordingly.

**Background-initiated starts.** A cold launch can be triggered by background work — silent push,
background fetch, a scheduled background task. The window remains open until the user actually opens
the app, so the duration can be arbitrarily long. **No field distinguishes these either.** A cold
launch above roughly 30 seconds on a modern device is almost certainly prewarmed or
background-initiated rather than slow.

**Durations are unclamped.** No upper bound is applied. Use percentiles, not means.

**First run after install.** Cold launch data is not available on an app's very first run after
installation, so cold-launch volume sits slightly below session volume for this reason alone.

**Late SDK initialization.** If the SDK is started later in the launch sequence, the total remains
correct but `sceneConnect` and the three view-lifecycle stages will be **absent**, and `first_screen`
will reflect the view controller present at SDK-start time rather than the true first screen. If a cold
group carries only `preMain` and `appInit` while the total is large, verify where the SDK is
initialized before drawing conclusions about the missing stages.

**Missing screen name.** Screen names longer than 60 characters are omitted rather than truncated, so
`first_screen` may be absent. This is common in SwiftUI apps, where the resolved name is a long generic
hosting-controller type.

**Screen names are not comparable between cold and hot.** Cold launches always name the resolved UIKit
view-controller class, with no fallbacks. Hot launches prefer an app-supplied name where one has been
set — a SwiftUI name appears only where the app explicitly tagged that view — and otherwise fall back
through a web-view composite, the view-controller class, the window class, and finally the literal
`N/A`. There is no automatic SwiftUI type resolution on either path. Do not group across the two types
on `first_screen`.

**SwiftUI lifecycle apps.** The total, `preMain`, `appStartup`, and `appInit` are all valid, but
`appInit` is largely framework time you do not control, and the three view-lifecycle stages are
normally **absent**: hosting controllers are not instrumented, so no view-lifecycle stage is recorded
for them. Do not read that absence as missing data. The time those stages would have covered falls into
the unattributed remainder, which is correspondingly larger in these apps — optimize against the
remainder rather than waiting for stages that will not arrive. Where the three stages do appear, the
first screen resolved to a UIKit view controller rather than a hosting controller, and they measure
that controller's UIKit lifecycle, never SwiftUI `body` evaluation.

**Multiple windows and scenes.** Only the first scene of a launch is measured. Opening an additional
window produces no launch record, and there is no per-scene breakdown.

**App extensions are not instrumented.** No launch data is produced from them.

**Reduced cold-launch coverage from asynchronous root setup.** A cold launch is not recorded if no view
controller is resolvable at the moment the launch completes. Apps that construct their root view
controller asynchronously may see cold-launch volume below expectation.

**`endAppLaunch()` called too early.** If the call happens before `applicationDidBecomeActive`, the
total ends at your earlier timestamp, no `endAppLaunch` stage is emitted, and the remaining stages were
measured against the later automatic end. In the two-stage form that shows as **a stage sum larger than
the total**; in the detailed form the unattributed remainder absorbs the shortfall and the group looks
normal. Verify the call site rather than the arithmetic; move it, and treat affected data as unreliable.
A zero-valued `endAppLaunch` stage is a different, harmless case: the call landed at effectively the
same instant as the automatic end, so it measured nothing and the total is still time-to-activation.

**`endAppLaunch()` is honoured once per launch.** Repeat calls within the same launch are ignored.

## 6. Getting a true first-frame number

The SDK does not measure time to first frame. For that, use MetricKit's `MXAppLaunchDiagnostic` or an
Xcode Instruments App Launch trace, and treat the SDK's total as a complementary signal covering
process creation through activation.
