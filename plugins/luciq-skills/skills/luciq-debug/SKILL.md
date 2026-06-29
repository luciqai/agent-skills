---
name: luciq-debug
description: Use when the user wants to investigate a Luciq production signal end to end, propose a code fix, or answer "why is this happening". Triggers include pasting a crash ID, fingerprint, or stack trace; mentioning a Luciq bug number, hang, or ANR; asking "what broke since version X"; flagging a rating drop or review spike; or asking why a session crashed, hung, or terminated. Also covers APM performance signals across all metrics — a slow endpoint, latency/p95 spike, apdex drop, network failure-rate spike, slow app launch, UI jank (frozen / slow frames), slow screen loading, user-flow drop-off, a throughput change, a bottleneck, or "what got slower/flakier since version X". Pulls evidence via the Luciq MCP server, maps it to local source, forms an evidence-cited hypothesis.
---

# Luciq Production Debugging

Investigate a Luciq production signal end to end. Default to evidence-based reasoning. Cite the MCP tool result that supports each claim. If a query returns nothing, surface that fact instead of filling in plausible-looking guesses.

## When NOT to use this skill

- First-time SDK install or wiring `Luciq.start(...)`, use `luciq-setup`.
- Renaming Instabug symbols to Luciq, or upgrading between Luciq SDK versions, use `luciq-migrate`.
- General mobile debugging where Luciq is not the data source. This skill is grounded in what the Luciq MCP exposes; without that, do not pretend to use it.

If the user's request fits any of the above, STOP and route them to the right skill rather than running this one.

## Prerequisites

The Luciq MCP server must be configured and authenticated. If MCP tools are not available, STOP and direct the user to https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide for setup, or run `luciq-setup` to wire it.

The MCP exposes (verbatim names):

| Tool | Purpose |
| --- | --- |
| `list_applications` | List apps and their tokens for the authenticated user. |
| `list_crashes` | List crash groups with filters (version, OS, date range). |
| `crash_details` | Full details for a crash group: top frames, occurrence sample, distributions. |
| `crash_patterns` | Distribution by `pattern_key` (e.g. `oses`, `app_versions`, `devices`). |
| `list_occurrences_tokens` | Occurrence ULIDs for a crash group, paginated. |
| `get_occurrence_details` | Per-occurrence detail: session profiler, logs URLs, device state. |
| `list_app_hangs` | Hang and ANR groups. iOS surface as `FATAL_UI_HANG`, Android as `ANDROID_FATAL_HANG`. |
| `list_bugs` | User-reported bugs. |
| `bug_details` | Full bug detail including compressed log archive URLs. |
| `list_reviews` | App Store / Play Store reviews filtered by `rating` and `app_version`. |
| `apm_list_groups` | Rank APM groups worst-first for a `metric`. Sort `by` `apdex`/`apdex_change`/`occurrences`/`dissat_count` (all metrics), `p95`/`p50` (all but `frame_drop`), `failure_rate` (network), `frozen_frames_percent`/`slow_frames_percent` (`frame_drop`). |
| `apm_group_view` | Per-group panels for a `metric`: `summary`, `apdex_chart`, `throughput_chart`, `spans_table`, `dimensions` (all); `outliers` (all but `frame_drop`); plus metric-specific `failure_rate`, `stages_breakdown`, `web_vitals`, `frames_distribution`, `delayed_frames`. Inapplicable views return in `ignored_views`. |
| `apm_occurrence` | Per-occurrence detail by `selector: worst \| by_token \| list`. |

YOU MUST cite which of these produced any piece of evidence in your hypothesis. Do not invent capabilities the MCP does not expose. See "Out of scope" below for what the MCP deliberately does not return.

## Workflow

Run the following loop. Every step is gated on evidence.

### Step 1. Identify the entry point

Determine the kind of signal being debugged. If the user has not specified, ask. Do not pick at random.

