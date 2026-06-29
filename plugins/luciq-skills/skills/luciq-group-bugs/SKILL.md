---
name: luciq-group-bugs
description: Use when the customer wants to consolidate, group, or deduplicate their Luciq bugs by marking duplicates according to their own grouping logic. Triggers include "group my bugs by X", "mark these bugs as duplicates", "dedupe / consolidate the bug list", "merge bugs that share the same screen / failed request / tag / title / version". Fetches a scoped candidate set via list_bugs, derives an explainable grouping key per bug (from list_bugs metadata and, only when the key needs it, bug_details logs and steps), renders a dry-run plan, and marks duplicates via update_bug ONLY after the customer approves. This is a WRITE skill — it mutates how bugs are grouped. For root-causing one bug or proposing a code fix use luciq-debug; for a read-only report of bug volume and themes use luciq-readout.
---

# Luciq Bug Grouping

Consolidate a customer's bug list by marking duplicates according to **their own** grouping logic. The mechanism is **filter, then cluster by an explainable key**: compile the customer's logic into (1) a `list_bugs` filter set that bounds the candidate pool and (2) a per-bug **grouping key** built from the exact fields their logic names, then group bugs that share a key and merge each group into one master.

This is the plugin's first **write** skill. `update_bug`'s `mark_as_duplicate` action is destructive (`destructive_hint: true`): the duplicate's occurrences move into the master's group and the duplicate's status, priority, and assignee are **overwritten** by the master's — and are not rolled back when the bug is later unmarked. There is no bulk undo on the server. So the entire spine of this skill is **propose → prove → confirm → write**: the skill computes a dry-run plan, shows the exact key that unites every group, and calls `update_bug` only after the customer approves the plan. It never writes from logic alone.

Every merge in the plan is auditable: the customer can see *why* two bugs grouped (the verbatim key) before a single write happens. A merge the customer didn't approve never happens.

## When NOT to use this skill

- **Root-causing one specific bug** and proposing a code fix → use `luciq-debug`. That skill maps a single occurrence to source and forms a hypothesis. This one reorganizes many bugs.
- **A read-only report** of bug volume, priorities, or themes → use `luciq-readout`. That skill never mutates; it reports. This one mutates grouping and must never be used just to "look at" bugs.
- **General bug triage where Luciq is not the data source.** This skill is grounded in what the Luciq MCP exposes; without it, do not pretend to use it.
- **Logic that cannot reduce to concrete fields** ("group bugs about the same user journey", "cluster by vibe"). This skill is deterministic by design — it does not semantically guess. If the logic is fuzzy, STOP and ask the customer to restate it in terms of concrete fields (title, screen, tag, category, failed request, app version, user attribute). Do not invent a clustering it can't explain.

If the request fits the first three, route there and stop.

## Prerequisites

The Luciq MCP server must be configured and authenticated. If MCP tools are not available, STOP and direct the customer to https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide for setup, or run `luciq-setup`.

The MCP exposes (verbatim names) — this skill uses exactly four:

| Tool | Role in this skill | Read/Write |
| --- | --- | --- |
| `list_applications` | Resolve `(slug, mode)`. Never hard-code a slug. | read |
| `list_bugs` | Fetch the scoped, capped candidate pool using the compiled filter set. | read |
| `bug_details` | Conditional enrichment — called **only** when the grouping key depends on per-bug logs, user steps, or attributes not returned by `list_bugs`. | read |
| `update_bug` | The write. `action: mark_as_duplicate` (+ `original_bug_number`) merges a bug into a master; `action: unmark_as_duplicate` powers undo-last. Post-approval only. | **write** |

**Permission.** `update_bug` requires `bugs.list.modify`. If the authenticated token lacks it, the skill can still fetch candidates and render the dry-run plan, but it CANNOT apply — say so at the plan stage and stop before the write.

**Web-fetch for log-based keys.** Grouping by network failures or user steps additionally needs (a) the `bugs.network_logs.view` / `bugs.user_steps.view` permissions, so `bug_details` includes the archive URLs, and (b) a web-fetch capability to retrieve those signed URLs — the MCP tools return only the URL, not the log contents. Keys built from inline fields (title, category, screen, tag, version, user attribute) need neither. If either is unavailable, the log-based recipes can't run; say so rather than substituting a weaker key.

**`update_bug` is callable inline.** Its input schema is a flat object (no top-level `anyOf` / `oneOf` / `not`), so unlike the `apm_*` tools it is **not** stripped by the AI-94 top-level-combinator issue. Call it through the normal MCP client; no direct-JSON-RPC workaround is needed.

## The cardinal rule

**No `update_bug` write happens until the customer has approved the rendered plan.** Not from the client, not from a direct call, not "the rule is obviously right so I'll just apply it". The plan is the contract: only groups and merges shown in the approved plan get written. This is the inverse of `luciq-readout`'s absolute "never write" — here writes happen, but *only* post-approval.

## Workflow

