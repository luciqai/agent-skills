---
name: luciq-onboard
description: Use after the Luciq SDK is installed to help the user discover which Luciq products fit their app and configure them in a personalized, evidence-based, conversational walkthrough. Trigger phrases include "onboard me to Luciq", "walk me through Luciq", "help me get started with Luciq", "what should I set up with Luciq", "what Luciq products should I use", "tour Luciq", "best way to use Luciq for my app", or any moment a user finishes luciq-setup and asks what to do next. This skill reads the user's repo (code, CLAUDE.md, README, AGENTS.md), detects any existing mobile observability SDKs (Sentry, Crashlytics, Bugsnag, Datadog, Embrace, New Relic, App Center, Instabug-legacy, UXCam, Smartlook, MetricKit) along with the user's posture on each of them, and recommends Luciq products with cited rationale — never as a generic feature menu. Specifically NOT for first-time SDK install (use luciq-setup), not for upgrading SDK versions (use luciq-migrate), not for debugging a specific crash, hang, or user-reported bug (use luciq-debug).
---

# Luciq Personalized Onboarding

End-to-end personalized walkthrough of the Luciq product suite for an app that already has the SDK installed. The skill scans the project to understand what the app is, what the team values, and what observability is already in place — then walks the user through the Luciq products that actually fit, with cited reasoning at every step. Skips products that don't fit. Frames excluded products positively as "add later" with a revisit condition.

The aim is a conversational experience the user remembers — one where every recommendation is justified by something the agent observed in their own repo, not a generic pitch.

## When NOT to use this skill

Hand off to a sibling skill for any of the following:

- **First-time SDK install** — the SDK isn't initialized yet → `luciq-setup`.
- **Upgrading a Luciq SDK version or migrating from the legacy Instabug SDK** → `luciq-migrate`.
- **Investigating a specific crash, hang, regression, or user-reported bug** → `luciq-debug`.
- **API signature lookups** — point the user at https://docs.luciq.ai.

If the user's ask matches any of the above, STOP and route them. Running `luciq-onboard` on an uninstrumented project produces incorrect recommendations because every analysis step assumes the SDK init is already present.

## Canonical sources of truth

Verify product names, dashboard URLs, and config keys against the live docs before quoting them in the conversation. Hardcoded values in this skill are illustrative.

| Concern | Source |
| --- | --- |
| Product setup details (per platform) | https://docs.luciq.ai |
| iOS product setup | https://docs.luciq.ai/ios/setup-luciq-for-ios |
| Android, RN, Flutter, KMP | the platform's setup space under https://docs.luciq.ai |
| User's apps and workspace | Luciq MCP `list_applications` (if authenticated) |
| User's prior crashes / patterns | Luciq MCP `crash_patterns`, `list_crashes`, `list_bugs` |
| The user's repo | local file system — read directly |

## Operating principles

These shape every conversational turn the skill produces. Internalize them; they're the difference between onboarding that feels like a wizard and onboarding that feels like a thoughtful peer.

1. **Cite every recommendation.** Never say "I recommend X" without naming the source: a CLAUDE.md line quoted verbatim, a file:line in the user's code, a precedent from their other Luciq apps, or a specific archetype rationale.
2. **Show your work before asking.** If a question can be answered by reading the repo, answer it — don't ask. Only ask the user things only the user knows.
3. **One conversational beat at a time.** Never present a wizard form. Present one product, one decision, one ask.
4. **Default to recommending, fall back to asking.** Every question is a tax on the user; reserve it for genuinely undecidable cases.
5. **Skip and defer are first-class.** A user who says "not now" hasn't failed — they've made a choice. Capture it with a reason and a revisit condition, then move on.
6. **Honest about competitors, never disparaging.** Position Luciq's strengths alongside what the user already has. Never criticize a competitor's product.
7. **Activation > configuration.** A configured product the user hasn't seen working is a half-delivery. End the walk with a single concrete verification step that produces real data on the user's dashboard.

## Workflow checklist

Track every phase. STOP on any phase that can't complete with confidence — never fake progress.

```
Onboarding Progress:
- [ ] 0. Detect mode (FAST / AUDIT / GUIDED)
- [ ] 1. Analyze the project (silent, parallel)
- [ ] 2. Recap — conflicts first, then app understanding
- [ ] 3. Present the plan (three positive buckets)
- [ ] 4. Product walk (Ask → Apply → Summarize per product)
- [ ] 5. End-of-walk activation (one consolidated Aha)
- [ ] 6. Handoff — write LUCIQ_ONBOARDING.md
```

