# The dry-run plan

The plan is the contract the customer approves before any write. It must make every proposed merge auditable: which bugs merge, into which master, and the **verbatim key** that united them. Nothing is written that isn't shown here.

## Required elements

1. **Scope line** — app slug, mode, candidate count pulled, and the cap (and whether the scope exceeded it).
2. **The grouping logic** — restated in one line, plus the compiled key recipe.
3. **One block per proposed group**, each showing:
   - the **master** (number + report date), flagged as oldest (or "reassigned by you"),
   - each **member** that will merge into it (number + title),
   - the **verbatim key** shared by the group.
4. **Skipped / not grouped** — every candidate that did not join a group, with a reason.
5. **Write summary** — total groups, total merges, and the destructive-side-effect reminder.

## Layout

```
GROUPING PLAN — app: telepass-tpay (production)
Logic: same screen + same failed requests
Key recipe: current_view + failed_requests_sig
Candidates: 142 pulled (cap 300 — full scope covered)

GROUP 1  ·  3 bugs  ·  key: view=CheckoutActivity | failed=[GET /…/daily-maintenance 404, POST /…/authenticate 401]
  MASTER  #4012  "Payment fails when confirming on checkout"   (reported 2026-06-20, oldest)
  merge → #4048  "Checkout page freezes after tapping confirm" (reported 2026-06-21)
  merge → #4101  "Nothing happens when I tap the button"        (reported 2026-06-23)

GROUP 2  ·  2 bugs  ·  key: view=MapSearchActivity | failed=[GET /…/search/parking 500, GET /…/geocode 503]
  MASTER  #4077  "Parking search returns no results"            (reported 2026-06-22, oldest)
  merge → #4090  "Map fails to load nearby parking"             (reported 2026-06-22)

SKIPPED (not grouped) — 3
  #4055  no network log
  #4061  unique key (no other bug matches)
  #4099  already a duplicate of #3900

WRITE SUMMARY
  2 groups · 3 merges total
  ⚠ Merging moves each duplicate's occurrences into its master and OVERWRITES the
    duplicate's status, priority & assignee with the master's. This skill snapshots
    status/priority first so it can restore them on undo; assignee CANNOT be restored.
    No bulk undo on the server.

Approve this plan to apply, reassign any master first, or tell me to adjust the logic.
```

## Rules

- **Verbatim key, always.** Never summarize the key as "similar" — show the actual composite string, so the customer can see exactly why bugs grouped.
- **Master is explicit.** State which bug is the master and why (oldest, or reassigned). The customer can reassign before approving.
- **Skips are itemized.** Every non-grouped candidate appears with a reason. A bug silently absent from both the groups and the skip list is a reporting bug.
- **Destructive reminder is in the write summary**, not buried — the customer approves knowing status/priority get overwritten.
- **No write language before approval.** The plan describes what *would* happen; it never implies anything has been applied.

## Post-apply report

After the customer approves and the apply loop runs, report:

```
APPLIED — app: telepass-tpay (production)
GROUP 1: #4048, #4101 → master #4012   ✅
GROUP 2: #4090 → master #4077          ✅
Failures: none

Undo (3 bugs merged this session) — choose:
  a) Detach only — unmark; leaves the master's status/priority on each bug
  b) Detach + restore — unmark, then re-apply each bug's pre-merge status/priority
  (assignee can't be restored either way)
```

If any `update_bug` failed, list each failed member and the error; the rest still applied. Offer undo-last only for merges made this session (from the ledger), never for pre-existing groups.
