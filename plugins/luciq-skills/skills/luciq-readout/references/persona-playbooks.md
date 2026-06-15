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

**Leads on:** one stability headline — `monitoring.crash_free_sessions.value` — with its direction vs last period, the App Store rating trend, and a single one-line top risk with its blast radius. Context against a benchmark, framed as something to validate.

**Tool calls:**
1. `app_insights(slug, mode)` for the headline `monitoring` rates and their `rate` (change) fields.
2. `list_reviews(slug, mode, sort_by=date)` for the rating trend; optionally `filters.rating=[1,2]` for the low-end signal.
3. `list_crashes(slug, mode, sort_by=affected_users_counter, limit=1)` for the single biggest blast-radius issue — reported as one line, by users affected, no ID, no trace.

**Drill-down included:** none inline.

**Omit / suppress:** stacktraces, device / OS matrices, raw occurrence counts, issue IDs, tool names in the narrative (keep them in a source footer).

**Framing:** a few sentences of narrative, two or three trended numbers, tied to user impact. If `monitoring` errored, say "crash-free rate unavailable for this window" — do not substitute a count.

**Worked outline:**
```
<App> is at 99.3% crash-free sessions this period, up slightly from last.
App Store sentiment is steady in the low-3s; the recurring theme is performance, not data loss.
Top risk: an out-of-memory issue affecting the largest user group on older devices — contained, not spreading.
Context: 99.3% sits just under the ~99.5%+ that's typical for healthy consumer apps — worth a look, not an alarm. (benchmark, to validate)
[sources: crash-free + rates from app_insights; rating from list_reviews; top risk from list_crashes by affected users]
```

---

## VP Eng / VP Product

**The reader's decision:** which release and which squad needs attention, and is the latest version a regression?

**Leads on:** crash-free sessions and users across the recent versions, the ANR / OOM / hang rates, regression flags by version, and the top issues by users affected with their owning team. Per-platform split if cross-platform.

**Tool calls:**
1. `app_insights(slug, mode, filters.app_version=[<vNew>])` and again for `[<vBaseline>]` — the version comparison spine. Match windows.
2. `list_crashes(slug, mode, sort_by=affected_users_counter, filters.app_versions=[<vNew>])` for the top-issue list with `team`.
3. `crash_patterns(slug, mode, number=<top>, pattern_key=app_versions)` to confirm whether a top issue concentrates in the new version (regression) and to read per-version `adoption` so a higher count on a higher-exposure version isn't miscalled a regression.

**Drill-down included:** top-issue list — titles and owning team, not traces.

**Omit / suppress:** full stack traces, the device long tail, per-developer metrics.

**Framing:** comparative across versions and squads, in summarized panels. Label each top issue new / regressed / trending. State confidence where a version's exposure is thin (cite `crash_patterns` session counts).

**Worked outline:**
```
Version 3.1.4 vs 3.0.4 (matched window, production):
  crash-free sessions  99.47%  vs  98.10%   (improved)
  app-hang-free        99.55%  vs  97.63%   (improved)
  OOM-free             99.85%  vs  99.53%   (improved)
3.1.4 is the healthier release across every monitoring rate.
Top issues on 3.1.4 by users affected, with owners:
  • Out-of-memory on ViewController — ~246 users — Alert Response Team
  • SIGABRT on the exceptions screen — ~227 users — Alert Response Team
Both span 3.0.4 and 3.1.4 (not new-in-version); neither is a 3.1.4 regression — confirmed via crash_patterns version split.
[sources: app_insights per version; list_crashes by affected users; crash_patterns app_versions]
```

---

## Product Manager

**The reader's decision:** is my flow healthy for users, and what are they actually saying?

