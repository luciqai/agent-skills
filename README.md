# Luciq Agent Skills

Claude Code skills for the Luciq mobile observability SDK. Real edits, MCP queries, and CLI runs, directly inside your IDE.

**Platforms:** `iOS` · `Android` · `Flutter` · `React Native` · `KMP`. Auto-detected per invocation.

---

## Install

### Claude Code

Add the Luciq marketplace and install the plugin in one step:

```
/plugin marketplace add luciqai/agent-skills
/plugin install luciq-skills@luciq.ai
```

The plugin install also wires up the Luciq MCP server, so the skills get production data right away.

Skills available after install:
- `/luciq-skills:luciq-setup`. SDK install and configuration.
- `/luciq-skills:luciq-onboard`. Personalized product walkthrough after the SDK is installed.
- `/luciq-skills:luciq-masking-rules`. PII / masking audit and compliance-framework prep (HIPAA / GDPR / PCI / SOC2).
- `/luciq-skills:luciq-debug`. Production signal investigation.
- `/luciq-skills:luciq-migrate`. Instabug to Luciq migration and SDK upgrades.
- `/luciq-skills:luciq-verify`. End-to-end SDK upgrade verification.
- `/luciq-skills:luciq-alert-config`. Create, change, or inspect a specific alert.
- `/luciq-skills:luciq-alert-gaps`. Find unmonitored metrics and add the missing alerts.
- `/luciq-skills:luciq-alert-noise`. Reduce noisy alerts and cut alert fatigue.

### Cursor

```
/plugin marketplace add luciqai/agent-skills
/plugin install luciq-skills@luciq.ai
```

### npx

```bash
npx luciq-skills install            # project-local
npx luciq-skills install --global   # all projects
```

### Manual install (fallback)

**User-global** (works in every project)
```bash
mkdir -p ~/.claude/skills
cp -r agent-skills/plugins/luciq-skills/skills/luciq-* ~/.claude/skills/
```

**Project-local** (only this repo)
```bash
mkdir -p .claude/skills
cp -r agent-skills/plugins/luciq-skills/skills/luciq-* .claude/skills/
```

---

## Skills

### `luciq-setup` ([docs](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/agent-skills/luciq-setup))

Install and configure the Luciq SDK end-to-end. Edits your build files, inserts the init call at the right entry point, configures invocation and auto-masking, and wires up the Luciq MCP server.

**Try saying:**
- `"Add Luciq to this Flutter project"`
- `"Set up Luciq for Android, use a floating button invocation"`
- `"Initialize Luciq and mask the payment fields"`

---

### `luciq-onboard`

Personalized walkthrough of the Luciq product suite for an app that already has the SDK installed. Reads your repo (code, `CLAUDE.md`, `README`, `AGENTS.md`), detects any existing mobile observability SDKs and their config posture (Sentry, Crashlytics, Bugsnag, Datadog, Embrace, New Relic, App Center, UXCam, Smartlook, MetricKit), then recommends the Luciq products that actually fit — in three positively-framed buckets (*Recommended now* / *Optional* / *Can be added later*), with cited rationale at every step. Auto-enumerates individual PII-bound views per sensitive screen and proposes per-view privacy markers (`.luciq_privateView()` / `Modifier.luciqPrivate()` / `LuciqPrivateView`) with per-match confirmation. Ends with one consolidated activation moment that proves Luciq is working end-to-end, and writes `LUCIQ_ONBOARDING.md` so the next session picks up exactly where this one left off.

**Try saying:**
- `"Onboard me to Luciq"`
- `"What Luciq products should I set up?"`
- `"Walk me through Luciq"`
- `"What am I missing in my Luciq setup?"`

> **Pairs with** the Luciq MCP server — authenticated MCP unlocks the *"your other apps already do this"* precedent quotes; the skill still works without it.
>
> **Hands off PII deep-dives to** `luciq-masking-rules` — onboard configures per-view masking inline (layer 1 of 3); the deep audit (auto-mask types, network mask key list, consent gating, grayscale, FLAG_SECURE, SSUI `isPrivate`, compliance presets, pre-prod checklist) is `luciq-masking-rules`'s job.

---

### `luciq-masking-rules`

PII / masking audit and compliance-framework prep for an app that already has the SDK installed. Scans all three masking layers — screen / view markers, network logs, defense-in-depth (consent gating, grayscale, FLAG_SECURE, `usersPageEnabled`, SSUI `isPrivate`) — surfaces gaps against the framework you name (HIPAA / GDPR / PCI-DSS / SOC2 / CCPA / FERPA), and walks the controls that close them one at a time with cited rationale. Ends with a visual masking verification on the dashboard and writes `LUCIQ_MASKING.md` with the pre-production privacy checklist and copy-pasteable server-side support requests.

**Try saying:**
- `"Audit my Luciq PII posture"`
- `"Prep Luciq for HIPAA review"`
- `"What's masked in Luciq right now?"`
- `"Add masking to my checkout screen"`

