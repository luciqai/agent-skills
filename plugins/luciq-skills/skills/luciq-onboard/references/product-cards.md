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
- **Sub-capabilities to offer in the same Ask (one extra line each, not separate products):**
  - **Report Categories** — propose a small custom taxonomy (e.g. "Checkout / Auth / Other") when the archetype has obvious user-facing surfaces. One enum + one config call.
  - **Extended Bug Report** — propose enabling when CLAUDE.md / README signals high-stakes debugging (compliance, regulated industry, support-load mention). Off by default — opt-in.
  - **Proactive Bug Reporting** — propose when a post-action moment exists in code (post-purchase, post-onboarding-complete). Single API call at that site.
- **Per-view privacy markers** on individual PII-bound views. Consume the `sensitive_views` list from the profile (built in Phase 1 Track B) and propose the platform-appropriate marker for each entry — see the platform marker table in `SKILL.md` Phase 1 Track B for the canonical syntax per platform.
  Follow the confirmation policy in SKILL.md Track B: confirm the first 3–5 views individually so the user sees the pattern, then batch-confirm the rest with a single question. Drop back to per-match if the user inspects a specific row. Reject-once-and-continue on false positives within both modes.
- Coarse screen-level fallback: if `sensitive_views` is empty or shallow (e.g. heavily generated UI), default the money path and auth screens to use the wrapper variant (`LuciqPrivateView { ... }` on iOS, `LuciqPrivateView(child: ...)` on Flutter / RN) at the screen root so the screen is masked even before per-view enumeration catches up.

**Style match.**
- If Sentry / Bugsnag / etc. has `attachScreenshot: false` → recommend Luciq screenshot capture off as default.
- If competitor restricts to release builds only → mirror that gating.
- If a competitor declares **view-level masking** (Sentry replay `mask` tag, UXCam `occludeSensitiveView`, Smartlook `registerBlacklistedView`, Datadog `privacy` markers), translate the *same view set* to Luciq's per-view markers above. The user's team has already decided what's sensitive — mirror their decision, don't relitigate it.
- If `accessibility_posture` (from Phase 1 Track B) is **"strong"** → default the invocation to the **floating button** alongside (or instead of) shake. Cite the team's a11y identifier usage (file:line of one example) as evidence in the Ask. Reason: shake invocation is hostile to motor-impaired users — the floating button is operable via VoiceOver, switch control, and keyboard. If posture is **"partial"**, mention both options in the Ask and let the user pick. If **"absent"**, default per platform without comment.

**What's left for you.**
- Nothing required — reports start arriving on next launch.
- Optional: configure custom report attributes (app version, user tier, env) on the dashboard.
- If `locales.count > 1` (Track E5), provide localized prompt text for each of `<list locales from profile>` on the dashboard so the invocation hints, comment placeholder, and submit-button labels match the user's chosen language.
- **Deep PII / masking audit** (auto-mask types at SDK init, network mask key list, consent gating, grayscale, FLAG_SECURE, SSUI `isPrivate`, compliance-framework presets, pre-prod checklist) → run `luciq-pii` when you're ready. The per-view markers proposed above are layer 1 of 3; `luciq-pii` covers the rest.

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
- Any production app needs reliable crash reporting — universal fit.
- CLAUDE.md / README mentions stability, crash-free rate, or a recent incident → MUST.

**Anti-signals.**
- Dual crash handler conflict already surfaced in Phase 2 — don't add a third capturer before the user resolves the first two. (This is about an unresolved *conflict*, not about competitor presence.)

**Existing competitor context (mention in Ask, never defer).**
- If a competitor crash reporter is active (Sentry, Firebase Crashlytics, Bugsnag, Embrace), name it honestly in the Ask. Example phrasing:
  > *"You already run `<SDK>` for crashes at `<file:line>`. Luciq Crash differentiates on session-context-rich repro steps and replay-linked crashes — worth adding alongside, evaluating as a swap, or staying on `<SDK>`. Your call."*
- Do not move Crash Reporting out of "Recommended now" because a competitor is present. The customer decides whether to adopt, swap, or stay. See SKILL.md Operating Principle 6.

**Apply targets.**
- Generally nothing beyond the SDK init from `luciq-setup` — crash reporting is on by default for Luciq.
- If symbolicated stack traces matter, propose adding the Luciq CLI to CI for dSYM / ProGuard mapping upload. When `ci_system` is detected (Track E1), propose a specific diff to the primary workflow file / Fastlane lane / Bitrise step — not a generic "see the CLI docs" pointer. When `ci_system` is `none`, fall back to the doc pointer in *What's left for you*.
- If `ci_system.env_matrix` shows multiple build configs (debug / staging / release), propose env-gated app tokens at the SDK init site instead of a hardcoded string.

**Style match.**
- If competitor crash reporter gates init on release stage only → mirror.

**What's left for you.**
- dSYM (iOS) / mapping file (Android) upload step in CI for symbolicated stack traces — see the CLI setup docs.
- Optional: custom keys / metadata on crash reports.
- If your app handles regulated data (PHI, PCI, EU user data), run `luciq-pii` to audit what may end up in crash payloads (thread state, captured network logs, repro-step screenshots) — crash capture is opt-out for the same surfaces masking covers.

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
- Hobby app or one-screen utility — APM adds noise without value.

