# LUCIQ_ONBOARDING.md — handoff template

The skill writes this file at the repo root at the end of Phase 6. It's
the durable artifact of the onboarding session — re-readable next week,
hand-off-able to a teammate, queryable by sibling skills (`luciq-debug`,
`luciq-migrate`).

**Rules.**

- If the file already exists, **append** a new dated session block — do
  not overwrite. The file accumulates the team's Luciq journey across
  multiple sessions and contributors.
- The doc has **two halves separated by a hard `---` divider**: a
  celebratory top half (plain English, no API names, anyone can read it
  in under a minute) and a technical bottom half (cite-heavy, complete,
  for the engineer who comes back later).
- Cite every technical-half decision with a source: `CLAUDE.md:12`,
  `file.swift:42`, an inferred archetype rationale, or a precedent quote
  from MCP. The top half stays citation-free — it's the celebration, not
  the audit.
- Every "Ready when you are" item must name a revisit trigger in plain
  English — *when on App Store*, *after wiring identifyUser*, *when DAU > 1k*.
- For conflicts surfaced in Phase 2, list them even if the user did not
  address them this session — accountability survives.
- **Dashboard URL sourcing.** Derive URLs from MCP `list_applications` or
  the live Luciq dashboard. Never construct paths by stitching slug +
  capability name — surface shapes change between versions and
  constructed URLs become broken links.
- Replace every `<placeholder>` below with real values from the profile
  and the session. If a section has no entries, write *"None this session"*
  rather than deleting the heading — keeps the doc parseable.

---

## Template

```markdown
# Luciq Onboarding

This file records the Luciq products configured for this app, the
decisions made during onboarding sessions, and the conditions for
revisiting deferred items. Appended to over time; do not rewrite from
scratch.

App: **<repo / app name>** (<workspace / token reference if known>)
Platform: <iOS / Android / RN / Flutter / KMP>
Archetype: <e-commerce / fintech / social / media / B2B-tool / ...>
Dashboard: <https://app.luciq.ai/apps/...>

---

## Session — <YYYY-MM-DD>

# 🎉 You're set up.

> **<N> conflicts** · **All PII masked** [· <other earned wins>]

<One short paragraph (2–3 sentences) in plain English of what the app
can do now that it couldn't yesterday. No API names. Lead with the
team's benefit, not the SDK's capability.>

## ✅ Enabled now — <N> products

| | Product | What it does for you |
|---|---|---|
| 🐛 | **<Product>** | <plain-English 1-sentence user-facing value — what the team/user gets, never what the API does> |
| ... | | |

## 🔜 Ready when you are — <N> more

Not on yet because each one needs something to happen first. Each has a
crystal-clear trigger:

| | Product | Turn on when… |
|---|---|---|
| 📊 | **<Product>** | …<specific trigger condition in plain English>. |
| ... | | |

If nothing was deferred, write:
*Nothing held back this session — everything that fits the app is enabled.*

## 👉 Do this next — 30 seconds to see it working

1. <First concrete step, e.g., Build and run the app.>
2. <Trigger the primary product, e.g., Shake the simulator (`Ctrl+Cmd+Z`).>
3. <Submit / capture / verify, e.g., Send a report titled *"test from onboarding"*.>

Open the **<primary dashboard name>** below. Your <report/crash/event>
appears in a couple of minutes. That's the moment everything goes from
*set up* to *actually working*.

**Your three dashboards:**
- 📊 <Capability> → <dashboard URL>
- 📊 <Capability> → <dashboard URL>
- 📊 <Capability> → <dashboard URL>

---

# 🔧 The technical details

*Everything below is the audit trail — what was edited, what was decided,
and how the agent figured things out. Useful for the next engineer who
opens this file, or for the agent in a future session. Skip if you just
wanted the wins above.*

## What was wired (and where)

All <N> products live in **`<file path>`** (or list per-product if
scattered across multiple files):

| Product | Code change | Key decision |
|---|---|---|
| <Product> | <one-line code change with file:line> | <one-line cited decision — what masking, what posture matched, what was deliberately not customized> |
| ... | | |

⚠️ **Not verified yet** — none of the <N> have produced first data on
the dashboard. The *Do this next* step at the top closes that loop.

(If verification *was* completed this session, replace the warning with:
✅ **Verified <YYYY-MM-DD HH:MM UTC>** — first <report/crash/event>
visible on the dashboard.)

## What's left for you (no code needed)

- **<Product>** — <doc-pointer line: dashboard config, CI symbol upload,
  push token registration, etc.>
- ...

If nothing is left, write:
*None — Luciq starts capturing on next launch.*

## "Ready when you are" — implementation notes

- **<Product>** — <one-line implementation pointer for when the trigger fires>.
- ...

## Dashboard capabilities

Sourced from `references/post-onboarding-capabilities.md`.

**Live now** (auto-derived from the products above — no SDK work needed):
- 📊 **<Capability>** — <one-line what it shows>.
- ...

**Unlock later** (each names a verbatim revisit condition from the
post-onboarding capabilities reference):
- **<Capability>** — needs <condition stated verbatim>.
- ...

If neither bucket has entries, write: *None this session.*

## Conflicts detected (independent of Luciq)

- ⚠ **<Conflict kind>** — <SDKs involved, file:line for each>.
  <One-line impact today.> Status this session: <addressed / not addressed>.

If none, write:
*None — Luciq is the only mobile observability SDK on the project.*

## Competitor coverage

Products the customer *chose* not to adopt this session because they
prefer their existing competitor SDK. Reflects the customer's choice,
never a pre-judgment by the skill — every Luciq product is recommended
on its own merits regardless of competitor presence.

- **<Product>** — customer chose to stay on `<SDK name>` at `<file>:<line>`.
  Reason: <verbatim quote from the conversation, if any>.
  Re-evaluate when the customer raises it — no auto-revisit.

If none, write:
*None this session — no competing observability SDKs are installed.*

## How the agent figured this out

- **Context docs** — <CLAUDE.md/AGENTS.md/README quotes with line
  numbers, or *none — defaulted to archetype heuristics*>.
- **Money path** — `<file>:<line>` (or *not identified*).
- **Auth flow** — login `<file>:<line>`, logout `<file>:<line>` (or
  *no auth flow detected*).
- **Sensitive views covered by the masking rule** — <list with
  file:line and bound property>.
- **Accessibility posture** — <strong/partial/absent + cited example
  file:line if any>.
- **Detected SDK style** — <one-line summary, e.g.,
  "Sentry — privacy-conservative, low sample, strict env gating", or
  *"none — greenfield observability"*>.
- **Workspace precedent** — <one-line, or *MCP not authenticated*>.

## When to reach for sibling skills

- A user reports a crash, hang, or bug → `luciq-debug`
- Upgrading the SDK between versions → `luciq-migrate`
- Verifying an SDK upgrade end-to-end → `luciq-verify`
- Deep PII / masking audit or compliance prep → `luciq-pii`

Always include `luciq-pii` in this list when Bug Reporting, Session
Replay, or APM were configured — the per-view markers applied this
session are layer 1 of 3, and the user should know how to revisit the
full posture later.

---

*Session metadata: <FAST / AUDIT / GUIDED> mode · <operator name> ·
SDK `<sdk name and version>` · <package manager> · product `<product name>` ·
import `<import>`.*
```

