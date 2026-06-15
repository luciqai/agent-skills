# Persona Playbooks

One readout, five altitudes. Each persona gets a different lead metric, a different set of tool calls, a different drill-down depth, and — most importantly — a different omit-list. This file is the per-persona spec the `SKILL.md` workflow points at in step 6.

The single rule under all of them: **the wrong altitude is a worse readout than a short one.** A C-suite reader who gets a stacktrace stops trusting the document. An EM who gets a revenue narrative instead of stack frames can't act. Match the altitude to the reader's decision.

Field names and tool shapes referenced here are defined in `metrics-glossary.md`. Every figure cites the tool and params that produced it.

## The altitude ladder

```
C-suite   ── one number + direction + one risk. No tool names in the prose.
VP        ── versions × squads, summarized panels. Top issues by title.
PM        ── the owned flow, in users and journeys. Verbatim review quotes.
EM        ── triage. Raw counts, deltas, and full stack frames.
QA        ── thresholds side by side. Reports the data; does not call the ship.
```

A readout can be requested for one persona or several. When several, render each as its own section at its own altitude — do not produce one merged document that's wrong for everyone.

---

## C-suite (CEO / CPO / CTO)

**The reader's decision:** is the product stable enough to keep investing / talking about, and is anything on fire?

**Leads on:** one stability headline — `monitoring.crash_free_sessions.value` — with its direction vs last period, the App Store rating trend, the NPS score, and a single one-line top risk with its blast radius. Context against a benchmark, framed as something to validate.

**Tool calls:**
1. `app_insights(slug, mode)` for the headline `monitoring` rates and their `rate` (change) fields.
2. `list_reviews(slug, mode, sort_by=date)` for the rating trend; optionally `filters.rating=[1,2]` for the low-end signal.
3. `list_surveys(slug, mode, filters.type=[1])` then `survey_details(slug, mode, id=<nps survey>)` for the NPS `score` — one number, no per-response detail.
4. `list_crashes(slug, mode, sort_by=affected_users_counter, limit=1)` for the single biggest blast-radius issue — reported as one line, by users affected, no ID, no trace.

**Drill-down included:** none inline.

**Omit / suppress:** stacktraces, device / OS matrices, raw occurrence counts, issue IDs, APM apdex tables, tool names in the narrative (keep them in a source footer).

**Framing:** a few sentences of narrative, two or three trended numbers, tied to user impact. If `monitoring` errored, say "crash-free rate unavailable for this window" — do not substitute a count. If no NPS survey is published, omit the line — don't infer a score from reviews.

**Worked outline:**
```
<App> is at 99.3% crash-free sessions this period, up slightly from last.
App Store sentiment is steady in the low-3s and the in-app NPS is +8; the recurring theme is performance, not data loss.
Top risk: an out-of-memory issue affecting the largest user group on older devices — contained, not spreading.
Context: 99.3% sits just under the ~99.5%+ that's typical for healthy consumer apps — worth a look, not an alarm. (benchmark, to validate)
[sources: crash-free + rates from app_insights; rating from list_reviews; NPS from survey_details; top risk from list_crashes by affected users]
```

---

## VP Eng / VP Product

**The reader's decision:** which release and which squad needs attention, and is the latest version a regression?

**Leads on:** crash-free sessions and users across the recent versions, the ANR / OOM / hang rates, the key APM rates (network apdex + failure rate, launch and screen p95, flow drop-off), regression flags by version, the top issues by users affected with their owning team, and the NPS trend. Per-platform split if cross-platform.

**Tool calls:**
1. `app_insights(slug, mode, filters.app_version=[<vNew>])` and again for `[<vBaseline>]` — the version comparison spine, covering both the `monitoring` rates AND the `apm` performance section. Match windows.
2. `list_crashes(slug, mode, sort_by=affected_users_counter, filters.app_versions=[<vNew>])` for the top-issue list with `team`.
3. `crash_patterns(slug, mode, number=<top>, pattern_key=app_versions)` to confirm whether a top issue concentrates in the new version (regression) and to read per-version `adoption` so a higher count on a higher-exposure version isn't miscalled a regression.
4. `survey_details(slug, mode, id=<nps survey>)` for the NPS `score` and the promoter / detractor split — a one-line trend panel.

**Drill-down included:** top-issue list — titles and owning team, not traces — plus a summarized APM panel.

**Omit / suppress:** full stack traces, the device long tail, per-developer metrics.

**Framing:** comparative across versions and squads, in summarized panels. Label each top issue new / regressed / trending. State confidence where a version's exposure is thin (cite `crash_patterns` session counts). APM stays at the apdex / p95 summary level — no per-span breakdown.

