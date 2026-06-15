# Encryption at Rest & in Transit

Masking strips PII before it can be stored or sent. Encryption protects whatever non-masked data legitimately does flow through the SDK. The two are layered defenses, not alternatives — the audit cites the encryption posture in the handoff so the compliance reviewer sees both layers.

Verify the live versions and platform specifics against the SDK Encryption & Data Protection Reference before quoting them — algorithms and key-management details evolve.

## Posture summary

| Layer | iOS | Android |
|---|---|---|
| **In transit** | TLS 1.2+ with HMAC-SHA256 request signing | TLS 1.2+ with HMAC-SHA256 request signing |
| **At rest (on-device)** | AES-256-GCM via CryptoKit (v16.0.0+); PII keys in iOS Keychain | AES-256-GCM (API-tiered key management) |

After transmission is confirmed, the SDK deletes the local copy from storage.

Server-side encryption (Luciq's storage and key management) is out of scope for a mobile masking audit — the developer can't detect or configure it from their repo. If the team asks about it during a compliance review, route them to Luciq's enterprise/security contact rather than answering from this skill.

## iOS PII keys encrypted at rest

The iOS SDK selectively encrypts these field keys via CryptoKit and stores them in the iOS Keychain:

- `IBGName`
- `IBGEmail`
- `IBGDeviceUUID`
- Stored push-notification tokens

If the team is asking *"is the user's email safe on disk?"*, this is the answer to cite.

## On-device data categories that carry PII risk

These are the local stores the SDK uses before transmission. Each is encrypted at the field level; the audit's job is to ensure masking keeps sensitive values from entering them in the first place.

| Store | Data | PII level |
|---|---|---|
| `session_table` | `user_email`, `user_name`, `app_token`, `user_attributes`, `user_events` | Critical |
| `network_logs` | `url`, `request`, `response`, `headers` | High |
| `crashes_table` | `crash_message`, `threads_details` | High |
| `anrs_table` | ANR thread data | High |
| `attachments` | `local_path`, `url`, `name` | Medium |

Key inference for audits:

- **`session_table`** is why masking + per-view markers matter for user attribute values — `usersPageEnabled = false` (see `defense-in-depth.md` §4) is the toggle that limits what gets written here.
- **`network_logs`** is what `network-masking.md` protects. Auto-mask + manual obfuscate/omit decide what enters this store.
- **`crashes_table` / `anrs_table`** can incidentally carry PII in stack traces (logged tokens, stringified user objects). Surface in the handoff as a "watch for it" item — masking doesn't apply to crash strings; the fix is upstream (don't include raw PII in log/exception messages).
- **`attachments`** can include user-uploaded files (screenshots a user added to a bug report). Consent flow and `attachments_quality` controls govern this — see the live docs.

## When to surface encryption in the recap

The audit doesn't *configure* encryption (it's on by default) — but the recap should state the posture so the user sees the whole picture, not just masking. Include one line in Phase 2:

> *Encryption: AES-256-GCM at rest on-device (iOS Keychain for PII keys), TLS 1.2+ with HMAC-SHA256 in transit. Masking + encryption are layered — masking keeps raw PII out of local stores; encryption protects what legitimately flows through them.*

Skip the line only if the user explicitly scoped the audit to masking and waved off the broader posture.

## When the team asks "can the backend decrypt and see X?"

State the answer plainly:

- For **masked values** — no. The unmasked value never existed off-device. The backend has only the `*`-redacted form.
- For **non-masked PII** — yes, the backend can decrypt and serve it to authorized dashboard users. Encryption at rest protects against storage compromise, not authorized access. If the team needs *no one at Luciq* to see a value, the answer is masking, not encryption.

This distinction comes up often during compliance reviews; capture it verbatim in the handoff when it does.

## What this reference does NOT cover

- **Custom logs your app writes outside Luciq's capture** — console logs, third-party crash reporters, debug builds. None of these are touched by Luciq's encryption.
- **The team's own backend.** Out of scope — the team's services and data warehouses have their own posture, independent of Luciq.
- **Luciq's server-side storage.** Out of scope for a mobile audit (see posture summary above). Route compliance questions to Luciq's security contact.
- **Key rotation specifics.** Client-side key management is API-tiered on Android and Keychain-managed on iOS. Verify version-specific behavior against the SDK reference before quoting it to a compliance auditor.
