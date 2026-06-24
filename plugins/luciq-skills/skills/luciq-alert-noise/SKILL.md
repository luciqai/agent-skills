---
name: luciq-alert-noise
description: Use when the user wants to reduce noisy, chatty, or spammy Luciq alerts, cut alert fatigue, or stop being over-notified. Triggers include "my alerts are too noisy", "I get too many alert emails/notifications", "alerts are firing constantly", "clean up / tune / audit my alerts", "which alerts are spammy", "stop paging me so much", or asking which alert rules fire too often. Inspects each alert's trigger frequency via the Luciq MCP and recommends targeted fixes (raise threshold, narrow scope, throttle, merge, or disable) — never blindly silencing a safety-critical alert.
---

# Luciq Alert Noise Reduction

Find the alert rules that fire too often to be useful, and fix them at the source. Noise is not "an alert fired a lot" — it is "an alert fired a lot **and the firings were not individually worth a notification**." The job is to cut fatigue without cutting coverage. Every recommendation is grounded in MCP data; never guess which alerts are noisy.

## When NOT to use this skill

- The user wants to **add** missing alerts or check monitoring coverage — use `luciq-alert-gaps`.
- The user wants to **create, change, or manage one specific alert** they describe — use `luciq-alert-config`.
- The user is investigating *why* something crashed/hung — use `luciq-debug`.
- First-time SDK install or wiring `Luciq.start(...)` — use `luciq-setup`.
- The user wants to resolve/acknowledge a specific firing (incident), not change the rule. That is a one-call `write_triggered_alerts` action, not a noise audit — just do it directly.

If the request fits one of the above, STOP and route there.

## Prerequisites

The Luciq MCP server must be configured and authenticated. If the alert tools are not available, STOP and direct the user to set up the MCP server (or run `luciq-setup`).

Tools this skill uses (verbatim names):

| Tool | Action | Purpose |
| --- | --- | --- |
| `read_alerts` | `list` | All alert rules + their `conditions_met_count` (the rolling trigger count) and current `status`. Sort by `highest_triggered_count` to surface the worst first. |
| `read_alerts` | `details` | Full payload of one rule. Call before updating, to mirror the existing shape. |
| `read_alerts` | `init` | Per-app catalog of valid types/triggers/conditions/actions/operators and lookup IDs. Call before any update. |
| `read_triggered_alerts` | `list` | Actual firing history with `status` (open / resolved), `type`, `count`, and timestamps. Use to judge whether firings were actionable. |
| `write_alerts` | `update` | Apply a remediation to a rule. State-changing — confirm first. |
| `write_alerts` | `delete` | Remove a fully redundant rule. State-changing — confirm first. |
| `write_triggered_alerts` | `resolve` | Clear stale open firings as a side cleanup. |

You MUST base every "this alert is noisy" claim on a value the MCP returned. Do not infer noise from a rule's title or your priors.

## What "noisy" means

Luciq tracks how often each rule's conditions are met on a rolling 8-day window and exposes it as `conditions_met_count` on the `read_alerts` list response. That counter is the product's own noise signal: the dashboard treats a rule that crosses **4** matches in the window as a candidate for noise. Use `> 4` as the entry filter for "look closer", not as the verdict.

A rule is genuinely noisy when both hold:
1. It fires frequently (`conditions_met_count` is high relative to the others, and well above 4), AND
2. The firings are not individually worth a separate notification — because the threshold is trivially low, the scope is too broad (no conditions), it duplicates another rule, or it pages on a non-actionable signal.

A rule that fires often **and every firing matters** (a real incident stream) is not noise. The fix there is throttling the *notification*, not weakening the *detection*.

## Workflow

### Step 1. Pull the alert inventory

Call `read_alerts(action: "list", sort_by: "highest_triggered_count", sort_direction: "desc")`. This is the spine of the audit. Note for each rule: `ulid`, `type`, `trigger`, `conditions`, `actions` (and any `frequency` throttle), `status`, and `conditions_met_count`.

Drop disabled rules from consideration — a disabled rule is already silent. Say so if the user asked about one.

### Step 2. Triage by trigger count

Partition the enabled rules:

- **Quiet** (`conditions_met_count` ≤ 4): leave alone. Do not recommend changes to a rule that isn't firing much, even if it looks imperfect. Surface that they are healthy.
- **Loud** (`conditions_met_count` > 4): candidates. Continue to Step 3 for each.

If nothing is loud, report that plainly — "no noisy alerts, here's what you have" — and stop. Do not invent problems.

### Step 3. Diagnose each loud rule

For each candidate, decide *why* it is loud before deciding the fix. When the count alone is ambiguous, call `read_triggered_alerts(action: "list", filters: { ... }, sort_by: "count")` to see whether the firings were distinct real events or the same thing over and over.

Map the cause to the right remediation:

