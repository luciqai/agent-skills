---
name: luciq-pii
description: Use ONLY when the customer explicitly invokes a PII / masking audit on their own initiative, in a fresh message, with one of these phrases (or a close variant) — "audit my PII", "check my masking", "review Luciq privacy / PII posture", "prep Luciq for HIPAA / GDPR / SOC2 / PCI", "add masking to <screen>", "what's masked in Luciq?". Nothing else is a trigger. `luciq-onboard` finishing is NOT a trigger. The assistant suggesting a PII review and the customer agreeing is NOT a trigger. The customer must say a PII-shaped phrase themselves, unprompted. This skill scans the user's repo and Luciq SDK config for masking posture (auto-mask types, per-view markers, network auto-masking, manual obfuscate/omit, consent gating, grayscale, FLAG_SECURE, SSUI isPrivate handling), compares it against compliance frameworks the user mentions, and walks the user through adding the controls that fit — with cited rationale. Specifically NOT for first-time SDK install (use `luciq-setup`), not for the full product walk (use `luciq-onboard`), not for SDK upgrades (use `luciq-migrate`), not for debugging a specific incident (use `luciq-debug`).
---

# Luciq PII & Masking Audit

End-to-end PII posture audit and masking apply for an app that already has the SDK installed. Scans what's masked today (screen, view-level, network), surfaces gaps against the customer's stated compliance posture, and walks the user through closing them — one control at a time, with cited reasoning.

The aim is a conversational audit the user can re-run later — before launch, before a new screen ships, before a compliance review — without re-doing onboarding.

## When NOT to use this skill