**Worked outline:**
```
Version 3.1.4 vs 3.0.4 (matched window, production):
  crash-free sessions  99.47%  vs  98.10%   (improved)
  app-hang-free        99.55%  vs  97.63%   (improved)   [3.0.4 hang rate was trending down]
  OOM-free             99.85%  vs  99.53%   (improved)
  network apdex        0.920   vs  0.907    (improved)
  cold-launch p95      561ms   vs  1278ms   (improved, less than half)
3.1.4 is the healthier release across every monitoring AND performance rate.
Top issues on 3.1.4 by users affected, with owners:
  • Out-of-memory on ViewController — ~246 users — Alert Response Team
  • SIGABRT on the exceptions screen — ~227 users — Alert Response Team
Both span 3.0.4 and 3.1.4 (not new-in-version); neither is a 3.1.4 regression — confirmed via crash_patterns version split.
In-app NPS: +8 (40% promoters / 28% passive / 32% detractors) — a sizable detractor base despite the positive score.
[sources: app_insights per version (monitoring + apm); list_crashes by affected users; crash_patterns app_versions; survey_details NPS]
```

---

## Product Manager

**The reader's decision:** is my flow healthy for users, and what are they actually saying?

**Leads on:** crash-free / hang health for the owned flow (filter `current_views` to the flow's screens), the flow's performance (screen-load p95 and flow drop-off from `app_insights.apm`), top issues by users affected on those screens, review themes and NPS verbatim feedback in users' own words, and new-in-version issues on the flow.

**Tool calls:**
1. `list_crashes(slug, mode, filters.current_views=[<flow screens>], sort_by=affected_users_counter)` and `list_app_hangs(...)` with the same `current_views` filter — the flow's worst offenders.
2. `app_insights(slug, mode)` for the `apm.screen_loadings` p95 and `apm.flows` drop-off — the flow's performance signal.
3. `list_reviews(slug, mode, filters.rating=[1,2,3])` for the negative-to-mixed themes; quote bodies verbatim.
4. `survey_details(slug, mode, id=<nps survey>, filters.nps=...)` for detractor / passive verbatim feedback ("how can we do better"); quote verbatim.
5. `list_bugs(slug, mode)` for user-reported issues touching the flow (match on `title`).

**Drill-down included:** the issue list plus representative verbatim review and survey quotes.

**Omit / suppress:** symbolicated stack traces, infra detail.

**Framing:** flow- and user-centric, tied to journeys. A hang on `PaymentViewController` is "checkout stalls for users," not "main thread unresponsive 3000ms."

**Worked outline:**
```
Checkout flow health (screens: Pay.PaymentViewController, Pay.StatmentViewController):
  • A hang on the payment screen affected ~789 users — checkout stalls before the user can pay.
  • A hang loading statement history affected ~753 users — the history view freezes on open.
Flow performance: ~43% of flow runs drop off (75,108 of 174,841) and screen-load p95 is ~312ms. [app_insights apm]
A user-reported bug corroborates: "Cannot complete premium checkout payment." [list_bugs]
What users are saying (verbatim):
  • "It's sluggish, clunky, and prone to crashes. I can't rely on it for important tasks." — 1 star review, US
  • "the features are cumbersome to use ... navigating through the app [is] a chore." — 2 star review, FR
  • "Reduce screen hangs" — NPS detractor (score 2); "You should add a product tour" — NPS detractor (score 0). [survey_details]
The "reduce screen hangs" verbatim and the payment-screen hang point at the same thing — report both signals; don't assert one caused the other.
[sources: list_app_hangs + list_crashes filtered by current_views; app_insights apm; list_reviews; survey_details; list_bugs]
```

---

## Engineering Manager

**The reader's decision:** what does my team triage first, and what's the actual stack?

**Leads on:** new and trending issues in the team's components (filter `teams`), crash / ANR / OOM rates with deltas vs the prior version, top crashes by both frequency and users, the device / OS breakdown, and — the EM-only depth — the per-occurrence stack, one real session, and the aggregated diagnostics for the top crash.

**Tool calls (the step-4b chain):**
1. `list_crashes(slug, mode, filters.teams=[<id>], sort_by=first_occurred_at, direction=asc)` for new-in-window, and again `sort_by=occurrences_counter` and `affected_users_counter` for the worst by volume and by impact. Pick the top group's `number`.
2. `crash_details(slug, mode, number=<top>)` for the stack frames — lead with the `is_grouping_frame` and the deepest `application` frame; drop the system frames.
3. `list_occurrences_tokens(slug, mode, number=<top>)` for the occurrence ULIDs (newest = lexicographically largest).
4. `get_occurrence_details(slug, mode, number=<top>, ulid=<newest>)` for one concrete session (device, OS, memory, screen, foreground/background, duration) — the repro context.
5. `crash_diagnostics(slug, mode, number=<top>)` (async, re-call while `generating`) for the aggregate: screen-flow `patterns`, device/OS/version `distributions`, and the memory/battery/storage/duration histograms.
6. `crash_patterns(slug, mode, number=<top>, pattern_key=oses)` / `=devices` for the per-key breakdown.
7. *(optional)* When the EM also needs the slowest endpoints / screens, a direct JSON-RPC `apm_list_groups` call (metric `network` sorted by `failure_rate`, and `screen_loading` sorted by `p95`) — see the constraint note in `metrics-glossary.md`. Read-only; label the result as sourced via a direct call.

**Drill-down included:** full stacktraces, one occurrence's detail, the diagnostics aggregate, and (optionally) the per-span APM list. Raw numbers are fine and expected.

**Omit / suppress:** exec and revenue narrative.

**Framing:** granular and triage-oriented. Lead the list with the application frame, not the system frames.

**Worked outline:**
```
Alert Response Team — top crashes, production:
  #1 OOM on ViewController — 1094 occ / 1100 users — no stack trace (OOM)
  #2 NSRangeException "index 100 beyond bounds for empty NSArray" on IBGCPPExcpetionsTableViewController — 1113 occ / 1121 users
  #3 SIGABRT (_wrap_pthread_kill) on IBGCPPExcpetionsTableViewController — 1095 occ / 1097 users
#2 NSRangeException stack (application frames only):
  -[IBGObjcException throwExceptionPrivate]  (grouping frame)
  ← -[IBGCPPExcpetionsTableViewController tableView:didSelectRowAtIndexPath:]  ← _main
One occurrence (newest of 196 tokens, ulid 01KV49…EWG27):
  iPhone 12 Pro, iOS 14.3, memory 4297/6144 MB, app in background, session 6:58, on IBGCPPExcpetionsTableViewController.
Diagnostics across occurrences (crash_diagnostics, 500 sessions):
  memory p90 73%; screen flow loops Stations ↔ NowPlaying before the crash; spread across iPhone 13/XS/11.
OS spread (crash_patterns oses): iOS 14.2 (64), 15.3 (62), 16.0 (60) — broad, not version-specific.
[sources: list_crashes by team; crash_details stack_frames; list_occurrences_tokens; get_occurrence_details; crash_diagnostics; crash_patterns oses]
```

---

## QA / Release

**The reader's decision (made by the release owner, not this skill):** does the build clear the team's bar?

**Leads on:** crash-free and ANR / OOM / hang for the candidate version laid against the team's own ship thresholds, the APM rates (network apdex, launch / screen p95) against their thresholds, new-in-version issues, regression count vs baseline, and the worst offenders with repro context.

**Tool calls:**
1. `app_insights(slug, mode, filters.app_version=[<candidate>])` for the `monitoring` rates AND the `apm` rates to place against thresholds.
2. `list_crashes(slug, mode, filters.app_versions=[<candidate>], sort_by=first_occurred_at, direction=asc)` for new-in-version.
3. `crash_patterns(slug, mode, number=<top>, pattern_key=app_versions)` for the regression delta and per-version exposure.

**Drill-down included:** the issue list plus repro context.

**Omit / suppress:** long-term business trends.

**Framing:** a threshold readout — metric, value, threshold, pass/under, side by side. **This skill reports the comparison; it does not write "ship," "hold," or "rollback."** That decision belongs to the release owner; the readout's job is to make the call obvious, not to make it.

**Worked outline:**
```
Release candidate 3.1.4 vs team thresholds (production, matched window):
  metric              value     threshold   status vs threshold
  crash-free sessions 99.47%    ≥ 99.0%     above
  app-hang-free       99.55%    ≥ 99.0%     above
  OOM-free            99.85%    ≥ 99.5%     above
  network apdex       0.920     ≥ 0.90      above
  cold-launch p95     561ms     ≤ 2000ms    above (well under)
New-in-version issues on 3.1.4: none surfaced in window (sorted first_occurred_at).
Regression vs 3.0.4: every monitoring rate improved; no regression flagged.
Decision: deferred to the release owner — this is the data, not the verdict.
[sources: app_insights per version; list_crashes new-in-version; crash_patterns app_versions]
[note: thresholds above are illustrative — substitute the team's actual bar.]
```

---

## Cross-persona discipline

- **Confidence travels with the number.** If a version's exposure is thin, every persona hears "low sample," phrased for their altitude — "early rollout" for a VP, "n is small, treat as directional" for an EM.
- **A missing section is reported at every altitude.** An errored `app_insights.monitoring` becomes "crash-free unavailable this window" for the exec and "monitoring section returned an error — pulled volume from list_crashes instead, which is not the same metric" for the EM.
- **Reviews and survey feedback are quoted, never summarized into a claim.** "Users call checkout sluggish" is fine when followed by the verbatim quote; it is not fine as a standalone assertion. NPS verbatims ("how can we do better") get the same treatment as review bodies.
- **Performance lives at the `apm` aggregate.** Every tier that gets performance gets it as apdex / p95 / drop-off summaries from `app_insights.apm`, not per-span traces. The per-span `apm_*` tools are stripped from the MCP client (top-level-combinator issue) and are `luciq-debug`'s job; an EM readout may optionally reach the read-only `apm_list_groups` via a direct JSON-RPC call for a slowest-endpoint / slowest-screen list, labeled as sourced that way. No other tier descends below the aggregate.
- **Read-only, always.** No tier — and no step — ever calls a write tool. A readout reports; it never mutates a bug, a status, or anything else.
- **No verdicts.** No persona's readout ends in "ship it." The QA tier lays the bar and the numbers next to each other and stops.
