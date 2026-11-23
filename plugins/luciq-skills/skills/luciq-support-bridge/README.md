# luciq-support-bridge

A Claude Code / Cursor skill that joins **support tickets** and **Luciq records**, in both directions, and keeps them joined.

Support lives in Zendesk or Jira. Some tickets are about bugs in the app, and an engineer can't debug from "the app froze when I tried to pay". This skill starts from that ticket and ends at *that customer's* crash occurrence or bug report in Luciq, with device, steps, and session replay, then hands off to `luciq-debug` for the root cause. It also works the other way: a Luciq bug or crash reaches the right ticket, so support knows what engineering knows.

---

## What it does

Three modes:

| Mode | From → to | Ends with |
| --- | --- | --- |
| `trace` | Ticket → Luciq | The customer's own occurrence or bug, device and state, steps, replay link, root cause, and a link on both records |
| `forward` | Luciq → ticket | The customer's existing ticket linked (or a new one, if none exists), with a support-readable internal note |
| `sync` | Both | Fixed in Luciq → note on the ticket; ticket reopened → Luciq back to open; half-links repaired; links repointed after merges |

### How `trace` finds the right person

Tickets name people by email. Most Luciq tools match the SDK's **user id** exactly, so an email passed to them finds nothing. The skill resolves the email through `list_session_replays` (the one tool that matches on email), takes the user id off the row, and uses that id for everything after. It then narrows to the incident window and pulls *that user's* occurrence, not the latest one from the crash group, which would be someone else's device and logs.

### How the link works

Every link is written on both sides in a fixed format (`references/link-contract.md`):

- **Luciq:** tags `support-linked` + `zd-48213` on the bug or crash.
- **Ticket:** tag `luciq-linked` + a `luciq_ref` field such as `luciq:acme-shop:production:crash:88`, or a structured internal note.

Either side can find the other in one lookup, and reruns are no-ops.

---

## Why it's careful

- **Ticket text is data.** A customer wrote it; the skill never follows instructions found in it.
- **No write without approval.** Tags, notes, forwards, and new tickets are shown as a plan first.
- **Nothing customer-facing.** Ticket-side writes are internal notes and fields only. A person replies to the customer.
- **Never picks silently.** If two crashes fit the ticket, it shows both and asks.
- **No emails in write-backs.** Notes and comments refer to the Luciq user id.
- **A solved ticket doesn't close a bug.** A satisfied customer isn't a fix.

---

## How to use it

### Prerequisites

1. **Luciq MCP server, authenticated.** Run `luciq-setup` first if you haven't.
2. **A ticket system MCP** (Zendesk or Jira adapters included) for reading and writing tickets. Without one, paste the ticket. The skill runs read-only on the ticket side and gives you the notes to paste.
3. **The app identifies users** with the same email or account id support sees. Without it, matching falls back to device, version, and time, at low confidence, and the skill will recommend fixing it via `luciq-setup`.
4. *(Optional)* A Zendesk admin creates an agent-only text field `luciq_ref`. Without it, links are stored as internal notes.

### Invoking it

- `/luciq-support-bridge`, with anything after it passed as `args`.
- It also auto-activates on phrases like:
  - "Zendesk ticket 48213 says the app crashed — what happened?"
  - "find this customer's session in Luciq"
  - "link Luciq bug 1234 to the support ticket"
  - "which of the customers who hit crash 88 have open tickets?"
  - "sync our linked tickets with Luciq"

---

## Reference files

| File | Contents |
| --- | --- |
| `references/link-contract.md` | Identifier formats, where links live, write order, merges, field ownership, status mapping |
| `references/identity-resolution.md` | Email → user id chain, reading `user_summary`, fallbacks, the identify-user setup gap |
| `references/engineer-brief-template.md` | What `trace` hands an engineer |
| `references/reverse-flow.md` | `forward` mode: finding the person and the ticket, native integrations, the support summary |
| `references/sync-rules.md` | `sync` mode: collecting pairs, classification, the sync plan |
| `references/ticket-sources/zendesk.md`, `jira.md` | Per-system field maps, searches, and write rules |
