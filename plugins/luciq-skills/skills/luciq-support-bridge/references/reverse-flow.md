# Mode `forward` — Luciq → ticket

Start from a Luciq bug or crash. End with it attached to the right ticket: the customer's existing one if there is one, a new one only if not. Support ends up knowing what engineering knows, in words they can use.

```
Forward Progress:
- [ ] 1. Resolve app + mode; read the record (bug_details / crash_details)
- [ ] 2. Check for an existing link (link-contract) → if linked, stop and show it
- [ ] 3. Find the person or people behind it
- [ ] 4. Search the ticket system for their open ticket near the incident
- [ ] 5. Decide: link to existing / create new / nothing to forward
- [ ] 6. Render the forward plan (ticket action, support summary, link writes); ⛔ wait for approval
- [ ] 7. Write: ticket first, then Luciq; read both back
```

## Step 3 — Find the person

| Record | Where the person is |
| --- | --- |
| Bug | `bug_details` → `email`, `state.fields.user_name`. There's no user id on a bug |
| Crash | `list_occurrences_tokens` → `get_occurrence_details` → `user.email`, `user.uuid` for each occurrence |

A crash group usually has many users (`affected_users_counter`). Ask which the user wants:

- **One customer** — the user names them, or picks from the affected-users list.
- **Proactive outreach** — "which customers hit this and have open tickets?" Search tickets for each affected email. Cap it (default 20 occurrences) and say so. Don't create tickets in this case, only link existing ones.

## Step 4 — Search for an existing ticket

Look for a ticket from that requester that's still open and created near the incident: from the incident time to incident + 7 days, since customers report late. The query is per system; see `ticket-sources/<system>.md`.

Rank matches by time proximity and subject/symptom overlap, and show them. Linking to an existing ticket is always preferred to creating one. A second ticket for the same customer about the same problem is the duplicate this mode exists to prevent.

## Step 5 — Decide

| Found | Action |
| --- | --- |
| One plausible open ticket | Propose linking to it |
| Several | Show them ranked and ask |
| None, and the user wants a ticket | Propose creating one (below) |
| None, and the reporter is internal (QA, dogfooding) | Say so; propose nothing |

### Creating a ticket

**Crashes — prefer the native integration.** Call `forward_crash` with no `integration` to list the app's connected integrations. If the target system is there, forward through it; Luciq then records the forward itself.
- It works once per integration per crash. A "can't forward twice" result means a ticket already exists; find it rather than retrying.
- To attach a crash to an **existing Jira issue**, use `forward_crash` with `integration` and `issue_url` (Jira only, `supports_linking: true`).

**Bugs, or when there's no native integration** — create the ticket through the ticket system's MCP with the support summary below. In read-only ticket mode, render the ticket text for the user to file.

A native forward still needs the contract's link writes (`support-linked` + key tag, `luciq_ref` on the ticket). The native link isn't readable through the contract.

## The support summary

This goes on the ticket as an **internal note**. It's written for a support agent, not an engineer: no stack traces, no file paths, no user email.

```
[luciq-link] luciq:acme-shop:production:crash:88 <-> zd-48213
What happened: the app froze for about 4 seconds on the payment screen and was closed.
Who's affected: 37 users on app 4.1.2, iPhone and iPad. Not specific to this customer.
Status in engineering: Open, not yet assigned.            ← from crash_details status_id
Workaround: none known.                                    ← only if engineering stated one
Safe to tell the customer: "We've found the problem and engineering is looking into it."
Luciq: <dashboard URL>
```

- The first line is the contract's link note, so the note doubles as the ticket-side link.
- **"Workaround" and "fixed in" only come from engineering**: a Luciq comment, or the user telling you. Never infer them.
- The engineer brief (`engineer-brief-template.md`) goes on the Luciq side as the crash `comment`. For bugs, `update_bug` has no comment field, so it's shown to the user only.

## Red Flags

- "No ticket matched by email, I'll create one." First check the fallbacks (other requester emails in the ticket system, the customer's organization), and ask.
- "37 users hit this, I'll open 37 tickets." Proactive outreach links existing tickets only.
- "I'll tell support it's fixed in 4.2 because there's a newer version." Only engineering says "fixed in".
- "`forward_crash` failed with already-forwarded, I'll retry with the other integration." Find the existing ticket instead.
