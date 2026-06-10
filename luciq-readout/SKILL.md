---
name: luciq-readout
description: Use when the user wants a shareable, audience-tailored readout of a Luciq app's health or quality, rather than a single fix or a ship/hold decision. Covers version-vs-version and period-over-period comparisons rendered for a chosen persona: C-suite, VP, PM, EM, or QA. Triggers include asking for an exec or leadership summary, a release readout, a stability or quality report for a specific audience, comparing version X to version Y, or summarizing how the app is doing this week vs last. Pulls headline aggregates from app_insights and slices detail across crashes, hangs, bugs, and reviews via the Luciq MCP, then renders the same data at the altitude each audience needs, citing every number to its source tool. For a ship/hold/rollback verdict use luciq-release-check; to root-cause one crash, hang, or bug use luciq-debug; to verify an SDK upgrade use luciq-verify.
---

<!--
Triggers (things the user might say):
- "give me an exec / leadership summary of [app]"
- "build a release readout for [version]"
- "stability report for the VP / for [persona]"
- "how is the app doing this week vs last week"
- "compare [version X] to [version Y] for a PM"
- "quality report I can send to leadership"
- "EM readout: what's regressing in our screens"
NOTE: this skill produces a shareable REPORT artifact, not a ship decision.
For ship / hold / rollback, that is luciq-release-check.
-->

# Luciq Stakeholder Readouts

Produce a shareable, audience-tailored readout of a Luciq app's health and quality. Default to evidence-based reasoning. Every number in the readout is cited to the MCP tool and the parameters that produced it. If a query returns nothing, or a section comes back as an error, surface that fact. Do not fill it in with a plausible-looking number.

The job of this skill is communication, not adjudication. It renders the same underlying data at the altitude each audience needs. It does not decide whether to ship.

## When NOT to use this skill

- A ship, hold, or rollback decision on a release, use `luciq-release-check`. That skill owns the verdict and the threshold logic. This one produces the readout, not the decision.
- Root-causing one specific crash, hang, or bug and proposing a code fix, use `luciq-debug`.
- Verifying that an SDK version upgrade did not break the integration, use `luciq-verify`.
- General reporting where Luciq is not the data source. This skill is grounded in what the Luciq MCP exposes. Without it, do not pretend to use it.

If the user's request fits any of the above, STOP and route them to the right skill rather than running this one. When `luciq-release-check` produces a verdict and the user then wants something they can forward to a VP or exec, that is the handoff into this skill.

## Prerequisites

The Luciq MCP server must be configured and authenticated. If MCP tools are not available, STOP and direct the user to https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide for setup, or run `luciq-setup` to wire it.

The MCP tools this skill draws on (verbatim names, qualified as `luciq:<tool_name>` when invoked):

| Tool | Role in a readout |
| --- | --- |
| `list_applications` | Resolve the app slug and token at the start. Filter by `platform`. |
| `app_insights` | The headline aggregate source. Returns `crashes`, `bugs`, `apm` (networks, launches, screen-loads, flows), and `monitoring` (crash-free sessions, ANR, OOM, app-hang rates) for one app. This is what feeds the exec tier. |
| `list_crashes` | Top issues sliced by version, OS, device, screen, feature flag, team, severity, status, or type. |
| `crash_patterns` | Distribution of one crash group across versions, devices, OSes, screens, foreground/background, or experiments. |
| `list_app_hangs` | Hang and ANR groups, sliced the same ways as crashes. |
| `list_bugs` | User-reported bug volume by priority, status, version. |
| `list_reviews` | App Store / Play sentiment by rating, version, country, OS, prompt type. |
| `crash_details` / `crash_diagnostics` / `get_occurrence_details` / `list_occurrences_tokens` | Per-issue depth for the EM tier: stacktrace, device metrics, screen flow, session profiler. `crash_diagnostics` is async, re-call while `status` is `generating`. |

YOU MUST cite which tool produced any number in the readout. Do not invent capabilities the MCP does not expose. See "Out of scope" for what it deliberately does not return.

## The tool surface and the angles it unlocks

A readout is only as good as the slices behind it. `app_insights` carries the headline numbers but takes only `app_version` and `date_ms` filters. Every richer angle comes from the list and pattern tools, which expose a wide filter surface. Reach for the angle the persona and the question call for.