Track every step. Stop and ask rather than guess — a wrong rule silently merges unrelated bugs and overwrites their status and priority.

```
Grouping Progress:
- [ ] 1. Resolve app + mode (list_applications) — never hard-code a slug
- [ ] 2. Elicit the grouping logic (free-form + suggested starters)
- [ ] 3. Compile logic -> (a) list_bugs filter set, (b) grouping-key recipe
       └─ if the logic is fuzzy / can't reduce to concrete fields: STOP, ask the customer to restate
- [ ] 4. Fetch candidates (list_bugs, scoped + capped; warn/paginate if larger — never silently truncate)
- [ ] 5. Enrich ONLY if the key needs it (bug_details for network-log / user-step / attribute signals)
- [ ] 6. Compute the grouping key per bug -> form groups -> DROP singletons (a group of one is not a duplicate)
- [ ] 7. Pick the master per group = oldest bug (overridable by the customer)
- [ ] 8. Render the dry-run PLAN (groups, master, members, the verbatim key, the skipped list)
- [ ] 9. ⛔ HARD GATE — wait for explicit customer approval
- [ ] 10. Snapshot each member's status/priority, then apply: update_bug action=mark_as_duplicate per member, recording each write
- [ ] 11. Report results; offer undo-last (detach only, OR detach + restore status/priority)
```

### Step 1 — Resolve app and mode

Call `list_applications`. Confirm `mode` with the customer; default to `production`. Each mode (`production`, `beta`, `staging`, `alpha`, `qa`, `development`) is a separate dataset. All candidates and the master in any merge must share one `(slug, mode)` — the skill never merges across apps or modes.

### Step 2 — Elicit the grouping logic

Ask the customer, in plain language, how they want bugs grouped. Offer a few starters so they don't start from a blank page:

- **By title** — bugs whose titles describe the same problem.
- **By screen** — bugs reported from the same `current_view`.
- **By failed request** — bugs whose network logs share the same failed endpoint(s) and status.
- **By tag or category** — bugs sharing a tag set or category.
- **By app version** — same issue scoped to a version.
- **By user attribute** — bugs from users with the same attribute value (e.g. `plan = pro`).

**Dimensions combine — treat the starters as multi-select, not pick-one.** The customer can choose more than one at once (e.g. "same screen **and** same failed request", or "same title **and** same app version"). Each chosen dimension becomes one component of the composite key (see `references/grouping-keys.md`). The customer can also describe their own; the starters are examples, not a closed menu.

### Step 3 — Compile the logic (the deterministic gate)

Translate the logic into two artifacts (recipes are in `references/grouping-keys.md`):

- **Filter set** — `list_bugs` filters that bound the candidate pool (e.g. `app_version`, `tag`, `status_id`, date range).
- **Key recipe** — the per-bug composite key the logic implies (e.g. `current_view` + sorted failed requests).

**If the logic cannot be reduced to concrete fields, STOP here.** Tell the customer what's missing and ask them to restate it concretely. Do not approximate fuzzy logic with a semantic guess — a merge the skill can't explain is a merge it shouldn't make.

### Step 4 — Fetch candidates

Call `list_bugs` with the compiled filter set, scoped to `(slug, mode)`. `list_bugs` returns **at most 50 bugs per call** (`limit` max 50, default 20), so to assemble a candidate pool larger than one page, **paginate with `offset`** (0, 50, 100, …) until you hit the cap or the results run out. Cap the total pulled (default ~300, i.e. ~6 pages). If the scope exceeds the cap, warn the customer, show what is covered, and offer to narrow the filters or raise the cap. **Never silently truncate** — a partial set presented as complete is a silent error.

### Step 5 — Enrich (conditional)

`list_bugs` returns only a thin CSV row per bug: `title`, `categories`, `type`, `duplicate_type`, `email`, `status_id`, `priority_id`, `number`, `reported_at`, `last_activity`, `duplicated_bugs_count`. Any key field beyond those comes from `bug_details`. Call `bug_details` per candidate only when the key recipe needs it, and only for the candidates in scope. Two tiers of enrichment:

- **Inline fields** — `current_view`, `tags`, `app_version`, and `user_attributes` are returned directly in the `bug_details` response (`state.fields.*` / top-level `tags`). Read them straight off the payload.
- **Log-archive signals** — the network-log and user-step signals are **not** inline. `bug_details` returns only a **signed archive URL** under `state.logs.network_log.url` / `state.logs.user_steps.url` (and only if the token has `bugs.network_logs.view` / `bugs.user_steps.view`). To build `failed_requests_sig` or `user_steps_sig` you must, per candidate: (1) read the URL from `bug_details`, (2) **fetch** it (plain HTTPS GET — the URL is pre-signed, no auth header), (3) **decompress + parse** the archive (typically base64 → zlib → JSON), then (4) derive the signature. This needs a web-fetch capability alongside the MCP tools; the Claude Code / Cursor host provides one. If the permission is missing, the URL is absent, or the log is empty, the bug is **skipped** (see "missing fields"), never guessed.