| Entry point | Required input | First MCP tool to call |
| --- | --- | --- |
| Crash group | Crash number, fingerprint, or pasted stack trace | `crash_details` (or `list_crashes` to find it first) |
| Specific occurrence of a crash | Crash number plus ULID | `get_occurrence_details` |
| App hang or ANR | Hang number, or "recent UI hangs" | `list_app_hangs` |
| User-reported bug | Bug number | `bug_details` |
| Regression between versions | Two version numbers | `list_crashes` filtered by version, then `crash_patterns` with `pattern_key: app_versions` |
| Review or rating signal | Date range and version | `list_reviews` filtered by `rating` and `app_version` |
| APM performance regression | "what got slower/flakier since X", two versions; which signal (metric) | `apm_list_groups` for the matching `metric` sorted by `apdex_change`, then `apm_group_view` with `dimensions` |
| Worst APM group | The signal: slow endpoint/launch/screen, jank, flow drop-off (metric) | `apm_list_groups` for that `metric` sorted by its pain key (`p95`, `failure_rate`, `frozen_frames_percent`, `dissat_count`), then `apm_group_view` |
| Throughput spike / drop | Group + window | `apm_group_view` with `throughput_chart` for the group |

### Step 2. Pull MCP context

Sequence the available Luciq MCP tools deliberately for the entry point:

- Crashes: `list_crashes`, `crash_details`, `crash_patterns`, then `list_occurrences_tokens` and `get_occurrence_details` for one or more sessions.
- Hangs: `list_app_hangs` filtered to the recent window. iOS hangs surface as `FATAL_UI_HANG`, Android as `ANDROID_FATAL_HANG`.
- Bug reports: `list_bugs` then `bug_details`. The response includes URLs to compressed logs (network, console, session profiler) when available.
- Regressions: filter `list_crashes` by the two versions, diff the result, then call `crash_patterns` with `pattern_key: app_versions` for the highest-impact new groups.
- Review signals: `list_reviews` filtered to low ratings, then correlate with crash and hang activity in the same window.
- APM regression: choose the `metric` for the signal, then `apm_list_groups` sorted by `apdex_change` (signed delta) across the two `app_version` values, take the most-degraded groups, then `apm_group_view` with `dimensions` to localize each regression to a cohort (OS, device, country, version), then `apm_occurrence` with `selector: worst` for a concrete worst case to reason over.
- APM group deep dive: `apm_list_groups` for the metric sorted by its pain key to find the group, then `apm_group_view` — `summary` for the headline metrics, then the view that matches the pain: `spans_table` (or `stages_breakdown` for launch/screen_loading) for a slow segment, `outliers` for the tail driving p95 (not on `frame_drop`), or the `failure_rate` view for a failing network group, then `apm_occurrence` (`worst`), which is the worst-failed request when the pain is failures, not the slowest.
- On a 403/501 from an APM tool, SKIP the APM step with the reason; never infer "no regression" from a tool error.

### Step 3. Symbolicate if obfuscated (crash / hang track)

If the top frame is a hex address, an obfuscated symbol, or `<unknown>`, the build is missing its symbol artifact (dSYM for iOS, R8/ProGuard mapping for Android, split-debug-info for Flutter, source map for React Native). STOP and direct the user to upload symbols before continuing. Do not reason over hex addresses.

### Step 4. Map to local source

**Crash / hang track — map the top frame:**

- `Grep` the symbol (class plus method) across the project.
- `Read` the matched file with a small window around the offending line (10 lines above and below).
- For multi-platform projects (KMP, RN, Flutter), prefer the platform-specific source set first (`iosMain/`, `androidMain/`).

**APM track — map the endpoint / span to the call site:**

The APM group name is the request signature (method + URL path template, e.g. `GET /v2/orders/{id}`). Map it to the code that issues or handles it:

- `Grep` the path template, the host, or the path segments across the project. For a client SDK, that's the request-building call site (the URL string, the route constant, or the API-client method). For a server repo, it's the route/handler registration.
- When `spans_table` localized the cost to one segment (e.g. a DB span, a downstream call, a serialization span), grep that segment's operation name — the bottleneck is usually inside that call, not in the request setup.
- Use the `dimensions` breakdown to constrain the hypothesis: a regression isolated to one OS version, one device tier, or one app version points at a different cause (client-side change, OS behavior, rollout) than one that's uniform across cohorts (backend/dependency).

If the symbol or endpoint does not exist locally, the repo isn't its source: a different commit than the build for a crash symbol, or a different service/dependency for an endpoint. Surface that fact rather than guessing at a fix.

### Step 5. Form a hypothesis

Use this structure exactly. Cite each piece of evidence to the MCP tool that produced it.