## 0. Detect mode

Read the user's trigger phrasing and pick a mode. Different modes produce different conversation lengths.

| Trigger phrasing | Mode | Behavior |
| --- | --- | --- |
| "must-haves", "fast", "quick", "just the basics" | **FAST** | Apply the top 3 "Recommended now" products with one-line confirms each. No end-of-walk activation. ~2 minutes. |
| "what am I missing", "audit", "what should I set up" | **AUDIT** | Report-only. Print the analysis, present the plan in three buckets, write the handoff doc. Apply nothing without explicit per-product confirmation in a follow-up. |
| anything else, including "onboard me", "walk me through", "tour" | **GUIDED** | Full arc with conflict recap, per-product walk, and end-of-walk activation. ~10 minutes. This is the default. |

If unclear, default to GUIDED. Confirm the chosen mode in one line at the start so the user knows what they're about to spend time on.

## 1. Analyze the project (silent, parallel)

This phase runs without conversation. The output is a single structured **project profile** the rest of the workflow reads from. Do all four analysis tracks in parallel — they're independent and deterministic.

### Track A — Context docs

Read in priority order. Stop at the first source rich enough to anchor the recap. Augment with later sources if shallow.

1. `CLAUDE.md` (repo root + any nested)
2. `AGENTS.md`, `.cursorrules`, `.windsurfrules`
3. `README.md`, `ARCHITECTURE.md`, `docs/*.md`

Extract: app purpose (one sentence), team's stated priorities, PII / privacy posture, mention of compliance frameworks (GDPR, HIPAA, SOC2, PCI), and any quotable line (with line number) the recap can cite verbatim. The cited quote is what makes the recap feel uncanny — find at least one if context exists.

### Track B — Archetype + money path + auth

From the existing `luciq-setup` profile (or a fresh scan), infer:

- **Archetype**: e-commerce / fintech / social / media / productivity / gaming / B2B-tool / internal — based on deps (`Stripe`, `RevenueCat`, `Firebase Auth`, `Auth0`) and screen names (`CheckoutView`, `FeedView`, `DashboardView`).
- **Money path**: the file:line of the screen where revenue is captured (checkout, paywall, subscription). E-commerce without an identified money path means the archetype guess is shaky — ask once.
- **Auth flow**: login and logout file:line. Needed for product recommendations that depend on `identifyUser`.

### Track C — Mobile observability SDK scan + deep config read

Detect every active mobile observability SDK on the project, then for each one read its init site and extract what's on, what's off, and what's tuned. See `references/observability-sdks.md` for the v1 detection patterns, config keys per SDK, and the coverage matrix.

Three signals per SDK:

1. **Manifest match** — package declared in Podfile / Package.swift / build.gradle(.kts) / package.json / pubspec.yaml.
2. **Init call match** — the start/configure call is present in source.
3. **Config artifact match** — config files like `GoogleService-Info.plist`, `sentry.properties`.

A package without an init call is **shelf-ware** — flag it (offer cleanup later), don't treat it as active. All three signals together = confirmed active.

For each confirmed-active SDK, extract:
- **What's on** (enabled features)
- **What's off** (explicitly disabled features — this is the most valuable column, signals team intent)
- **What's tuned** (non-default sample rates, thresholds, redaction lists, env gating)

From the extracted config, infer a **style** (one line): "privacy-conservative, low sample, strict env gating" / "permissive, full PII capture, debug+release". Luciq's defaults in Phase 4 should match this style.

### Track D — Workspace precedent (MCP)

If the Luciq MCP is authenticated, call `list_applications` to enumerate the user's other Luciq apps. For each, optionally call `apm_list_groups` and read masking/replay config patterns to infer the team's "house style" across apps. A precedent quote like *"your other 3 apps run replay at 5%"* is one of the strongest trust-building moves available.

If MCP is not authenticated, skip silently — do not nag the user to authenticate. Precedent is a nice-to-have, not a requirement.

### Conflict detection (in the same pass)

Conflicts are deterministic logic over what the analysis already found — compute them in the same parallel sweep. See `references/observability-sdks.md` for the per-SDK conflict rules. Severity:

