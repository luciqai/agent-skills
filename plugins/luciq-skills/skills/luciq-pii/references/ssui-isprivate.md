# Server-Driven UI: `isPrivate` Flow

In server-driven UI apps, the view tree is inflated at runtime from server JSON. There's no compile-time surface to annotate. The pattern below is the reference document's §6 recommendation, restructured as an audit-applyable checklist.

## When this section applies

Track E detected one or more SSUI inflate sites — patterns like `inflateFromJson`, JSON-driven `RemoteConfig` UI, `View` factories that consume server payloads, or in React Native: a remote-rendered component system.

If no SSUI is detected, skip this section entirely — don't propose the pattern speculatively.

## The five-step pattern

1. **Extend the SSUI schema with an `isPrivate` boolean** on every node type that can render PII. Server controls per-node sensitivity at deploy time without an app release.
2. **At render time, after a node is inflated**, mark the resulting view private if `node.isPrivate` is true. Platform-specific:
   - **iOS UIKit**: `view.ibgPrivate = true`
   - **iOS SwiftUI**: `view.luciqPrivate()` modifier
   - **Android Views**: `Luciq.addPrivateViews(view)` (pair with `Luciq.removePrivateViews(view)` when the node leaves the screen, or `Luciq.removeAllPrivateViews()` on teardown)
   - **Android Compose**: `Modifier.luciqPrivate(isPrivate = node.isPrivate)`
   - **React Native**: `Luciq.addPrivateViews([viewRef])` keyed off `node.isPrivate`
   - **Flutter**: `SessionReplay.addPrivateViews([widgetKey])` keyed off `node.isPrivate`
3. **Add a global safety net at SDK init** — appropriate auto-mask types per `auto-mask-types.md`. A forgotten flag on a single node still can't leak when the safety net catches the type.
4. **Verify in a dev build** that masked regions render as solid blocks in repro-step screenshots and Session Replay frames.
5. **Gate the SSUI render path behind a feature flag** (ideally per app version) so a bad server payload can be turned off without an app release.

## Example server-controlled node

```json
{
  "type": "text",
  "value": "4111 2222 3333 4444",
  "style": "card-number",
  "isPrivate": true
}
```

## Client handling when inflating the node

```kotlin
// Android Views
val view = inflateFromJson(node)
if (node.isPrivate) {
    Luciq.addPrivateViews(view)
}
```

```kotlin
// Android Compose
Text(
    text = node.value,
    modifier = Modifier.luciqPrivate(isPrivate = node.isPrivate)
)
```

```swift
// iOS SwiftUI — at render time after inflate
let view = node.render()
return node.isPrivate
    ? AnyView(view.luciqPrivate())
    : AnyView(view)
```

```javascript
// React Native — after inflate, mark by ref
const ref = useRef(null);
useEffect(() => {
    if (node.isPrivate && ref.current) {
        Luciq.addPrivateViews([ref.current]);
    }
}, [node.isPrivate]);
return <RenderedNode ref={ref} {...props} />;
```

```dart
// Flutter — after inflate, mark by widget key
final key = GlobalKey();
if (node.isPrivate) {
    SessionReplay.addPrivateViews([key]);
}
return RenderedNode(key: key, ...);
```

## Audit checklist (used in Phase 4)

For each SSUI inflate site Track E found, the audit walks:

1. **Schema review** — does the SSUI node schema already have an `isPrivate` field? If yes, proceed; if no, surface as a "Close now (requires server change): extend SSUI schema."
2. **Inflate-site instrumentation** — propose the per-platform marker call as a diff at the inflate site. Show before applying.
3. **Safety net** — verify the SDK init has appropriate `setAutoMaskScreenshotsTypes` per archetype. If missing, propose as a separate Phase 4 item (see `auto-mask-types.md`).
4. **Dev-build verification** — added to Phase 5 verification steps when SSUI was instrumented this session.
5. **Render-path feature flag** — verify in passing; if absent, surface as a "monitor" item, not a "close now" — feature flags for rollout safety are an architectural choice, not strictly a PII issue.

## When the server payload itself is unsafe

If the server already shipped values like the card number above in plain text — meaning the value is in the SSUI payload itself, not just rendered — the apply step is **not** sufficient. Masking applies to the rendered view; the raw JSON payload still passes through the app's runtime memory and any network capture below Luciq's mask layer.

Surface honestly:

> *"The SSUI payload contains `4111 2222 3333 4444` as a string value. Per-view masking will hide it in screenshots and replay frames, but the raw value is still in app memory and any custom logging. The cleaner fix is to send a tokenized reference (`"value_ref": "card_xyz"`) and resolve it on-device, with a per-view marker as defense-in-depth. Code-side, we can do the marker now; the schema change is a server conversation."*

Don't apply silently and call it done.
