# LUCIQ_ONBOARDING.md — handoff template

The skill writes this file at the repo root at the end of Phase 6. It's the durable artifact of the onboarding session — re-readable next week, hand-off-able to a teammate, queryable by sibling skills (`luciq-debug`, `luciq-migrate`).

**Rules.**

- If the file already exists, **append** a new dated session block — do not overwrite. The file accumulates the team's Luciq journey across multiple sessions and contributors.
- Cite every decision with a source: `CLAUDE.md:12`, `file.swift:42`, an inferred archetype rationale, or a precedent quote from MCP.
- Every "Can be added later" item must name a revisit condition — `when on App Store`, `after wiring identifyUser`, `when DAU > 1k`.
- For conflicts surfaced in Phase 2, list them even if the user did not address them this session — accountability survives.
- Replace every `<placeholder>` below with real values from the profile and the session. If a section has no entries, write *"None this session"* rather than deleting the heading — keeps the doc parseable.

---

## Template

```markdown
# Luciq Onboarding

This file records the Luciq products configured for this app, the decisions
made during onboarding sessions, and the conditions for revisiting deferred
items. Appended to over time; do not rewrite from scratch.

App: <repo / app name>
Platform: <iOS / Android / RN / Flutter / KMP>
Archetype: <e-commerce / fintech / social / media / B2B-tool / ...>
Dashboard: <https://app.luciq.ai/apps/...>

---

## Session — <YYYY-MM-DD>

Mode: <FAST / AUDIT / GUIDED>
Operator: <user or agent name, if known>

### Products active

- ✅ **<Product>** — <one-line summary of what was configured>
  - Edited: `<file>:<line>`
  - Decisions: <bullet of non-default choices + cited reasons>
  - First data verified: <timestamp or "not verified this session">

### Products you can add later

- **<Product>** — <one-line reason this is timed for later>
  - Revisit when: <specific condition — `app is on the App Store`,
    `identifyUser is wired in the auth flow`, `DAU > 1k`, etc.>

### Products you chose to stay on a competitor for (this session)

This section records products the customer *chose* not to adopt this
session because they prefer their existing competitor SDK. It reflects
the customer's choice, never a pre-judgment by the skill — every Luciq
product is recommended on its own merits regardless of competitor
presence.

- **<Product>** — customer chose to stay on `<SDK name>` at `<file>:<line>`.
  Reason given: <verbatim quote from the conversation, if any>.
  Re-evaluate whenever the customer is open to it — no auto-revisit.

### What's left for you (no code needed)

- <product>: <doc-pointer line — dashboard config, CI symbol upload,
  push token registration, etc.>
- ...

If nothing is left, write: *None — Luciq starts capturing on next launch.*

### Dashboard capabilities now active

Capabilities whose prereqs the products configured above just satisfied.
These are auto-derived or dashboard-only — no SDK work was needed.
Sourced from `references/post-onboarding-capabilities.md`.

- 📊 **<Capability>** — <one-line what it shows> — `<dashboard URL>`

If none unlock this session, write: *None this session.*

### Capabilities that unlock later

Capabilities whose prereqs aren't met yet. Each names a verbatim
revisit condition from the post-onboarding capabilities reference.

- **<Capability>** — unlocks when `<condition stated verbatim>`.

If none apply, write: *None this session.*

### Conflicts detected (independent of Luciq)

- ⚠ **<Conflict kind>** — <SDKs involved, file:line for each>.
  <One-line explanation of the impact today.>
  Status this session: <addressed / not addressed>.

If none, write: *None detected.*

### Context the skill used

- CLAUDE.md: <line numbers cited during the session>
- Money path: `<file>:<line>` (or *not identified*)
- Auth flow: login `<file>:<line>`, logout `<file>:<line>` (or *no auth*)
- Detected SDK style: <one-line summary, e.g.,
  "Sentry — privacy-conservative, low sample, strict env gating">
- Workspace precedent: <one-line, or *MCP not authenticated*>

### When to reach for sibling skills

- A user reports a crash, hang, or bug → `luciq-debug`
- Upgrading the SDK between versions → `luciq-migrate`
- Verifying an SDK upgrade end-to-end → `luciq-verify`
- Deep PII / masking audit or compliance-framework prep → `luciq-pii`
```

---

## Example — filled in

This is what a real session looks like after the skill writes it. Use as a sanity check on the format.