**Existing competitor context (mention in Ask, never defer).**
- If a competitor APM (Datadog RUM, New Relic Mobile, Sentry perf, Firebase Performance) is active, name it in the Ask. Example phrasing:
  > *"You already run `<SDK>` for perf at `<file:line>`. Luciq APM differentiates on money-path Apdex tied to user reports — worth adding alongside or evaluating as a swap. Your call."*
- Do not move APM out of "Recommended now" because a competitor is present. The customer decides. See SKILL.md Operating Principle 6.

**Apply targets.**
- Auto-screen tracking on, matched to competitor's posture (sample rate, env gating).
- Network logging on, with masking from the profile (headers like Authorization, body fields like password / token / card).
- Configure tracked hosts from `network_client.base_urls` (Track E3). Propose `Luciq.setNetworkHosts([...])` populated with the actual host list — no guessing, no generic placeholder. If E3 found no client, fall back to asking the user once.
- Apply network-header masking at the interceptor / adapter site recorded in `network_client.init_file_line` so masks live next to existing request logic, not in a separate config block.

**Style match.**
- Sample rate inheritance: if Sentry `tracesSampleRate: 0.1`, propose Luciq APM at 10% on screens, 100% on the money path.
- App-hang threshold inheritance: if Sentry `appHangTimeoutInterval: 1.5`, mirror.

**What's left for you.**
- Optional: custom traces / spans for business-critical flows (cart checkout, payment confirmation).
- Optional: Apdex threshold tuning on the dashboard once you have data.
- **Network-mask key list** — Luciq auto-masks a default set of headers and query params (`authorization`, `password`, `api_key`, `client_secret`, etc.) starting SDK 14.2.0. If your API uses custom sensitive headers (`x-patient-id`, `x-stripe-customer`, `x-org-token`), they need to be added server-side via Luciq support. Run `luciq-pii` to enumerate the candidates and prep the support ticket.
- **Deep PII / network audit** (auto-mask types, full network key review, manual obfuscate / omit on sensitive endpoints, compliance presets) → run `luciq-pii`.

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
- **Per-view privacy markers** on individual PII-bound views — same `sensitive_views` list from the profile that Bug Reporting consumed; if Bug Reporting was already in the walk, those markers are already in place and this is a no-op. If Session Replay is being added without Bug Reporting, apply the per-view markers now following the confirmation policy in SKILL.md Track B (first 3–5 individual, rest batch-confirm).
- Coarse per-screen masking as a fallback layer: money path screen and auth screen wrapped in the screen-root marker variant (e.g. `LuciqPrivateView { CheckoutView() }` on iOS) so the entire screen masks even if enumeration missed a view.
- Sample rate: inherit from competitor if a replay-capable competitor exists, otherwise default per the live setup guide.
- **Mention but do not configure: device-tier auto-throttling on Android** (~30% capture on low-end, ~60% mid, 100% high-end; navigation-mode fallback on low-end). Surface in the Summarize block so the user knows replay self-protects performance — not a knob the skill tunes.

**Style match.**
- Sentry `replaysSessionSampleRate: 0.05` → propose Luciq replay at 5%.
- Competitor's masking tag pattern → translate to Luciq's masking API.

**What's left for you.**
- Review masking when you add new screens with sensitive UI.
- Optional: per-screen replay disable on screens you never want recorded.
- **Deep PII / masking audit** (auto-mask types, network masking, consent gating, grayscale, FLAG_SECURE, SSUI `isPrivate`, compliance presets) → run `luciq-pii`. Session Replay is the highest-PII-surface product; running the deep audit is recommended **before going to production** if your app handles regulated data (PHI, PCI, EU user data).
- If GDPR / CCPA applies and you don't already have consent gating, surface it explicitly in the Summarize block: *"Session Replay is currently unconditional — under GDPR / CCPA you'll want a consent gate before going live. Run `luciq-pii` to add it."*

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
- `distribution_model.primary` (Track E4) is `testflight-only` / `firebase-appdist` / `internal` / `unknown` with no store channels active → defer until launch.
- Internal-only / one-time-use utility → defer.
- Very low DAU — survey responses won't be statistically useful yet.

**Apply targets.**
- Nothing in code beyond the SDK presence — surveys are configured on the dashboard.
- If push notification setup exists, mention that survey delivery can use it.
- **Soft dependency: `identifyUser` + custom user attributes.** Attribute-based targeting (user tier, plan, region) only works if those attributes are set in code. If the auth flow file:line is known, propose adding the relevant `setUserAttribute` calls there; otherwise note the limitation in Summarize.

**Style match.**
- None at the code level — surveys are dashboard-configured.

