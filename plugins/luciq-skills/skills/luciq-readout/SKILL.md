---
name: luciq-readout
description: Produce a shareable, audience-tailored readout of a Luciq app's health and quality, not a single fix or ship decision. Covers version-vs-version and period-over-period comparisons rendered for a chosen persona: C-suite, VP, PM, EM, or QA. Use whenever the user asks for an exec or leadership summary, a release readout, a stability or quality report, a "how is the app doing this week vs last" rollup, or a "compare version X to version Y for a PM" comparison. Pulls headline aggregates (stability, APM performance) from app_insights and slices detail across crashes, hangs, bugs, reviews, and NPS/CSAT surveys via the Luciq MCP, drilling into per-occurrence stacktraces and diagnostics for the EM tier, then renders the same data at the altitude each audience needs, citing every number to the tool and params that produced it. For root-causing one crash, hang, or bug use luciq-debug; for verifying an SDK upgrade before shipping use luciq-verify; for first-time SDK integration use luciq-setup.
---

# Luciq Stakeholder Readouts

Produce a shareable, audience-tailored readout of a Luciq app's health and quality. The mechanism is **render the same data at the right altitude**: pull headline aggregates from `app_insights` (stability rates plus the APM performance section), slice detail across crashes, hangs, bugs, reviews, and NPS/CSAT surveys, drill into per-occurrence stacktraces and diagnostics for the EM tier, then compose a report tuned to one persona's question. The skill catches the failure mode of generic reporting — a dashboard dump that nobody reads, a stacktrace pasted into a C-suite summary, a crash-free percentage quoted from a section that actually returned an error. None of those are wrong on their face. All of them produce a readout that looks authoritative and misleads.

The job of this skill is communication, not adjudication. Every number is cited to the MCP tool and the parameters that produced it. If a query returns nothing, or a section comes back as an error, that fact is surfaced — never filled in with a plausible-looking number. **A readout's only value is that the reader can trust every figure in it.** A fabricated number destroys that for the whole document.

## When NOT to use this skill

- Root-causing one specific crash, hang, or bug and proposing a code fix, use `luciq-debug`. That skill maps a single occurrence to local source and forms an evidence-cited hypothesis. This one summarizes many occurrences for an audience.
- Verifying that an SDK version upgrade did not break the integration before shipping, use `luciq-verify`. That skill audits a synthetic smoke against a contract. This one reports production health.
- First-time integration of Luciq into a project, use `luciq-setup`.
- General reporting where Luciq is not the data source. This skill is grounded in what the Luciq MCP exposes; without it, do not pretend to use it.

If the request fits any of the above, route there and stop. Composing a readout when the user wanted a fix, a verdict, or an investigation wastes the audience's trust on the wrong artifact.

## Prerequisites

### Hard dependencies (skill refuses to run without these)

| Artifact | What for | If missing |
| --- | --- | --- |
| **Luciq MCP server, authenticated** | The entire readout is grounded in what the Luciq MCP exposes — `list_applications`, `app_insights` (stability + APM), `list_crashes`, `crash_patterns`, `list_app_hangs`, `list_bugs`, `list_reviews`, `list_surveys` / `survey_details` (NPS/CSAT), and the per-occurrence detail tools (`crash_details`, `list_occurrences_tokens`, `get_occurrence_details`, `crash_diagnostics`). Without it the skill has no data to render. | STOP. Direct the user to `luciq-setup`, or to https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide. Do not assemble a readout from memory or from a prior session's numbers — a readout with stale or invented figures is the exact failure this skill exists to prevent. |
| **A resolved app slug and mode** | Every tool keys off `(slug, mode)` | Run `list_applications` and confirm with the user which app and mode (default `production`). |

### Optional inputs (the readout works without these, sharpens with them)

| Input | What it adds | If missing |
| --- | --- | --- |
| **A named persona** | Sets the altitude, the lead metric, the drill-down depth, and the omit-list | If unspecified, ASK. Do not guess the audience — the wrong altitude is the most common way a readout fails. |
| **A comparison frame** | Version-vs-version or period-over-period gives the readout a "what changed" spine | Default to a single snapshot of the current window, and say so. |
| **A segment cut** (OS, device, screen, flag, team, geography) | Answers "where is the problem concentrated" instead of just "how big is it" | Skip; report at the version / period level and note that no segment was requested. |

## Reference files

Detailed material is split out so the SKILL.md stays workflow-focused. Read the relevant reference when the workflow points to it:

