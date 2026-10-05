# The engineer brief

This is what `trace` hands an engineer, and what `forward` posts on the Luciq record. It replaces "can't reproduce, need more info" with the exact session. Every line comes from a tool result or the ticket, and says which.

## Layout

```
SUPPORT → LUCIQ BRIEF — zd-48213
App: acme-shop (production) · iOS

TICKET                                                   [from: Zendesk]
  "App froze when I tried to pay" — opened 2026-09-29 12:31 UTC
  Customer-stated time: "just now" → window 11:31–12:31 UTC (assumed UTC)

MATCH                                                    confidence: high
  User id u-5521    resolved from requester email        [from: list_session_replays]
  Record            Hang #88 "Main thread blocked 4.2s"  [from: list_crashes, user_uuids]
  Occurrence        01M3…  at 12:24:07 UTC               [from: list_occurrences_tokens, user_uuids]
  Why this one      only crash in window; version + device match the ticket
  Other candidates  none

DEVICE & STATE                                           [from: get_occurrence_details]
  iPhone 13 · iOS 18.1 · app 4.1.2 (5) · SDK 19.12.1
  foreground · view "CheckoutViewController" · memory 1186/3780 MB

STEPS                                                    [from: user_steps log]
  1. … (real user steps from the log, not the ticket)
  — or: "user steps not read: <reason>"; customer's account: "…"   [from: ticket]

REPLAY
  https://dashboard.luciq.ai/…/session-replay/<session_id>   [from: list_session_replays]

ROOT CAUSE                                               [from: luciq-debug]
  HYPOTHESIS / CONFIDENCE / EVIDENCE / ROOT CAUSE — verbatim luciq-debug format

LINKS
  Proposed: zd-48213 ↔ luciq:acme-shop:production:crash:88   (not yet written)
```

## Rules

- **Confidence is about the match, separately from the root cause.**
  - High: resolved by user id, with one candidate in the window and version/device agreeing.
  - Medium: resolved by user id, but several candidates were ranked and the user chose one.
  - Low: no user id (device, version, and time only), or the ticket and record disagree on version or device.
- **Steps are labelled by source.** Luciq's user steps and the customer's description are never merged into one list.
- **Always show "Other candidates".** "None" is a claim too.
- **No email in the brief** when it's written back anywhere. Use the user id. In the terminal, showing the email is fine.
- **Disagreements are listed, not smoothed over:** "Ticket says iPhone 15; Luciq occurrence is iPhone 13".
- **LINKS says "not yet written"** until the write order in `link-contract.md` completes and reads back.
