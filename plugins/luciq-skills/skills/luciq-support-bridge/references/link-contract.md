# The link contract

A link joins one support ticket to one Luciq record (a bug or a crash). Every mode of this skill — `trace`, `forward`, `sync` — reads and writes links through this contract and nothing else. A link that doesn't follow the formats below doesn't count: the skill never parses free text to guess one.

The rule behind the contract: **a link is written on both sides, or it's a half-link.** Either side must be able to find the other in one lookup, without fuzzy matching again.

## Identifiers

### Luciq ref (stored on the ticket)

```
luciq:<slug>:<mode>:<kind>:<number>
```

| Part | Value | Source |
| --- | --- | --- |
| `slug` | Application slug | `list_applications` — never typed by hand |
| `mode` | `production`, `beta`, `staging`, `alpha`, `qa`, `development` | `list_applications` |
| `kind` | `bug` or `crash` (crashes, app hangs, and non-fatals share `crash` — one numbering scheme) | The record's source tool |
| `number` | Per-application number | `list_bugs` / `bug_details`, `list_crashes` / `crash_details` |

Example: `luciq:acme-shop:production:crash:88`

Slug and mode are required. Bug and crash numbers are per-application, so `bug:1234` alone points at a different bug in every app.

### Ticket key (stored on the Luciq record)

```
<system>-<ticket-id>
```

| System | Format | Example |
| --- | --- | --- |
| Zendesk | `zd-<ticket id>` | `zd-48213` |
| Jira | `jira-<issue key, lowercased>` | `jira-mob-812` → issue `MOB-812` |
| Freshdesk | `fd-<ticket id>` | `fd-9921` |
| Intercom | `ic-<conversation id>` | `ic-215004` |

Lowercase the whole key and keep it comma-free (Luciq tag names cannot contain commas). When reading a Jira key back, uppercase the project part.

If one app is linked to more than one instance of the same system, qualify the key with the instance: `zd-acme-48213`. Pick one form per app and never mix them.

## Where the link lives

### On the Luciq record

| Record | Marker | Specific key | Tool |
| --- | --- | --- | --- |
| Bug | tag `support-linked` | tag `zd-48213` | `update_bug` with `tags`, `tag_action: "append"` |
| Crash | tag `support-linked` | tag `zd-48213`, plus a link note as `comment` | `update_crash` with `tags`, `tag_action: "append"`, `comment` |

- **Always `append`.** Never `replace` — it wipes the customer's own tags.
- The marker exists because `list_bugs` matches tags exactly, with no prefix search: `list_bugs` with `filters.tag: [["support-linked"]]` returns every linked bug in one call.
- **`list_crashes` has no tag filter.** Linked crashes can't be listed from the Luciq side, so for crashes the ticket side is the source of truth. The crash tags still matter: they answer "which ticket?" once you have a crash open.
- `update_crash` comments are synced to any linked tracking-tool issue. That helps with Jira, but it means the comment text must be safe to show there.

### On the ticket

| System | Marker | Specific ref |
| --- | --- | --- |
| Zendesk | tag `luciq-linked` | custom text field `luciq_ref` |
| Jira | label `luciq-linked` | custom field `Luciq Ref` if configured, else a link note comment |
| Any system without a custom field | its tag/label | a link note (see below) as an internal comment |

A crash linked to a Jira issue can also be linked natively with `forward_crash` and `issue_url` (Jira only, `supports_linking: true`). Do that **as well as** writing the ref, not instead of it: the native link isn't readable through the contract.

### Several links on one record

Links are many-to-many: many customers hit the same crash, and one customer can file a ticket that matches both a crash and a bug.

- Luciq side: one tag per ticket (`zd-48213`, `zd-48790`, …). The marker appears once.
- Ticket side: `luciq_ref` holds a space-separated list: `luciq:acme-shop:production:crash:88 luciq:acme-shop:production:bug:1234`.

## The link note

This is the one structured text format. It's used as the crash comment, and as the ticket-side ref wherever there's no custom field. The first line is machine-read; everything after it is for people.

