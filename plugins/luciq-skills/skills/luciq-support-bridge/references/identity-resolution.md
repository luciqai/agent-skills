# Identity resolution

A ticket names a person by email. Most Luciq tools name a person by the **SDK-reported user id**, matched exactly. This file is the bridge between the two, and the step most likely to go wrong silently.

## Which tool matches what

| Tool / filter | Matches on | An email here… |
| --- | --- | --- |
| `list_session_replays` → `filters.user` | User id **or** email. A value containing `@` is matched against the email | resolves ✓ |
| `list_bugs` → `filters.email` | The bug **reporter's** email | resolves, for bugs only ✓ |
| `user_summary` → `user_uuid` | User id, exactly | returns `user_found: false` ✗ |
| `list_crashes` / `list_bugs` → `filters.user_uuids` | User id, exactly | matches nothing ✗ |
| `list_occurrences_tokens` → `filters.user_uuids` | User id, exactly | matches nothing ✗ |

So an email always goes through `list_session_replays` (or `list_bugs` `filters.email`) first, and the id comes out.

## The chain

```
ticket requester email
  │
  ▼  list_session_replays(slug, mode, filters: { user: [email], date_ms: window })
sessions[].user.id   ← also user.name, user.email, and each session's session_replay_url
  │
  ├─▶ user_summary(slug, mode, user_uuid: id)                     footprint + counts
  ├─▶ list_crashes(filters: { user_uuids: [id], date_ms })         crash groups
  ├─▶ list_bugs(filters: { user_uuids: [id], reported_at })        bug reports
  └─▶ list_occurrences_tokens(number, filters: { user_uuids: [id] })  their occurrences
```

Session rows look like this (fields used by this skill):

```json
{
  "user": { "id": "19", "name": "…", "email": "…" },
  "session_id": "1790684905405-1651066581",
  "app_version": "1.0.0 (1)",
  "device": "…", "os": "…",
  "start_time": 1790684905405, "duration": 34004,
  "session_type": "Frustrating",
  "session_replay_url": "https://dashboard.luciq.ai/…/session-replay/1790684905405-1651066581"
}
```

`list_session_replays` defaults to the last 7 days. Always pass the ticket's window as `date_ms`.

## Reading `user_summary`

- `user_found: false` → the id doesn't exist. Check you passed an **id**, not an email.
- `user_found: true`, `has_data_in_window: false` → the user exists but was quiet in the window. Report it. Widen only if the user asks. `period_days` maxes out at 56.
- `crashes` and `bugs` are **counts** (`occurrences`, `distinct`), not records. Get the records from `list_crashes` / `list_bugs` with `user_uuids`.
- Counts and lists can disagree: a count of 1 crash while `list_crashes` returns nothing for the same user and window has been seen. Report both. Then check the user's sessions with `list_session_replays` `filters.issues` (`fatal_crash`, `anr`, `oom`, `fatal_hang`, `non_fatal_crash`, …) before concluding anything.

## Going the other way (Luciq record → person)

Used by `forward` mode.

| Start | Person comes from | Id available? |
| --- | --- | --- |
| Bug | `bug_details` → `email`, `state.fields.user_name` | **No user id** on the bug. Resolve the email through `list_session_replays` if you need one |
| Crash occurrence | `get_occurrence_details` → `user.uuid`, `user.email`, `user.name` | Yes |
| Crash group | Its occurrences (`list_occurrences_tokens` → `get_occurrence_details`) | Per occurrence. A group has many users |

## Fallbacks, in order

When the email resolves to nothing:

1. **Right app and mode?** A customer on TestFlight is in `beta`, not `production`. A cross-platform product may have separate iOS and Android apps. Check the ticket's platform field and `list_applications`.
2. **Right window?** Try the ticket's full lifetime (created → now), not just the stated time. Say you did.
3. **Reporter email.** `list_bugs` with `filters.email` — the customer may have filed an in-app report with an email the SDK didn't set as the user's.
4. **Other identifiers in the ticket.** An account or user id in a custom field or the body → try it directly as `user_uuid`. Customer-provided ids are weak anchors; confirm with the user.
5. **User attributes.** If the app sets an attribute that support also sees (account id, plan id), filter by it: `list_crashes` / `list_bugs` `filters.user_attributes`, `list_session_replays` `filters.user_attributes` (exact, case-sensitive key).

If none of these resolve, stop and report every query tried, with its filters and window.

## When the app doesn't identify users

Signs: session rows with an empty or missing `user.email`, ids that look like device-generated UUIDs, no hits across several tickets whose customers certainly used the app.

This is a setup gap, not a data gap. Route to `luciq-setup` with the recommendation:

- Call the SDK's identify-user API at login with the **same email support sees** (or a stable account id support can see on the ticket).
- Optionally set a user attribute support can search by, e.g. the account id.

Without this, `trace` falls back to device, version, and time, which is a weak anchor. Say so in the brief and cap confidence at **low**.
