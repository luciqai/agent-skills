# Metrics Glossary and Tool Surface

What every Luciq MCP tool used by `luciq-readout` returns, what each metric actually means, and which signals the MCP does and does not expose. Read this before quoting any number. Field paths used in `SKILL.md` come from here.

The shapes below were confirmed against live MCP responses, but the MCP evolves — when a field is missing or a shape differs from what's documented here, trust the live response and surface the discrepancy rather than forcing the documented shape.

## Table of contents

1. [Identifiers, modes, platforms](#identifiers-modes-platforms)
2. [`list_applications`](#list_applications)
3. [`app_insights` — the headline source](#app_insights--the-headline-source)
4. [`list_crashes` / `list_app_hangs`](#list_crashes--list_app_hangs)
5. [`crash_patterns` — and the adoption signal](#crash_patterns--and-the-adoption-signal)
6. [`list_bugs`](#list_bugs)
7. [`list_reviews`](#list_reviews)
8. [`list_surveys` / `survey_details` — NPS / CSAT](#list_surveys--survey_details--nps--csat)
9. [Per-occurrence detail tools](#per-occurrence-detail-tools)
10. [Tools the readout does not use](#tools-the-readout-does-not-use)
11. [Filter-naming differences across tools](#filter-naming-differences-across-tools)
12. [What the MCP does NOT expose](#what-the-mcp-does-not-expose)

## Identifiers, modes, platforms

- An app is keyed by **`slug`** (e.g. `ios-demo-app`) and **`mode`**. The same app can exist in multiple modes.
- **`mode`** enum: `production`, `beta`, `staging`, `alpha`, `qa`, `development`. Each mode is a separate dataset. A readout must state which mode it's on; `beta` numbers presented as production is a silent error.
- **Platform** values differ by tool. `list_applications` uses lowercase `ios | android | react_native | flutter`. The crash / hang filter `platform[]` uses UPPERCASE `IOS | ANDROID | DART | JAVASCRIPT` (`DART` = Flutter, `JAVASCRIPT` = React Native). Mixing these up returns empty and looks like "no data."

## `list_applications`

Lists apps the authenticated developer can see. Optional `platform`, `limit`, `offset`. Returns rows of `name, token, slug, mode, created_at, target_os, platform`. Use it to resolve `(slug, mode)` at the start of every readout. Never hard-code a slug.

## `app_insights` — the headline source

`app_insights(slug, mode, filters?)`. `filters` accepts `app_version: ["<version>"]` and `date_ms: {gte, lte}`. Returns four **independent** sections; any one can carry an `error` while the others return data.

```jsonc
{
  "crashes":   { "is_sessions_v3": false, "non_fatal_crashes": { "value": 2 } },
  "bugs":      { "error": "Failed to fetch data: " },          // commonly errors — see note
  "apm": {
    "networks":        { "data": { "avg_apdex": 0.881, "avg_apdex_change": -0.254,
                                   "failures_count": { "total": 24937 }, "total_count": 500268 },
                         "has_occurrences": true, "has_key_metrics": true },
    "screen_loadings": { "data": { "avg_apdex": 0.822, "avg_apdex_change": -3.31,
                                   "avg_95th_percentile_ms": 311.67 }, ... },
    "cold_launches":   { "data": { "apdex": 0.898, "apdex_change": -0.197,
                                   "95th_percentile_ms": 1644.77 }, ... },
    "hot_launches":    { "data": { "apdex": 0.905, "apdex_change": -9.51,
                                   "95th_percentile_ms": 1621.83 }, ... },
    "flows":           { "data": { "avg_apdex": 0.935, "avg_apdex_change": -2.04,
                                   "drop_off_count": 75108, "total_count": 174841 }, ... }
  },
  "monitoring": {
    "is_sessions_v3": true,
    "crash_free_sessions": { "value": 99.32, "rate": 0.109 },
    "anr":               { "value": 100.0,  "rate": 0.0 },
    "oom":               { "value": 99.81,  "rate": 0.024 },
    "app_hangs":         { "value": 99.38,  "rate": 0.052 },
    "user_termination":  { "value": 99.54,  "rate": 0.065 }
  }
}
```

What the numbers mean:

| Field | Meaning | Readout note |
| --- | --- | --- |
| `monitoring.crash_free_sessions.value` | Percent of sessions with no fatal crash, e.g. `99.32` = 99.32%. | The single best C-suite headline. It is a **rate**, so it compares cleanly across versions. |
| `monitoring.*.value` (`anr`, `oom`, `app_hangs`, `user_termination`) | Each is a "free" percentage — `anr.value: 100.0` means 100% ANR-free (good), not 100% ANR. | High is good for all of these. Don't invert. |
| `monitoring.*.rate` | The **period-over-period change** in that metric, not the rate itself. | Easy to misread. `crash_free_sessions: {value: 99.32, rate: 0.109}` means "99.32% crash-free, up ~0.11 over the prior period." A negative `rate` (seen on `app_hangs` for one version: `-0.079`) is a worsening. Cite the direction explicitly. |
| `apm.networks.data.avg_apdex` | Network apdex 0-1 (higher better). `failures_count.total` / `total_count` give the failed and total request counts. | Apdex is a satisfaction score, not a success rate. State it as apdex, not as "% of requests OK." |
| `apm.*.avg_apdex_change` / `apdex_change` | Change vs prior period, in the apdex's own units. | Same direction caveat as `rate`. |
| `apm.screen_loadings.avg_95th_percentile_ms`, `apm.*_launches.95th_percentile_ms` | p95 latency in ms. | A latency, lower is better. |
| `apm.flows.drop_off_count` / `total_count` | Flow drop-offs out of total flow runs. | A funnel signal; useful for PM readouts. |
| `crashes.non_fatal_crashes.value` | Count of non-fatal crash groups in scope. | A count (volume), not a rate. |

**Empty vs error vs data.** A section can be:
- `{"error": "..."}` — the service failed for that section. Report **unavailable**, never reconstruct.
- present with `has_occurrences: false` and `data: null` — **no data captured** for that window. Report as no-data, not as a healthy zero.
- present with `data: {...}` — real data, safe to cite.

**The `bugs` section error.** In live testing, `app_insights.bugs` returned `{"error": "Failed to fetch data: "}` on every app probed, while `list_bugs` returned full data. They are different sources. If you need bug volume, pull `list_bugs` and cite it; never present a `list_bugs` count as the `app_insights.bugs` figure, and never fill the errored section with it.

## `list_crashes` / `list_app_hangs`

`list_crashes(slug, mode, filters?, sort_by?, direction?, limit?, offset?)`. Returns rows (CSV-style) with, per crash group:

`number, exception, crash_cause, crash_type, platform, status_id, current_view, occurrences_counter, affected_users_counter, min_app_version, max_app_version, first_occurred_at, last_occurred_at, severity, app_version, team, signals, exception_name, ...`

| Field | Meaning |
| --- | --- |
| `number` | The crash group's integer ID. Feeds `crash_patterns` and `crash_details`. |
| `occurrences_counter` | Total occurrences of this group in scope — **volume**. |
| `affected_users_counter` | Distinct users hit — **blast radius**. Lead with this for impact. |
| `crash_type` | `CRASH`, `NON_FATAL`, `OOM` (iOS), `ANR` (Android). |
| `current_view` | Screen where it occurred (e.g. `Pay.PaymentViewController`). Powers the `current_views` filter. |
| `team` | JSON `{name, id}` of the owning team — the EM / VP "who owns this." |
| `status_id` | `1` open, `2` closed, `3` in progress. |
| `severity` | Numeric severity rank. |
| `first_occurred_at` / `last_occurred_at` | Sort `first_occurred_at` ascending within a version to find **new-in-version** issues. |

`sort_by`: `occurrences_counter` (volume), `affected_users_counter` (impact), `severity`, `first_occurred_at`, `last_occurred_at`, plus version sorts. `direction` `asc`/`desc`. `limit` max 50.

`list_app_hangs` has the same shape and filter surface minus `type` / `subtype`. Hang rows carry `crash_type: FATAL_UI_HANG` and an `exception` like "The app's main thread was unresponsive for more than 3000 milliseconds." The `crash_cause` on a hang often points at the offending source line (e.g. `PaymentViewController.Parsing() (PaymentViewController.swift:52)`) — useful for a PM / EM, never for C-suite.

## `crash_patterns` — and the adoption signal

`crash_patterns(slug, mode, number, pattern_key, filters?, sort_by?, direction?)`. Returns the distribution of ONE crash group (`number`) across the chosen `pattern_key`.

```jsonc
// pattern_key = app_versions  (carries adoption + total_sessions_count)
{
  "total_occurrences_count": 1214,
  "total_sessions_count": 2994,
  "patterns_list": [
    { "value": "3.0.4 (3)", "occurrences_count": 262, "adoption": 0,
      "first_seen": "...", "last_seen": "..." },
    { "value": "3.1.4 (4)", "occurrences_count": 213, "adoption": 1351, ... }
  ]
}

// pattern_key = oses  (no adoption / total_sessions_count on this key — confirmed live)
{
  "total_occurrences_count": 1214,
  "patterns_list": [
    { "value": "iOS 14.2", "occurrences_count": 64, "first_seen": "...", "last_seen": "..." }
  ]
}
```

`pattern_key` values: `app_versions`, `devices`, `oses`, `current_views`, `app_status` (foreground/background), `experiments`.

- `patterns_list[].value` — the bucket label (a version, device, OS, screen, status, or experiment).
- `patterns_list[].occurrences_count` — occurrences of this crash in that bucket.
- `patterns_list[].adoption` — a per-bucket session/exposure count for the bucket. **This is the one adoption signal the MCP exposes.** It is scoped to this crash group's pattern query, not the whole app. **It is not on every `pattern_key`:** confirmed present on `app_versions` and absent on `oses` in live responses, so query `pattern_key=app_versions` when you need adoption, and don't assume it's there on a key that omitted it — check the response.
- `total_occurrences_count` — group-level total, returned on every key. `total_sessions_count` accompanies the `app_versions` response (absent on `oses` in testing). Trust the live response over this note.

**How to use adoption honestly.** When you state "version 3.1.4 has more crashes than 3.0.4," the `adoption` per bucket lets you say whether that's because 3.1.4 has far more exposure. Cite it to `crash_patterns` and scope it correctly: it describes *this crash group's* distribution, not app-wide rollout. Do not generalize a single group's `adoption` into an app-level adoption percentage, and never invent adoption for a version where you only have `app_insights`. The `experiments` pattern key is how you attribute a regression to a flag or rollout.

## `list_bugs`

`list_bugs(slug, mode, filters?, sort_by?, direction?, limit?, offset?)`. User-reported bug reports (distinct from crashes). Rows: `priority_id, status_id, categories, email, number, reported_at, last_activity, title, type, duplicated_bugs_count`.

- `priority_id`: `-1` N/A, `1` Trivial, `2` Minor, `3` Major, `4` Blocker.
- `status_id`: `1` New, `2` Closed, `3` In Progress.
- `title` is the user's report title (e.g. "Cannot complete premium checkout payment") — a strong PM signal. `categories` carries the bucket (Bug / Question / Improvement / Frustrating experience).
- `duplicated_bugs_count` — how many duplicates merged in; a rough frequency proxy.

## `list_reviews`

`list_reviews(slug, mode, filters?, limit?, offset?, sort_by?, sort_direction?)`. App Store / Play reviews. Rows: `id, title, star_rating, body, username, country, app_version, device, date`.

- Filter `rating[]` (1-5), `app_version[]`, `country[]`, `os[]` (`ios`/`android`), `prompt_type[]` (`custom`/`native`/`app_store`), `date_ms`.
- `body` is the verbatim review text. **Quote it directly** in PM / VP readouts; a paraphrase becomes your claim instead of the user's words.
- Reviews are the external quality proxy execs ask about. A rating trend is a fair C-suite headline; individual review quotes belong in PM-tier readouts.

## `list_surveys` / `survey_details` — NPS / CSAT

The in-app voice-of-customer signal, distinct from store reviews. Surveys are run inside the app; reviews are posted to the App Store / Play.

`list_surveys(slug, mode, filters?, limit?, offset?)` lists published / paused / draft surveys, newest-first. Filter `status[]` (`0` draft, `1` published, `2` paused) and `type[]` (`0` custom, `1` nps, `2` app_store). Rows carry `id`, `title`, `type` (`"nps"` / `"custom"`), `status`, `responses_count`, `created_at`. Use it to find the live NPS survey's `id`.

`survey_details(slug, mode, id, filters?, page?)` returns the survey definition plus response statistics and a page of individual responses (25/page). For an **NPS** survey the headline is the `nps` object:

```jsonc
"nps": {
  "promoters": 50, "passives": 35, "detractors": 40,
  "promoters_pct": 40.0, "passives_pct": 28.0, "detractors_pct": 32.0,
  "score": 8
}
```

| Field | Meaning | Readout note |
| --- | --- | --- |
| `nps.score` | The Net Promoter Score (promoters % − detractors %), an integer. | A fair C-suite / VP headline alongside the App Store rating. State it as "NPS", not as a percentage. |
| `nps.promoters` / `passives` / `detractors` (+ `_pct`) | Response counts and shares per NPS class. | The split is the VP-tier context: a positive-looking score can still hide a large detractor base. |
| `responses[].responses[].value` | The per-question answer. For the 0-10 NPS question it's the score; for the open follow-up ("How can we do better?") it's the **verbatim** user text. | Quote the verbatim follow-up answers as PM-tier evidence — like reviews, never paraphrase into a claim. Filter to detractors/passives with `filters.nps` for the negative themes. |
| `responses[].country` / `device` / `os` | Per-response segment. | Lets a PM cut feedback by segment, same as reviews. |

Empty / no survey: `list_surveys` returning nothing, or a survey with `responses_count: 0`, means **no NPS signal** for the scope. Report that; do not estimate a score from review ratings — they're different instruments.

## Per-occurrence detail tools

For the EM tier only. `(slug, mode, number)` addresses a crash group; occurrences within it are addressed by ULID token. The four compose the step-4b chain in `SKILL.md`.

- `crash_details(slug, mode, number)` — synchronous. Returns `exception`, `exception_name`, `crash_cause`, `severity`, `priority_id`, `status_id`, `threads_count`, `sdk_version`, `team`, and a `stack_frames[]` array (each frame: `index`, `library`, `description`, `type` = `system`/`application`, `is_grouping_frame`). The application frames are the ones a fix targets; lead the EM with the `is_grouping_frame` and the deepest `application` frame before the system frames.
- `list_occurrences_tokens(slug, mode, number)` — returns `states_tokens` (an array of ULID tokens for individual occurrences) and `total_occurrences`. ULIDs are time-prefixed; `max(tokens)` lexicographically is the newest. (The array is a page of recent occurrences, not necessarily all of `total_occurrences`.)
- `get_occurrence_details(slug, mode, number, ulid)` — full single-session payload under `state.fields`: `app_version`, `current_view`, `os`, `device`, `memory` (`used/total MB`), `storage`, `duration`, `app_status` (foreground/background), `country`/`city`, plus `logs` (signed URLs to compressed logs and experiments files) and the `user`. One concrete repro context. Heavy; pull only for the deepest EM drill-down.
- `crash_diagnostics(slug, mode, number)` — **async**; returns `status: generating` with a `retry_after_seconds` until ready, then `status: ready` with an `aggregation` block: `patterns` (screen-flow navigation paths with `support_pct` / `support_count`), `total_sessions`, `distributions` (`devices`, `os_versions`, `app_versions`, `current_views`, `app_status` — each a label→count map), and `metrics` (`memory_used_percent`, `battery_level`, `storage_used_percent`, `duration` — each with `mean`, `p50`, `p90`, and histogram `buckets`). Also re-states `crash_details` and the full `stacktrace`. This is the aggregate-across-occurrences view; `crash_patterns` is the per-key distribution. Re-call while `generating`.

A full stacktrace and occurrence detail are EM-tier depth. They must never appear in a C-suite, VP, PM, or QA readout — see the omit-lists in `persona-playbooks.md`.

## Tools the readout does not use

| Tool | Why excluded |
| --- | --- |
| `update_bug` | **Write / mutating tool** — changes a bug's status / priority / assignment. A readout is strictly read-only; it must never alter the data it reports. Never call it, by any path. |
| `bug_details` | One bug's deep payload (logs, breadcrumbs, repro steps). The readout uses `list_bugs` for volume / themes; single-bug depth is `luciq-debug`'s job. Pull a top-bug snippet only if a quick check shows it adds readout value; default exclude. (Callable via the client — excluded by scope, not availability.) |
| `apm_list_groups` / `apm_group_view` / `apm_occurrence` | Per-span APM deep-drill: the slowest-group list, one group's apdex / p95 / failure-rate panels, and one occurrence's per-stage span timeline. The readout reports performance at the `app_insights.apm` aggregate; span-level depth is `luciq-debug`'s territory and not the readout's primary performance source. All three are stripped from the client by AI-94 but are read-only and reachable via direct JSON-RPC — see the constraint note below for the (confirmed-working) optional drill path. |

### Known constraint — four tools stripped from the MCP client (AI-94)

Four tools — `update_bug`, `apm_list_groups`, `apm_group_view`, `apm_occurrence` — carry a **top-level `anyOf` / `allOf` / `oneOf` / `not` combinator** in their server-side `inputSchema` (the `apm_*` tools use `allOf` with `if`/`then` to gate `sort.by`, `views`, `selector`, and `filters` per `metric`; `update_bug` uses `anyOf` + `not`). The Anthropic Messages API rejects a top-level combinator on a tool's input schema, so Claude Code strips these four from the in-session tool list. Confirmed live: a `tools/list` against the server returns all 18 tools, and exactly these four carry a top-level combinator; the other 14 are callable via the normal MCP client. This is a known server-side issue tracked as **AI-94** (the combinators belong below the top level), not something a readout fixes.

- **`update_bug`** — the strip changes nothing for a readout; a write tool is out of scope regardless. Never reach it by any path.
- **`apm_*`** — the readout's performance dimension comes from the fully-callable `app_insights.apm` aggregate. When a persona genuinely needs per-span detail, all three read-only `apm_*` tools can be reached by a **direct JSON-RPC `tools/call`** to the MCP HTTP endpoint (`{"jsonrpc":"2.0","method":"tools/call","params":{"name":"<tool>","arguments":{...}}}`) with the same `Email` / `Token` headers the MCP client is configured with. **All three confirmed working live against this path:**
  - `apm_list_groups(slug, mode, metric, sort?, limit?)` — per metric (`network` / `screen_loading` / `launch` / `flows` / `frame_drop`), the per-group `uuid`, `pattern` / `name`, `method`, `apdex_score`, `failure_rate`, `latency_p95_ms`, `occurrences_count`. The slowest-endpoint / slowest-screen list. (e.g. top failing network group ~5.2% failure rate / p95 ~705ms, of 41 network groups.)
  - `apm_group_view(slug, mode, metric, group_uuid | group_url+method, views[])` — one group's panels in a single call. `views` (string or `{name, pattern_key}`): `summary` (occurrences, apdex satisfying/tolerable/frustrating, p50/p95, failure_rate split client/server), `failure_rate` (weekly trend + failure-type breakdown), `apdex_chart`, `throughput_chart`, `spans_table`, `dimensions` (gated `pattern_key`: `os_version`, `app_version`, `device`, `platform`, …), `outliers`, plus screen-only `web_vitals` / `stages_breakdown` and frame-only `frames_distribution` / `delayed_frames`. Views not applicable to the metric are dropped and listed in `ignored_views`.
  - `apm_occurrence(slug, mode, metric, group_uuid | group_url+method, selector, token?, limit?)` — one or more occurrences in a group. `selector`: `worst`, `by_token` (needs `token`), or `list` (paginated). Returns `occurrence_details` (device / os_version / app_version / country / radio / carrier / the running `experiments` / the timed metric) plus a `spans[]` per-stage timeline (`original_identifier`, `duration_mus`, `start_time`). For network that's `dns_lkp` / `cnct_hs` / `tls` / request stages; for screen loading it's `view_did_load` → `view_will_appear` → … → `end_screen_loading_api`, so you can name the dominant slow stage. (Note: `selector: worst` returned a server-side "Failed to fetch data" on one network group while `list` worked on the same group and `worst` worked on a screen group — the tool is reachable; surface a per-query server error honestly and try another selector / group rather than fabricating.)

  Label any figure pulled this way as sourced via a direct `apm_*` call, and never use the same path to reach `update_bug` or any write tool.

## Filter-naming differences across tools

These bite. Confirm the call shape before concluding "no data":

| Concept | `list_crashes` / `list_app_hangs` | `list_bugs` | `list_reviews` | `app_insights` |
| --- | --- | --- | --- | --- |
| App version filter | `app_versions[]` (plural) | `app_version[]` | `app_version[]` | `filters.app_version[]` |
| Platform values | `IOS`/`ANDROID`/`DART`/`JAVASCRIPT` (UPPER) | — | `os[]` = `ios`/`android` | — |
| Date range | `filters.date_ms{gte,lte}` | (limited) | `filters.date_ms{gte,lte}` | `filters.date_ms{gte,lte}` |

`crash_patterns` uses `experiments` as a `pattern_key`; do not confuse it with a filter. Empty results from a wrong-case platform value look identical to "the app is healthy" — they are not. Re-run with the correct shape before stating any conclusion.

## What the MCP does NOT expose

Do not estimate, reconstruct, or imply any of these:

- **App-level adoption / rollout percentage.** Not in `app_insights`. The only adoption datum is per-crash-group `adoption` in `crash_patterns` (on the `app_versions` key), correctly scoped.
- **MTTR / time-to-resolve.** Not exposed.
- **Retention, DAU/MAU, revenue.** Not in scope of these tools. Tie stability to user impact qualitatively; don't fabricate a business metric.
- **A reconstructed value for an errored or empty `app_insights` section.** Report it unavailable.
- **An NPS score where no survey exists or it has no responses.** NPS comes only from an actual `survey_details` `nps` object; don't infer it from review ratings (different instrument).
- **Per-span APM detail** beyond the `apm` section's aggregates is not the readout's primary source. The `apm_*` tools that expose it are stripped from the MCP client by AI-94 (see the constraint note above) and are `luciq-debug`'s territory; all three are read-only and reachable via the confirmed direct JSON-RPC path, but a readout reaches them only when a persona truly needs span depth, and labels the result accordingly. Session replay is not exposed to these tools.

What the MCP does expose but the readout still won't touch: **`update_bug`** (and any write tool). It can change data; a readout never mutates the data it reports. See "Tools the readout does not use" above.

When the user asks for one of these, say it isn't exposed (or isn't a readout's job) rather than producing a plausible-looking number.