> **Pairs with** `luciq-onboard` — onboard handles per-view markers during the product walk; `luciq-masking-rules` covers the remaining layers and re-runs whenever a new sensitive screen ships or a compliance review approaches.
>
> **Guidance only.** Compliance is a broader program than masking config; the skill states this verbatim in its handoff doc and points decisions back to legal / compliance.

---

### `luciq-debug` ([docs](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/agent-skills/luciq-debug))

Investigate any production signal: crash, hang, bug report, performance regression, or App Store rating drop. Pulls the full context via MCP, maps it to your local repo, and proposes a fix with every claim traced back to its source.

**Try saying:**
- `"Why is crash AB-1234 happening?"`
- `"What broke since version 3.2.0?"`
- `"Which endpoints got slower since 3.2.0?"` *(APM)*
- `"Our App Store rating dropped last week, what's going on?"`

> **Requires** the Luciq MCP server authenticated. The Claude Code plugin install wires it automatically; manual setup is at the [MCP install guide](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server).

---

### `luciq-migrate` ([docs](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/agent-skills/luciq-migrate))

Migrate from Instabug to Luciq, or upgrade between Luciq SDK versions. Renames symbols, updates dependency manifests, shows 3 sample diffs before touching anything, then bulk-applies and verifies with a build.

**Try saying:**
- `"Migrate this project from Instabug to Luciq"`
- `"Upgrade Luciq SDK to v2"`
- `"Replace all deprecated Luciq APIs"`

---

### `luciq-verify`

Verify a Luciq SDK upgrade end to end before shipping. Scaffolds a verification harness into your debug variant, drives a deterministic smoke, pulls the resulting occurrence through MCP, and audits it against a customer-specific rule pack — masking callbacks, URL redirection, preserved headers, user attributes, PII redaction. Outputs a pass/fail HTML + Markdown report.

**Try saying:**
- `"Verify the Luciq upgrade before we release"`
- `"Is it safe to ship the new Luciq SDK?"`
- `"Run upgrade verification against this build"`

> **Requires** the Luciq MCP server authenticated.

---

### `luciq-readout`

Produce a shareable, audience-tailored readout of an app's health. Pulls headline aggregates from MCP, slices detail across crashes, hangs, bugs, and reviews, then renders the same data at the altitude each audience needs — C-suite, VP, PM, EM, or QA — with every number cited to the tool that produced it. Outputs an HTML + Markdown report you can forward.

**Try saying:**
- `"Give me an exec summary of how the iOS app is doing"`
- `"Build a release readout comparing 3.1.4 to 3.0.4 for a VP"`
- `"Stability report for leadership, this week vs last"`

> **Requires** the Luciq MCP server authenticated.

---

### `luciq-alert-config`

Create and manage an individual Luciq alert (rule). Translates a natural-language intent — "alert me when crash-free sessions drop below 99%" — into a valid `write_alerts` payload by reading the app's `init` catalog first and building strictly from it. Never guesses an id, threshold, or whether a metric is even available; asks for anything missing and surfaces tool rejections honestly.

**Try saying:**
- `"Alert me when ANR rate goes above 1%"`
- `"Change the threshold on my crash-spike alert"`
- `"Disable that alert"` / `"Show me my alerts"`

> **Requires** the Luciq MCP server authenticated.

---

### `luciq-alert-gaps`

Find what you're *not* monitoring and add the missing alerts. Cross-references current metric health (via MCP) against your existing alert rules and proposes alerts only for metrics that are both unhealthy (or material) and uncovered — never duplicating coverage or alerting on healthy metrics.

**Try saying:**
- `"Am I missing any alerts?"`
- `"What should I be alerting on?"`
- `"I just installed Luciq — what alerts should I create?"`

> **Requires** the Luciq MCP server authenticated. **Pairs with** `luciq-alert-config` to author each proposed alert.

---

### `luciq-alert-noise`

Reduce noisy, chatty alerts and cut alert fatigue. Inspects each alert's trigger frequency via MCP and recommends targeted fixes — raise threshold, narrow scope, throttle, merge, or disable — without ever blindly silencing a safety-critical alert.

**Try saying:**
- `"My alerts are too noisy"`
- `"Clean up / audit my alerts"`
- `"Which alerts are spammy?"`

> **Requires** the Luciq MCP server authenticated.

---

## How it works

| | |
|---|---|
| **Platform detection** | Identifies your stack in ≤ 2 file reads. No config needed. |
| **Live MCP data** | Pulls crashes, session context, and review signals directly from Luciq. |
| **Diff before apply** | Shows changes and confirms risky steps before running anything. |
| **Cited reasoning** | Every debug claim links back to the MCP result that produced it. |
| **Hard stops** | If a prerequisite is missing or a build fails, it stops and tells you exactly why. |

## License

[Apache-2.0](LICENSE).
