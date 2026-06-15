# Defense-in-Depth Controls

Five controls that aren't masking per se, but compound with it. The audit treats each as a separate Phase 4 item — propose, confirm, apply, summarize. Never bundle them silently.

## 1. User consent gating (Session Replay)

The reference document's strongest "don't" is *"don't enable Session Replay for all users without a consent flow where required."* Required under GDPR for EU users, under CCPA for California users, and under most healthcare privacy regimes for PHI sessions.

### Pattern

```swift
if userHasConsented {
    SessionReplay.enabled = true
} else {
    SessionReplay.enabled = false
}
```

### How to detect today's state

- Grep for `SessionReplay.enabled = true` or platform equivalent. If the assignment is unconditional and reachable from app start, gating is missing.
- Grep for an existing consent state (`UserDefaults.standard.bool(forKey: "consent")`, a `ConsentManager`, a feature flag named `analytics_consent`). Reuse it — don't invent a new one.

### Apply

Wrap the `SessionReplay.enabled = true` site in the detected consent check. If no consent state exists in the app, **don't invent one** — surface as "Close now (requires product design): add a consent flow before Session Replay can run under <framework>." Code can't substitute for a real consent UX.

### How to revoke

`SessionReplay.enabled = false` mid-session stops capture immediately. Surface that in the handoff so the team knows the kill switch exists.

## 2. Grayscale screenshot mode

Defense-in-depth — reduces visual detail and cuts file size 40–60%. **Never propose grayscale as a substitute for masking.** Surface in the same Ask as the proposal that triggered it.

### Pattern (iOS Session Replay)

```swift
SessionReplay.screenshotQualityMode = .greyScale
```

Verify per-platform equivalents against the live docs.

### When to propose

- Healthcare / financial apps where bandwidth and incidental exposure both matter.
- Apps with frequent screen captures (high replay sample rate) where grayscale meaningfully shrinks transfer.
- CLAUDE.md / README signals "minimize on-the-wire PII surface."

### When to skip

- Color is load-bearing for the app (design tools, photo apps, color-coded medical imagery). State this honestly — never quietly downgrade UX for a phantom privacy gain.

## 3. FLAG_SECURE (Android)

Android's `WindowManager.LayoutParams.FLAG_SECURE` prevents the OS from including a window in screenshots, recent-apps thumbnails, and screen recordings. By default, **Luciq respects FLAG_SECURE windows and does not capture them.** This is the safe default.

### Override

```kotlin
Instabug.Builder(application, token)
    .ignoreFlagSecure(true)  // Default: false
    .build()
```

Setting `ignoreFlagSecure(true)` means Luciq captures FLAG_SECURE windows. **Almost never the right call.** If you find this set, surface as a "Close now" item with the consequence stated:

> *"`ignoreFlagSecure(true)` at `LuciqInit.kt:18` overrides the OS-level secure-window protection. FLAG_SECURE windows (typically payment screens, ID verification, biometric prompts) will be captured by Luciq. Recommend reverting to default unless your team has a documented reason."*

### When NOT to surface as a red flag

- Team has documented (CLAUDE.md / README) the reason — e.g., a payment SDK uses FLAG_SECURE but Luciq capture is still wanted for QA. Cite the line and proceed with the team's choice.

## 4. `usersPageEnabled = false`

A server-side toggle that limits user attribute transmission to keys only — values are not sent. Useful when the team treats attribute values as PII but still wants attribute keys for segmentation.

### Detection

Server-controlled — there's no local code signal. If a CLAUDE.md / README line mentions minimizing user-attribute transmission, surface as a support-ticket request item:

> *"Email Luciq support to disable the users-page feature for app `<token>` so only attribute keys (not values) transmit."*

### When to propose

- B2B apps where user identifiers are themselves sensitive (employee IDs, internal usernames).
- Compliance regimes that classify any user attribute value as PII.

## 5. Server-Driven UI (`isPrivate` flow)

See `ssui-isprivate.md` for the full flow. Surface here only when Track E detected SSUI inflate sites (`inflateFromJson`, RemoteConfig-driven UI, etc.). The audit's job is to propose the `isPrivate` schema + safety-net pattern, not to design the SSUI itself.

## Video recording caveat (always state in handoff)

Per-view masking is **not supported** for video recording on any platform — iOS, Android, Flutter, React Native. If the app uses video recording (custom feature, not Luciq's session capture), state plainly that masking doesn't apply there and the team must scope recording to non-sensitive contexts or skip it on sensitive screens.

State this in the Phase 4 Summarize block whenever Session Replay is configured, even if the app doesn't currently use custom video recording — it's the most common surprise.