(See the field-source map and the fetch procedure in `references/grouping-keys.md`.)

### Step 6 — Compute keys and form groups

Build the key for each candidate per `references/grouping-keys.md` (normalize, sort sets, strip URL query strings). Group bugs by identical key. **Drop singleton keys** — only keys shared by ≥2 bugs become proposed merges. A bug missing a field the key requires gets **no key** and goes on the skipped list with the reason ("skipped: no network log") — it is never bucketed into a catch-all group.

### Step 7 — Pick the master

For each group, default the master to the **oldest** bug (earliest reported / lowest number), preserving the original report and its history. Show that choice in the plan. The customer can reassign the master for any group before approving.

### Step 8 — Render the dry-run plan

Render the plan per `references/plan-format.md`. For each group show: the master (number + report date), each member that will merge, and the **verbatim key** that united them. Separately list every skipped / not-grouped bug with its reason. Nothing merges that isn't on this plan.

### Step 9 — Hard gate

Present the plan and **wait for explicit approval.** If the token lacks `bugs.list.modify`, say the plan can be shown but not applied, and stop here.

### Step 10 — Apply

Marking a bug as a duplicate **overwrites its status, priority, and assignee** with the master's (`inherit_parent_values` on the server), and unmarking does **not** roll those back. So **before** marking each member, snapshot its current `status_id` and `priority_id` (already present on the candidate's `list_bugs` row) into the session ledger — that snapshot is what makes "restore status/priority" possible in undo. Then, for each member in each approved group, call:

```
update_bug(slug, mode, number: <member>, action: "mark_as_duplicate", original_bug_number: <master>)
```

Apply sequentially and record each result (ok / failure, the bug number, and the pre-merge status/priority snapshot) in the session ledger. Guards:
- **Self-merge guard** — never mark the master as a duplicate of itself.
- **Already-grouped** — if a candidate is already a duplicate/master, surface it in the plan and exclude it from re-merge by default.
- **Continue on failure** — if one `update_bug` fails, record it, keep going, and report all failures at the end. Never silently drop a member.

### Step 11 — Report and offer undo-last

Summarize what merged (groups, masters, member counts) and list any failures. Then offer **undo-last** in two modes, using the session ledger:

- **Detach only** — `update_bug(action: "unmark_as_duplicate")` per member. Restores each bug to standalone but leaves the parent's status/priority on it (unmark does not roll those back).
- **Detach + restore status/priority** — after unmarking each member, re-apply its snapshotted values via `update_bug(status_id:, priority_id:)`.

Tell the customer up front that **assignee cannot be restored** in either mode — `update_bug` has no assignee parameter, so a merge's assignee change is irreversible through this skill. Only offer undo for merges this skill made this session; never unmark pre-existing groups.

## Out of scope

This skill is bugs-only and deliberately does not touch `crash_*`, `apm_*`, `list_app_hangs`, `app_insights`, surveys, or reviews. It does not change a bug's status, priority, tags, or assignee except as the unavoidable side effect of `mark_as_duplicate` (which the customer is told about up front, including that assignee can't be restored). It does not regroup across apps/modes, and it does not move bugs between two existing masters (that's beyond v1 — unmark then re-mark instead).

## Style

- Do not fabricate bug numbers, counts, or keys. Every number in the plan comes from a tool result.
- Do not merge anything not on the approved plan.
- Do not approximate fuzzy logic with a semantic guess — restate-or-stop.
- If `list_bugs` returns nothing for the scope, surface that; do not invent candidates.
- Always show the verbatim key for every group so each merge is auditable.

## Red Flags — STOP and surface to the customer

If you catch yourself thinking any of these, you are about to ship a wrong or unaudited merge. STOP:

- "The logic is a bit vague but I can probably cluster these by meaning." No. Restate-or-stop — this skill is deterministic.
- "I'll apply the merges without showing the plan because the rule is obviously right." Never. The plan + approval gate is the contract.
- "The scope is bigger than the cap but I'll just group what I pulled." That's a silent truncation. Warn and offer to narrow or proceed explicitly.
- "This bug has no network log but it probably belongs with the others." No — missing field means skipped, never catch-all.
- "I'll quietly skip the member that failed to merge." Surface every failure in the end report.
- "I'll mark the master as a duplicate too." Self-merge guard — the master is never a duplicate of itself.
- "The token can't write, but I'll try the merges anyway." Stop at the plan stage and tell the customer the permission is missing.
- "Undo will put everything back the way it was." It won't — unmark restores neither status/priority (only the snapshot + re-apply does) nor assignee (not at all). Say what undo can and can't restore.
- "I'll group by screen / tag / version straight from the list_bugs rows." Those fields aren't in the `list_bugs` response — pull them from `bug_details` first.

The pattern: every shortcut trades "looks done" for "actually correct and reversible". A destructive write the customer didn't approve is the one failure this skill exists to prevent.