- **High** — dual crash handlers, racing ANR detectors, multiple session-replay capturers. Today's capture is non-deterministic. State this honestly.
- **Medium** — multiple network interceptors, overlapping method swizzling on lifecycle methods.
- **Low** — shelf-ware packages, deprecated SDKs still in the manifest.

Conflicts get **surfaced** in Phase 2's recap, never as a separate phase. Capture all of them in the handoff doc whether or not the user addresses them.

## 2. Recap — conflicts first, then app understanding

Open with conflicts if any exist. State them plainly, separate from any Luciq recommendation. This is the trust moment — surfacing problems the user has *independent* of whether they adopt Luciq is what earns credibility for everything that follows.

Example opener for a project with detected conflicts:

> Heads-up before we start: Sentry (AppDelegate.swift:23) and Firebase Crashlytics (AppDelegate.swift:18) both install crash signal handlers. Only one captures any given crash today — your crash capture is non-deterministic. Worth fixing regardless of what we do next.

Then the cited app understanding. Every line is sourced — a CLAUDE.md quote with line number, a file:line for the money path, an inferred style from a competitor's config:

> Quick read on your app:
> - iOS SwiftUI e-commerce app. Money path on `CheckoutView.swift:42`.
> - Your CLAUDE.md line 12 says *"never log financial data"* — I'll default masking aggressive on checkout.
> - Sentry is configured conservatively (replay at 5%, `attachScreenshot: false`, `sendDefaultPii: false`) — Luciq's defaults below will match that posture.
> - Your other 2 apps in this workspace both use Bug Reporting with shake invocation.

If no conflicts and no rich context exist, the recap is two lines instead of six — don't pad. Quality of evidence over quantity of lines.

## 3. Present the plan — three positive buckets

Score each of the 8 Luciq products against the profile (see `references/product-cards.md` for per-product fit signals and anti-signals). Group into three buckets. **Never use negative labels like "not a fit" or "skip" in user-facing copy** — always frame as timing.

- **Recommended now** — strong fit, applying this session.
- **Optional — add if you'd like** — reasonable fit; user's call this session or later.
- **Can be added later** — better timed for the future, with a specific revisit condition stated.

Every item in "Can be added later" must name *when* it makes sense:

> Can be added later:
> – **App Ratings** — best once you're live on the App Store. I'll wire it then.
> – **Crash Reporting** — Sentry covers this on your app today. If you ever want to consolidate vendors, I can switch you over in one session.
> – **In-App Replies** — depends on `identifyUser`. When you wire your auth flow, add this.

Close the plan presentation with one question: *"Want to adjust any bucket before I start?"* If the user moves something between buckets, accept it and proceed.

In AUDIT mode, stop here — write the handoff doc (Phase 6) and exit. Don't apply anything.

## 4. Product walk — per-product micro-flow

For each product in "Recommended now" (and any "Optional" the user picked up), run the three-step micro-flow. Per-product copy and apply targets live in `references/product-cards.md`. Read that file before starting the walk.

### A. Ask

One line: name the product, give one-line value, give the user's *specific* reason for fit (cited).

> **Bug Reporting** — your users shake the phone or screenshot to send a report with logs, network, repro steps. Strong fit for you because no competitor on your stack handles user-initiated reports, and your CLAUDE.md mentions support load. Include it?

Three responses available: **Yes / No / Tell me more**. "Tell me more" expands the why; "No" goes to defer (record the reason).

### B. Apply

Derive the *exact* changes from the profile, not from defaults. Show a diff before applying. Confirm.

- Use the **money path** to scope APM and Session Replay aggressiveness.
- Use the **competitor's style** to set sample rates, screenshot capture, env gating.
- Use the **CLAUDE.md privacy line** to set masking aggressiveness.
- Use the **auth flow file:line** for `identifyUser` injection sites.

If a required file edit conflicts with uncommitted user changes, STOP and surface — don't overwrite work.

