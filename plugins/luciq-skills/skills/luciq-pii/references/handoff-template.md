# LUCIQ_PII.md — handoff template

The skill writes this file at the repo root at the end of Phase 6. It's the durable artifact of the PII audit — re-readable next quarter, hand-off-able to legal / compliance, queryable by `luciq-debug` later.

**Rules.**

- If the file already exists, **append** a new dated session block — do not overwrite. The file accumulates the team's PII journey across multiple sessions and contributors.
- Cite every finding and every decision: `file:line`, CLAUDE.md line, framework requirement, precedent quote.
- State the framework named (or *not specified*). Never imply the audit produced compliance certification.
- Replace every `<placeholder>` below with real values. If a section has no entries, write *"None this session"* rather than deleting the heading — keeps the doc parseable.

---

## Template

```markdown
# Luciq PII Posture

This file records the PII / masking decisions made for this app, the
controls currently in place, and outstanding items. Appended to over
time; do not rewrite from scratch.

App: <repo / app name>
Platform: <iOS / Android / RN / Flutter / KMP>
Archetype: <e-commerce / fintech / healthcare / B2B / ...>
SDK version: <version from manifest>
Dashboard: <https://app.luciq.ai/apps/...>

---

## Session — <YYYY-MM-DD>

Mode: <FAST / AUDIT / GUIDED>
Compliance framework: <HIPAA / GDPR / PCI-DSS / SOC2 / CCPA / FERPA / not specified>
Operator: <user or agent name, if known>

> Guidance only — this document does not constitute compliance
> certification. Consult legal / compliance for the full obligation set
> under the named framework.

### Posture snapshot

By layer:

**Layer 1 — Screen / view masking**
- Auto-mask: `<types or "not configured (platform default: <default>")>` at `<file:line or n/a>`
- Per-view markers: `<count_marked> / <count_enumerated>` sensitive views marked
- Coarse screen-level fallback: `<list screens wrapped, or "none">`

**Layer 2 — Network**
- Auto-masking: `<on / off / default>` (SDK `<version>`)
- Manual obfuscate sites: `<list file:line, or "none">`
- Manual omit sites: `<list file:line, or "none">`
- Custom mask keys requested via support: `<list keys, or "none">`

**Layer 3 — Defense in depth**
- Consent gating: `<file:line, or "not gated">`
- Grayscale mode: `<on / off / n/a>`
- FLAG_SECURE (Android): `<respected (default) / overridden via ignoreFlagSecure(true) at file:line>`
- `usersPageEnabled`: `<enabled / disabled / default>`
- SSUI `isPrivate`: `<wired at <inflate sites> / no SSUI detected>`

### Controls applied this session

- ✅ **<Control>** — <one-line summary>
  - Edited: `<file>:<line>`
  - Citation: `<CLAUDE.md:X | framework preset | competitor parity | precedent quote>`

### Controls deferred this session

- **<Control>** — <one-line reason this is timed for later>
  - Revisit when: `<specific condition>`

### Server-side requests (out of code's reach)

Copy-paste these into a support ticket to Luciq:

> Email: support@luciq.ai
> Subject: PII masking config — app `<token>`
> Body:
> - Add the following keys to the automatic network mask list: `<keys>`.
> - Disable the users-page feature so only attribute keys (not values)
>   transmit. (If requested this session.)
> - <Any other server-side asks captured this session.>

If none, write: *None this session — all controls applied are code-side.*

### Pre-production privacy checklist

(Adapted from `references/preprod-checklist.md`. Mark current state per item.)

**Layer 1**
- [<state>] Auto-mask configured at SDK init.
- [<state>] All text input fields are automatically masked.
- [<state>] Login / authentication screens marked private.
- [<state>] Payment screens marked private.
- [<state>] Personal-information screens marked private.
- [<state>] All enumerated sensitive views individually marked.

**Layer 2**
- [<state>] Network auto-masking enabled (SDK ≥ 14.2.0).
- [<state>] Custom mask keys submitted to support.
- [<state>] Sensitive endpoints obfuscated or omitted.

**Layer 3**
- [<state>] User-consent flow implemented (where framework requires).
- [<state>] Session Replay gated on consent.
- [<state>] Grayscale mode set per posture.
- [<state>] FLAG_SECURE respected (Android).
- [<state>] `usersPageEnabled` set per posture.
- [<state>] SSUI `isPrivate` wired (if applicable).

**Process**
- [<state>] Privacy policy mentions session recording (if Replay is on).
- [<state>] QA has visually verified masking on the dashboard.
- [<state>] Legal / compliance approved the configured posture.
- [<state>] Masking config is in source control and reviewable.
- [<state>] Re-audit scheduled before next major release.

### Visual verification

- Verified screen: `<file path or screen name>`
- Verification timestamp: `<YYYY-MM-DD HH:MM UTC>` or *not verified this session*
- Dashboard URL: `<link>`

### Context the skill used

- CLAUDE.md: <line numbers cited during the session>
- Framework presets loaded: `<framework or "none">`
- Sensitive views source: `<LUCIQ_ONBOARDING.md from <date> | fresh enumeration>`
- Detected SDK style match: `<one-line summary, if applicable>`
- Workspace precedent: <one-line, or *MCP not authenticated*>

### Red flags surfaced (independent of Luciq)

- ⚠ **<Issue>** — <one-line explanation>
  Status this session: <addressed / not addressed>.

If none, write: *None detected.*

### When to reach for sibling skills

- Full product walk (Bug Reporting, Replay, APM, etc.) → `luciq-onboard`
- Upgrading the SDK between versions → `luciq-migrate`
- Verifying an SDK upgrade end-to-end → `luciq-verify`
- A user reports a crash, hang, or bug → `luciq-debug`

### Next audit

Recommend re-running `luciq-pii`:
- Before each major release.
- After any new sensitive screen ships.
- After any change to the SSUI schema (if applicable).
- After regulatory updates relevant to `<framework>`.
```

