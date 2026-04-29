# Luciq Agent Skills

Claude Code skills for the Luciq mobile observability SDK — real edits, MCP queries, and CLI runs, directly inside your IDE.

**Platforms:** `iOS` · `Android` · `Flutter` · `React Native` · `KMP` — auto-detected per invocation.

---

## Install

### Claude Code

Add the Luciq marketplace and install the plugin in one step:

```
/plugin marketplace add github.com/luciqai/agent-skills
/plugin install luciq@luciq
```

Skills available after install:
- `/luciq:luciq-setup` — SDK install and configuration
- `/luciq:luciq-debug` — production signal investigation
- `/luciq:luciq-migrate` — Instabug → Luciq migration and SDK upgrades

### Cursor
Coming soon.

### Other agents (npx)
Coming soon.

### Manual install (fallback)

**User-global** — works in every project
```bash
mkdir -p ~/.claude/skills
cp -r agent-skills/skills/luciq-* ~/.claude/skills/
```

**Project-local** — only this repo
```bash
mkdir -p .claude/skills
cp -r agent-skills/skills/luciq-* .claude/skills/
```

---

## Skills

### `luciq-setup` — [docs](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/agent-skills/luciq-setup)
Install and configure the Luciq SDK end-to-end: edits your build files, inserts the init call at the right entry point, configures invocation and auto-masking, and wires up the Luciq MCP server.

**Try saying:**
- `"Add Luciq to this Flutter project"`
- `"Set up Luciq for Android, use a floating button invocation"`
- `"Initialize Luciq and mask the payment fields"`

---

### `luciq-debug` — [docs](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/agent-skills/luciq-debug)
Investigate any production signal — crash, hang, bug report, performance regression, or App Store rating drop. Pulls the full context via MCP, maps it to your local repo, and proposes a fix with every claim traced back to its source.

**Try saying:**
- `"Why is crash AB-1234 happening?"`
- `"What broke since version 3.2.0?"`
- `"Our App Store rating dropped last week — what's going on?"`

> **Requires:** Luciq MCP server authenticated — see the [MCP install guide](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server). Run `luciq-setup` to wire it automatically.

---

### `luciq-migrate` — [docs](https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/agent-skills/luciq-migrate)
Migrate from Instabug → Luciq or upgrade between Luciq SDK versions. Renames symbols, updates dependency manifests, shows 3 sample diffs before touching anything, then bulk-applies and verifies with a build.

**Try saying:**
- `"Migrate this project from Instabug to Luciq"`
- `"Upgrade Luciq SDK to v2"`
- `"Replace all deprecated Luciq APIs"`

---

## How it works

| | |
|---|---|
| **Platform detection** | Identifies your stack in ≤ 2 file reads — no config needed |
| **Live MCP data** | Pulls crashes, session context, and review signals directly from Luciq |
| **Diff before apply** | Shows changes and confirms risky steps before running anything |
| **Cited reasoning** | Every debug claim links back to the MCP result that produced it |
| **Hard stops** | If a prerequisite is missing or a build fails, it stops and tells you exactly why |