| Reference | When to read |
| --- | --- |
| `references/metrics-glossary.md` | Before composing any readout. Defines every MCP tool's response shape, what each metric actually means (crash-free sessions, apdex, the `rate` change field, OOM / ANR / hang), the identifier and enum model, the filter-naming differences across tools, and — critically — exactly which adoption / volume signals the MCP does and does not expose. Field paths and number meanings used in this SKILL.md come from here. |
| `references/persona-playbooks.md` | When composing for a specific persona. Per-persona spec: the lead metric, the exact tool calls that build the readout, the drill-down to include, the omit-list, the framing, and a worked outline for each of C-suite, VP, PM, EM, and QA. |

## Canonical sources of truth

Verify tool surface and number meanings against live sources — the MCP evolves, and shapes memorized here can go stale:

| Concern | Source |
| --- | --- |
| Which apps, slugs, and modes exist | Luciq MCP `list_applications` |
| MCP tool surface and authentication | https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide |
| What a given metric means on the dashboard | The product guides at https://docs.luciq.ai — confirm a metric's definition before framing it for an exec |

## Tool coverage — what the readout uses, and what it deliberately doesn't

The Luciq MCP surface is broad. A readout uses the tools that aggregate or slice many occurrences for an audience, and stays away from the ones that mutate data or root-cause a single issue. This table is the contract.

**Tools the readout USES**

| Tool | Tier(s) it serves | What it contributes |
| --- | --- | --- |
| `list_applications` | all | Resolve `(slug, mode)` at the start. Never hard-code a slug. |
| `app_insights` | all | Headline stability rates (`monitoring`) AND the APM performance section (`apm`: networks, screen loads, cold/hot launches, flows). The single most important call. |
| `list_crashes` | VP, PM, EM, QA | Top issues by users affected / volume / recency, sliced by version, OS, device, screen, flag, team, type, status. |
| `crash_patterns` | VP, EM, QA | Distribution of ONE crash group across versions / OSes / devices / screens / experiments, plus the per-bucket `adoption` signal (on `app_versions`). |
| `list_app_hangs` | PM, EM, QA | Hang / ANR volume and worst offenders, same slicing as crashes. |
| `list_bugs` | PM, VP | User-reported bug volume by priority / status / version (the `app_insights.bugs` section commonly errors; this is the real source). |
| `list_reviews` | C-suite, VP, PM | App Store / Play rating trend and verbatim review bodies — the external quality proxy. |
| `list_surveys` + `survey_details` | C-suite, VP, PM | NPS / CSAT score and verbatim survey feedback — the in-app voice-of-customer signal alongside store reviews. |
| `crash_details` | EM | Synchronous stacktrace (`stack_frames[]`); the application frames are the fix target. |
| `list_occurrences_tokens` | EM | The occurrence ULIDs of one crash group, to address a single session. |
| `get_occurrence_details` | EM | The deepest drill: one session's device metrics, screen flow, memory / battery / storage at crash time. |
| `crash_diagnostics` | EM | Aggregated diagnostics across occurrences — screen-flow patterns, device/OS/version distributions, metric histograms. Async: re-call while `status` is `generating`. |

The EM tier is the one that earns the per-occurrence chain: `list_crashes` (pick the group) → `crash_details` (the stack) → `list_occurrences_tokens` → `get_occurrence_details` (one session) → `crash_diagnostics` (the aggregate pattern). No other tier descends this far; doing so for a VP or C-suite reader violates the omit-list.

**Tools the readout deliberately does NOT use**

| Tool | Why it's out of scope |
| --- | --- |
| `update_bug` | **Write / mutating tool.** A readout is read-only reporting; it must never change a bug's status, priority, or assignment. Never call it — not via the client, not via a direct JSON-RPC call. |
| `bug_details` | Single-bug deep payload (logs, breadcrumbs, repro). The readout reports bug *volume and themes* via `list_bugs`; per-bug depth is `luciq-debug`'s job. (Pull a single "top bug" snippet only if a quick check shows it genuinely adds readout value; default exclude.) |
| `apm_list_groups` / `apm_group_view` / `apm_occurrence` | Per-span APM deep-drill (one slow screen / endpoint / flow down to the trace). The readout reports performance at the `app_insights.apm` aggregate level; these per-span tools are the deeper drill `luciq-debug` reaches for. They are **not the primary performance source** for a readout. See the note below on reaching them when a persona genuinely needs span-level depth — they are currently stripped from the MCP client by a known server-schema issue, and the `app_insights.apm` aggregate carries the readout's performance dimension on its own. |

