---
name: luciq-alert-config
description: Use when the user wants to create, set up, configure, change, enable, disable, delete, or inspect a specific Luciq alert (rule). Triggers include "alert me when…", "notify me when…", "create/set up an alert for…", "add an alert", "change the threshold on…", "turn off/disable this alert", "delete that alert", "show me my alerts", or naming a metric and a condition to watch (crash-free sessions, ANR, network failure rate, apdex, p95, launch time, crash spikes). Authors a valid alert payload by reading the per-app init catalog first, asking for any missing detail instead of guessing, and surfacing tool rejections honestly.
---

# Luciq Alert Configuration

Create and manage individual Luciq alerts (rules) correctly. The work is translating a
user's natural-language intent into a valid `write_alerts` payload — and the only way to
do that reliably is to read the app's `init` catalog first and build strictly from it.
Never guess an id, a threshold, or whether a metric is even available.

## When NOT to use this skill

- The user wants to **reduce too many / noisy** alerts → `luciq-alert-noise`.
- The user wants to find **missing coverage / what they're not monitoring** → `luciq-alert-gaps`.
- The user is investigating *why* something crashed or hung → `luciq-debug`.
- First-time SDK install / wiring `Luciq.start(...)` → `luciq-setup`.

This skill is for acting on a *specific* alert the user describes — create it, change it,
or manage its lifecycle.

## Prerequisites

The Luciq MCP server must be configured and authenticated. If the alert tools are not
available, STOP and direct the user to set up the MCP server (or run `luciq-setup`).

Tools this skill uses:

| Tool | Action | Purpose |
| --- | --- | --- |
| `read_alerts` | `init` | The per-app catalog: valid rule types, triggers, conditions, actions, operators, time-window keys, and lookup tables (developers/teams/tracking tools/tags). The source of truth for what's possible. |
| `read_alerts` | `list` / `details` | Find or inspect an existing alert (for update / enable / disable / delete). |
| `write_alerts` | `create` / `update` / `delete` | Apply the change. State-changing — confirm intent first. |

## Workflow

### Step 1. Classify the intent

- **Create** a new alert ("alert me when…", "set up an alert for…")
- **Update** an existing alert ("change the threshold to…", "also notify Slack")
- **Enable / disable** ("pause this alert", "turn it back on")
- **Delete** ("remove that alert")
- **Inspect** ("show my alerts", "what does alert X do")

For inspect, call `read_alerts(list/details)` and answer. For the rest, continue.

### Step 2. Gather the spec — never create on an unstated value

A create/update needs: the **metric/trigger**, a **threshold** (for threshold triggers), a
**time window** (where applicable), optional **conditions** (filters), and an **action**
(who/where to notify). Two distinct cases:

