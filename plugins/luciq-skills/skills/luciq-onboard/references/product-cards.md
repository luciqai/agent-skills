# Luciq Product Cards

One card per Luciq product. The skill reads this file during Phase 4 (product walk) to fill in the per-product Ask, Apply, and Summarize beats. Cards are intentionally short — they're conversational source material, not docs.

For every product:

- **Value (one line)** — used verbatim in the Ask step.
- **Fit signals** — what in the profile makes this product a recommendation. Each signal here is something the analysis already detected; the skill cites it in the Ask.
- **Anti-signals** — what makes this product better deferred. Each becomes a "Can be added later — because…" line if applicable.
- **Apply targets** — what the skill changes in code, derived from the profile.
- **Style match** — how to inherit defaults from a detected competitor SDK so Luciq's posture matches the team's.
- **What's left for you** — only what the user can't do via code. Doc-pointing only. Never name third-party tools.
- **Verification (for end-of-walk)** — concrete steps the user takes to see the product working. Only the primary product (usually Bug Reporting) uses this in Phase 5; others get it embedded in their Summarize block for self-verification.

Verify product names, SDK class names, and dashboard surface labels against https://docs.luciq.ai before quoting them. The cards below are illustrative.

---

## Bug Reporting

**Value.** Your users shake the phone or screenshot to send a report — screenshots, network logs, repro steps, and an attached video. No support ticket round-trip.

**Fit signals.**
- Any app with real users — universal fit.
- Anti-signal absent (see below).
- CLAUDE.md / README mentions support load, beta program, or QA process → upgrade this from STRONG to MUST.
- Workspace precedent: any other Luciq app in the user's workspace uses Bug Reporting.

**Anti-signals.**
- None — this is the canonical Luciq product. Always at least "Optional" unless the user explicitly excludes it.

**Apply targets.**
- Invocation event: shake (default), screenshot, floating button, or programmatic only. Default per platform per the live setup guide.
- If the app has a sensitive screen (money path, auth flow, PII screen), avoid screenshot invocation there — recommend shake or floating button as the default, and propose programmatic-off for the sensitive screen.
- **Per-view privacy markers** on individual PII-bound views. Consume the `sensitive_views` list from the profile (built in Phase 1 Track B) and propose the platform-appropriate marker for each entry:
    - iOS SwiftUI → `.luciq_privateView()` modifier on the view (e.g. `TextField("Card", text: $cardNumber).luciq_privateView()`).
    - iOS UIKit → `view.luciq_privateView = true` on the matched `UITextField` / `UILabel` / `UITextView` / `UIImageView`.
    - Android Compose → `Modifier.luciqPrivate()` on the matched `TextField` / `Text` / `Image`.
    - Android Views → `Luciq.addPrivateViews(view)` in `onViewCreated` / `onCreate`, or `LuciqPrivateView.setPrivateView(view, true)`.
    - React Native → wrap the matched `TextInput` / `Text` / `Image` in `<LuciqPrivateView>...</LuciqPrivateView>`.
    - Flutter → wrap in `LuciqPrivateView(child: ...)`.
  Per-match confirmation is mandatory — show one diff per view with the file:line and the suggested marker. Never bulk-apply. Reject-once-and-continue on false positives.
- Coarse screen-level fallback: if `sensitive_views` is empty or shallow (e.g. heavily generated UI), default the money path and auth screens to use the wrapper variant (`LuciqPrivateView { ... }` on iOS, `LuciqPrivateView(child: ...)` on Flutter / RN) at the screen root so the screen is masked even before per-view enumeration catches up.

**Style match.**
- If Sentry / Bugsnag / etc. has `attachScreenshot: false` → recommend Luciq screenshot capture off as default.
- If competitor restricts to release builds only → mirror that gating.
- If a competitor declares **view-level masking** (Sentry replay `mask` tag, UXCam `occludeSensitiveView`, Smartlook `registerBlacklistedView`, Datadog `privacy` markers), translate the *same view set* to Luciq's per-view markers above. The user's team has already decided what's sensitive — mirror their decision, don't relitigate it.

**What's left for you.**
- Nothing required — reports start arriving on next launch.
- Optional: configure custom report attributes (app version, user tier, env) on the dashboard.

**Verification (primary — used in Phase 5).**
1. Build and launch.
2. Trigger the chosen invocation event (e.g., Ctrl+Cmd+Z for shake in the simulator).
3. Type "test from onboarding" and submit.
4. Open the dashboard's Bugs surface for this app.
5. The report should appear within seconds.