```
HYPOTHESIS: <one sentence>
CONFIDENCE: <low / medium / high>

EVIDENCE:
- Top frame: <file>:<line> - <symbol>     [from: crash_details]
- Distribution: <e.g. only iOS 18.0+>     [from: crash_patterns]
- Repro context: <e.g. backgrounded for ~5s>  [from: get_occurrence_details]
- Correlated signal: <e.g. matching review text>  [from: list_reviews]

ROOT CAUSE: <the specific defect>
```

For an APM investigation the evidence lines come from the APM channel instead:

```
HYPOTHESIS: <one sentence>
CONFIDENCE: <low / medium / high>

EVIDENCE:
- Group: GET /v2/orders/{id}  apdex 0.71 (was 0.94)   [from: apm_list_groups, sort apdex_change]
- p95: 2,140ms (was 410ms)                             [from: apm_group_view summary]
- Cohort: regression isolated to iOS 18.x             [from: apm_group_view dimensions]
- Bottleneck: DB span "orders.fetch" = 1,800ms        [from: apm_group_view spans_table]
- Call site: <file>:<line>                             [from: Grep]

ROOT CAUSE: <the specific defect>
```

Confidence is honest. Three corroborating MCP sources is high. Reasoning from the top frame or single number alone is low. A latency number with no cohort breakdown and no span decomposition is a symptom, not a root cause.

### Step 6. Propose a fix

Show a diff. Explain how the fix addresses the root cause. Flag any side effects. Optionally write a failing test that reproduces the issue before applying. Do not apply the diff without user confirmation.

## Pattern library

Carry these patterns. Reach for them when the corresponding signature appears in the MCP data.

### Swift Concurrency (iOS)

When the top frame involves `async`, `await`, an actor, or a `Sendable` violation:

- Check whether the crash is `Swift runtime: Fatal error: ...` rather than a typical exception. That is a concurrency-safety check firing.
- Confirm OS distribution via `crash_patterns` with `pattern_key: oses`. Swift 6 strict-concurrency checks behave differently across iOS versions.
- Look at the session profiler from `get_occurrence_details` for hop-to-`@MainActor` patterns near the crash time.
- Do not recommend slapping `@MainActor` on a class to silence the error. Treat that as a smell, not a fix.

### Android ANRs (`ANDROID_FATAL_HANG`)

When `list_app_hangs` returns an Android hang:

- The `crash_cause` field tells you where the main thread was blocked, but not always what blocked it. Pull a few `get_occurrence_details` to see recent main-thread activity and pending I/O.
- Check `pattern_key: app_versions` to see whether the ANR is a regression or a long-tail issue.
- Common offenders: synchronous network calls on the main thread, large `SharedPreferences.commit()` writes, blocking `Lock` acquisitions, work scheduled on the wrong dispatcher.

### iOS UI hangs (`FATAL_UI_HANG`)

- The hang `exception` summary indicates duration class.
- Pull the occurrence to confirm what the user was doing. The `current_view` and `app_status` (foreground / background) fields disambiguate.
- Common offenders: synchronous Core Data on `NSManagedObjectContext.viewContext`, file I/O on the main queue, expensive layout work in `viewDidLayoutSubviews`.

### Out-of-memory crashes

- OOMs surface as terminations. Check `crash_type` and the exception name.
- Pull the occurrence's `state.memory` and `state.storage` fields from `get_occurrence_details` for resource state at termination.
- Look at `pattern_key: devices`. OOMs concentrate on lower-RAM devices and surface a device-tier story the agent should call out.

### Network failure correlated crashes

- For crashes with a stack frame in networking code, pull the occurrence's logs URL from `get_occurrence_details` (compressed log archive).
- Cross-reference with bug reports in the same window via `bug_details`. The `state.logs.network_log` URL often shows the failed request that preceded the crash.
- Do not assume timeout vs DNS failure vs server error without log evidence. The categories matter for the fix.

### APM latency regression

When `apm_list_groups` sorted by `apdex_change` shows a group degrading between versions:

