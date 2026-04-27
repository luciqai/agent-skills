# Luciq Agent Skills

> **Note:** This repository is currently under active implementation and is not yet complete.

Claude Code skills for the Luciq mobile observability SDK. They live inside an engineer's IDE (Claude Code, Cursor, Claude Desktop, or any MCP-compatible client) and turn plain-English requests into real edits, queries, and CLI runs.

## Skills

| Skill | When to invoke |
|---|---|
| [`luciq-docs`](luciq-docs/SKILL.md) | Looking up Luciq SDK APIs, config, or platform support |
| [`luciq-setup`](luciq-setup/SKILL.md) | Installing or initializing Luciq in a project |
| [`luciq-debug`](luciq-debug/SKILL.md) | Investigating a crash, bug, hang, performance regression, or rating drop |
| [`luciq-symbolicate`](luciq-symbolicate/SKILL.md) | Uploading symbol files or wiring CI auto-upload |
| [`luciq-release-check`](luciq-release-check/SKILL.md) | Deciding whether a release is safe to roll out |
| [`luciq-feature-flags`](luciq-feature-flags/SKILL.md) | Wrapping code in Luciq feature-flag checks |
| [`luciq-migrate`](luciq-migrate/SKILL.md) | Migrating Instabug → Luciq or upgrading SDK versions |

All skills work across **iOS, Android, Flutter, React Native, KMP** — platform is auto-detected per invocation.

## Install

### User-global (recommended — works in every project)
```bash
mkdir -p ~/.claude/skills
cp -r agent-skills/luciq-* ~/.claude/skills/
```

### Project-local (only this repo)
```bash
mkdir -p .claude/skills
cp -r agent-skills/luciq-* .claude/skills/
```

## Prerequisites

| Skill | Needs |
|---|---|
| `luciq-debug`, `luciq-release-check` | Luciq MCP server configured + OAuth'd. `luciq-setup` wires this. |
| `luciq-symbolicate` (Flutter) | `luciq_cli` installed: `dart pub global activate luciq_cli` |
| Everything else | None — pure code + repo work |

## Design principles

- **Auto-detect platform** in ≤2 file reads per invocation. Stop at first match.
- **Cite evidence** when consuming MCP data — never fabricate stack traces or counts.
- **Show diffs** before applying code edits. Confirm risky steps (`pod install`, bulk renames).
- **Fail fast** with a clear pointer when prerequisites are missing — usually back to `luciq-setup`.
- **Defer to `luciq-docs`** when an API surface might be version-dependent. Don't hardcode what could go stale.