**A known constraint on four tools.** `update_bug`, `apm_list_groups`, `apm_group_view`, and `apm_occurrence` carry a top-level `anyOf` / `allOf` / `oneOf` / `not` combinator in their server-side `inputSchema`. The Anthropic Messages API forbids a top-level combinator on a tool's input schema, so Claude Code strips these four from the in-session tool list — they are not callable via the normal MCP client. This is a known server-side issue (the combinators should be pushed below the top level); a readout does not try to fix it. For `update_bug` the strip is irrelevant — a readout would never call a write tool anyway. For the three `apm_*` tools, the readout's performance dimension comes from the `app_insights.apm` aggregate, which is fully callable. **If, and only if, a persona genuinely needs per-span APM detail** (one slow endpoint or screen down to its p95 / failure-rate group), the read-only `apm_list_groups` can be reached by a direct JSON-RPC `tools/call` against the MCP HTTP endpoint (method `tools/call`, params `{name, arguments}`), using the same auth headers the MCP client uses — this bypasses the client-side schema strip without touching the server. Treat that as an optional deeper drill, label it in the readout as sourced via a direct call, and never use the same path to reach a write tool. If you can't authenticate the direct call, fall back to the `app_insights.apm` aggregate and say so — never fabricate a per-span number.

## Workflow checklist

Track every step. Stop and ask rather than guess on persona or comparison frame — a readout at the wrong altitude, or one that compares mismatched windows, is worse than no readout.

```
Readout Progress:
- [ ] 1. Resolve the app and mode (list_applications)
- [ ] 2. Confirm the audience and the angle (persona, comparison frame, segment cut)
- [ ] 3. Pull headline aggregates incl. APM (app_insights, once per version/window in scope)
- [ ] 4. Slice the detail for the chosen angle (list_/pattern tools; surveys for voice-of-customer)
- [ ] 4b. EM tier only: drive the per-occurrence chain (crash_details -> tokens -> occurrence -> diagnostics)
- [ ] 5. Apply the comparison rules before stating any delta
- [ ] 6. Compose for the persona (lead metric, drill-down, omit-list)
- [ ] 7. Render HTML + Markdown, cite every number to its tool and params
```

## 1. Resolve the app and mode

Call `list_applications` to get the slug. Filter by `platform` if the user named a stack. Confirm the `mode` with the user; default to `production`. An app can have several modes (`production`, `beta`, `staging`, `alpha`, `qa`, `development`) — each is a separate dataset. Never assume; a readout on `beta` data presented as production is a silent error.

## 2. Confirm the audience and the angle

Resolve three things before pulling any data. Ask if any is unspecified — do not guess.

- **Persona.** C-suite, VP (Eng or Product), PM, EM, or QA. This sets the lead metric, the drill-down, and the omit-list. Spec per persona is in `references/persona-playbooks.md`.
- **Comparison frame.** Version-vs-version, period-over-period, or a single snapshot. This decides how many `app_insights` calls you make and which deltas you can honestly state.
- **Segment cut (optional).** A device tier, OS, screen (`current_views`), feature flag / experiment, owning team, or geography (reviews `country`). Pick the one cut that answers the persona's question; do not run every cut by reflex.

## 3. Pull headline aggregates

`app_insights` is the headline source. It returns four independent sections — `crashes`, `bugs`, `apm` (networks, screen loads, cold / hot launches, flows), and `monitoring` (crash-free sessions, ANR, OOM, app hangs, user termination). Call it once per version or window in scope.

- For a version comparison, call once per version via `filters.app_version: ["<version>"]`.
- For a period comparison, call once per window via `filters.date_ms: {gte, lte}`.
- **Each section is independent and may carry an `error` object instead of data.** When a section errors, record it as unavailable for that scope. Do NOT reconstruct it from another tool and present it as the same metric — a count assembled from `list_crashes` is a volume, not the `monitoring` crash-free rate. (In live testing the `bugs` section of `app_insights` frequently returns `{"error": ...}` while `list_bugs` returns data fine; the two are not interchangeable. See `references/metrics-glossary.md`.)
- A section can also be present-but-empty (`has_occurrences: false`, `data: null`). That means "no data captured," not "zero is good." Report it as no-data, not as a healthy zero.