- Sanity-check the target before trusting the apdex. `apm_group_view summary` returns the group's configured apdex target as `threshold_ms` (also on every `apm_list_groups` item). If `threshold_ms` sits below `50th_percentile_ms`, the target is under the median — more than half of otherwise-healthy requests score unsatisfied, so a low or declining apdex is a target-config problem, not a code defect. Weigh `threshold_ms` against the endpoint's business role (a list/read call should be near-real-time, a few hundred ms; a heavy export needn't be) before attributing a fix to code.
- Confirm with the absolute numbers, not just apdex: pull `apm_group_view summary` for `50th_percentile_ms` and `95th_percentile_ms` before and after. A p50 that's flat with a p95 that exploded is a tail problem (a slow cohort or a slow dependency), not a uniform slowdown.
- Always run `dimensions` to localize. A regression confined to one OS version or device tier is a different bug than one uniform across cohorts.
- Use `spans_table` to attribute the time. The fix targets the dominant span — chasing the request-setup code when the cost is in a DB span wastes effort.
- Use `outliers` when p95/p99 moved but the median didn't — the tail requests carry the signature.

### APM failure-rate spike

When `apm_list_groups` sorted by `failure_rate` flags a group:

- Split `total_failure_rate` into `client_failure_rate` vs `server_failure_rate`. Client failures (4xx, timeouts, cancellations) point at the app; server failures (5xx) point at the backend. They lead to opposite fixes.
- Filter the group by `failure_name` / `failure_type` to see whether it's one error class or many.
- Cross-reference the window with `list_crashes` and `bug_details` — a failure-rate spike that coincides with a crash spike on the same call path is usually one root cause, not two.

### APM throughput change

When `throughput_chart` shows a spike or drop:

- A drop in throughput with flat latency often means callers stopped calling (a client-side gating change, a feature flag, a rollout) — not a performance defect. Check `dimensions` by `app_version` and correlate with a release.
- A spike with rising latency is load-driven; the fix is usually capacity/backpressure, not a code path. Say which one the evidence supports; don't default to "optimize the code."

## Out of scope

The skill is grounded in what the Luciq MCP exposes today. It deliberately does not:

- Compute crash-free session rate or any aggregate metric the MCP does not return.
- Reason about App Store rating drops as a primary investigation entry point. `list_reviews` is correlation, not causation.

When new MCP tools land (release comparison, session replay), this skill grows with them. Until then, if the user asks for one of those, say so plainly.

## Style

- Do not fabricate stack traces, line numbers, or counts.
- Do not propose a fix without naming the root cause.
- Do not apply edits without showing a diff and getting confirmation.
- If MCP returns nothing for a query, surface that. Do not fill in plausible-looking data.

## Red Flags - STOP and surface to the user

If you catch yourself thinking any of these, you are about to ship a fabricated investigation. STOP, surface to the user, do not proceed:

- "MCP returned nothing, but the user clearly wants an answer, so I'll reason from the symbol name." That is a guess, not a hypothesis. Surface the empty result.
- "The top frame is a hex address but I can probably figure it out from context." Do not. Stop and ask the user to upload symbols.
- "The local symbol doesn't exist but the file looks similar enough." It isn't. The repo is at a different commit; surface that.
- "I'll quote a crash-free session rate from memory." The MCP does not expose that metric. Saying you computed it from MCP data is a fabrication.
- "Confidence is high because the top frame matches my prior." One source is not three. Lower confidence to low or medium.
- "I'll apply the fix without a diff because it's obviously right." Show the diff. Get confirmation. Always.
- "The hypothesis cites the symbol but not which MCP tool produced it." Add the citation, or weaken the hypothesis.
- "APM returned a 403/501, so there's no regression." A tool error isn't a clean result, SKIP the step, say APM was unavailable, never infer "no regression." Only a genuine server-down 5xx (500/502/503) STOPs; 403 and 501 return a body to inspect.
- "I filtered APM with `app_versions`/`experiments`/`devices` and got nothing, must be broken." Those are crash-channel names. APM uses `app_version`, `experiment`, `device: { operator, values }`, re-run before concluding.
- "p95 doubled, so the endpoint's code is slow. I'll optimize it." Not yet. run `dimensions` (one cohort?) and `spans_table` (which segment?) first. The cost may be a downstream call or one OS version; optimizing the wrong layer fixes nothing.
- "Throughput dropped, so performance regressed." A throughput drop with flat latency usually means fewer callers, not a slower path. Correlate with a release / flag before calling it a defect.
- "I'll slice by the `email` custom attribute." APM addresses custom attributes by numbered slot (1–20), not name, and the slot→name map is org config you can't infer. Ask the user which slot it is.
- "I'll quote a latency number from a group without saying which tool/view gave it." Cite `apm_list_groups` vs `apm_group_view <view>`. they're different aggregations and conflating them misstates the evidence.

The pattern: every shortcut here trades "sounds confident" for "actually true." The skill's job is to be true.