| Tool | Parameters you can pivot on | Angle it unlocks |
| --- | --- | --- |
| `app_insights` | `filters.app_version[]`, `filters.date_ms{gte,lte}`, `mode` | Headline KPIs for the exec tier. Call once per version for a version comparison, or once per window for a period comparison. Each returned section (`crashes`, `bugs`, `apm`, `monitoring`) is independent and may carry an `error` instead of data. |
| `list_crashes` | filters: `app_versions[]`, `os_versions[]`, `devices[]`, `current_views[]`, `feature_flags[]`, `platform[]`, `type[]` (CRASH/ANR/OOM/NON_FATAL), `subtype[]` (CRITICAL/ERROR/WARNING/INFO, requires NON_FATAL), `status_id[]`, `teams[]`; `sort_by` (occurrences_counter, affected_users_counter, severity, first/last_occurred_at), `date_ms` | Top issues by version, OS, device tier, screen, feature flag, owning team, severity, status, or type. Sort by `affected_users_counter` for impact, `occurrences_counter` for volume, `first_occurred_at` to surface new-in-version. |
| `crash_patterns` | `number`, `pattern_key` (app_versions, devices, oses, current_views, app_status, experiments), filters, `sort_by` | Distribution of one crash across versions, devices, OSes, screens, foreground/background, or experiments. The experiment breakdown is how you attribute a regression to a rollout or flag. |
| `list_app_hangs` | filters: `app_versions[]`, `os_versions[]`, `devices[]`, `current_views[]`, `platform[]`, `status_id[]`, `teams[]`; `sort_by` | Hang and ANR volume and worst offenders, sliced the same ways. |
| `list_bugs` | filters: `app_version[]`, `priority_id[]` (Blocker to Trivial), `status_id[]` (New/Closed/In Progress) | User-reported bug volume by priority, status, version. |
| `list_reviews` | filters: `rating[]` (1-5), `app_version[]`, `country[]`, `os[]`, `prompt_type[]` (custom/native/app_store), `date_ms`; `sort_direction` | The external quality proxy execs ask about. Slice by low rating, version, country, OS, or prompt type. |
| `list_occurrences_tokens` / `get_occurrence_details` | occurrence filters incl. `app_status` (foreground/background), `experiments[]`, plus the `(slug, mode, number, ulid)` tuple | Drill into individual sessions for the EM tier. |

The headline angles a readout is usually built around: **version X vs version Y**, **this period vs last period**, and within either, a segment cut by **device tier, OS, screen (`current_views`), feature flag or experiment, owning team, or geography (reviews `country`)**. Pick the cut that answers the persona's question, do not run all of them by reflex.

## Personas

Resolve the audience before composing. If the user has not said who the readout is for, ask. Do not guess the altitude.

| Persona | What leads the readout | Drill-down included | Omit / suppress | Framing |
| --- | --- | --- | --- | --- |
| C-suite (CEO / CPO / CTO) | One stability headline (crash-free sessions %), direction vs last period, App Store rating trend, one-line top risk and its blast radius, context vs an external benchmark | none inline | stack traces, device/OS matrices, raw counts, issue IDs, tool names | Short narrative, a few trended numbers, tied to user and revenue impact |
| VP Eng / VP Product | Crash-free sessions and users across recent versions, ANR/OOM/hang rates, regression flags by version, top issues by users affected with owning team, per-platform split | top-issue list (titles, not traces) | full traces, device long tail, per-developer metrics | Comparative across versions and squads, summarized panels |
| Product Manager | Crash-free for the owned flow (`current_views` filter), top issues by users affected on key flows, review themes, new-in-version issues | issue list plus representative review quotes | symbolicated traces, infra detail | Flow and user centric, tied to journeys |
| Engineering Manager | New and trending issues in their components or teams (`teams` filter), crash/ANR/OOM rates with deltas vs prior version, top crashes by frequency and by users, device/OS breakdown | full stacktraces (`crash_diagnostics`), occurrence detail | exec and revenue narrative | Granular, triage-oriented, raw numbers are fine |
| QA / Release | Crash-free and ANR/OOM/hang vs the team's ship thresholds, new-in-version issues, regression count vs baseline, worst offenders | issue list plus repro context | long-term business trends | Threshold readout. For the actual ship/hold/rollback call, hand off to `luciq-release-check`. |

The omit-list is load-bearing. A readout at the wrong altitude is a worse readout than a short one. Do not paste a stacktrace into a C-suite summary to look thorough, and do not strip the traces out of an EM readout to look clean.

## Workflow

1. Resolve the app and mode. `list_applications` to get the slug. Confirm `mode` (default `production`).
2. Confirm the audience and the angle. Persona (from the table above), comparison type (version-vs-version, period-over-period, or single snapshot), the two versions or two windows, and any segment cut. Ask if unspecified.
3. Pull the headline aggregates. `app_insights` for each version or window in scope. Read the `monitoring`, `crashes`, `bugs`, and `apm` sections. If any section returns an `error`, record it as unavailable for that scope. Do not reconstruct it from other tools and present it as the same metric.
4. Slice the detail for the chosen angle. Use `list_crashes`, `list_app_hangs`, `list_bugs`, `list_reviews`, and `crash_patterns` with the filters that match the cut. Sort to match intent (impact vs volume vs new-in-version).
5. Apply the comparison rules below before stating any delta.
6. Compose the readout for the persona. Lead with that persona's headline, include only their drill-down, honor their omit-list.
7. Render in both HTML (shareable) and Markdown. Cite every number to `luciq:<tool>` and its params.

