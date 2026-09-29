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
- `/luciq-skills:luciq-group-bugs`. Consolidate the bug list by marking duplicates from your own grouping logic.
- `/luciq-skills:luciq-migrate`. Instabug to Luciq migration and SDK upgrades.
- `/luciq-skills:luciq-verify`. End-to-end SDK upgrade verification.
- `/luciq-skills:luciq-alert-config`. Create, change, or inspect a specific alert.
- `/luciq-skills:luciq-alert-gaps`. Find unmonitored metrics and add the missing alerts.
- `/luciq-skills:luciq-alert-noise`. Reduce noisy alerts and cut alert fatigue.
- `/luciq-skills:luciq-symbolicate`. Make crash reports readable — symbol uploads for every platform, and wiring them into a release pipeline.
- `/luciq-skills:luciq-automate`. Get Luciq data out of the conversation — exports, aggregation, scheduled reports, build gating.

### Cursor

```
/plugin marketplace add luciqai/agent-skills
/plugin install luciq-skills@luciq.ai
```

### Kiro CLI

Kiro reads steering files, not plugins. The installer copies each skill into
`.kiro/steering/` with `inclusion: manual`:

```bash
npx luciq-skills install --kiro            # project-local (.kiro/)
npx luciq-skills install --kiro --global   # all workspaces (~/.kiro/)
```

Because inclusion is manual, the steering files stay out of context until you
reference one in a Kiro session:

```
#luciq-debug why is crash AB-1234 happening?
#luciq-setup add Luciq to this Android project
```

The Luciq MCP server is set up separately — see the [MCP setup guide](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server)
for the Kiro config.

### npx

```bash
npx luciq-skills install            # project-local
npx luciq-skills install --global   # all projects
```

Project installs add the Luciq MCP server to `.mcp.json` at the project root; `--global` adds it at user scope via `claude mcp add`. Restart Claude Code afterwards — a running session doesn't pick up new skills or MCP servers.

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

### `luciq-group-bugs`

Consolidate your bug list by marking duplicates according to your **own** grouping logic. Describe a rule in plain language — "same screen and same failed request", "basically the same title", "share a tag set" — and the skill pulls a scoped set of bugs, compiles your rule into an explainable grouping key per bug, and renders a dry-run plan showing exactly which bug merges into which master and the verbatim key that united them. It marks the duplicates only after you approve, and offers a two-mode undo of what it merged this session (detach only, or detach and restore each bug's pre-merge status/priority).

**Try saying:**
- `"Group my bugs on the checkout screen that hit the same failed request"`
- `"Mark the bugs with basically the same title as duplicates"`
- `"Consolidate the bug list by tag"`

> **Requires** the Luciq MCP server authenticated **and** the `bugs.list.modify` permission to apply merges. Without the permission it still produces the dry-run plan. This is the one skill that *writes* — it always shows a plan and waits for your approval before any merge.

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

### `luciq-symbolicate`

Make crash reports readable. Installs and authenticates the `luciq` CLI, uploads symbol files for every platform — dSYMs, ProGuard/R8 mappings, NDK `.so` files, React Native source maps, Flutter Dart symbols — and wires those uploads into CI (GitHub Actions, Fastlane, Gradle, Bitrise, CircleCI, an Xcode build phase) with the token read from a secret. Built around the three flags that fail *silently*: get `--mode`, `--version-name` or `--version-code` wrong and the upload succeeds, nothing errors, and nothing deobfuscates. So it reads the version off the build system rather than from memory, and requires one manual upload to print `✓` before it will touch a CI file.

**Try saying:**
- `"Our Android crashes aren't deobfuscated — fix it"`
- `"The stack trace in Luciq is just hex addresses"`
- `"Upload the dSYMs for this build to Luciq"`
- `"Add Luciq symbol upload to our release workflow"`

> **Needs no MCP server** — symbol uploads have no MCP equivalent, so the CLI is the only path for them. One CLI token authenticates everything and targets an app by `--slug` + `--mode`; uploads additionally need `settings.mapping_files.modify`.
>
> **Hands off to** `luciq-debug` once the trace is readable, and `luciq-automate` for exports, scheduled reports and build gating.

---

### `luciq-automate`

Get Luciq data out of the conversation and into a file, another tool, a scheduled job, or a build's exit code. Exports and dumps large sets to CSV or JSON, counts and aggregates across many records or several apps, feeds data into a script, runs unattended on a schedule, and gates a release on a metric. Resolves the app via `luciq apps list`, picks typed flags over raw `--filters`, and only pipes to `jq` after confirming the output is JSON. Aggregates in the pipe rather than paging every record into the conversation to count them: on a 208-crash account that is the difference between ~39,000 characters and under 200.

**Try saying:**
- `"Export every open crash across all our apps to a CSV"`
- `"How many open crashes per app version? Just the counts"`
- `"Run this crash summary every Monday at 8am"`
- `"Stop the release if crash-free sessions drop below 99%"`

> **Needs no MCP server** — but data commands run the *same* server-side tools as the MCP under the same permissions and plan gates, so the CLI is never a way around a block. What it adds is determinism, volume, and an exit code.
>
> **Hands off to** `luciq-debug` and `luciq-readout` for a conversational one-off, `luciq-group-bugs` for rule-based dedup, and the `luciq-alert-*` skills for alert authoring.
>
> **Hands off to** `luciq-debug` for root-causing a signal and `luciq-readout` for reports: a question is MCP's job, a command is this skill's.

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