Hand off to a sibling skill (or simply don't run) for any of the following:

- **First-time SDK install** — the SDK isn't initialized yet → `luciq-setup`.
- **Full product walk** (Bug Reporting, Replay, APM, Surveys, etc.) → `luciq-onboard`.
- **Upgrading a Luciq SDK version or migrating from the legacy Instabug SDK** → `luciq-migrate`.
- **Investigating a specific crash, hang, regression, or user-reported bug** → `luciq-debug`.
- **API signature lookups** — point the user at https://docs.luciq.ai.
- **After `luciq-onboard` completes.** Onboard does not invite a PII audit. Wait for the customer to invoke this skill on their own, in a fresh ask.

If the user's ask matches any of the above, STOP and route them. Running `luciq-pii` on an uninstrumented project produces incorrect results because every detection step assumes the SDK init is already present.

## Canonical sources of truth

Verify SDK class names, API signatures, default key lists, and config flags against the live docs before quoting them. Hardcoded values in this skill are illustrative.

| Concern | Source |
| --- | --- |
| Per-platform masking APIs | https://docs.luciq.ai (per-platform setup guides) |
| Auto-masking screenshot types | iOS / Android / Flutter / RN sections of the live setup guides |
| Network auto-masking key list | Server-side, configurable; the in-skill list is the SDK 14.2.0 default |
| Session Replay privacy & consent | https://docs.luciq.ai (Session Replay → Privacy & Data Masking) |
| User's repo | local file system — read directly |
| User's apps and workspace | Luciq MCP `list_applications` (if authenticated) |

## Operating principles

These shape every conversational turn the skill produces.

1. **Cite every finding and every recommendation.** Never say "masking is enabled" without `file:line`. Never say "you should mask X" without naming the signal (CLAUDE.md line, view binding, compliance framework the user named).
2. **Defense in depth, not single-layer.** The reference model has three layers: automatic type-based masking (safety net), manual per-view marking (precise), and network-layer masking. A real audit checks all three — never declare "PII is handled" off one control.
3. **Masking is client-side only.** Never imply the dashboard or backend can mask retroactively. If raw data already shipped, it shipped — the only fix is forward.
4. **One control at a time.** Per-control Ask → Apply → Summarize, same micro-flow as `luciq-onboard`. No wizard forms.
5. **Match the team's compliance posture, don't invent one.** If the user names HIPAA, default to the HIPAA preset (see `references/compliance-defaults.md`). If they name nothing, default per archetype and offer the preset rather than assume.
6. **Honest about gaps, never alarmist.** Surface what's missing with the consequence stated plainly. No FUD, no "you're exposed" language.
7. **Activation > configuration.** A masking config that's never visually verified is a half-delivery. End with a screenshot-of-a-masked-screen verification, not just "config applied."

## Workflow checklist

Track every phase. STOP on any phase that can't complete with confidence — never fake progress.

```
PII Audit Progress:
- [ ] 0. Detect mode (FAST / AUDIT / GUIDED) and compliance posture
- [ ] 1. Posture scan (silent, parallel) — all three layers + defense-in-depth controls
- [ ] 2. Recap — what's masked today, with citations
- [ ] 3. Plan — three positive buckets (close now / optional / monitor)
- [ ] 4. Per-control walk (Ask → Apply → Summarize)
- [ ] 5. Verification — visually confirm masking on one sensitive screen
- [ ] 6. Handoff — write LUCIQ_PII.md (pre-prod checklist + posture snapshot)
```

## 0. Detect mode + compliance posture

Two reads happen at the trigger: mode, and stated compliance framework.

**Mode** (same vocabulary as `luciq-onboard`):

| Trigger phrasing | Mode | Behavior |
| --- | --- | --- |
| "must-haves", "fast", "quick" | **FAST** | Apply the top 3 missing controls with one-line confirms. ~2 minutes. |
| "audit", "what am I missing", "report", "review" | **AUDIT** | Report-only. Posture scan + recap + bucketed plan + handoff doc. Apply nothing without follow-up confirmation. |
| anything else, including "review my PII", "prep for HIPAA" | **GUIDED** | Full arc with per-control walk and verification. ~8 minutes. Default. |

**Compliance posture** — scan the trigger message and Track A (CLAUDE.md / README) for an explicit framework mention: HIPAA, GDPR, SOC2, PCI-DSS, CCPA, FERPA. If named, load the matching preset from `references/compliance-defaults.md` and confirm it in one line at the start: *"Treating this as a HIPAA audit — aggressive masking, consent gating, no grayscale-only."* If not named, proceed with archetype defaults and offer the relevant preset in Phase 3.

Confirm mode + posture in one line so the user knows what they're about to spend time on.

## 1. Posture scan (silent, parallel)

This phase runs without conversation. The output is a structured **PII profile** the rest of the workflow reads from. Do all five tracks in parallel.

### Track A — Context docs

Read in priority order, same as `luciq-onboard`:

1. `CLAUDE.md` (repo root + any nested)
2. `AGENTS.md`, `.cursorrules`, `.windsurfrules`
3. `README.md`, `ARCHITECTURE.md`, `docs/*.md`

Extract: explicit privacy lines, compliance framework mentions, "never log X" rules, user consent obligations. Find at least one quotable line with line number — that's what makes the recap feel uncanny.

### Track B — Sensitive view enumeration

Run the same enumeration `luciq-onboard` does (see its Track B): for each sensitive screen, identify individual views bound to PII-flavored properties, with `file:line, view_type, binding, suggested_marker`. Same false-positive filters (test/spec/mock paths, validator utilities, `node_modules`, `Pods/`, `build/`). Re-enumerate from scratch every run — the audit should be evidence-driven from the current repo state, never relying on a prior session's notes which may be stale.

The structured output is `sensitive_views: [{screen, file, line, view_type, binding, suggested_marker, currently_marked: bool}]`. The `currently_marked` flag is the key new column — set true if the view already has the Luciq marker applied at its site.

### Track C — Auto-mask configuration

Detect what the SDK init does for automatic screenshot masking. See `references/auto-mask-types.md` for per-platform patterns.

| Platform | Grep / read |
|---|---|
| iOS | `SessionReplay.autoMaskScreenshotOptions`, `Luciq.setAutoMaskScreenshotsTypes`, `IBGSessionReplay.autoMaskScreenshotOptions` |
| Android | `Luciq.setAutoMaskScreenshotsTypes(`, `Instabug.setAutoMaskScreenshotsTypes(` |
| Flutter | `SessionReplay.setAutoMaskingTypes(`, `Luciq.setAutoMaskScreenshotsTypes(` |
| React Native | `Instabug.setAutoMaskScreenshotsTypes(`, `Luciq.setAutoMaskScreenshotsTypes(` |

Output: `auto_mask: { configured: bool, file_line, types: [TEXT_INPUTS | LABELS | MEDIA | WEB_VIEWS | MASK_NOTHING] }` or `{ configured: false }`. **A missing call is not the same as `MASK_NOTHING`** — record the distinction. The platform default (typically `TEXT_INPUTS`) applies when not configured; quote it from the live setup guide before recapping.

### Track D — Network masking configuration

Detect network masking state and any custom obfuscate/omit hooks.

| Signal | Locations to grep |
|---|---|
| Auto-mask explicit state | `setNetworkAutoMaskingState(`, `NetworkLogger.autoMaskingEnabled`, `IBGNetworkLogger.autoMaskingEnabled` |
| Manual obfuscate | `NetworkLogger.obfuscateLog(`, `obfuscateLog(`, custom request-mutator interceptors |
| Manual omit | `NetworkLogger.omitLog(`, `omitLog(` |
| Custom mask key extensions | support-ticket / server-side config — flag as "verify with admin" if no local signal |

Output: `network_masking: { auto_enabled: bool | "default-on", file_line, obfuscate_sites: [...], omit_sites: [...], custom_keys_requested: bool }`. Default is on starting with SDK 14.2.0 — record SDK version (read from Podfile.lock / Package.resolved / build.gradle / package.json / pubspec.yaml) so the recap can state whether auto-masking applies.

### Track E — Defense-in-depth controls

Five small reads, each one a separate control in the plan.

| Control | Signal |
|---|---|
| **Consent gating** | `SessionReplay.enabled =`, gated on a user-consent boolean (CLAUDE.md mention of consent flow) |
| **Grayscale screenshots** | `SessionReplay.screenshotQualityMode = .greyScale`, `screenshotQualityMode` |
| **FLAG_SECURE (Android)** | `ignoreFlagSecure(`, manifest review for `WindowManager.LayoutParams.FLAG_SECURE` on sensitive Activities |
| **`usersPageEnabled`** | `usersPageEnabled = false`, server-controlled — flag for verification |
| **SSUI inflate sites** | code paths that inflate views from server JSON (`inflateFromJson`, `JSONSerialization` → view tree, RemoteConfig-driven UI). If present, the audit must propose an `isPrivate` flow per `references/ssui-isprivate.md` |

Output: `defense_in_depth: { consent_gating, grayscale, flag_secure_overridden, users_page_enabled, ssui_inflate_sites: [...] }`.

Encryption posture (AES-256-GCM at rest, TLS 1.2+ with HMAC-SHA256 in transit, iOS Keychain for PII keys) is on by default and not configurable from the audit — but it belongs in the recap and handoff so the user sees masking + encryption as a layered posture, not just masking. See `references/encryption-at-rest.md` for the one-line recap form and the on-device data category table.

### Track F — Workspace precedent (MCP, optional)

If the Luciq MCP is authenticated, call `list_applications` and read masking config from peer apps. A precedent quote like *"your other 3 apps mask `TEXT_INPUTS + LABELS` at SDK init"* is the strongest trust move available for an audit. Skip silently if MCP isn't authenticated.

### Compliance-framework alignment (in the same pass)

If a framework was named at trigger or found in Track A, load its preset from `references/compliance-defaults.md` and compare each profile value to the preset. The deltas drive the Phase 3 plan.

| Framework | One-line minimum (see reference for full preset) |
|---|---|
| **HIPAA** | Aggressive auto-mask (`TEXT_INPUTS + LABELS + MEDIA`), per-view markers on every PHI view, network auto-mask on, consent gating before Session Replay. |
| **GDPR** | Consent gating before Session Replay (and ideally before SDK init in EU), no PII in network logs, right-to-erasure documentable. |
| **PCI-DSS** | Per-view markers on every cardholder data view, network auto-mask on, never log raw PAN/CVV, grayscale optional. |
| **SOC 2** | Auto-mask on as a baseline control, masking config under version control, audit trail of changes. |
| **CCPA / FERPA** | Consent gating + per-view markers on regulated data fields; verify against current statute text — defaults here are illustrative. |

## 2. Recap — what's masked today

Open with one line stating the overall posture honestly: *"Strong on view-level, weak on network"* / *"No auto-mask configured — relying on per-view markers alone"* / *"HIPAA-ready except for consent gating."* Then the cited evidence, capped at 6 lines.

Example for a partially-configured iOS SwiftUI app under HIPAA:

> Quick read on your PII posture:
> - Auto-mask: `TEXT_INPUTS + LABELS` at `LuciqInit.swift:24` — matches HIPAA minimum.
> - Per-view markers: 7 of 11 sensitive views marked; gap is 4 `Text` views on `PatientProfileView.swift:31-58` showing PHI.
> - Network auto-masking: enabled by default (SDK 14.3.1); no custom keys for your `x-patient-id` header — recommend adding via support.
> - Consent gating on Session Replay: **missing**. CLAUDE.md:8 says *"never record before consent"* — currently records on first launch.
> - Grayscale: off. Optional under HIPAA — defense-in-depth, not required.
> - SSUI: no inflate-from-JSON sites detected.

Cite the strongest 6 signals. Skip pad lines. If the posture is fully clean, say so plainly in one line and proceed to Phase 3 with the "monitor" bucket only.

## 3. Plan — three positive buckets

Never use "you're missing X" framing. Always positive bucketing.

- **Close now** — gaps with a clear apply step, named compliance fit, and high impact.
- **Optional — add if you'd like** — defense-in-depth controls; valuable, not strictly required.
- **Monitor** — controls already in place; revisit conditions for when they may need updating.

Every item in "Close now" must name its control, the cited gap, and the proposed apply target:

> Close now:
> – **Mark the 4 unmarked PHI views** — `PatientProfileView.swift:31-58` — propose `.luciqPrivate()` modifier per view, batch-confirm after first 2.
> – **Consent gating for Session Replay** — wrap `SessionReplay.enabled = true` in your existing consent check at `OnboardingFlow.swift:74` (CLAUDE.md:8).
> – **Add `x-patient-id` to the network mask list** — server-side config; I'll prep a support ticket request line for the handoff.

Close the plan with one question: *"Want to adjust any bucket before I start?"*

In AUDIT mode, stop here — write the handoff doc (Phase 6) and exit. Don't apply.

## 4. Per-control walk

For each "Close now" item (and any "Optional" the user picked up), run the three-step micro-flow.

### A. Ask

One line: name the control, the cited gap, the proposed change. Three responses: **Yes / No / Tell me more**.

> **Per-view markers on PatientProfileView** — 4 `Text` views bind to `patient.firstName`, `patient.lastName`, `patient.dob`, `patient.mrn`. Propose `.luciqPrivate()` on each. Apply?

For per-view markers, follow the confirmation policy in `luciq-onboard` SKILL.md Track B: confirm the first 3–5 individually, then batch-confirm the rest. Drop back to per-match if the user inspects a row.

### B. Apply

Derive the exact diff from the profile, not from defaults. Show before applying. Confirm.

- Use the **compliance preset** to choose auto-mask aggressiveness — see `references/compliance-defaults.md`.
- Use the **CLAUDE.md privacy line** as the override authority.
- Use the **competitor's masking style** (if any was detected in `luciq-onboard`) to keep posture consistent across SDKs.
- If a required file edit conflicts with uncommitted user changes, STOP and surface — don't overwrite work.

For server-side controls (network mask key additions, `usersPageEnabled`), prepare a one-line support-ticket request the user can copy — these can't be code-applied.

### C. Summarize

After applying, three short blocks:

> Done.
> - Marked 4 PHI views on `PatientProfileView.swift:31-58` with `.luciqPrivate()`.
> - Wrapped `SessionReplay.enabled = true` in `userHasConsented` check at `OnboardingFlow.swift:74`.
>
> What's left for you:
> - Email support to add `x-patient-id` to the network mask key list (template in `LUCIQ_PII.md`).
> - Verify masked regions in the dashboard after next session — see Phase 5.
>
> Moving to the next control.

## 5. Verification

After all selected controls are applied, run **one** verification round-trip — same shape as `luciq-onboard` Phase 5.

> All set. To verify masking visually:
>  1. Build and launch the app.
>  2. Navigate to one screen you just marked private (e.g., `PatientProfileView`).
>  3. Trigger a bug report or wait for a Session Replay frame.
>  4. Open the dashboard: `<dashboard URL for this app>`
>  5. Confirm masked regions render as solid black rectangles.
>
> Tell me when you see the masked screen — or just come back later.

If the user reports masking didn't work, diagnose (marker on parent vs child, auto-mask off, build cache?). Never claim success without confirmation. If the user says "later," accept and move on — record in the handoff that verification was not visually confirmed.

In FAST mode, skip the wait. The handoff doc still includes verification steps so the user can do it themselves.

## 6. Handoff — write LUCIQ_PII.md

Write `LUCIQ_PII.md` at the repo root using the template in `references/handoff-template.md`. The doc is the durable artifact — re-readable next quarter, hand-off-able to legal / compliance, queryable by `luciq-debug` later.

Contents:

- **Posture snapshot** — what's masked today, by layer (auto-mask, per-view, network, defense-in-depth).
- **Compliance posture** — framework named (or *not specified*), preset applied, deltas resolved this session.
- **Controls applied** — each with the `file:line` edited.
- **Controls deferred** — each with revisit condition.
- **Server-side requests** — copy-pasteable support ticket lines (network mask keys, `usersPageEnabled`).
- **Pre-production privacy checklist** — from `references/preprod-checklist.md`, with current state per item.
- **Visual verification** — timestamp + screen name if confirmed, or *not verified this session*.
- **When to reach for sibling skills** — `luciq-onboard` for product walk, `luciq-migrate` for SDK upgrades, `luciq-debug` for incident investigation.

If `LUCIQ_PII.md` already exists, *append* a new dated session block — don't overwrite. The file accumulates the team's PII journey.

## Style

- ALWAYS show diffs before applying any code edit. Confirm.
- Cite every finding with a source — `file:line`, CLAUDE.md line, framework requirement, precedent quote.
- One control at a time. No wizard forms.
- Never declare PII handled off a single layer. State which layers you verified.
- Never use FUD ("you're exposed", "you'll get fined"). State the gap and the compliance fit, let the user decide.
- Verify SDK class names and config keys against the live docs before quoting them.

## Red flags — STOP and surface to the user

If you catch yourself thinking any of these, stop and surface:

- *"Auto-mask is on, so per-view markers don't matter."* The §2.4 behavior matrix in the reference shows auto-mask alone misses anything outside its declared types; per-view markers fill the gap. Both matter.
- *"They didn't name a framework, so I'll skip compliance."* The audit should still surface relevant presets as offers in Phase 3 — the user may not know HIPAA applies until you mention it.
- *"Network auto-masking is on by default — no need to check."* Default-on is true for SDK ≥ 14.2.0; verify the version before claiming this. Older SDKs need an explicit call.
- *"Masking config was applied — I'll claim verified."* Visual verification needs explicit user confirmation that masked regions render as solid blocks on the dashboard. Otherwise it's a half-delivery.
- *"This view doesn't look sensitive, I'll skip the marker."* Track B is a positive enumeration with explicit signals. Don't filter on intuition. If a binding matches a PII pattern, surface it; let the user defer it explicitly.
- *"Grayscale alone is privacy."* Grayscale is defense-in-depth, not a substitute for masking. State that explicitly when it's the only control proposed.
- *"They said 'not now' on consent gating — fine, move on."* Capture the reason verbatim in the handoff. If the framework is HIPAA / GDPR, also surface the consequence in one neutral sentence before moving on.

Every shortcut here trades "looks done" for "actually compliant." The skill's job is honest posture — not maximum control count.