---

## Example — filled in

This is what a real session looks like after the skill writes it. Use as a sanity check on the format.

```markdown
# Luciq PII Posture

App: HealthApp
Platform: iOS (SwiftUI)
Archetype: healthcare
SDK version: 14.3.1
Dashboard: https://app.luciq.ai/apps/xyz789

---

## Session — 2026-06-15

Mode: GUIDED
Compliance framework: HIPAA (named by user at trigger)
Operator: Heba Mekawi

> Guidance only — this document does not constitute compliance
> certification. Consult legal / compliance for the full obligation set
> under HIPAA.

### Posture snapshot

**Layer 1 — Screen / view masking**
- Auto-mask: `[.textInputs, .labels, .media, .webViews]` at `LuciqInit.swift:24`
- Per-view markers: 11/11 sensitive views marked
- Coarse screen-level fallback: `PatientProfileView`, `BillingView`

**Layer 2 — Network**
- Auto-masking: default-on (SDK 14.3.1)
- Manual obfuscate sites: none
- Manual omit sites: `APIClient.swift:88` (`/patients/{mrn}/diagnosis` endpoint)
- Custom mask keys requested via support: `x-patient-id`, `x-mrn`

**Layer 3 — Defense in depth**
- Consent gating: `OnboardingFlow.swift:74`
- Grayscale mode: off (color-coded vitals are load-bearing)
- FLAG_SECURE: n/a (iOS app)
- `usersPageEnabled`: disabled (requested via support)
- SSUI `isPrivate`: no SSUI detected

### Controls applied this session

- ✅ **Per-view markers on PatientProfileView** — 4 Text views marked
  - Edited: `PatientProfileView.swift:31, 39, 47, 55`
  - Citation: HIPAA preset + CLAUDE.md:8 ("never log PHI")

- ✅ **Consent gating on Session Replay** — wrapped enable call
  - Edited: `OnboardingFlow.swift:74`
  - Citation: HIPAA preset; CLAUDE.md:8

- ✅ **Omit log on /patients/{mrn}/diagnosis** — added omitLog hook
  - Edited: `APIClient.swift:88`
  - Citation: HIPAA preset (URL contains MRN)

### Controls deferred this session

- **Grayscale screenshot mode** — color-coded vitals are UX-critical.
  - Revisit when: vitals coloring is decoupled from the underlying value.

### Server-side requests (out of code's reach)

> Email: support@luciq.ai
> Subject: PII masking config — app xyz789
> Body:
> - Add the following keys to the automatic network mask list:
>   `x-patient-id`, `x-mrn`.
> - Disable the users-page feature so only attribute keys (not values)
>   transmit.

### Visual verification

- Verified screen: `PatientProfileView`
- Verification timestamp: 2026-06-15 16:21 UTC
- Dashboard URL: https://app.luciq.ai/apps/xyz789/issues/abc

### Context the skill used

- CLAUDE.md: line 8 ("never log PHI")
- Framework presets loaded: HIPAA
- Sensitive views source: fresh enumeration (no recent LUCIQ_ONBOARDING.md)
- Detected SDK style match: n/a (no competitor observability SDK)
- Workspace precedent: MCP not authenticated

### Red flags surfaced (independent of Luciq)

- ⚠ Raw MRN in console log at `APIClient.swift:102` — outside Luciq's
  capture, but still on-device. Recommend the team strip the log.
  Status this session: not addressed (handed off to API team).

### When to reach for sibling skills

- Full product walk → `luciq-onboard`
- Upgrading the SDK → `luciq-migrate`
- A user reports a crash, hang, or bug → `luciq-debug`

### Next audit

Recommend re-running `luciq-pii`:
- Before the next App Store release.
- After any new PHI-rendering screen ships.
- After HIPAA Privacy Rule updates.
```
