# Post-onboarding capabilities

The skill onboards products the user can **apply in code, this session**. Several Luciq capabilities don't fit that bar — they auto-derive from products that *are* in the cards, live entirely on the dashboard, or need Luciq support / account-admin enablement before they work.

These belong in the handoff doc, **never in the three Phase-3 buckets**. The skill must not promise something it can't apply during the walk.

Each entry below has:

- **What it is** — one line.
- **Unlocks when** — the SDK-side or org-side prerequisite. If the prereq is satisfied this session, the capability is *now active* and goes in the handoff's "Now active" list. Otherwise it goes in "Unlocks later" with the condition stated verbatim.
- **Where it lives** — dashboard URL pattern or *"requires Luciq support."*
- **Handoff copy** — the exact line the skill writes into `LUCIQ_ONBOARDING.md`.

---

## Auto-derived (free with the cards they depend on)

### Frustration-Free Sessions (FFS)

- **What it is.** A 0–100% north-star KPI that bundles crashes, hangs, slow launches, network failures, and broken flows into a single score per session.
- **Unlocks when.** Crash Reporting + APM are both active.
- **Where it lives.** App Health Dashboard → Frustration-Free Sessions.
- **Handoff copy.** *"FFS is live now that Crash + APM are configured — open `<dashboard URL>` to see the score for your first build."*

### App Health Dashboard

- **What it is.** Single-screen overview of crash-free rate, OOM rate, app launch time, network perf, screen loading, UI hangs, and store ratings — color-coded.
- **Unlocks when.** Any active Luciq product starts emitting data.
- **Where it lives.** Dashboard home.
- **Handoff copy.** *"App Health overview is now your starting page — `<dashboard URL>`."*

### Issues List + Frustration Impact

- **What it is.** Unified list of crashes, hangs, force restarts, and perf issues, auto-ranked by their share of frustrating sessions.
- **Unlocks when.** Crash Reporting active. APM active sharpens the ranking.
- **Where it lives.** Dashboard → Issues.
- **Handoff copy.** *"Issues List ranks problems by how many user sessions they ruined — start triage here, not in raw crash counts."*

### Business Impact

- **What it is.** Correlates app quality with MAU retention; the only Luciq surface readable by a non-engineering exec.
- **Unlocks when.** All of: APM active, SDK ≥ v12.0.0, workspace MAU ≥ 10,000 (HyperLogLog-estimated). Currently beta — flag in handoff copy.
- **Where it lives.** Dashboard → Business Impact (beta).
- **Handoff copy (active).** *"Business Impact (beta) is now reporting — `<dashboard URL>`."*
- **Handoff copy (deferred).** *"Business Impact unlocks once MAU ≥ 10k and SDK ≥ v12. Revisit when you cross the threshold."*

---

## Dashboard-only (no SDK work, configured in Luciq UI)

### Alerts & Rules

- **What it is.** Per-product alert templates — crash-free rate drop, perf regression, bug spike, network failure pattern, accelerating-crash detection, rollout regression. Delivers to Slack, email, webhooks.
- **Unlocks when.** The originating product is active. Predefined alerts can be enabled with one click per product; triggered alerts need custom conditions.
- **Where it lives.** Dashboard → Settings → Alerts & Rules.
- **Handoff copy.** *"For each active product, predefined alert templates are one-click enable at `<dashboard URL>/settings/alerts`. The relevant templates for you: `<list per active product>`."*

### Rollout Management

- **What it is.** Monitor + pause / resume App Store phased rollouts when crash-free rate drops.
- **Unlocks when.** App Store Connect integration completed on the dashboard. Not SDK-driven.
- **Where it lives.** Dashboard → Releases.
- **Handoff copy (if store presence detected).** *"You ship to the App Store — connect App Store Connect at `<dashboard URL>/integrations` to enable rollout monitoring and pause-on-regression."*
- **Skip entirely** if no store presence (internal / enterprise distribution).

### Team Ownership + Team Dashboard

- **What it is.** Auto-route crashes / bugs / perf to teams by file path, package, screen name, URL, or category. Per-team performance dashboard.
- **Unlocks when.** Multi-team organization. Profile signal: multiple Xcode targets, multiple Gradle modules, or a `CODEOWNERS` file in the repo.
- **Where it lives.** Dashboard → Settings → Team Ownership.
- **Handoff copy (if multi-team signal).** *"This repo has `<N>` modules / a CODEOWNERS file — set up Team Ownership at `<dashboard URL>/settings/team-ownership` to auto-route issues."*
- **Skip entirely** if single-team / solo signal.

### One Code Apps

- **What it is.** Single Luciq app token spanning white-label / regional / brand variants of the same codebase, filtered by bundle ID.
- **Unlocks when.** Repo has multiple flavors / schemes / build variants of one app. Requires Luciq support activation.
- **Where it lives.** Requires support — contact via the dashboard help icon.
- **Handoff copy (if white-label signal).** *"This repo ships `<N>` variants of the same app — One Code Apps consolidates them under one Luciq token. Contact Luciq support to activate, then configure the App Variant API."*
- **Skip entirely** if single-variant.

---

## Support- / admin-gated (need a human at Luciq or admin role)

### Detect Agent (AI)

- **What it is.** AI flags visual regressions and broken-functionality issues from real user sessions.
- **Unlocks when.** Session Replay active (provides the input data). Account-level enablement.
- **Where it lives.** Dashboard → Issues → Detect Agent.
- **Handoff copy (if Replay active).** *"Detect Agent uses your replay data to flag visual / functionality regressions. Available once Luciq enables it on your account — request via `<dashboard URL>`."*

### Resolve Agent (AI)

- **What it is.** Reads a crash stack, cross-references your GitHub source code, generates a fix, opens a PR. Up to 5 iterations per crash.
- **Unlocks when.** All of: Crash Reporting active, GitHub-hosted source (not GitLab / Bitbucket / Azure DevOps — currently GitHub-only), platform in {iOS, Android, React Native}, account admin role, per-account enablement by Luciq.
- **Where it lives.** Crash details page → "Launch Resolve Agent."
- **Handoff copy (if all prereqs met).** *"Install the Luciq CodeLink GitHub App at `<install URL>`, then ask Luciq support to enable Resolve Agent on your account. Once on, every crash details page gets a 'Launch Resolve Agent' button."*
- **Handoff copy (if any prereq missing).** *"Resolve Agent unlocks when `<missing prereq stated verbatim>`. Revisit when that's true."*

### Release Agent / PR Review (AI)

- **What it is.** AI reviews PRs against patterns from your own dashboard's known issues.
- **Unlocks when.** Same GitHub + admin + enablement prereqs as Resolve Agent. Bonus signal: `.github/pull_request_template.md` exists (indicates active PR workflow).
- **Where it lives.** GitHub PR checks once webhooks are wired.
- **Handoff copy.** Same conditional pattern as Resolve Agent.

---

## How the skill uses this file

1. **During Phase 1 (Analyze)** — populate the profile with the prereq signals each capability above needs to check (store presence, multi-team, white-label, git host, admin role, MAU tier, SDK version).
2. **During Phase 6 (Handoff)** — for each capability above, check its "Unlocks when" against the profile + the products configured this session, then write the appropriate handoff copy. The handoff template has two slots for this: **"Dashboard capabilities now active"** and **"Capabilities that unlock later."**
3. **Never** introduce these capabilities in the Phase 3 buckets or the Phase 4 product walk. The Ask / Apply / Summarize loop only applies to things with an SDK-side diff to confirm.
