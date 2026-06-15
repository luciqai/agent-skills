# Pre-Production Privacy Checklist

Adapted from the reference document's §7.4. The audit lands this in `LUCIQ_PII.md` with the current state per item — `done` / `pending` / `n/a` — so the team can resolve outstanding items before a launch or compliance review.

The checklist is descriptive (what to verify), not prescriptive (one-size policy). State the current state for each item; don't omit items the team chose to skip.

## Layer 1 — On-device masking

- [ ] **Auto-mask configured** at SDK init — `<file:line>` or *not configured (platform default applies: `<default>`)*.
- [ ] **All text input fields are automatically masked** — verified via `TEXT_INPUTS` in the configured set, or per-view markers cover the gaps.
- [ ] **Login / authentication screens are marked private** — `<file:line>` of each.
- [ ] **Payment screens are marked private** — `<file:line>` of each.
- [ ] **Personal-information screens are marked private** — `<file:line>` of each.
- [ ] **Sensitive views on each screen individually marked** — count or list, e.g., `4/4 views on PatientProfileView`.
- [ ] **Manual per-view review completed** for screens that grew sensitive views since the last audit.

## Layer 2 — Network

- [ ] **Network auto-masking enabled** — default-on for SDK ≥ 14.2.0. Current SDK: `<version>`. State: `<on / off / default>`.
- [ ] **Custom mask keys requested** — list of keys submitted to Luciq support, with ticket reference if available.
- [ ] **Sensitive endpoints obfuscated or omitted** — list of endpoints + obfuscate/omit decision.
- [ ] **No raw PAN / CVV / SSN observed in network logs** during dev-build inspection.

## Layer 3 — Defense in depth

- [ ] **User-consent flow implemented** where required by framework — `<file:line>` of the gate, or *N/A — no framework requires it*.
- [ ] **Session Replay gated on consent** — `<file:line>`, or *not gated*.
- [ ] **Grayscale screenshot mode** — *on / off / not applicable*.
- [ ] **FLAG_SECURE respected (Android)** — `ignoreFlagSecure` is `false` or unset.
- [ ] **`usersPageEnabled` set per posture** — *enabled / disabled / default*.
- [ ] **SSUI `isPrivate` flow in place** if applicable — list of inflate sites with the marker call, or *N/A — no SSUI detected*.

## Process

- [ ] **Privacy policy mentions session recording** if Session Replay is on.
- [ ] **QA has verified masking visually** on the dashboard for at least one sensitive screen.
- [ ] **Legal / compliance has approved** the configured posture for the named framework, if one was named.
- [ ] **Masking config is in source control** and reviewable (file is not gitignored, no secrets inline).
- [ ] **Re-audit scheduled** before each major release or new sensitive-screen ship.

## What this checklist is not

- **Not a legal document.** Resolving every item does not constitute compliance certification. State this verbatim in the handoff.
- **Not a one-time exercise.** Add a Phase 6 handoff line recommending re-runs of `luciq-pii` before launches and after new sensitive screens land.
- **Not a substitute for masking the underlying data.** A checked "auto-mask configured" item only covers types the developer chose; per-view markers cover the gaps, and neither covers raw values stored in app memory or backend databases outside Luciq's surface.