- **Metric/trigger is ambiguous** ("alerts about network performance"; "crashes happen too
  much / too many crashes / app is crashing a lot"): vague intensity words don't name a
  single trigger — "too many crashes" could mean occurrences in a time window, affected
  users in a time window, or a % of users/sessions. Ask which the user means before going
  further. Do NOT pick one silently, and do NOT map volume language to a stability *rate*
  like `crash_free_session` (that's a different concept).
- **Metric is clear but the threshold/value is unstated** ("alert me when crash-free
  sessions are low", "the app launch feels slow"): the threshold is a user-specific choice
  — do NOT silently create with a guessed number. Either ask what number they want, or
  **propose the standard baseline and confirm before creating** (e.g. "I'll alert when
  launch apdex drops below the standard 0.85 — want a different threshold?"). Do not call
  `write_alerts` until the user has supplied or confirmed the threshold.

The rule: a missing threshold/channel/time-window is never silently filled. You may
*suggest* the documented baseline, but the create only fires after the user confirms it.
A fabricated-and-shipped threshold is the failure mode to avoid.

### Step 3. Read the init catalog

Call `read_alerts(action: "init", slug, mode)`. This tells you, for THIS app and plan:
which rule types exist, each type's triggers, the valid conditions/operators, the actions,
the time-window keys for each trigger, and the real lookup ids. Everything you send must
come from here.

### Step 4. Map intent → an init-exposed type + trigger; gatekeep

Pick the type and trigger that match the user's words. Disambiguate carefully:

| User says | Trigger |
| --- | --- |
| crash affecting X% of **sessions** | `configurable_velocity_alert` |
| crash affecting X% of **users** | `crash_affecting_percentage_of_users` |
| crash-free **sessions** below X% | `crash_free_session` |
| crash-free **users** below X% | `crash_free_users_overall` |
| ANR / "app not responding" | `anr_free_users_overall` / `anr_free_sessions_overall` |
| "slowest 5% / 95th percentile" latency | `p95` |
| network failures / error rate | `failure_rate` |
| crash spike / accelerating | `accelerating_crash` |
| any new crash | `crash_reported` |

If the type/trigger/condition/action the user wants is **not in init** (plan-gated, e.g.
release rollout or feature flags; platform-gated, e.g. ANR on iOS; or simply unsupported),
STOP and tell the user it isn't available for this app and why. Do not force it.

### Step 5. Build a correct payload

Encode to the wire format the tool expects — getting this wrong silently malforms the rule:

- **Operators are stringified integers**: `"1"`=equals, `"4"`=less than, `"5"`=greater than,
  `"8"`=is one of, `"3"`=contains. Send `>` as `"5"`, `<` as `"4"`.
- **`trigger_options.time` is the integer key** from init's time options for that trigger —
  read it from init. Never send `"1h"`, `24`, or a raw minute count.
- **Apdex (Overall app, Release rollout) thresholds are 0–1 decimals**: `0.8` for 80%,
  never `80`. Other percentages (crash-free, ANR, failure_rate, dropoff, velocity) are
  **literal numbers** (e.g. `99`, `10`).
- **p95 / p50 thresholds are in seconds** (`0.5` = half a second), not milliseconds.
- **Crashes use `app_version_v2`**, never the deprecated `app_version`.
- **Lookup values** (tracking-tool id for `forward`, developer ids for `send_email`, team
  id for `set_team`) come from init's lookup tables — never invented. `send_email` to
  everyone is `{ "developer_ids": ["all"] }`.
- **Operation**: `0` = AND, `1` = OR (a plain integer, not a string).

Value ranges (a value outside the range is invalid — fix it or ask, don't send it):
apdex 0–1; crash-free / ANR / velocity / failure_rate / dropoff 0–100.

Pick an **action** — an alert with no action is silent. Default to `send_email` to the
relevant developers unless the user named a channel (then `forward` to that tracking tool).

### Step 6. Write, then verify honestly

Call `write_alerts(action, …)`. Confirm before creating/deleting if the intent was at all
ambiguous. If the tool returns an error (e.g. a 422: out of range, limit reached, id not
found), **surface that failure plainly** — say what failed and why. Never report success
for a call that errored. On success, confirm the alert's effective behavior back to the user.

## Style

- Translate, don't interrogate: ask only for the piece that's genuinely missing, one question.
- Mirror the user's numbers exactly (97% stays 97%, not "about 95%").
- Confirm state-changing actions (create/delete/disable) before firing when intent is fuzzy.
- Never claim an alert was created until the tool returns success.

## Red Flags — STOP

- "No threshold given, I'll use a sensible default and create it." Stop — you may *propose*
  the standard baseline, but confirm with the user before calling write_alerts. Never ship
  a create on a threshold the user didn't state or confirm.
- "I'll call write_alerts without init." Stop — you'll send ids/triggers the app may not
  support, and the write fails or corrupts the rule.
- "The type isn't in init but the user asked for it, I'll send it anyway." Stop — it's
  unavailable. Say so.
- "It returned a 422 but I'll tell the user it's set up." Never. Report the failure.
- "Apdex 90% → send 90." Stop — apdex is 0–1; send `0.9`.
- "Crashes filter on app_version." Stop — use `app_version_v2`.