---

## Example — filled in

This is what a real session looks like after the skill writes it. Use as
a sanity check on the format. (Based on the eCommerce iOS sample app.)

```markdown
# Luciq Onboarding

This file records the Luciq products configured for this app, the
decisions made during onboarding sessions, and the conditions for
revisiting deferred items. Appended to over time; do not rewrite from
scratch.

App: **eCommerce** (iOS1-iOS, production token)
Platform: iOS (SwiftUI)
Archetype: e-commerce (fashion retail)
Dashboard: https://app.luciq.ai/apps/ios1

---

## Session — 2026-06-14

# 🎉 You're set up.

> **0 conflicts** · **All PII masked**

Four products are now watching your app so you don't have to. Together
they cover the full picture — *what* broke, *why* it broke, and *what
the user was doing* when it broke.

## ✅ Enabled now — 4 products

| | Product | What it does for you |
|---|---|---|
| 🐛 | **Bug Reports** | Users shake the phone to send a report — screen, logs, network, repro steps included. No more *"it doesn't work"* emails with zero context. |
| 💥 | **Crash Reporting** | Every crash gives you the full stack trace, device state, and the screen the user was on. Clean signal — nothing else was competing for it. |
| ⚡ | **Performance (APM)** | Measures how fast every screen loads and every network call. Wired carefully on your Stripe checkout, where *slow = lost revenue*. |
| 🎬 | **Session Replay** | Watch a short replay of what the user actually did. Passwords, emails, addresses, and card fields are blurred — you see the journey without the secrets. |

## 🔜 Ready when you are — 5 more

Not on yet because each one needs something to happen first. Each has a
crystal-clear trigger:

| | Product | Turn on when… |
|---|---|---|
| 📊 | **APM Flows** | …you want to know *where* people drop off in checkout. |
| 💬 | **In-App Surveys** | …you have real daily users to ask. |
| ⭐ | **App Ratings** | …you launch on the App Store. |
| ↩️ | **In-App Replies** | …you add push notifications (`identifyUser` is already wired). |
| 🚩 | **Feature Flags** | …you start running A/B experiments. |

## 👉 Do this next — 30 seconds to see it working

1. Build and run the app.
2. Shake the simulator (`Ctrl+Cmd+Z`).
3. Send a report titled *"test from onboarding"*.

Open the **Issues** dashboard below. Your report appears in a couple of
minutes. That's the moment everything goes from *set up* to *actually
working*.

**Your three dashboards:**
- 📊 App Health → https://app.luciq.ai/apps/ios1/health
- 📊 Issues (ranked by impact) → https://app.luciq.ai/apps/ios1/issues
- 📊 Frustration-Free Sessions → https://app.luciq.ai/apps/ios1/ffs

---

# 🔧 The technical details

*Everything below is the audit trail — what was edited, what was decided,
and how the agent figured things out. Useful for the next engineer who
opens this file, or for the agent in a future session. Skip if you just
wanted the wins above.*

## What was wired (and where)

All four products live in **`eCommerce/eCommerceApp.swift`** (one file,
one init block):

| Product | Code change | Key decision |
|---|---|---|
| Bug Reporting | Invocation set up (line 34) | Shake + screenshot — default for the platform; no competitor posture to match. Global `Luciq.setAutoMaskScreenshots(.textInputs)` covers every PII field below. |
| Crash Reporting | `CrashReporting.enabled = true` | Set explicitly for clarity. No competing crash reporter on the project (Firebase here is Analytics/Auth/Firestore — not Crashlytics). |
| APM | `APM.enabled = true` | UI traces + screen loading on (defaults). Network timing flows through existing `NetworkLogger.setRequestObfuscationHandler` — Authorization/Cookie headers + password/token/card body fields stay redacted. |
| Session Replay | `SessionReplay.enabled = true` | User steps + network captured. Masking inherits the global `.textInputs` rule. Default sample rate (no competitor replay to match). |

⚠️ **Not verified yet** — none of the four have produced first data on
the dashboard. The *Do this next* step at the top closes that loop.

## What's left for you (no code needed)

- **Crash Reporting** — upload dSYMs for symbolicated stack traces.
  Release config already emits `dwarf-with-dsym`. No CI detected, so
  this is a manual or Luciq-CLI step.
- **Session Replay** — re-check masking when you add new screens with
  sensitive UI.
- **All products** — optional custom attributes (app version, user tier,
  env) on the dashboard.

## "Ready when you are" — implementation notes

- **APM Flows** — instrument `APM.startFlow` / `endFlow` at the
  `Cart → Checkout → OrderConfirmation` lifecycle sites.
- **In-App Surveys** — no store / CI / distribution config detected —
  reads as a portfolio build. Turn on once DAU is real.
- **App Ratings & Reviews** — publish on the App Store first.
- **In-App Replies** — `identifyUser` already wired at
  `AuthenticationManager.swift:24`. Add push-token registration to
  enable notification delivery; works in-app without push meanwhile.
- **Feature Flags** — turn on when you run real A/B experiments.
  Firebase Remote Config is present (`RCValues.swift`) but only used for
  app colors (README.md:38), not experiments.

## Dashboard capabilities

**Live now** (auto-derived from the four products above):
- 📊 **App Health** — crash-free rate, app launch, network, screen
  loading, UI hangs at a glance.
- 📊 **Frustration-Free Sessions (FFS)** — 0–100% session-quality KPI,
  live now that Crash + APM are both configured.
- 📊 **Issues List + Frustration Impact** — crashes / hangs / perf
  ranked by share of frustrating sessions.

**Unlock later:**
- **Business Impact (beta)** — needs APM + workspace MAU ≥ 10,000 + SDK ≥ v12.
- **Detect Agent (AI)** — uses Session Replay data to flag visual
  regressions. Request enablement via the dashboard.
- **Resolve Agent (AI)** — needs GitHub-hosted source + admin role +
  per-account enablement.

## Conflicts detected (independent of Luciq)

None — Luciq is the only mobile observability SDK on the project.

## Competitor coverage

None this session — no competing observability SDKs are installed.

## How the agent figured this out

- **Context docs** — no CLAUDE.md / AGENTS.md; README.md is rich
  (app purpose `README.md:5-11`, money path `README.md:44`, test card
  numbers noted `README.md:52`, Remote Config used for colors `README.md:38`).
- **Money path** — Stripe checkout at
  `eCommerce/Views/Checkout/CheckoutView.swift`,
  `eCommerce/Services/PaymentManager.swift`.
- **Auth flow** — Firebase email/password; `identifyUser` / `logOut`
  wired into the auth-state listener at `AuthenticationManager.swift:24`.
- **Sensitive views covered by the global `.textInputs` mask** —
  `SignInView.swift:43-44` (email, password),
  `SignUpView.swift:44-47` (name, email, password),
  `ResetPasswordView.swift:37` (email),
  `EditEmailView.swift:46,56` (new email, current password),
  `EditPasswordView.swift:44` (new password),
  `AddOrEditShippingAddressView.swift:28` (shipping address),
  plus card data inside the Stripe PaymentSheet.
- **Accessibility posture** — absent (0 accessibility identifiers) —
  default invocation kept.
- **Detected SDK style** — none; greenfield observability, Luciq defaults
  used.
- **Workspace precedent** — Luciq MCP authenticated; multiple iOS apps
  in the account (TestQC, iOS1-iOS, Test-iOS). iOS1-iOS production token
  in use.

## When to reach for sibling skills

- A user reports a crash, hang, or bug → `luciq-debug`
- Upgrading the SDK between versions → `luciq-migrate`
- Verifying an SDK upgrade end-to-end → `luciq-verify`
- Deep PII / masking audit or compliance prep → `luciq-pii`

---

*Session metadata: GUIDED mode · Claude Code agent · SDK
`luciq-ios-sdk 19.8.1` (SPM) · product `Luciq` · import `LuciqSDK`.*
```
