# Interpreting Luciq APM metric data

Read this before interpreting any APM duration, then read the per-metric platform file:
`references/metrics/<metric>/<platform>.md`.

## Units and aggregation — every metric

- **Latencies in the MCP surface are milliseconds** (`latency_p50_ms`, `latency_p95_ms`,
  `threshold_ms`). The SDK measures in microseconds; the API divides by 1000 before returning. Never
  mix the two.
- **Read `latency_p50_ms` and `latency_p95_ms` together, and never average either across groups or
  versions.** The API returns percentiles, already computed — a percentile of percentiles is not a
  percentile. A flat p50 with a moved p95 is a tail problem, one slow cohort or dependency, not a
  uniform slowdown. Durations are unclamped, so that tail can be arbitrarily long.
- **`threshold_ms` is the group's configured apdex target, not a measurement.** If it sits below
  `50th_percentile_ms`, more than half of otherwise-healthy occurrences score unsatisfied, so a low or
  falling apdex is a target-configuration problem rather than a code defect. Check it before
  attributing an apdex change to code.
- **Absent means unavailable, not zero.** A field the SDK could not resolve is omitted rather than
  sent as a sentinel. Do not read an absent value as a measurement of zero.
- **You hold three inputs the server cannot combine for you**: the metric data, this guidance, and the
  customer's source code. Several checks below are answerable only by reading the codebase — do that
  rather than inferring from numbers alone.

---

# App Launch

## The measured window

| Platform | Type | Starts at | Ends at |
|---|---|---|---|
| iOS | `cold` | Process creation | First `applicationDidBecomeActive` |
| iOS | `hot` | `applicationWillEnterForeground` | `applicationDidBecomeActive` |
| Android | `cold` | SDK init, before `Application.onCreate` | First `Activity.onResume` |
| Android | `warm` | First `Activity.onCreate` | `Activity.onResume` |
| Android | `hot` | First `Activity.onStart` | `Activity.onResume` |

**The window closes before the first frame is drawn.** View rendering, image decoding, Compose's
first composition, and any async first-screen loading happen after the end anchor and are **not** in
the total. `endAppLaunch()` extends the window to a point you choose, reported as an `endAppLaunch`
stage. **Without that stage, a total is time-to-activation or time-to-resume — not
time-to-interactive.**

Two anchor details that decide where to look in code: on Android your own `Activity.onResume()` body
runs *inside* the window; on iOS your `applicationDidBecomeActive(_:)` body runs *after* the anchor
and is largely outside it.

## Platform facts you must apply

| Fact | Applies to |
|---|---|
| Prewarmed launches include dormant idle time and inflate the tail; **no field marks them** | iOS |
| Background-initiated cold starts can run for minutes; **no field marks them either** | iOS |
| Stage durations are self-time — work in nested stages is subtracted | iOS |
| No `warm` type exists — a suspended-then-resumed app reports as `hot` | iOS |
| `cold` does **not** start at process creation; earlier startup work is invisible | Android |
| `warm` includes configuration-change relaunches (rotation, theme, locale) | Android |
| Stages are disjoint and sum to the total | Android |
| **JS or Dart startup is outside the window** unless `endAppLaunch()` is instrumented; a cold total measures the native shell only | React Native, Flutter |
| No `hot` records exist — hot capture is disabled in this SDK | React Native |
| Reduced Android `cold` coverage is structural, not a misconfiguration | Flutter |

Launch types are **not comparable across platforms**: Android reports as `warm` what iOS reports as
`hot`, and cold totals begin at different points. Segment by platform before aggregating.

## Capture is gated per account

Launch capture is provisioned server-side, independently of anything in the codebase. APM, each launch
type, the detailed stage breakdown (iOS), and **`endAppLaunch()` itself** are each provisioned and each
default to off.

**`endAppLaunch()` is the important one.** It is the only way to make a launch total reflect
user-perceived startup — and if its capability is not provisioned, **the call is rejected and does
nothing**. So a missing `endAppLaunch` stage has two very different causes: the app never calls it
(fixable in code), or the capability is off (not fixable in code). **Read the codebase before
recommending either.**

Also: the first session after an install captures nothing, and disabling a launch type removes
already-stored records of that type — so "it was there yesterday" can be an account change rather than
a code change.

## What the MCP actually returns for launch

The tools return **aggregates, not individual launch records**. Plan every check around that.

| Source | What you get |
|---|---|
| `apm_list_groups(metric: 'launch')` | One row per launch group: `uuid`, `name`, `type`, `key_metric`, `threshold_ms`, `apdex_score`, `apdex_change`, `occurrences_count`, `latency_p50_ms`, `latency_p95_ms` |
| `apm_group_view(metric: 'launch')` | `summary`, `apdex_chart`, `throughput_chart`, `spans_table`, `dimensions`, `outliers`, `stages_breakdown`. Panels that don't apply come back in `ignored_views` |
| `apm_occurrence(metric: 'launch')` | Individual traces via `selector: worst \| by_token \| list`; launch-only filter `launch_latency_ms` |
| `app_insights` | App-level `cold_launches` / `hot_launches` apdex and p95 |

`dimensions` accepts `pattern_key` of `platform`, `app_version`, `device`, `os_version`,
`first_screen`, `experiment` for launch. `first_screen` is launch-specific and is the closest thing to
a per-launch screen name.

There is **no** per-response metadata block, no launch-type census, no session count, and no SDK
version in the payload. Where a check below needs the SDK version, read it from the project
(`Podfile.lock`, `build.gradle`, `package.json`, `pubspec.yaml`).

## Before interpreting — run in order

1. **Read the platform file** for this app: `references/metrics/app-launch/<platform>.md`. It carries
   the stage boundaries, the account-gating detail, per-stage optimization targets, and the conditions
   under which the data misleads. On React Native or Flutter, read the wrapper file **and** the native
   file it names.
2. **Establish which launch types exist.** Compare `type` across `apm_list_groups` rows, or use
   `app_insights`'s `cold_launches` / `hot_launches`. An absent type is a gating or platform condition,
   not a fast launch.
3. **Check for an `endAppLaunch` stage** in `apm_group_view`'s `stages_breakdown`. If no group has one,
   no total here reaches time-to-interactive. Then grep the codebase: if the call is absent, recommend
   instrumenting it; if it is present, the account capability is unprovisioned and the fix is with
   Luciq support, not the app.
4. **Treat the tail as contaminated until proven otherwise.** On iOS, prewarmed and
   background-initiated launches are indistinguishable in the data and can each run for minutes. Use
   `latency_p50_ms` and the `outliers` view to separate a genuine regression from tail contamination;
   never quote a mean.
5. **If Android `cold` is absent or implausibly rare**, check the manifest for `android:process` —
   **unless the app is Flutter**, where reduced cold coverage is expected and structural.
6. **Discount Android `warm`** by the app's configuration-change rate before treating warm counts as
   user-initiated launches.
7. **Localize before concluding.** Run `dimensions` on `app_version`, `os_version`, and `device`. A
   change confined to one cohort has a different cause than one uniform across all of them.