## Comparison rules

When the readout compares two versions or two periods, hold to these. They keep a comparison honest.

- **Match the windows.** Use the same `date_ms` length for both sides. Crash-free percentages and raw volumes both scale with exposure time, so unequal windows mislead. Never compare a 7-day window to a 30-day window and call the difference a regression.
- **Adoption is not exposed. Do not invent it.** The MCP does not return rollout or adoption percentage. You cannot normalize by it. Instead, show absolute volumes (occurrence counts, affected users) next to every delta, and label a comparison low-confidence when a version's totals are small or its rollout is clearly early. Say "early rollout, low sample" rather than implying parity.
- **Prefer rates over raw where the tool gives them.** The `monitoring` rates from `app_insights` (crash-free sessions, ANR, OOM, hang) compare cleanly across versions. Raw list counts depend on traffic volume, so frame them as volume, not as a like-for-like rate.
- **Separate new from regressed from trending.** New-in-version (sort `first_occurred_at`, or absent from the baseline list), returned after being fixed, and accelerating in rate are three different stories that drive three different actions. Label them distinctly.
- **Segment before concluding.** A flat version-level delta can hide a device- or OS-specific regression. Pivot with `crash_patterns` or the filter surface before declaring a release healthy.
- **Benchmarks are context, not measurement.** If you cite an industry stability benchmark, present it as an external observation to validate, never as a Luciq-measured fact.

## Output format

Render the readout in both HTML and Markdown so it is forwardable. The HTML is the shareable artifact, the Markdown is the inline preview.

Structure, adapted to the persona's altitude:

```
<App> health readout — <persona>
Scope: <version X vs Y | period A vs B | snapshot>, mode=<mode>, window=<window>

HEADLINE
- <the one-or-few numbers this persona leads on>  [from: luciq:app_insights ...]

WHAT CHANGED
- <deltas, labeled new / regressed / trending, with confidence>  [from: ...]

TOP ISSUES  (depth set by persona; omit for C-suite)
- <issue, users affected, version, owning team>  [from: luciq:list_crashes sort=affected_users_counter ...]

VOICE OF USER  (when relevant)
- <rating trend, review themes>  [from: luciq:list_reviews ...]

CONTEXT
- <vs prior period, vs benchmark — observation, to validate>

CAVEATS
- <unavailable app_insights sections, low-sample comparisons, adoption not exposed>
```

Every line that carries a number carries a citation. The citation names the tool and the params that produced it, for example `[from: luciq:app_insights version=4.3.0 window=last_14d]` or `[from: luciq:list_reviews rating=1,2 country=US]`.

## Out of scope

Grounded in what the Luciq MCP exposes today. This skill deliberately does not:

- Emit a ship, hold, or rollback verdict. That is `luciq-release-check`. Report the data, route the decision.
- Compute adoption or rollout percentage, MTTR, or time-to-resolve. The MCP does not expose them. Do not estimate them.
- Reconstruct an `app_insights` section that returned an `error`. Report it as unavailable for that app and window.
- Reach for session replay or per-span APM aggregates beyond what the `app_insights` `apm` section returns.

When new MCP tools land (adoption metrics, release comparison endpoints, deeper APM aggregates), this skill grows with them. Until then, if the user asks for one of those, say so plainly.

## Style

- Pick the persona before composing. If unspecified, ask. Do not guess the audience.
- Honor the persona omit-list. Wrong altitude is a worse readout than a short one.
- Cite every number to its tool and the params that produced it. Do not paraphrase a source you did not query.
- Label every comparison's confidence. Low sample and early rollout are caveats, not asterisks to bury.
- Render in both HTML and Markdown. No fabricated numbers, ever. A missing section is reported, not filled.

## Red Flags - STOP and surface to the user

If you catch yourself thinking any of these, you are about to ship a readout that looks authoritative and is not. STOP, surface to the user, do not proceed:

- "The exec just wants a number, so I'll quote a crash-free rate even though `app_insights` returned an error for `monitoring`." Report the section as unavailable. A blank is honest, an invented number is not.
- "The two versions cover different date ranges, but it's close enough." It is not. Match the windows or label the comparison low-confidence.
- "Adoption looks fine, so I'll say the new version is healthy." The MCP does not give you adoption. Do not imply it.
- "This is for a VP, so I'll paste the stacktrace to look thorough." Wrong altitude. Honor the omit-list.
- "Version-level crash-free barely moved, so the release is clean." Segment first. A device- or OS-specific regression hides inside a flat aggregate.
- "I'll write ship or hold here, the data clearly points that way." That is `luciq-release-check`'s job. Report the data, route the decision.
- "I'll cite the number to `app_insights` without noting it was a single small window." If the sample is thin, the caveat is part of the number.

The pattern: every shortcut here trades a readout that looks authoritative for one that is actually true. The skill's job is the latter.
