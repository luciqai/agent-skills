# iOS — keeping the app token out of source control

The token must never be a string literal in Swift. On iOS the working path has three links, and the obvious shortcut breaks silently.

```
Config/Luciq.xcconfig   (gitignored)   LUCIQ_APP_TOKEN = <token>
        │  base configuration of the app target
        ▼
Info.plist  (a real file)              LuciqAppToken = $(LUCIQ_APP_TOKEN)
        │
        ▼
Bundle.main.object(forInfoDictionaryKey: "LuciqAppToken")
```

## The trap: `INFOPLIST_KEY_<Custom>`

In projects with `GENERATE_INFOPLIST_FILE = YES` it is tempting to add `INFOPLIST_KEY_LuciqAppToken = $(LUCIQ_APP_TOKEN)`. Xcode only injects `INFOPLIST_KEY_` settings for keys it recognises, so a custom key is **dropped with no warning** — the build is green and the token is missing at runtime. A custom key needs a real `Info.plist` file. Xcode still merges the generated keys into it.

## Wire it with the script

```bash
ruby <skill-dir>/scripts/add_token_config.rb --project <App>.xcodeproj --target <AppTarget>
```

Xcode must be closed (same reason as the package script). The script:

- creates `Config/Luciq.xcconfig` with an empty `LUCIQ_APP_TOKEN =` and a committed `Config/Luciq.xcconfig.example`;
- adds `Config/Luciq.xcconfig` to `.gitignore`;
- sets it as the target's base configuration — or, if the target already has one (CocoaPods does this), adds `#include? "…/Luciq.xcconfig"` to that file. `#include?` means a missing file is not a build error, so a fresh clone still builds, with an empty token;
- adds `LuciqAppToken = $(LUCIQ_APP_TOKEN)` to the target's `Info.plist`, creating `Config/Info.plist` and pointing `INFOPLIST_FILE` at it when the project had none. `Config/` sits outside the app folder, so an Xcode 16 synchronized folder won't also copy it in as a resource.

It never takes the token. Put the value in `Config/Luciq.xcconfig` yourself (the user gave it to you, or it came from `list_applications`), with a single edit to that file only.

If the script can't run, STOP and give the user these steps to do in Xcode; don't hand-edit `project.pbxproj`.

## Read it at the entry point

```swift
import LuciqSDK

let token = Bundle.main.object(forInfoDictionaryKey: "LuciqAppToken") as? String ?? ""
if token.isEmpty || token.hasPrefix("$(") {
    assertionFailure("Luciq token missing — fill in Config/Luciq.xcconfig")
} else {
    Luciq.start(withToken: token, invocationEvents: [.shake, .floatingButton])
}
```

`hasPrefix("$(")` catches an `Info.plist` whose variable was never expanded.

## CI

CI writes the file from a secret before building:

```bash
echo "LUCIQ_APP_TOKEN = $LUCIQ_APP_TOKEN" > Config/Luciq.xcconfig
```

## Gotcha

`//` starts a comment in `.xcconfig`. Luciq app tokens are hex, so this doesn't bite — but don't reuse this file for URLs without escaping them as `https:/$()/…`.