Read the field meanings in `references/metrics-glossary.md` before quoting any of these numbers. `crash_free_sessions.value` is a percentage; its sibling `rate` is the period-over-period change, not the rate itself — misreading that pair is an easy way to invert a trend.

**The `apm` section is a real readout dimension, not just context.** It returns network apdex and failure counts, screen-load p95 latency, cold / hot launch apdex and p95, and flow drop-off counts — performance signals an EM, a VP, or a PM cares about (slow screens, failing endpoints, sluggish launches, leaky funnels). Surface it for those tiers; keep it out of a C-suite one-number summary. This `apm` section is the performance layer the readout uses, and on its own it covers the whole performance dimension. The per-span APM tools (`apm_list_groups` / `apm_group_view` / `apm_occurrence`) drill one slow screen or endpoint down to a trace — that's deeper than a readout usually needs and is `luciq-debug`'s territory. They are also currently stripped from the MCP client by the top-level-combinator issue noted in the tool-coverage section, so they are not callable inline; when a persona genuinely needs the slowest-endpoint / slowest-screen list, the read-only `apm_list_groups` can be reached by a direct JSON-RPC `tools/call` to the MCP HTTP endpoint and the result labeled as sourced that way. When you don't take that path, the `app_insights.apm` aggregate still gives you the whole performance dimension; say so rather than implying span-level detail you didn't pull.

## 4. Slice the detail for the chosen angle

The headline numbers tell you how big; the list and pattern tools tell you where and what. Reach for the cut the persona and question call for.

| Tool | Pivot on | Angle it unlocks |
| --- | --- | --- |
| `list_crashes` | `app_versions[]`, `os_versions[]`, `devices[]`, `current_views[]`, `feature_flags[]`, `platform[]` (UPPERCASE: `IOS` / `ANDROID` / `DART` / `JAVASCRIPT`), `type[]` (CRASH / ANR / OOM / NON_FATAL), `subtype[]`, `status_id[]`, `teams[]`; `sort_by` (`occurrences_counter`, `affected_users_counter`, `severity`, `first_occurred_at`, `last_occurred_at`) | Top issues by version, OS, device, screen, flag, owning team, severity, status, or type. Sort by `affected_users_counter` for blast radius, `occurrences_counter` for volume, `first_occurred_at` to surface new-in-version. |
| `crash_patterns` | `number` (the crash group), `pattern_key` (`app_versions`, `devices`, `oses`, `current_views`, `app_status`, `experiments`), filters, `sort_by` | Distribution of ONE crash group across versions, devices, OSes, screens, foreground/background, or experiments. The experiment breakdown attributes a regression to a rollout or flag. This tool also returns per-bucket `adoption` and a `total_sessions_count` — see the adoption note below. |
| `list_app_hangs` | same filter surface as crashes (no `type` / `subtype`) | Hang / ANR volume and worst offenders, sliced the same ways. `crash_type` on hang rows reads `FATAL_UI_HANG`. |
| `list_bugs` | `app_version[]`, `priority_id[]` (`-1` N/A, `1` Trivial … `4` Blocker), `status_id[]` (`1` New / `2` Closed / `3` In Progress) | User-reported bug volume by priority, status, version. |
| `list_reviews` | `rating[]` (1-5), `app_version[]`, `country[]`, `os[]`, `prompt_type[]` (`custom` / `native` / `app_store`), `date_ms`; `sort_direction` | The external quality proxy execs ask about. Slice by low rating, version, country, OS, or prompt type. Review bodies are real user words — quote them verbatim for a PM, never paraphrase into a claim. |
| `list_surveys` + `survey_details` | `list_surveys` filters by `status` / `type` (`1` = nps); `survey_details` keys off the survey `id`, filters responses by rating / version / country / `nps` score / `search_words` | The in-app voice-of-customer signal. `list_surveys` finds the published NPS/CSAT survey; `survey_details` returns the headline `nps` object (`score`, promoter / passive / detractor splits) and individual verbatim responses. NPS score is a fair C-suite / VP headline; the verbatim "how can we do better" answers are PM-tier evidence — quote them, don't summarize. If no survey exists or it's empty, say so; don't imply a score. |
| `crash_details` / `list_occurrences_tokens` / `get_occurrence_details` / `crash_diagnostics` | the `(slug, mode, number)` tuple; `get_occurrence_details` also takes a `ulid` from `list_occurrences_tokens` | Per-issue depth (stacktrace, single-session device metrics, aggregated screen flows and distributions) for the EM tier only. This is the chain in step 4b. `crash_diagnostics` is async — re-call while `status` is `generating`. |