---

## Crash Reporting

**Value.** Fatal crashes captured with repro steps, network logs, and the session context that led up to them.

**Fit signals.**
- No competitor mobile crash reporter detected.
- CLAUDE.md / README mentions stability, crash-free rate, or a recent incident → MUST.

**Anti-signals.**
- A competitor crash reporter is active (Sentry, Firebase Crashlytics, Bugsnag, Embrace, etc.). Frame as "covered today by `<SDK>`; if you ever want to consolidate vendors, switching is a one-skill job."
- Dual crash handler conflict already surfaced in Phase 2 — don't add a third before the user resolves the first two.

**Apply targets.**
- Generally nothing beyond the SDK init from `luciq-setup` — crash reporting is on by default for Luciq.
- If symbolicated stack traces matter, propose adding the Luciq CLI to CI for dSYM / ProGuard mapping upload.

**Style match.**
- If competitor crash reporter gates init on release stage only → mirror.

**What's left for you.**
- dSYM (iOS) / mapping file (Android) upload step in CI for symbolicated stack traces — see the CLI setup docs.
- Optional: custom keys / metadata on crash reports.

**Verification.**
1. Trigger a controlled, non-fatal test exception via the SDK's test method (or a deliberate `fatalError` in debug).
2. Wait for the next app launch (crashes are dispatched on next session start).
3. Open the dashboard's Crashes surface.

---

## APM (Application Performance Monitoring)

**Value.** Slow screens, slow network calls, app hangs, and an Apdex score that quantifies user-perceived performance.

**Fit signals.**
- E-commerce checkout, social feed, media player — any archetype where speed shows up in support tickets.
- Money path identified in profile (the screen where APM matters most).
- CLAUDE.md / README mentions performance, p95, latency, hangs, or Apdex → MUST.

**Anti-signals.**
- A competitor APM (Datadog RUM, New Relic, Sentry perf, Firebase Performance) is active. Frame as "covered today; checkout-scoped APM in Luciq can still complement it by tying perf to the user reports — your call."
- Hobby app or one-screen utility — APM adds noise without value.

**Apply targets.**
- Auto-screen tracking on, matched to competitor's posture (sample rate, env gating).
- Network logging on, with masking from the profile (headers like Authorization, body fields like password / token / card).
- Configure tracked hosts to the user's API domain(s) if detectable from the networking config.

**Style match.**
- Sample rate inheritance: if Sentry `tracesSampleRate: 0.1`, propose Luciq APM at 10% on screens, 100% on the money path.
- App-hang threshold inheritance: if Sentry `appHangTimeoutInterval: 1.5`, mirror.

**What's left for you.**
- Optional: custom traces / spans for business-critical flows (cart checkout, payment confirmation).
- Optional: Apdex threshold tuning on the dashboard once you have data.

**Verification.**
- Navigate through 3-5 screens in the app.
- Open the dashboard's APM surface — screen load times should appear within ~1 minute.

---

## Session Replay

**Value.** Watch the actual user session that led to a bug or a crash — video synced with network calls, taps, and console logs.

**Fit signals.**
- Bug Reporting is also being adopted — Session Replay magnifies its value.
- High-stakes flows (checkout, signup) where "repro steps" aren't enough.
- Workspace precedent: another app in the user's workspace uses replay.

**Anti-signals.**
- CLAUDE.md / README signals strict privacy posture (HIPAA, financial, healthcare) without robust masking config in the existing competitor → defer until masking is reviewed.
- No Bug Reporting and no Crash Reporting selected — replay needs a triggering event to be useful.

**Apply targets.**
- Enable Session Replay.
- **Per-view privacy markers** on individual PII-bound views — same `sensitive_views` list from the profile that Bug Reporting consumed; if Bug Reporting was already in the walk, those markers are already in place and this is a no-op. If Session Replay is being added without Bug Reporting, apply the per-view markers now using the platform-appropriate API (see Bug Reporting card for the per-platform marker reference). Per-match confirmation; never bulk-apply.
- Coarse per-screen masking as a fallback layer: money path screen and auth screen wrapped in the screen-root marker variant (e.g. `LuciqPrivateView { CheckoutView() }` on iOS) so the entire screen masks even if enumeration missed a view.
- Sample rate: inherit from competitor if a replay-capable competitor exists, otherwise default per the live setup guide.

