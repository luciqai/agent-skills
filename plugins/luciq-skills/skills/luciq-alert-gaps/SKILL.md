---
name: luciq-alert-gaps
description: Use when the user wants to find what they are not monitoring and add the missing Luciq alerts. Triggers include "am I missing any alerts", "what should I be alerting on", "alerting/coverage gaps", "set up alerts for my app", "recommend alerts", "is anything unmonitored", "I just installed Luciq, what alerts should I create", or asking whether a degraded metric has an alert. Cross-references current metric health (via the Luciq MCP) against existing alert rules and proposes alerts only for metrics that are both unhealthy and uncovered — never duplicating coverage or alerting on healthy metrics.
---

# Luciq Alerting Gap Analysis

Find the metrics that matter, are currently unhealthy (or material), and have **no alert watching them** — then propose alerts that close those gaps. A gap is the intersection of two facts from MCP data: a metric is below a sensible bar, and no existing rule covers it. Recommending an alert for a healthy metric, or one that's already covered, is noise — don't.

## When NOT to use this skill

- The user's existing alerts fire too often — use `luciq-alert-noise`.
- The user wants to **create, change, or manage one specific alert** they describe — use `luciq-alert-config`.
- The user is investigating *why* something crashed/hung — use `luciq-debug`.
- First-time SDK install or wiring `Luciq.start(...)` — use `luciq-setup`.

If the request fits one of the above, STOP and route there.

## Prerequisites

The Luciq MCP server must be configured and authenticated. If the tools are not available, STOP and direct the user to set up the MCP server (or run `luciq-setup`).

Tools this skill uses (verbatim names):

| Tool | Action | Purpose |
| --- | --- | --- |
| `read_alerts` | `list` | Existing alert rules — what is already covered, by type and trigger. |
| `read_alerts` | `init` | Per-app catalog of valid types/triggers/conditions/actions and lookup IDs. Call before creating. Also reveals what the app's plan/platform actually supports. |
| `app_insights` | — | Top-level health: crash-free sessions (+ rate), ANR, OOM, app hangs, non-fatal crash count, bug totals, and whether APM has data. |
| `apm_list_groups` | — | Per-entity APM metric values: each network endpoint, launch, flow, screen, and frame-drop group with `apdex_score`, `failure_rate`, `p95_ms`, `p50_ms`, occurrences. Sort ascending by `apdex` / descending by `failure_rate` to find the worst. |
| `write_alerts` | `create` | Create a recommended alert. State-changing — confirm first. |

You MUST ground every "this is a gap" claim on a metric value the MCP returned and the absence of a matching rule. Do not recommend from a generic checklist alone.

## What "good coverage" looks like

Luciq ships a baseline of recommended alerts that encodes sensible defaults. Use it as the reference for both *which* metrics deserve an alert and *what threshold* to set:

| Area | Trigger | Threshold | Window | Notes |
| --- | --- | --- | --- | --- |
| Network | `apdex` | < 0.7 | 1 day | scope to key metrics / high-traffic endpoints |
| Network | `failure_rate` | > 10% | 3 hours | scope to high-traffic endpoints |
| App launches | `apdex` | < 0.85 | 1 day | key launch metric |
| Flows | `dropoff_rate` | > 30% | 1 day | end_reason in crashes / force_restarts |
| Screen loading | `apdex` | < 0.7 | 1 day | key screens |
| Screen rendering | `apdex` | < 0.7 | 1 day | key screens |
| Overall app | `apdex` (frustration-free sessions) | < 0.8 | 1 day | latest / top releases |
| Stability | `crash_free_session` / `crash_free_users_overall` | a target like 99% | — | the single most important safety net |
| Stability (Android) | `anr_free_users_overall` / `anr_free_sessions_overall` | a target like 99% | — | Android only |

These thresholds are the recommended bar. Use them as the alert threshold, and as the line for deciding whether a *current* value is "unhealthy enough" to be a gap.

## Workflow

### Step 1. Read current coverage

Call `read_alerts(action: "list")`. Build a map of what's already watched: for each existing rule, note its `type` + `trigger` and, where relevant, the entity it's scoped to (endpoint, screen, etc.). This is the "covered" set.

### Step 2. Read current health

