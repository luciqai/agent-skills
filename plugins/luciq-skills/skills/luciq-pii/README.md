# luciq-pii

A Claude Code / Cursor skill that audits a Luciq-instrumented app's PII / masking posture across all three masking layers — screen / view markers, network logs, and defense-in-depth controls — and walks the controls that close any gaps with cited rationale.

If you've ever stared at a launch checklist and wondered *"is my masking actually enough for HIPAA / GDPR / PCI?"* — that's this skill.

---

## What it does

Once the Luciq SDK is initialized, `luciq-pii` reads the user's repo and the SDK config in it, classifies the masking posture by layer, compares it against the compliance framework the user names (or proposes one based on archetype), and walks the controls that need closing — one at a time, with the evidence cited.

The skill specifically:

- Reads `CLAUDE.md`, `AGENTS.md`, `README` for explicit privacy lines, framework mentions, and consent obligations.
- Re-enumerates sensitive views per-platform on every run — the audit is always driven by the current repo state, never a prior session's snapshot.
- Detects what's masked today across **three layers**:
  - **Layer 1 — Screen / view.** Auto-mask types at SDK init (`TEXT_INPUTS`, `LABELS`, `MEDIA`, `WEB_VIEWS`) + per-view markers on individual PII-bound views.
  - **Layer 2 — Network.** Auto-masking state (default-on from SDK 14.2.0), the default key list (`authorization`, `password`, `api_key`, `client_secret`, …), and any manual `obfuscateLog` / `omitLog` sites.
  - **Layer 3 — Defense in depth.** Consent gating on Session Replay, grayscale mode, Android `FLAG_SECURE` handling, `usersPageEnabled` posture, server-driven UI `isPrivate` flow.
- Loads a **compliance preset** when the user names a framework — HIPAA / GDPR / PCI-DSS / SOC2 / CCPA / FERPA. Each preset is starting guidance, not a rubber stamp; the skill states verbatim that compliance is broader than masking config.
- Walks each gap through **Ask → Apply → Summarize**, same micro-flow as `luciq-onboard`. Per-view markers use the same "first 3-5 individually, then batch-confirm" policy.
- Prepares **copy-pasteable support-ticket requests** for the server-side controls code can't touch — custom network mask keys, `usersPageEnabled` toggle.
- Ends with **one visual verification** — masked regions on the dashboard render as solid black rectangles on a screen you actually navigated to.
- Writes `LUCIQ_PII.md` with the posture snapshot, applied controls, deferred items with revisit conditions, server-side requests, and a pre-production privacy checklist. Appended to over time; never overwritten.

---

## When to use it

Trigger the skill with one of:

- `"audit my Luciq PII"` / `"check my masking"`
- `"prep Luciq for HIPAA"` (or GDPR / SOC2 / PCI)
- `"what's masked in Luciq right now?"`
- `"add masking to <screen>"`

Three speed modes are picked from the trigger phrasing:

| Mode | Trigger phrasing | Behavior |
|---|---|---|
| **GUIDED** *(default)* | "audit", "review my PII", "prep for HIPAA" | Full arc with per-control walk and visual verification. ~8 minutes. |
| **FAST** | "must-haves", "fast", "quick" | Apply the top 3 missing controls with one-line confirms. ~2 minutes. |
| **AUDIT** | "report", "just tell me what's missing" | Report-only. Posture scan + bucketed plan + handoff doc. Applies nothing without follow-up. |

---

## When NOT to use it

The skill bails and routes to a sibling skill for any of:

- **SDK isn't initialized yet** → `luciq-setup`.
- **You want the full product walk** (Bug Reporting, Replay, APM, Surveys, etc.) → `luciq-onboard`. Onboard configures per-view markers inline as part of the walk; that's enough for most teams pre-launch. Reach for `luciq-pii` when masking is the actual question.
- **SDK upgrade or Instabug → Luciq migration** → `luciq-migrate`.
- **A specific incident (crash, hang, regression, bug report)** → `luciq-debug`.

---

## Workflow

Six phases. The first one is silent, the rest are conversational.