Delegate the actual API calls to the patterns in `luciq-setup` when they exist (don't reinvent installation primitives).

### C. Summarize

After applying, three short blocks:

> Done. Here's what I did:
> - Enabled Bug Reporting in `NotDemoAppApp.swift:14`
> - Set invocation to shake (matched your Sentry's conservative posture)
> - Masked text inputs on `CheckoutView.swift:42` per your CLAUDE.md line 12
>
> What's left for you (no code needed):
> - Nothing required — reports start arriving on next launch.
>
> Moving to the next product: **Session Replay**.

The "What's left for you" block lives in `references/product-cards.md` per product. Only list items the user genuinely needs to do — dashboard config, optional symbol upload setup. Never list third-party tool integrations by name. If nothing is left for the user, say so plainly.

## 5. End-of-walk activation

After all selected products are configured, run **one consolidated activation moment** — not one per product. The aim is a single concrete round-trip that proves Luciq is working end-to-end.

Use the **primary product** as the activation vehicle (Bug Reporting if included, otherwise the highest-ranked recommended product). The verification has three concrete steps and one waiting moment:

> All set. To see Luciq working end-to-end:
>  1. Build and launch the app.
>  2. Shake the simulator (Ctrl+Cmd+Z) — or use your chosen invocation event.
>  3. Type "test from onboarding" and submit.
>  4. Open your dashboard: `<dashboard URL for this app>`
>
> Tell me when you see the report — or just come back later.

Wait for confirmation. If the user reports they don't see it after 60 seconds, diagnose (build still running? wrong app token? simulator not invoking?) — never claim success without confirmation. If the user says "later," accept and move on — record in the handoff that activation was not verified.

In FAST mode, skip this phase. The handoff doc still includes the verification steps so the user can do it themselves.

## 6. Handoff — write LUCIQ_ONBOARDING.md

Write `LUCIQ_ONBOARDING.md` at the repo root using the template in `references/handoff-template.md`. The doc is the durable artifact of the session — re-readable next week, hand-off-able to a teammate, queryable by `luciq-debug` later.

Contents:

- **Products active** — each with the file:line edited and (if verified) the timestamp of the first report.
- **Products deferred** — each with its revisit condition.
- **Products covered by another SDK** — each with the SDK name and file:line.
- **What's left for you** — the doc-pointer items from each active product, deduplicated.
- **Conflict notes from Phase 2** — every conflict the analysis found, even if not addressed this session.
- **Dashboard URL for this app.**
- **When to reach for sibling skills** — `luciq-debug` for incident investigation, `luciq-migrate` for upgrades.

If `LUCIQ_ONBOARDING.md` already exists, *append* a new dated session block — don't overwrite. The file accumulates the team's Luciq journey.

## Style

- ALWAYS show diffs before applying any code edit. Confirm.
- Cite every recommendation with a source — CLAUDE.md line, file:line, precedent quote, or named archetype rationale.
- One conversational beat at a time. No wizard forms.
- Skip and defer are first-class. Capture reasons and revisit conditions.
- Never criticize a competitor. Position Luciq alongside what's there.
- Verify product names and dashboard surfaces against the live docs before quoting them.
- Match the team's observed style — if their Sentry is privacy-conservative, Luciq's defaults should be too.

## Red flags — STOP and surface to the user

If you catch yourself thinking any of these, you're about to ship a bad onboarding. Stop, surface, do not proceed:

- *"I'll recommend this even though there's no signal for it — it's a good Luciq feature."* Recommendation without citation breaks the trust the whole skill rests on. If you can't cite, don't recommend.
- *"I'll skip the conflict — it's not Luciq's problem."* Surfacing conflicts is the trust-building move. Skip it and the rest of the conversation feels like sales.
- *"Their CLAUDE.md says one thing but I'll override it because Luciq's default is better."* The user's stated intent wins. If you disagree, ask, don't override.
- *"I'll claim activation succeeded — the build is probably fine."* Activation needs explicit user confirmation that data is visible on the dashboard. Otherwise it's a half-delivery.
- *"I'll keep going even though MCP failed."* MCP failures are fine to skip silently in Phase 1 (precedent is optional). But if MCP fails *during apply* — e.g., looking up an app token — surface and stop. Don't fabricate a token or guess.
- *"They said 'not now' but I'll keep pitching it."* Defer means defer. Capture the reason, move on, leave it in the handoff doc with a revisit condition.
- *"I'll flag App Ratings as 'not a fit' since this is B2B."* Don't say "not a fit." Say "better added when you launch on the App Store" — same honesty, no sting.
- *"Sentry covers crashes; I'll convince them to switch to Luciq Crash anyway."* If a competitor genuinely covers a Luciq product, frame it as a future "consolidate vendors" option, not an immediate recommendation. Don't oversell.

Every shortcut here trades "looks done" for "actually helpful." The skill's job is to make the user *feel understood* and leave them with working Luciq products they trust — not to maximize feature adoption in one session.
