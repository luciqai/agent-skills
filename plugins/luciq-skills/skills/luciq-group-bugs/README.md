# luciq-group-bugs

A Claude Code / Cursor skill that consolidates your Luciq bug list by **marking duplicates according to your own grouping logic** — fetch a scoped set of bugs, propose groups from a rule you describe, and apply the merges only after you approve a dry-run plan.

If you've ever wanted to say *"group every bug on the checkout screen that hit the same failed request"* or *"merge all the bugs with basically the same title"* and have it done in one pass — that's this skill.

---

## What it does

You describe how you want bugs grouped, in plain language. The skill:

1. Pulls a scoped, capped set of candidate bugs (`list_bugs`).
2. Compiles your logic into an **explainable grouping key** per bug — built from the fields your logic names (title, screen, tags, category, failed requests, version, user attribute).
3. Forms groups from bugs that share a key, picks a master per group (oldest by default), and renders a **dry-run plan** showing exactly which bug merges into which — and the verbatim key that united them.
4. Marks the duplicates (`update_bug`) **only after you approve**.
5. Offers a one-step **undo** of everything it merged this session.

It mirrors how Luciq's automatic grouping works (a normalized fingerprint of failed network requests and user steps), but lets *you* define the rule.

---

## Why it's careful

This is a **write** skill — `update_bug`'s `mark_as_duplicate` is destructive:

- the duplicate's occurrences move into the master's group, and
- the duplicate's **status and priority are overwritten** by the master's,
- and there's no bulk undo on the server.

So the skill never writes from a rule alone. It always **proposes → proves → confirms → writes**: you see the full plan, with the exact key behind every group, before a single merge happens. A merge you didn't approve never happens.

It's also **deterministic by design**. If your logic can't be reduced to concrete fields (e.g. "group by vibe" / "same user journey"), it stops and asks you to restate it concretely — it will not semantically guess its way into an irreversible merge.

---

## How to use it

### Prerequisites

1. **Luciq MCP server, authenticated.** Run `luciq-setup` first if you haven't, or follow https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server/setup-by-ide.
2. **The `bugs.list.modify` permission** on the authenticated token — required to apply merges. Without it, the skill can still produce the dry-run plan, it just can't write.

### Invoking it

- The slash command `/luciq-group-bugs` invokes the skill; pass anything after it as `args`.
- It also auto-activates on phrases like:
  - "group my bugs by …"
  - "mark these bugs as duplicates"
  - "dedupe / consolidate the bug list"
  - "merge bugs that share the same screen / failed request / tag"

### The flow

1. Confirm the app and mode.
2. Tell it your grouping logic (it offers starters: by title, screen, failed request, tag, category, version, user attribute, or a combination).
3. It fetches candidates, computes keys, and shows you the plan.
4. Reassign any master if you want, then approve.
5. It applies the merges and offers undo.

---

## File map

```
plugins/luciq-skills/
├── commands/
│   └── luciq-group-bugs.md      ← /luciq-group-bugs slash command (invokes this skill)
└── skills/
    └── luciq-group-bugs/
        ├── README.md            ← you are here (human-facing)
        ├── SKILL.md             ← LLM-facing instructions; the workflow + safety gate
        └── references/
            ├── grouping-keys.md ← key recipes, normalization rules, list_bugs vs bug_details field map
            └── plan-format.md   ← the dry-run plan layout + worked example
```

The references are loaded only when the workflow needs them — progressive disclosure keeps `SKILL.md` focused.

---

## Related skills

- **`luciq-debug`** — root-cause one crash, hang, or bug and propose a fix. Different use case: investigate one issue, don't reorganize many.
- **`luciq-readout`** — read-only health/quality report for a stakeholder. It deliberately never writes; this skill is the one that mutates grouping.
- **`luciq-setup`** — first-time MCP/SDK setup. Run it before this skill can reach your data.