**The adoption nuance — get this right.** `app_insights` does NOT return adoption or rollout percentage; you cannot normalize its headline rates by exposure. But `crash_patterns` DOES return an `adoption` value per bucket (confirmed on the `app_versions` pattern key — a given pattern key, e.g. `oses`, may omit it) plus `total_sessions_count` and `total_occurrences_count` for the group. Use those where the tool gives them, and cite them to `crash_patterns`. Do not invent an adoption figure for a version where you only have `app_insights`, and do not present a `crash_patterns` session/adoption count as if it covered the whole app. Detail and exact field paths in `references/metrics-glossary.md`.

## 4b. EM tier only — drive the per-occurrence chain

For an EM readout, descend from the crash *group* to a single crash *occurrence* and the aggregated diagnostics. No other persona goes this deep. The chain:

1. `list_crashes(..., sort_by=affected_users_counter)` — pick the top crash group; note its `number`.
2. `crash_details(slug, mode, number)` — the synchronous stacktrace. Lead the EM with the **application** frames (`type: application`), especially the one flagged `is_grouping_frame`, and the deepest application frame before the system frames (the fix target). Drop the system frames from the readout.
3. `list_occurrences_tokens(slug, mode, number)` — the ULID tokens for individual occurrences (ULIDs are time-prefixed; the lexicographically largest is the newest). Note `total_occurrences`.
4. `get_occurrence_details(slug, mode, number, ulid)` — one session's full payload: device, OS, app version, memory / storage, foreground/background, session duration, the screen at crash time. One concrete repro context an engineer can act on.
5. `crash_diagnostics(slug, mode, number)` — the aggregate across occurrences: screen-flow `patterns` (the navigation path users were on), `distributions` (devices / OS / app versions / current views / app status), and `metrics` histograms (memory / battery / storage / duration). Async — if `status: generating`, re-call after `retry_after_seconds`.

This is the EM tier's evidence: the stack to fix, one real session to reproduce, and the distribution to scope blast radius. Keep all of it out of the C-suite, VP, PM, and QA readouts — a stack frame at the wrong altitude is noise.

## 5. Apply the comparison rules

Before stating any delta, hold to these. They are what keep a comparison honest.

- **Match the windows.** Use the same `date_ms` length for both sides. Crash-free percentages and raw volumes both scale with exposure time, so unequal windows mislead. Never compare a 7-day window to a 30-day window and call the difference a regression.
- **Prefer rates over raw where the tool gives them.** The `monitoring` rates from `app_insights` compare cleanly across versions. Raw list counts depend on traffic volume, so frame them as volume, not as a like-for-like rate. When you do have per-version session counts from `crash_patterns`, you can normalize a count — and you must cite that you did.
- **Label confidence by sample.** Mark a comparison low-confidence when a version's totals are small or its rollout is clearly early. Say "early rollout, low sample" rather than implying parity. `crash_patterns` session counts per version are the honest signal for how thin a version's exposure is.
- **Separate new from regressed from trending.** New-in-version (sort `first_occurred_at`, or absent from the baseline list), returned-after-fix, and accelerating-in-rate are three different stories that drive three different actions. Label them distinctly.
- **Segment before concluding.** A flat version-level delta can hide a device- or OS-specific regression. Pivot with `crash_patterns` or the filter surface before declaring a release healthy.
- **Benchmarks are context, not measurement.** If you cite an industry stability benchmark, present it as an external observation to validate, never as a Luciq-measured fact.

## 6. Compose for the persona

Lead with that persona's headline metric, include only their drill-down, honor their omit-list. The full per-persona spec — lead metric, tool calls, drill-down, omit-list, framing, worked outline — is in `references/persona-playbooks.md`. Summary:

