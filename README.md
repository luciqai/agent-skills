# Luciq Agent Skills

Claude Code skills for the Luciq mobile observability SDK — real edits, MCP queries, and CLI runs, directly inside your IDE.

**Platforms:** `iOS` · `Android` · `Flutter` · `React Native` · `KMP` — auto-detected per invocation.

---

## Install

<details>
<summary><strong>User-global</strong> — works in every project (recommended)</summary>

```bash
mkdir -p ~/.claude/skills
cp -r agent-skills/luciq-* ~/.claude/skills/
```
</details>

<details>
<summary><strong>Project-local</strong> — only this repo</summary>

```bash
mkdir -p .claude/skills
cp -r agent-skills/luciq-* .claude/skills/
```
</details>

---

## Skills

<details>
<summary><strong>luciq-setup</strong> — Install and configure the Luciq SDK</summary>

Edits your build files, inserts the init call at the right entry point, configures invocation and auto-masking, and wires up the Luciq MCP server — all in one go.

**Try saying:**
- `"Add Luciq to this Flutter project"`
- `"Set up Luciq for Android, use a floating button invocation"`
- `"Initialize Luciq and mask the payment fields"`

[View full skill →](luciq-setup/SKILL.md)
</details>

<details>
<summary><strong>luciq-debug</strong> — Investigate production issues end-to-end</summary>

Pulls crash details, session context, repro steps, and device/version distribution via MCP, maps it to your local repo, then proposes a fix with every claim traced back to its source.

**Try saying:**
- `"Why is crash AB-1234 happening?"`
- `"What broke since version 3.2.0?"`
- `"Our App Store rating dropped last week — what's going on?"`

> **Requires:** Luciq MCP server authenticated. Run `luciq-setup` first.

[View full skill →](luciq-debug/SKILL.md)
</details>

<details>
<summary><strong>luciq-migrate</strong> — Migrate Instabug → Luciq or upgrade SDK versions</summary>

Renames symbols, updates dependency manifests, shows 3 sample diffs before touching anything, then bulk-applies and verifies with a build.

**Try saying:**
- `"Migrate this project from Instabug to Luciq"`
- `"Upgrade Luciq SDK to v2"`
- `"Replace all deprecated Luciq APIs"`

[View full skill →](luciq-migrate/SKILL.md)
</details>

---

## Coming soon

| Skill | What it will do |
|---|---|
| `luciq-docs` | Look up Luciq SDK APIs, config options, and platform support |
| `luciq-symbolicate` | Upload symbol files and wire CI auto-upload |
| `luciq-release-check` | Decide whether a release is safe to roll out |
| `luciq-feature-flags` | Wrap code in Luciq feature-flag checks |

---

## How it works

| | |
|---|---|
| **Platform detection** | Identifies your stack in ≤ 2 file reads — no config needed |
| **Live MCP data** | Pulls crashes, session context, and review signals directly from Luciq |
| **Diff before apply** | Shows changes and confirms risky steps before running anything |
| **Cited reasoning** | Every debug claim links back to the MCP result that produced it |
| **Hard stops** | If a prerequisite is missing or a build fails, it stops and tells you exactly why |