```
[luciq-link] luciq:acme-shop:production:crash:88 <-> zd-48213
Linked by luciq-support-bridge on 2026-09-29 after a confirmed match.
Luciq: <dashboard URL>
Ticket: <ticket URL>
Match: user id u-5521 (resolved from requester email), app 4.1.2 (5), iPhone 13, iOS 18.1, within 20 min of ticket time
```

- The first line must match `^\[luciq-link\] luciq:\S+ <-> \S+$` exactly.
- Unlinking adds `[luciq-unlink]` with the same two identifiers. The latest line wins.
- On the ticket, always post it as an **internal** note, never as a public reply.
- **Never put the customer's email or other PII in the note.** Use the Luciq user id. The crash comment syncs to the tracker, and the ticket may be exported.

## Writing a link

Only write a link after the user confirmed the match (see the `trace` and `forward` workflows). The order is fixed:

1. **Validate.** The Luciq ref parses, its `slug` + `mode` came from `list_applications`, and the record exists (`bug_details` / `crash_details`). The ticket exists in the ticket system.
2. **Check for an existing link.** If it's already there on both sides, stop. Rerunning must be a no-op.
3. **Write the ticket side** (`luciq_ref` + marker, or link note + marker). It goes first because it's the only listable side for crashes.
4. **Write the Luciq side** (key tag + marker; plus the comment for crashes).
5. **Read both sides back.** Report the link as written only once both readbacks show it.

If step 4 fails after step 3 succeeded, report a **half-link** with the exact side that's missing. Don't roll step 3 back; `sync` repairs half-links.

## Removing a link

Only on the user's request, or when a merge repoints it (below).

- Luciq: `update_bug` / `update_crash` with `tags: ["zd-48213"]`, `tag_action: "remove"`. Remove `support-linked` only if no other ticket key tag is left.
- Ticket: remove that ref from `luciq_ref`, remove the marker if the list is now empty, and post a `[luciq-unlink]` note.

## Merges and repointing

A link must follow the record it points at when that record is merged.

| Event | What `sync` does |
| --- | --- |
| Linked bug marked as a duplicate (`update_bug` `mark_as_duplicate`) | Copy the key tags and marker to the master bug; replace the ref on the ticket with the master's; post a link note explaining the repoint |
| Linked crash merged into a parent | Same, pointing at the parent. A merged crash can't be updated directly anyway |
| Bug unmarked as a duplicate | Don't guess. Report it and ask which record the ticket belongs to |

Merged duplicates are hidden from `list_bugs` by default. To see them, pass all five `duplicate_type` values.

## Field ownership

Each field has one owner. `sync` posts notes about the other side's fields; it never writes them.

| Field | Owner | The other side may |
| --- | --- | --- |
| Engineering status, priority, assignee, root cause | Luciq | Read it, post it as a note on the ticket |
| Customer communication, ticket status, requester | Ticket system | Read it, post it as a comment on the Luciq record |
| The link itself (refs, key tags, markers) | This contract | Both sides are written only through the steps above |

## Status mapping (for `sync`)

Luciq statuses: bug `1` New, `2` Closed, `3` In Progress; crash `1` Open, `2` Closed, `3` In Progress.

| Observed | Proposed action | Side written |
| --- | --- | --- |
| Luciq Closed, ticket open | Internal note: "Fixed — <version if known>. Safe to reply to the customer." | Ticket (note only) |
| Luciq In Progress, ticket still in the support queue | Internal note: "Engineering is working on it." | Ticket (note only) |
| Ticket reopened (solved → open) while Luciq is Closed | Set Luciq to `1` with a comment citing the ticket | Luciq |
| Ticket solved, Luciq still open | Nothing. A satisfied customer doesn't mean the bug is fixed | — |
| Link exists on one side only | Report the half-link; propose writing the missing side | The missing side |

Every proposed action goes into the sync plan and is written only after approval.

## Validation checklist

A link is valid only if all of these hold:

- [ ] The Luciq ref matches `luciq:<slug>:<mode>:(bug|crash):<number>`, and slug + mode match `list_applications`
- [ ] The ticket key matches `<system>-<id>` in lowercase, with no commas
- [ ] Both sides carry the link, or it's reported as a half-link
- [ ] The marker is present on both sides whenever at least one key/ref is
- [ ] No link note contains an email address or other PII
- [ ] Every ticket-side write was an internal note or a field, never a public reply