| Persona | Leads on | Drill-down included | Omit / suppress | Framing |
| --- | --- | --- | --- | --- |
| C-suite (CEO / CPO / CTO) | One stability headline (crash-free sessions %), direction vs last period, App Store rating trend, NPS score, one-line top risk and its blast radius, context vs a benchmark | none inline | stacktraces, device / OS matrices, raw counts, issue IDs, APM apdex detail, tool names in the prose | Short narrative, a few trended numbers, tied to user and revenue impact |
| VP Eng / VP Product | Crash-free sessions and users across recent versions, ANR / OOM / hang rates, key APM rates (network apdex, launch / screen p95), regression flags by version, top issues by users affected with owning team, NPS trend, per-platform split | top-issue list (titles, not traces), an APM panel | full traces, device long tail, per-developer metrics | Comparative across versions and squads, summarized panels |
| Product Manager | Crash-free for the owned flow (`current_views` filter), flow drop-off and slow-screen APM for those screens, top issues by users affected on key flows, review themes, NPS verbatim feedback, new-in-version issues | issue list plus representative review and survey quotes | symbolicated traces, infra detail | Flow and user centric, tied to journeys |
| Engineering Manager | New and trending issues in their components / teams (`teams` filter), crash / ANR / OOM rates with deltas vs prior version, top crashes by frequency and by users, device / OS breakdown, per-occurrence stack and diagnostics | full stacktraces (`crash_details` / `crash_diagnostics`), occurrence detail (the step-4b chain) | exec and revenue narrative | Granular, triage-oriented; raw numbers are fine |
| QA / Release | Crash-free and ANR / OOM / hang vs the team's own ship thresholds, APM rates vs thresholds, new-in-version issues, regression count vs baseline, worst offenders | issue list plus repro context | long-term business trends | Threshold readout. This skill reports the data; it does not emit the ship / hold / rollback verdict — that decision stays with the release owner. |

The omit-list is load-bearing. A readout at the wrong altitude is a worse readout than a short one. Do not paste a stacktrace into a C-suite summary to look thorough, and do not strip the traces out of an EM readout to look clean.

## 7. Render HTML + Markdown

Render the readout in both HTML (the shareable, forwardable artifact) and Markdown (the inline preview). Structure, adapted to the persona's altitude:

```
<App> health readout — <persona>
Scope: <version X vs Y | period A vs B | snapshot>, mode=<mode>, window=<window>

HEADLINE
- <the one-or-few numbers this persona leads on>   [from: luciq:app_insights ...]

WHAT CHANGED
- <deltas, labeled new / regressed / trending, with confidence>   [from: ...]

PERFORMANCE   (VP / PM / EM / QA; omit for C-suite)
- <network apdex + failure rate, launch / screen p95, flow drop-off>   [from: luciq:app_insights apm ...]

TOP ISSUES   (depth set by persona; omit for C-suite)
- <issue, users affected, version, owning team>   [from: luciq:list_crashes sort=affected_users_counter ...]

EM DEEP DIVE   (EM tier only)
- <top crash: application stack frames, one occurrence's context, diagnostics distribution>   [from: luciq:crash_details / get_occurrence_details / crash_diagnostics number=<n>]

VOICE OF USER   (when relevant)
- <rating trend, verbatim review themes>   [from: luciq:list_reviews ...]
- <NPS score + splits, verbatim survey feedback>   [from: luciq:survey_details id=<id>]

CONTEXT
- <vs prior period, vs benchmark — observation, to validate>

CAVEATS
- <unavailable app_insights sections, low-sample comparisons, what adoption signal exists and what doesn't>
```

Every line that carries a number carries a citation naming the tool and the params that produced it, for example `[from: luciq:app_insights version=3.1.4 mode=production]` or `[from: luciq:list_reviews rating=1,2 country=US]`. The HTML should be clean and executive-ready: brand blue `#0A89FC`, a compact KPI band up top, generous whitespace, and a visible source footer per figure or per section. Anonymize any identifying app name if the artifact is meant to be shared outside the owning team.

## Out of scope

Grounded in what the Luciq MCP exposes today. This skill deliberately does not:

