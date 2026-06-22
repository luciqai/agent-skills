# Compliance-Framework Defaults

Per-framework preset that the audit applies when the user names the framework at trigger or in Track A. Presets are starting points — the audit still cites every individual decision; the framework is a recommendation source, not a rubber stamp.

**These presets are guidance for masking config only.** They don't constitute legal advice. Refer the user to their legal / compliance team for the full obligation set under each framework. State this in the handoff when a preset was applied.

Verify each preset against the live docs and the current statute text before applying — regulations evolve faster than this file.

## HIPAA (US healthcare)

PHI must not appear in screenshots, replay, network logs, or backend storage. Layered defense is non-negotiable.

| Control | Preset |
|---|---|
| Auto-mask types | `TEXT_INPUTS + LABELS + MEDIA + WEB_VIEWS` (all four) |
| Per-view markers | Every view binding to PHI fields (name, DOB, MRN, diagnosis, provider, claim) |
| Network auto-masking | On (require SDK ≥ 14.2.0; upgrade if older) |
| Custom network mask keys | Propose adding PHI-shaped headers (`x-patient-id`, `x-mrn`, etc.) via support ticket |
| Manual omit | Endpoints with PHI in the URL path (`/patients/{mrn}/...`) — propose `omitLog` |
| Consent gating | Required before Session Replay. Surface as "Close now" if missing. |
| Grayscale | Optional defense-in-depth; not required. Offer, don't force. |
| `usersPageEnabled` | Recommend disabling — patient identifiers as attribute values are PHI. |
| `ignoreFlagSecure` (Android) | Must be default (`false`). Override is a red flag. |
| SSUI `isPrivate` | Required on any node rendering PHI. |

## GDPR (EU users)

User-controlled consent is the primary obligation; right-to-erasure must be exercisable.

| Control | Preset |
|---|---|
| Auto-mask types | `TEXT_INPUTS + LABELS` minimum (archetype-dependent above) |
| Per-view markers | Every PII-bound view (name, email, address, location, identifier) |
| Network auto-masking | On |
| Consent gating | **Required** before Session Replay (and per the user's lawful-basis analysis, possibly before SDK init for EU users). Surface as "Close now" if missing. |
| Right-to-erasure | Verify the team can map a user to Luciq records and request deletion. Surface as handoff item, not code-applyable. |
| `usersPageEnabled` | Recommend disabling if user attribute values are PII. |
| Data residency | Verify Luciq region matches EU obligations. Surface as handoff item. |

## PCI-DSS (cardholder data)

Cardholder data (PAN, CVV, expiration, magnetic stripe, PIN) must never be stored unmasked, anywhere — including dev/staging.

| Control | Preset |
|---|---|
| Auto-mask types | `TEXT_INPUTS + LABELS + MEDIA + WEB_VIEWS` |
| Per-view markers | Every view rendering or capturing PAN, CVV, expiration, cardholder name, billing address |
| Network auto-masking | On |
| Custom network mask keys | Propose any payment-flow headers (`x-stripe-customer`, `x-card-token`) via support ticket |
| Manual omit | Endpoints carrying raw card data — recommend the team tokenize before Luciq sees the request; if unavoidable, `omitLog` |
| Tokenization preference | State plainly: raw PAN should never reach client logs. If the team's network layer carries raw PAN, the fix is tokenization (Stripe Elements, network tokenization), not masking. |
| Grayscale | Optional. |
| Consent gating | Not strictly required by PCI; recommend per app's other obligations. |

## SOC 2

Process and audit-trail focused. Masking is one of the documented controls.

| Control | Preset |
|---|---|
| Auto-mask types | `TEXT_INPUTS` baseline (archetype-dependent above) |
| Per-view markers | Every PII-bound view, per data classification |
| Network auto-masking | On |
| Version control | Masking config must be in source control with reviewable history. Verify the SDK init file is committed (not in `.gitignore`); flag if it is. |
| Audit trail | Surface the handoff doc itself as the audit artifact — log every session block with date, operator, decisions. |
| Change review | Recommend that masking config changes require code review (CODEOWNERS on the init file). Verify in passing. |

## CCPA (California consumers)

Right-to-know, right-to-delete, opt-out of sale. Masking config is supporting evidence.

| Control | Preset |
|---|---|
| Auto-mask types | `TEXT_INPUTS + LABELS` minimum |
| Per-view markers | Every PII-bound view |
| Network auto-masking | On |
| Consent gating | Recommended before Session Replay for CA users; verify the lawful basis with the team. |
| Right-to-delete | Same as GDPR — verify mappability to Luciq records. |

## FERPA (US education)

Student education records, when the app serves K–12 or higher ed.

| Control | Preset |
|---|---|
| Auto-mask types | `TEXT_INPUTS + LABELS + MEDIA` |
| Per-view markers | Every view rendering student records (name, ID, grades, attendance, disciplinary) |
| Network auto-masking | On |
| Consent gating | Required for under-13 users (parental consent); verify the team's flow. |
| `usersPageEnabled` | Recommend disabling — student IDs are protected. |

## No framework named

When the user names no framework, the audit proceeds with archetype defaults (see `auto-mask-types.md` recommended pairings) and offers the most-likely-applicable preset in Phase 3:

- Healthcare archetype → offer HIPAA preset.
- Fintech / e-commerce → offer PCI-DSS preset.
- B2B with EU users in CLAUDE.md / README → offer GDPR preset.
- Education → offer FERPA preset.
- Otherwise → proceed with archetype defaults; state in the handoff that no framework was named.

Offering a preset is not the same as applying one. The user must confirm before any preset-driven change lands.

## Always state in the handoff

Whichever preset (or no preset) was used, the handoff doc states it verbatim:

> *Framework: HIPAA (named by user at trigger). Preset applied: aggressive masking, consent gating, no `usersPageEnabled`. Audit guidance only; consult your legal/compliance team for the full obligation set.*

Never imply the audit "made the app compliant" — the audit configures masking; compliance is a broader program.
