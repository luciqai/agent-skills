# Auto-Mask Screenshot Types

The first layer of defense: a blanket rule applied to every screenshot the SDK captures. Pairs with per-view markers (precise) and the network layer (different surface). All three layers together = defense in depth.

Verify exact constant names, method signatures, and platform defaults against the live setup guides — the SDK evolved through the Instabug→Luciq rebrand and constants may differ across versions.

## Constants

| Constant | What it masks |
|---|---|
| `MASK_NOTHING` | Disables all automatic masking. Choose only when every sensitive view is individually marked and the team accepts that gap. |
| `TEXT_INPUTS` | Every text input field — `EditText` / Compose `TextField`, iOS `UITextField` / `UITextView`. Most common default. |
| `LABELS` | Every text label / static text — `TextView` / Compose `Text`, iOS `UILabel`, SwiftUI `Text`. Adds coverage for read-only PII (name, email shown back to the user). |
| `MEDIA` | Every image / media view — `ImageView` / Compose `Image`, iOS `UIImageView`, SwiftUI `Image`. Choose when user content includes uploaded images / documents / IDs. |
| `WEB_VIEWS` | Every `WebView`. Keep on when any embedded web content can render user data. |

## Per-platform API

### Android / cross-platform

```kotlin
Luciq.setAutoMaskScreenshotsTypes(
    MaskingType.TEXT_INPUTS,
    MaskingType.LABELS,
    MaskingType.WEB_VIEWS   // keep WebView default on when overriding
)
```

When overriding, **include every type that should remain masked** — the call is a full replacement, not additive. Forgetting `WEB_VIEWS` when it was previously on creates a silent leak.

### iOS (Session Replay)

```swift
SessionReplay.autoMaskScreenshotOptions = [.textInputs, .labels]
```

### React Native

Follow the live RN setup guide — option-set name and call site differ between Instabug-legacy and Luciq RN packages.

### Flutter

Follow the live Flutter setup guide — same caveat.

## Recommended pairings by archetype

The skill proposes one of these in Phase 3 / 4, then cites the archetype as the reason. Always offer the customer the chance to upgrade aggressiveness; never silently downgrade.

| Archetype | Minimum | Recommended | Maximum |
|---|---|---|---|
| **Hobby / utility** | `TEXT_INPUTS` (platform default) | `TEXT_INPUTS` | — |
| **B2B / productivity** | `TEXT_INPUTS` | `TEXT_INPUTS + LABELS` | + `WEB_VIEWS` if embedded web |
| **Consumer social / media** | `TEXT_INPUTS` | `TEXT_INPUTS + LABELS` | + `MEDIA` if user uploads |
| **E-commerce** | `TEXT_INPUTS + LABELS` | `TEXT_INPUTS + LABELS + WEB_VIEWS` | + `MEDIA` for receipts / IDs |
| **Fintech** | `TEXT_INPUTS + LABELS + WEB_VIEWS` | All four types | All four + per-view markers on PAN/CVV/IBAN |
| **Healthcare (HIPAA)** | `TEXT_INPUTS + LABELS + MEDIA` | All four types | All four + per-view markers on every PHI surface + consent gating |

## Per-view marker APIs (for cross-reference)

Auto-mask is the blanket layer; per-view markers are the precise layer. The marker APIs the audit cites:

| Platform | Mark private | Unmark | Clear all |
|---|---|---|---|
| iOS UIKit | `view.ibgPrivate = true` | `view.ibgPrivate = false` | — |
| iOS SwiftUI | `view.luciqPrivate()` | — (recompose without modifier) | — |
| Android Views | `Luciq.addPrivateViews(v1, v2)` | `Luciq.removePrivateViews(v)` | `Luciq.removeAllPrivateViews()` |
| Android Compose | `Modifier.luciqPrivate(isPrivate = true)` | `Modifier.luciqPrivate(isPrivate = false)` | — |
| React Native | `Luciq.addPrivateViews([ref1, ref2])` | (re-add without the ref) | — |
| Flutter | `SessionReplay.addPrivateViews([key1, key2])` | (re-add without the key) | — |

The marker works on any view reference — including views inflated at runtime from server JSON — with no compile-time annotation, manifest entry, or XML attribute required. Marking a `ViewGroup` or Compose parent automatically masks every descendant.

## How auto-mask combines with per-view markers

The reference document's §2.4 behavior matrix (paraphrased):

| Auto-mask configured | View marked private | Result |
|---|---|---|
| Yes | Yes | Masked |
| Yes | No | Masked **if view type is in auto-mask set**, otherwise not |
| No | Yes | Masked (the view is masked regardless) |
| No | No | Not masked |

Key inference for audits: **a view of a non-covered type with no per-view marker is not masked.** A `TEXT_INPUTS`-only config does nothing for a SwiftUI `Text` rendering a credit card number. Per-view markers fill the gap precisely; auto-mask catches what the team forgot.

## Platform support matrix

Use this in Phase 2 recap when stating what's available on the user's platform. "n/a" means the concept doesn't apply on that platform, not that it's missing.

| Capability | iOS | Android | Flutter | React Native |
|---|---|---|---|---|
| Auto type-based screenshot masking | Yes | Yes | Yes | Yes |
| Manual private views | Yes | Yes | Yes | Yes |
| Compose / SwiftUI modifier | Yes (SwiftUI) | Yes (Compose) | n/a | n/a |
| Auto network header/query masking | Yes | Yes | Yes | Yes |
| Manual network obfuscate / omit | Yes | Yes | Yes | Yes |
| Grayscale screenshot mode | Yes | Yes | Yes | Yes |
| Secure-window control (FLAG_SECURE) | n/a | Yes | n/a | n/a |
| Private views in **video recording** | **No** | **No** | **No** | **No** |

## What auto-mask does NOT do

- **Network logs.** Different surface — see `network-masking.md`.
- **Video recording.** Per-view masking is not supported for video recording on any platform; auto-mask types don't change that.
- **Server-side data.** Masking is client-side; once a value leaves the device unmasked, it stays unmasked.

State these explicitly in the Apply summary when you turn on auto-mask, so the user doesn't infer broader coverage than what's actually configured.