- **Mutate any data.** A readout is read-only. It never calls `update_bug` or any other write tool to change a bug's status, priority, or assignment — reporting must never alter the customer's data it reports on.
- Emit a ship, hold, or rollback verdict. Report the data; the decision stays with the release owner. A QA / Release readout lays the thresholds and the numbers side by side, but does not write "ship" or "hold."
- Root-cause a single issue. The per-occurrence chain (step 4b) is used to *show an EM the evidence*, not to author a fix. Deep single-issue debugging — including `bug_details` for one bug's logs and breadcrumbs, and the per-span `apm_*` tools for one slow screen or endpoint — is `luciq-debug`'s job. The readout reports bug *volume / themes* via `list_bugs` and performance at the `app_insights.apm` aggregate, not per-bug or per-span depth.
- Compute MTTR, time-to-resolve, or a whole-app adoption / rollout percentage. The MCP does not expose them at the app level. (Per-crash-group session and adoption counts from `crash_patterns` are the one real exception — use those, cite them, and don't generalize them to the whole app.)
- Reconstruct an `app_insights` section that returned an `error`, or a present-but-empty section, and present it as the real metric. Report it as unavailable for that app and window. Same for a survey: if none is published or it has no responses, report no NPS signal rather than implying a score.

When new MCP tools land (app-level adoption, release-comparison endpoints, deeper APM aggregates), this skill grows with them. Until then, if the user asks for one of those, say so plainly.

## Style

- Pick the persona before composing. If unspecified, ask. Do not guess the audience.
- Honor the persona omit-list. Wrong altitude is a worse readout than a short one.
- Cite every number to its tool and the params that produced it. Do not paraphrase a source you did not query.
- Label every comparison's confidence. Low sample and early rollout are caveats, not asterisks to bury.
- Quote review bodies verbatim. A user's words are evidence; a paraphrase is your claim.
- Render in both HTML and Markdown. No fabricated numbers, ever. A missing section is reported, not filled.

## Red Flags — patterns that mean STOP and surface to the user

If you catch yourself reasoning in any of these directions, you are about to ship a readout that looks authoritative and is not. STOP, surface to the user, do not proceed.

**Fabrication and missing data**
- "The exec just wants a number, so I'll quote a crash-free rate even though `app_insights` returned an error for `monitoring`." Report the section as unavailable. A blank is honest; an invented number is not.
- "The `apm` section is `has_occurrences: false`, so I'll report apdex as 1.0 / perfect." Empty is not zero-is-good. Report it as no data captured for that window.
- "I'll round the messy crash-free figure to a clean 99.5% for the exec." Don't fabricate precision in either direction. Cite the real value; round only the display, never the number you reason from.
- "I don't have last period's number handy, so I'll estimate the delta." If you didn't query the baseline window, you don't have a delta. Pull it or say the comparison is unavailable.

**Comparison integrity**
- "The two versions cover different date ranges, but it's close enough." It is not. Match the windows or label the comparison low-confidence.
- "Version-level crash-free barely moved, so the release is clean." Segment first. A device- or OS-specific regression hides inside a flat aggregate.
- "Version B's crash-free is higher, so it's healthier" — when B has a fraction of A's sessions. Early rollout, low sample. Cite the `crash_patterns` session counts and label confidence.
- "Adoption looks fine on the new version, so I'll call it healthy." `app_insights` gives you no app-level adoption. Don't imply it. The only adoption signal is per-crash-group from `crash_patterns`, and it doesn't cover the whole app.

**Altitude and omit-list**
- "This is for a VP, so I'll paste the stacktrace to look thorough." Wrong altitude. Honor the omit-list. A trace in a VP deck is noise that buries the signal.
- "The C-suite readout looks thin, so I'll add the device/OS matrix to fill the page." A short, true exec readout beats a padded one. Length is not credibility.
- "I'll name the tools (`list_crashes`, `app_insights`) in the C-suite prose so it reads rigorous." Keep tool names in the source footer, not the exec narrative. Cite without cluttering.

**Scope and routing**
- "I'll flip this bug to In Progress / reassign it while I'm reporting on it." STOP. A readout is read-only. `update_bug` and every write tool are off-limits — never mutate the data you're reporting on.
- "The NPS survey has no responses, so I'll estimate a score from the review ratings." Reviews and NPS are different instruments. No survey responses means no NPS signal — say so; don't manufacture one.
- "This is a C-suite summary, so I'll add the network apdex and screen p95 to look complete." APM detail is VP / PM / EM altitude. The exec gets one stability number and a direction, not an apdex table.
- "The data clearly points to ship, so I'll write 'ship it' at the top." That decision isn't this skill's to make. Lay the thresholds and numbers side by side; let the release owner decide.
- "The user pasted a single crash ID and asked why it happens — I'll readout the whole app." That's `luciq-debug`. Route it.
- "Reviews mention a checkout bug, so I'll assert the checkout crash caused the rating drop." Correlation, not causation. Report both signals; don't manufacture the link.
- "I'll cite the number to `app_insights` without noting it was a single small window." If the sample is thin, the caveat is part of the number.

Every shortcut here trades a readout that looks authoritative for one that is actually true. The skill's job is the latter.