**What's left for you.**
- Build your first survey on the dashboard (link to surveys docs).
- Targeting rules: event-triggered or attribute-based. Decide post-purchase, post-onboarding, or NPS-style anchor.
- If `locales.count > 1` (Track E5), write locale-aware survey copy for each of `<list locales from profile>` on the dashboard. Single-locale apps can skip this.

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
- `distribution_model.primary` (Track E4) is not `appstore` or `playstore` — no store presence to push ratings toward → frame as "Can be added later: when you launch publicly on the store."
- `distribution_model.primary` is `testflight-only` / `firebase-appdist` / `enterprise` / `internal` → defer until public store launch with the same framing.
- Pre-launch — no signed builds in CI yet.

**Apply targets.**
- Suggest the SDK call site(s) for trigger events — derived from the positive-event surfaces detected in the profile.
- Configuration of *when* to actually prompt lives on the dashboard.

**Style match.**
- None at the code level.

**What's left for you.**
- Configure trigger rules on the dashboard (link to ratings docs) — typically gated on time-since-install + happy-event count.
- If `locales.count > 1` (Track E5), the dashboard splits ratings per locale automatically — mention so the user knows where to find the per-locale breakdowns.

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
- Push notification wiring at `push_token_site` (Track E2). If detected, propose a `Luciq.setPushNotificationToken(token)` call immediately after the existing token acquisition — concrete diff, not a doc pointer. If not detected, leave the push integration as a *What's left for you* item — replies still work via in-app notification → email fallback.

**Style match.**
- None at the code level.

**What's left for you.**
- Push notification token registration with the SDK (see the in-app replies setup docs).
- Optional: reply templates on the dashboard.

**Verification.**
- Submit a test bug report identified as a known test user.
- Reply to the report from the dashboard.
- The reply should appear in-app on next foreground.

---

## Feature Flags

**Value.** Attach the experiment variants your app is running to every crash, hang, performance metric, and bug report — so when something breaks, you know *which variant* broke it.

**Fit signals.**
- A third-party experimentation SDK is active (LaunchDarkly, Statsig, Optimizely, Firebase Remote Config, Amplitude Experiment, GrowthBook). The user already evaluates flags — Luciq just attributes the outcome.
- CLAUDE.md / README mentions experiments, A/B tests, gradual rollouts, holdouts, multivariant onboarding.
- Workspace precedent: another Luciq app in the workspace already uses Feature Flags.

**Anti-signals.**
- Pre-launch app with no experiments running.
- No experimentation SDK detected and no mention of experiments — no inputs to attribute.

**Apply targets.**
- At each flag-evaluation site detected in code, propose a follow-up `Luciq.addFeatureFlag({ name, variant })` call so Luciq sees the same assignment the user's experimentation SDK made. Show one diff per site, confirm per-site — never bulk-apply.
- At sign-out or session-reset sites, propose `Luciq.removeAllFeatureFlags()` so a logged-out session doesn't inherit stale variants.
- Boolean flags: `Luciq.addFeatureFlag({ name })` (no variant).

**Style match.**
- If the experimentation SDK gates by environment (debug excluded), mirror that — only add Luciq flag attribution where the user's own SDK is also evaluating.

**What's left for you.**
- On the dashboard, the Feature Flags surface will show crash-free rate, Apdex, and per-variant breakdowns once data flows.

**Verification.**
- Trigger a known flag evaluation in the app, then trigger a test crash or submit a test report.
- On the dashboard, open the report — the active variants should be attached as attributes.

---

## APM Flows

**Value.** Track the completion rate, drop-off cause, and P50/P95 duration of the multi-step user journeys that actually matter — checkout, signup, onboarding — not just isolated screens.

**Fit signals.**
- Money path identified in the profile, with at least two screens between entry and success (e.g. `CartView → CheckoutView → ConfirmationView`).
- Archetype is e-commerce, fintech, or any app with a clear funnel.
- CLAUDE.md / README mentions conversion, funnel, drop-off, completion rate.
- APM is being adopted in the same session (Flows is an APM sub-feature — recommending it without APM is incoherent).

**Anti-signals.**
- Single-screen utility or hobby app — no meaningful journey.
- APM not being adopted this session → defer with revisit condition *"when you adopt APM."*

**Apply targets.**
- `Luciq.startFlow(name)` at the journey entry point (e.g. cart view appearance).
- `Luciq.endFlow(name)` at the success terminus (e.g. confirmation view appearance), and at known abandonment points if any.
- Flow names follow the user's existing screen-naming convention (don't invent new vocabulary — match what their navigation already calls these screens).
- One flow at a time per name — verify no parallel `startFlow` with the same name is possible in the proposed instrumentation.

**Style match.**
- If the user's competitor APM (Datadog RUM, Sentry perf) has custom transactions defined, name Luciq flows after the same transactions where they overlap — keeps the team's mental model consistent.

**What's left for you.**
- On the dashboard's APM > Flows surface, configure Apdex thresholds for each flow once you have a few days of data.

**Verification.**
- Run the instrumented flow end-to-end in the app (e.g. complete a test checkout).
- The flow should appear on the Flows surface within ~1 minute with one completion logged.

**Hard prereq.**
- SDK v13.0.0 or later. If the user is on an older SDK, defer with revisit condition *"after upgrading to SDK v13+."*
