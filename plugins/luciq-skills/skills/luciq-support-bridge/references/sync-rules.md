# Mode `sync`

Keep linked records honest after the link is made. Engineering closes a bug: support should know. A customer says it's still happening: engineering should know. `sync` finds those gaps, proposes notes and status changes, and writes only what's approved.

It runs on demand, or on a schedule (a routine that runs this mode and posts the plan for approval). The status mapping and field ownership are defined in `link-contract.md`; this file is the procedure.

```
Sync Progress:
- [ ] 1. Collect linked pairs from both sides
- [ ] 2. Read the current state of each pair
- [ ] 3. Classify each pair against the mapping table
- [ ] 4. Render the sync plan; ⛔ wait for approval
- [ ] 5. Apply approved rows; report every result
```

## Step 1 — Collect pairs

Bugs and crashes are collected differently, because only bugs can be listed by tag.

| Source | Query | Yields |
| --- | --- | --- |
| Luciq bugs | `list_bugs` with `filters.tag: [["support-linked"]]`, paginated with `offset`. Pass all five `duplicate_type` values so merged duplicates aren't hidden | Bugs with their key tags |
| Ticket system | Tickets tagged `luciq-linked` (see `ticket-sources/<system>.md`) | Tickets with their `luciq_ref` (bugs **and** crashes) |

Join them on the contract identifiers. Every pair falls into one of three sets:

- **Both sides** → a linked pair.
- **Luciq side only** (tag, no matching ref) → half-link, missing on the ticket.
- **Ticket side only** (ref, no matching tag) → half-link, missing on Luciq. For crashes this is the only way to find it, since `list_crashes` can't filter by tag. Read the crash with `crash_details` and check its tags.

Cap the run (default 100 pairs) and say if there are more. Never silently truncate.

## Step 2 — Read state

For each pair: the Luciq `status_id` (from `list_bugs` or `crash_details`), `duplicate_type` / merge state, and the ticket status plus its last status change.

## Step 3 — Classify

| Condition | Proposed action |
| --- | --- |
| Luciq Closed (`2`), ticket not solved | Internal note on the ticket: fixed. Include the version only if a Luciq comment or the user states it |
| Luciq In Progress (`3`), ticket open, no sync note yet | Internal note: engineering is working on it |
| Ticket reopened after being solved, Luciq Closed | `update_bug` / `update_crash` with `status_id: 1`, plus a comment (crashes) citing the ticket key |
| Ticket solved, Luciq open | **No action.** Report it as info only |
| Luciq bug is now a duplicate | Repoint: copy the key tags + marker to the master, replace the ticket's ref, and post a link note |
| Luciq crash merged into a parent | Same, pointing at the parent |
| Half-link | Write the missing side |
| Ticket or Luciq record deleted / not found | Report it; propose unlinking the surviving side |
| States already agree | Nothing. Leave it off the plan |

**Don't repeat notes.** Before proposing a note, check the ticket's recent internal notes for one this skill already posted with the same content. Sync must be idempotent: two runs in a row produce one note.

## Step 4 — The sync plan

```
SYNC PLAN — acme-shop (production) · 42 linked pairs read (cap 100)

NOTE ON TICKET (3)
  zd-48213 ← crash:88   Luciq Closed, ticket open       → "Fixed by engineering. Safe to update the customer."
  zd-48790 ← crash:88   Luciq Closed, ticket open       → same
  jira-mob-812 ← bug:1234  Luciq In Progress, ticket open → "Engineering is working on it."

REOPEN IN LUCIQ (1)
  bug:1190 ← zd-47002   ticket reopened 2026-09-28, Luciq Closed → status_id 1

REPOINT (1)
  bug:1201 → master bug:1100 (merged)   zd-47550 ref updated

REPAIR HALF-LINKS (1)
  crash:91   ticket zd-48001 has the ref; Luciq tag missing → add zd-48001, support-linked

INFO ONLY (2)
  zd-46100 solved while bug:1002 still open — not closing Luciq
  zd-45888 → bug:990 not found

Approve all, approve by section, or drop rows by id.
```

## Step 5 — Apply

Apply in plan order. Ticket-side writes come before Luciq-side writes within each pair, same as the contract. Record every result. Continue past failures and report them all at the end. A row that failed stays on the next run's plan.