```markdown
# Luciq Onboarding

This file records the Luciq products configured for this app, the decisions
made during onboarding sessions, and the conditions for revisiting deferred
items. Appended to over time; do not rewrite from scratch.

App: NotDemoApp
Platform: iOS (SwiftUI)
Archetype: e-commerce
Dashboard: https://app.luciq.ai/apps/abc123

---

## Session — 2026-06-08

Mode: GUIDED
Operator: Heba Mekawi

### Products active

- ✅ **Bug Reporting** — shake invocation, masking on checkout
  - Edited: `NotDemoAppApp.swift:14`
  - Decisions:
    - Invocation: shake (matched Sentry's conservative posture; avoided
      screenshot mode because CheckoutView is the money path)
    - Masking: text inputs on `CheckoutView.swift:42` per CLAUDE.md:12
      ("never log financial data")
  - First data verified: 2026-06-08 14:32 UTC

- ✅ **Session Replay** — 5% sample, money-path masked
  - Edited: `NotDemoAppApp.swift:18`
  - Decisions:
    - Sample rate 5% (matched Sentry replaysSessionSampleRate: 0.05)
    - Masking inherited from Bug Reporting's checkout masking
  - First data verified: 2026-06-08 14:33 UTC

### Products you can add later

- **App Ratings** — better added once you launch on the App Store.
  - Revisit when: app is live on the App Store with consumer users.

- **In-App Replies** — depends on identifyUser being wired.
  - Revisit when: you wire identifyUser into your auth flow
    (auth flow is at SettingsView.swift but no login flow yet).

### Products you chose to stay on a competitor for (this session)

- **Crash Reporting** — recommended on its own merits this session.
  Customer chose to stay on Sentry at `AppDelegate.swift:23` for now.
  Reason given: *"We're mid-quarter and don't want a crash-reporting swap
  before the Q3 release cuts. Revisit Q4."*
  Re-evaluate when the customer raises it.

- **APM** — recommended on its own merits this session. Customer chose
  to stay on Sentry perf alongside, did not adopt Luciq APM this session.
  Reason given: *"Want to see Bug Reporting + Replay land first before
  evaluating another perf vendor."*
  Re-evaluate when the customer raises it.

### What's left for you (no code needed)

- Bug Reporting: nothing required.
- Session Replay: review masking when you add new screens with sensitive UI.

### Dashboard capabilities now active

- 📊 **App Health Dashboard** — color-coded overview of crash-free rate,
  OOM, app launch, network, screen loading, UI hangs, ratings —
  `https://app.luciq.ai/apps/abc123/health`
- 📊 **Issues List + Frustration Impact** — unified crashes / hangs / perf
  list ranked by share of frustrating sessions —
  `https://app.luciq.ai/apps/abc123/issues`

### Capabilities that unlock later

- **Frustration-Free Sessions (FFS)** — unlocks when APM is also configured
  (Bug Reporting + Replay alone don't feed FFS; needs Crash + APM).
- **Business Impact (beta)** — unlocks when APM is configured *and*
  workspace MAU ≥ 10,000.
- **Resolve Agent (AI)** — unlocks when Crash Reporting is configured, the
  repo is GitHub-hosted, and account admin requests enablement.

### Conflicts detected (independent of Luciq)

- ⚠ **Dual crash handler** — Sentry at `AppDelegate.swift:23` and Firebase
  Crashlytics at `AppDelegate.swift:18` both install crash signal handlers.
  Today's crash capture is non-deterministic.
  Status this session: not addressed (user noted to handle separately).

### Context the skill used

- CLAUDE.md: line 12 ("never log financial data")
- Money path: `CheckoutView.swift:42`
- Auth flow: no login flow detected
- Detected SDK style: Sentry — privacy-conservative, low sample, strict env
  gating (replaysSessionSampleRate: 0.05, attachScreenshot: false,
  sendDefaultPii: false, enabledReleaseStages excludes debug)
- Workspace precedent: 2 other apps in workspace use Bug Reporting + Replay
  with shake invocation

### When to reach for sibling skills

- A user reports a crash, hang, or bug → `luciq-debug`
- Upgrading the SDK between versions → `luciq-migrate`
- Verifying an SDK upgrade end-to-end → `luciq-verify`
- Deep PII / masking audit or compliance-framework prep → `luciq-pii`
```