**Leads on:** crash-free / hang health for the owned flow (filter `current_views` to the flow's screens), top issues by users affected on those screens, review themes in users' own words, and new-in-version issues on the flow.

**Tool calls:**
1. `list_crashes(slug, mode, filters.current_views=[<flow screens>], sort_by=affected_users_counter)` and `list_app_hangs(...)` with the same `current_views` filter — the flow's worst offenders.
2. `list_reviews(slug, mode, filters.rating=[1,2,3])` for the negative-to-mixed themes; quote bodies verbatim.
3. `list_bugs(slug, mode)` for user-reported issues touching the flow (match on `title`).

**Drill-down included:** the issue list plus representative verbatim review quotes.

**Omit / suppress:** symbolicated stack traces, infra detail.

**Framing:** flow- and user-centric, tied to journeys. A hang on `PaymentViewController` is "checkout stalls for users," not "main thread unresponsive 3000ms."

**Worked outline:**
```
Checkout flow health (screens: Pay.PaymentViewController, Pay.StatmentViewController):
  • A hang on the payment screen affected ~789 users — checkout stalls before the user can pay.
  • A hang loading statement history affected ~753 users — the history view freezes on open.
A user-reported bug corroborates: "Cannot complete premium checkout payment." [list_bugs]
What users are saying (verbatim, 1-3 star):
  • "It's sluggish, clunky, and prone to crashes. I can't rely on it for important tasks." — 1 star, US
  • "the features are cumbersome to use ... navigating through the app [is] a chore." — 2 star, FR
[sources: list_app_hangs + list_crashes filtered by current_views; list_reviews; list_bugs]
```

---

## Engineering Manager

**The reader's decision:** what does my team triage first, and what's the actual stack?

**Leads on:** new and trending issues in the team's components (filter `teams`), crash / ANR / OOM rates with deltas vs the prior version, top crashes by both frequency and users, and the device / OS breakdown.

**Tool calls:**
1. `list_crashes(slug, mode, filters.teams=[<id>], sort_by=first_occurred_at, direction=asc)` for new-in-window, and again `sort_by=occurrences_counter` and `affected_users_counter` for the worst by volume and by impact.
2. `crash_patterns(slug, mode, number=<top>, pattern_key=oses)` and `=devices` for the breakdown.
3. `crash_details(slug, mode, number=<top>)` — and `crash_diagnostics` (async, re-call while `generating`) — for the stack frames. Application frames are the fix target.

**Drill-down included:** full stacktraces and occurrence detail. Raw numbers are fine and expected.

**Omit / suppress:** exec and revenue narrative.

**Framing:** granular and triage-oriented. Lead the list with the application frame, not the system frames.

**Worked outline:**
```
Alert Response Team — top crashes, production:
  #1 OOM on ViewController — 244 occ / 246 users — no stack trace (OOM)
  #2 SIGABRT (_wrap_pthread_kill) on IBGCPPExcpetionsTableViewController — 226 occ / 227 users
  #3 NSRangeException "index 100 beyond bounds for empty NSArray" — 199 occ / 200 users
NSRangeException stack (application frames):
  -[IBGCPPExcpetionsTableViewController tableView:didSelectRowAtIndexPath:]
  → -[IBGObjcException throwException] → throwExceptionPrivate
OS spread of #3: iOS 14.2 (64), 15.3 (62), 16.0 (60) — broad, not version-specific.
[sources: list_crashes by team; crash_details stack_frames; crash_patterns oses]
```

---

## QA / Release

**The reader's decision (made by the release owner, not this skill):** does the build clear the team's bar?

**Leads on:** crash-free and ANR / OOM / hang for the candidate version laid against the team's own ship thresholds, new-in-version issues, regression count vs baseline, and the worst offenders with repro context.

**Tool calls:**
1. `app_insights(slug, mode, filters.app_version=[<candidate>])` for the rates to place against thresholds.
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
- **Reviews are quoted, never summarized into a claim.** "Users call checkout sluggish" is fine when followed by the verbatim quote; it is not fine as a standalone assertion.
- **No verdicts.** No persona's readout ends in "ship it." The QA tier lays the bar and the numbers next to each other and stops.
