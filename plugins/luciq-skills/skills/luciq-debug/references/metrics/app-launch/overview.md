# App Launch — all platforms

Read `references/metrics/preamble.md` first for units, aggregation rules, and the aggregates-not-records
model. Then read the platform file: `references/metrics/app-launch/<platform>.md`.

## The measured window

| Platform | Type | Starts at | Ends at |
|---|---|---|---|
| iOS | `cold` | Process creation | The **first** `applicationDidBecomeActive` of the process |
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
| Prewarmed launches include dormant idle time and inflate the tail; `cold` only, and **no field marks them** | iOS |
| Background-initiated cold starts can run for minutes; **no field marks them either** | iOS |
| Stage durations are self-time — work in nested stages is subtracted | iOS |
| Stages can sum to less than the total — the unattributed remainder is real work, often the largest contributor | iOS |
| No `warm` type exists — a suspended-then-resumed app reports as `hot` | iOS |
| `cold` does **not** start at process creation; earlier startup work is invisible | Android |
| `warm` includes configuration-change relaunches (rotation, theme, locale) | Android |
| Stages are disjoint and sum to the total | Android |
| **JS or Dart startup is outside the window** unless `endAppLaunch()` is instrumented; a cold total measures the native shell only | React Native, Flutter |
| No `hot` records exist — hot capture is disabled in this SDK | React Native |
| Reduced Android `cold` coverage is structural, not a misconfiguration | Flutter |

Launch types are **not comparable across platforms**: the same user-visible scenario can land in
different types, and cold totals begin at different points. Segment by platform before aggregating;
never compare a type across platforms.

## Capture is gated per account

APM, each launch type, the detailed stage breakdown (iOS), and **`endAppLaunch()` itself** are each
provisioned server-side and each default to off.

**`endAppLaunch()` is the important one.** It is the only way to make a launch total reflect
user-perceived startup — and if its capability is not provisioned, **the call is rejected and does
nothing**. So a missing `endAppLaunch` stage has two very different causes: the app never calls it
(fixable in code), or the capability is off (not fixable in code). **Read the codebase before
recommending either.**

Also: the first session after an install captures nothing, and disabling a launch type removes
already-stored records of that type.

## What the MCP returns for launch

| Source | What you get |
|---|---|
| `apm_list_groups(metric: 'launch')` | One row per launch group: `uuid`, `name`, `type`, `key_metric`, `threshold_ms`, `apdex_score`, `apdex_change`, `occurrences_count`, `latency_p50_ms`, `latency_p95_ms` |
| `apm_group_view(metric: 'launch')` | `summary`, `apdex_chart`, `throughput_chart`, `spans_table`, `dimensions`, `outliers`, `stages_breakdown`. Panels that don't apply come back in `ignored_views` |
| `apm_occurrence(metric: 'launch')` | Individual traces via `selector: worst \| by_token \| list`; launch-only filter `launch_latency_ms` |
| `app_insights` | App-level `cold_launches` / `hot_launches` apdex and p95 |

`dimensions` accepts `pattern_key` of `platform`, `app_version`, `device`, `os_version`,
`first_screen`, `experiment` for launch. `first_screen` is launch-specific and is the closest thing to
a per-launch screen name.

Launch is the **most restricted** metric on the list surface: only `date_ms`, `app_version`,
`platform`, `key_metric`, and `user_attributes` are permitted. `group_name`, `count`, `apdex`, and the
percentile filters are rejected at the schema boundary — filter after retrieval instead.

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