**Style match.**
- Sentry `replaysSessionSampleRate: 0.05` → propose Luciq replay at 5%.
- Competitor's masking tag pattern → translate to Luciq's masking API.

**What's left for you.**
- Review masking when you add new screens with sensitive UI.
- Optional: per-screen replay disable on screens you never want recorded.

**Verification.**
- Submit a test bug report (covered by Bug Reporting verification).
- Open the report on the dashboard — a Session Replay tab should be attached.

---

## In-App Surveys

**Value.** Ask your users questions in-context — NPS, satisfaction, exit reasons — at the right moment, targeted by event or user attribute.

**Fit signals.**
- CLAUDE.md / README mentions retention, engagement, NPS, customer feedback, or growth goals.
- App has authenticated users (so surveys can target user segments).
- Post-action moments exist in the app (post-purchase, post-onboarding, post-content-consumption).

**Anti-signals.**
- Pre-launch app, no users yet → defer until launch.
- Internal-only / one-time-use utility → defer.
- Very low DAU — survey responses won't be statistically useful yet.

**Apply targets.**
- Nothing in code beyond the SDK presence — surveys are configured on the dashboard.
- If push notification setup exists, mention that survey delivery can use it.

**Style match.**
- None at the code level — surveys are dashboard-configured.

**What's left for you.**
- Build your first survey on the dashboard (link to surveys docs).
- Targeting rules: event-triggered or attribute-based. Decide post-purchase, post-onboarding, or NPS-style anchor.

**Verification.**
- After creating a survey on the dashboard with the current build version as a target, trigger the targeting event in the app.
- The survey should appear inline.

---

## App Ratings & Reviews

**Value.** Prompt happy users for a store rating at a moment that converts; route unhappy users to feedback first instead of a one-star review.

**Fit signals.**
- Consumer app with App Store / Play Store presence.
- Growth or retention goals in CLAUDE.md / README.
- Positive in-app events exist (purchase complete, content consumed, level passed).

**Anti-signals.**
- B2B / enterprise / internal tool — no store presence to push ratings toward → frame as "Can be added later: when you launch publicly on the store."
- Pre-launch.

**Apply targets.**
- Suggest the SDK call site(s) for trigger events — derived from the positive-event surfaces detected in the profile.
- Configuration of *when* to actually prompt lives on the dashboard.

**Style match.**
- None at the code level.

**What's left for you.**
- Configure trigger rules on the dashboard (link to ratings docs) — typically gated on time-since-install + happy-event count.

**Verification.**
- Once trigger rules are configured, perform the qualifying actions in the app to reach the prompt.

---

## Feature Requests

**Value.** Users submit and vote on feature ideas in-app, tied to their identity, so you build what your most engaged users actually want.

**Fit signals.**
- Product-led growth app, B2B SaaS, or community-engaged consumer app.
- CLAUDE.md / README mentions roadmap, user feedback, or community.

**Anti-signals.**
- Pre-launch app — no users to request features yet.
- Transactional one-time-use apps (ride-share, parking) — feature requests aren't a fit pattern.

**Apply targets.**
- Configure the invocation event for "request a feature" (often a menu item or a separate floating action).

**Style match.**
- None at the code level.

**What's left for you.**
- Review and respond to submissions on the dashboard as they arrive.
- Optional: status updates back to the requester via In-App Replies.

**Verification.**
- Submit a test feature request from the app.
- Open the dashboard's Feature Requests surface.

---

## In-App Replies

**Value.** Reply to user-submitted reports, requests, and surveys directly in-app — closes the loop with users without forcing them into email.

**Fit signals.**
- Support-conscious team (B2B, premium-tier consumer).
- `identifyUser` already wired (replies need a user identity).
- Push notification stack already present (improves reply delivery).

**Anti-signals.**
- No auth flow / `identifyUser` not wired → "Can be added later: when you wire identifyUser to your auth flow."
- High-volume consumer app with no support team to actually reply.

**Apply targets.**
- Hooks at `identifyUser` and logout sites (already covered by `luciq-setup` if those exist).
- Push notification setup (if not already present) for reply delivery.

**Style match.**
- None at the code level.

**What's left for you.**
- Push notification token registration with the SDK (see the in-app replies setup docs).
- Optional: reply templates on the dashboard.

**Verification.**
- Submit a test bug report identified as a known test user.
- Reply to the report from the dashboard.
- The reply should appear in-app on next foreground.