```
PII Audit Progress:
  0. Detect mode (FAST / AUDIT / GUIDED) + compliance posture
  1. Posture scan (silent, parallel) — context docs, sensitive views,
     auto-mask config, network masking, defense-in-depth, MCP precedent
  2. Recap — what's masked today, capped at 6 cited lines
  3. Plan — three positive buckets (close now / optional / monitor)
  4. Per-control walk (Ask → Apply → Summarize)
  5. Visual verification — one masked screen on the dashboard
  6. Handoff — write LUCIQ_PII.md
```

In **AUDIT** mode, the skill stops after Phase 3 and writes the handoff doc — useful when you want the report without the apply.

---

## Compliance frameworks supported

| Framework | What the preset configures |
|---|---|
| **HIPAA** | Aggressive auto-mask (`TEXT_INPUTS + LABELS + MEDIA + WEB_VIEWS`), per-view markers on every PHI surface, network auto-mask on, consent gating before Session Replay, `usersPageEnabled` disabled. |
| **GDPR** | Consent gating before Session Replay (and possibly before SDK init for EU users), no PII in network logs, right-to-erasure documentable in the handoff. |
| **PCI-DSS** | Per-view markers on every cardholder-data view (PAN, CVV, expiration, name), network auto-mask on, manual omit on endpoints carrying raw PAN. States plainly that tokenization is the cleaner fix. |
| **SOC 2** | Auto-mask on as a baseline control, masking config under source control, audit-trail handoff doc. |
| **CCPA** | Consent gating + per-view markers on regulated data fields, mappability to Luciq records for right-to-delete. |
| **FERPA** | Aggressive auto-mask + per-view markers on student records, parental consent flow for under-13 users. |
| **No framework named** | Archetype defaults; offers the most-likely-applicable preset in Phase 3. |

> **Not legal advice.** The presets are guidance for masking config; compliance is a broader program. The handoff doc states this verbatim and points decisions back to legal / compliance.

---

## File map

```
plugins/luciq-skills/
└── skills/
    └── luciq-pii/
        ├── README.md            ← you are here
        ├── SKILL.md             ← LLM-facing workflow definition
        └── references/
            ├── auto-mask-types.md       ← Layer 1: per-platform auto-mask APIs, archetype pairings
            ├── network-masking.md       ← Layer 2: default key list, manual obfuscate/omit
            ├── defense-in-depth.md      ← Layer 3: consent, grayscale, FLAG_SECURE, usersPageEnabled
            ├── ssui-isprivate.md        ← Server-driven UI isPrivate flow
            ├── compliance-defaults.md   ← HIPAA / GDPR / PCI / SOC2 / CCPA / FERPA presets
            ├── preprod-checklist.md     ← Pre-production privacy checklist
            └── handoff-template.md      ← LUCIQ_PII.md template with a worked example
```

The references are loaded only when the corresponding phase needs them.

---

## Related skills

- **`luciq-setup`** — first-time SDK integration. Run this first.
- **`luciq-onboard`** — full product walk (Bug Reporting, Replay, APM, Surveys, etc.). Onboard configures per-view markers inline as part of the walk; `luciq-pii` covers the deeper masking layers and compliance presets.
- **`luciq-migrate`** — SDK upgrades / legacy Instabug rename.
- **`luciq-verify`** — verifies an SDK upgrade end-to-end before shipping. Use after `luciq-migrate` to confirm the new SDK version preserves your masking contracts.
- **`luciq-debug`** — production incident investigation.

---

## What the skill explicitly will not do

- **Claim the app is compliant.** The skill configures masking; compliance is a broader program (data residency, DPA, deletion workflows, audit trails, legal review). The handoff doc states this verbatim.
- **Use FUD.** No "you're exposed," no "you'll get fined." Gaps are stated with the consequence and the compliance fit; the user decides.
- **Bulk-apply per-view markers silently.** First 3-5 individually, then batch-confirm the rest. The user can inspect any row.
- **Claim verification succeeded without the user's eyes.** Phase 5 waits for explicit confirmation that masked regions render as solid black on the dashboard.
- **Disable controls already in place.** If something is masked today, the skill records it; it doesn't propose turning it off.