- Call `app_insights` for the app-level picture: crash-free sessions (and whether it's trending down via `rate`), ANR/OOM/hang presence, non-fatal crash volume.
- Call `apm_list_groups` per APM metric (`network`, `launch`, `flows`, `screen_loading`, `frame_drop`), sorted to surface the worst entities first. Capture `apdex_score`, `failure_rate`, p95/p50 for the key/high-traffic groups.

If the app has no data yet (brand-new integration), skip straight to Step 4's baseline recommendation — there are no live metrics to evaluate, so propose the standard baseline as proactive coverage.

### Step 3. Compute the gaps

A metric is a **gap** when **both** are true — check coverage first, every time:
1. **No existing rule covers it** (no rule of that type+trigger, scoped to that entity). If `has_alert` is true for the metric, it is COVERED — it can never be a gap, no matter how bad the current value is. Do not recommend a second alert for it.
2. It is **below the bar** (network apdex < 0.7, failure_rate > 10%, dropoff > 30%, crash-free below target). Only metrics the tools actually surface count: stability (crash-free sessions/users, ANR) from `app_insights`, and per-entity performance (apdex/failure_rate/p95 per endpoint/screen/flow/launch) from `apm_list_groups`.

Explicitly exclude:
- **Healthy metrics** — value is above the bar. No alert needed, even if uncovered. Say so; don't recommend.
- **Already-covered metrics** — a rule of that type+trigger already watches it. No duplicate, even if the metric is currently bad.

When a real gap requires a rule type the app's plan or platform doesn't support (e.g. ANR on iOS, or a plan-gated type absent from `init`), still report it as a gap and name the plan/platform requirement. Do not silently drop it.

### Step 4. Present recommendations before creating anything

Output three groups so the user sees the full reasoning:

1. **Gaps to close** — for each: the metric, its current value, why it's a gap, and the proposed alert (type, trigger, threshold from the baseline table, window, scope).
2. **Healthy / no alert needed** — uncovered metrics that are fine, so the user knows you looked and chose not to add noise.
3. **Already covered** — so the user sees existing protection.

For a brand-new app, group 1 is the baseline set proposed proactively. Do not write yet.

### Step 5. Create approved alerts

For each recommendation the user approves:

1. Call `read_alerts(action: "init", slug, mode)`. Build payloads **only** from the types, triggers, conditions, and lookup IDs that init exposes for this app. If a recommended type/trigger isn't in init, it isn't available — surface that instead of forcing it.
2. Call `write_alerts(action: "create", ...)` with the payload.
3. Confirm each created alert back to the user.

Wire encoding the tool expects (get it right or the rule is silently malformed):
- Operators are **stringified integers**: `"1"`=equals, `"4"`=less than, `"5"`=greater than, `"8"`=is one of, `"3"`=contains.
- `trigger_options.time` is the **integer key** from init's time options for that trigger — not `"1h"` or `24`.
- Apdex (Overall app) thresholds are **0–1 decimals** (`0.8`, not `80`). failure_rate / crash-free / dropoff are literal percentages.
- p95/p50 thresholds are in **seconds**, not milliseconds.
- Lookup values (developer / team / tracking-tool IDs) come from init, never invented.
- APM rules carry a `count` floor so low-traffic noise doesn't trip them.

### Step 6. Pick a delivery channel

A created alert needs an action or it's silent. Default to `send_email` to the appropriate developers (use init's lookup; `["all"]` if the user has no preference). If the user names Slack/Jira/PagerDuty/etc., use a `forward` action with the tracking-tool ID from init. Don't create an alert with no action.

## Style

- Lead with current numbers: "checkout endpoint apdex is 0.45 (bar is 0.7), no alert" — concrete and checkable.
- Use the baseline thresholds for created alerts, not the metric's current bad value. (A metric at 0.45 still gets a 0.7 alert, so it keeps firing until truly fixed.)
- Don't over-recommend. A handful of meaningful alerts beats one per endpoint.
- Never present a create as done before it returns success.

## Red Flags — STOP and surface to the user

- "This metric has no alert, so it's a gap." Only if it's also unhealthy. A healthy uncovered metric is not a gap — don't add the alert.
- "This metric is bad, so add an alert." Check coverage first — if a rule already watches it, adding another is duplication.
- "I'll set the threshold to the current value (0.45)." No — use the baseline bar (0.7). An alert pinned to today's bad number won't tell you when things get worse.
- "I'll create the alert without calling init." Don't — you'll send a type/trigger or lookup ID the app doesn't support and the write fails or corrupts the rule.
- "ANR is a gap, I'll add it" — on an iOS app. ANR is Android-only. Report the gap with the platform caveat instead of creating an invalid rule.
- "I'll recommend the full baseline even though the app's metrics are all healthy." For an app with data, recommend only real gaps. The full baseline is for brand-new apps with no data yet.
- "I'll create twelve alerts, one per endpoint." That's how you manufacture the noise `luciq-alert-noise` has to clean up. Scope to key/high-traffic metrics.