| Diagnosis | Signal in the data | Remediation |
| --- | --- | --- |
| Threshold trivially low | e.g. `occurrences_count > 1`, `crash_free_session < 99.9`, p95 just above normal | **raise_threshold** to a meaningful level |
| Scope too broad | no `conditions`, fires on every crash/request/version | **narrow_conditions** (add app_version, key_metric, endpoint, etc.) |
| Detection is right, paging is too frequent | threshold sound, firings are real, but notified on every match | **add/lengthen throttle** (set `frequency` on the action) |
| Exact duplicate of another rule | same `type` + `trigger` + `conditions` as a sibling | **merge** (keep one, delete the other) |
| Fully redundant / obsolete | superseded by a broader rule, or watches a retired metric | **disable** or **delete** |

### Step 4. Protect safety-critical alerts

Some alerts are *supposed* to fire loudly because each firing is an emergency. Never weaken detection or disable these — at most, throttle the notification. Treat as safety-critical:

- `crash_affecting_percentage_of_users`, `configurable_velocity_alert` (a crash hitting real users)
- `crash_free_session` / `crash_free_users_overall` below ~95%
- `anr_free_users_overall` / `anr_free_sessions_overall`
- `affected_users_in_time` with a large user count

If one of these is loud, the recommendation is **add_throttle** or a small **raise_threshold**, with an explicit note that you are keeping detection intact. If you find yourself about to recommend disabling one, STOP — that is removing a safety net.

### Step 5. Present the plan before touching anything

Output a per-rule table the user can approve: rule title, why it's noisy (cite `conditions_met_count` and the diagnosis), and the proposed remediation. Group safety-critical rules separately so the user sees they're handled conservatively. Do not write yet.

### Step 6. Apply approved remediations

For each rule the user approves:

1. Call `read_alerts(action: "init", slug, mode)` to get valid fields/IDs, and `read_alerts(action: "details", ulid)` to mirror the rule's current payload.
2. Build the updated payload — change only the field the remediation targets (threshold value, an added condition, a `frequency` on the action, or `status`). Keep everything else identical.
3. Call `write_alerts(action: "update", ...)` (or `delete` for a confirmed merge/redundant rule).
4. Confirm each change back to the user with the new effective behavior.

Respect the payload rules the `write_alerts` tool documents — most importantly: Overall-app/Release-rollout apdex thresholds are 0–1 decimals (send `0.9`, not `90`); all other percentages are literal; operators are stringified integers; and you may only use types/triggers/conditions that `init` exposes for this app.

### Step 7. Optional — clear stale firings

If the audit surfaced open triggered alerts that are clearly stale (resolved in reality but still `open`), offer to clear them via `write_triggered_alerts(action: "resolve", ulid)`. This is cleanup, not noise reduction — keep it separate and only on request.

## Authoring changes correctly (read before any write_alerts call)

Every remediation you apply goes through `write_alerts`. Produce a valid payload:

1. Call `read_alerts(action: "init", slug, mode)` first and `read_alerts(action: "details", ulid)` to mirror the rule's existing shape. Build only from what init exposes for this app; if a field isn't in init, don't send it. Never invent a tracking-tool / developer / team id — take it from init's lookup tables.
2. Wire encoding the tool expects:
   - Operators are **stringified integers**: `"1"`=equals, `"4"`=less than, `"5"`=greater than, `"8"`=is one of, `"3"`=contains. Send `>` as `"5"`, `<` as `"4"`.
   - `trigger_options.time` is the **integer key** from init's time options for that trigger — not hours/minutes. Read the key from init; never send `"1h"` or `24`.
   - Apdex (Overall app) thresholds are **0–1 decimals** (`0.8` for 80%, never `80`). Other percentages (crash-free, failure_rate, velocity) are literal numbers.
   - p95/p50 thresholds are in **seconds** (`0.5` = half a second), not milliseconds.
   - Crashes use `app_version_v2`, not the deprecated `app_version`.
3. Value ranges: apdex 0–1; crash-free / ANR / velocity / percentage 0–100. Never raise a threshold past these bounds.
4. Change only the field the remediation targets; keep everything else identical to the existing rule.

## Style

- Quantify every claim: "fired 47 times in 8 days" beats "fires a lot".
- Prefer the least destructive fix that works: raise/narrow/throttle before disable; disable before delete.
- One change per rule per pass. Don't stack five edits and lose the thread.
- Never present a write as done before it returns success.

## Red Flags — STOP and surface to the user

- "This alert fires constantly, so disable it" — check first whether each firing is a real incident. If so, throttle, don't silence.
- "It's a crash-affecting-users alert firing 40 times, let's turn it off." Never. That's the alert doing its job. Throttle the notification.
- "I'll guess the threshold should be ~50." Base it on the metric's normal range from the data, or ask. Don't pull numbers from nowhere.
- "I'll update the rule without calling init." Don't — you'll send IDs/triggers the app may not support and the write will fail or silently corrupt the rule.
- "The user said clean up, so I'll batch-disable everything loud." Get per-rule approval. Bulk-disabling is how coverage quietly disappears.
- "conditions_met_count is 3 but the title sounds spammy, I'll flag it." 3 is below the signal. Leave it.
