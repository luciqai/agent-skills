# iOS — what Luciq changes on the App Store privacy card

Apple rejects apps whose App Privacy answers ("nutrition label") don't match what the binary collects. Adding Luciq changes that answer, and some SDK switches change it further. Setup must tell the user what to declare — it is a hand-off item, not something the agent can submit.

This is guidance for the developer, not legal advice. The final answers belong to whoever owns the app's App Store listing.

## Step 1 — read the SDK's own manifest

The SDK ships a privacy manifest. Read it from the installed package rather than quoting a table — the declared types and their *linked* flags change between SDK versions.

```bash
M=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 10 -name PrivacyInfo.xcprivacy \
      -path '*luciq-ios-sdk*ios-arm64/*' | head -1)
plutil -convert json -o - "$M" | python3 -c '
import json,sys
for t in json.load(sys.stdin)["NSPrivacyCollectedDataTypes"]:
    print(t["NSPrivacyCollectedDataType"].replace("NSPrivacyCollectedDataType",""),
          "linked" if t["NSPrivacyCollectedDataTypeLinked"] else "not linked",
          "tracking" if t["NSPrivacyCollectedDataTypeTracking"] else "")'
```

(CocoaPods: look under `Pods/` instead of DerivedData. If several projects match, use the one whose DerivedData folder belongs to this app.) It declares nine types, none used for tracking: Other Diagnostic Data, Performance Data, Crash Data, Product Interaction, Photos or Videos, Audio Data, Name, Email Address, User ID. **The linked flags differ by version** — 19.8.1 and 19.10.1 mark only Name, Email Address and User ID as linked; 19.11.0 marks all nine linked. Quote the installed file, never this paragraph.

The manifest declares everything the SDK *can* collect. What the app must answer on App Store Connect depends on what is actually turned on — step 2.

## Step 2 — map what's enabled to what to declare

| Enabled in this integration | App Privacy type | Linked to the user when… |
|---|---|---|
| SDK started at all (device, OS, logs) | Other Diagnostic Data | `identifyUser` is called |
| Crash reporting (on by default) | Crash Data | `identifyUser` is called |
| APM | Performance Data | `identifyUser` is called |
| Repro steps / user steps, Session Replay | Product Interaction | `identifyUser` is called |
| Bug-report screenshots, screen recording, repro-step screenshots, Session Replay screenshots | **Photos or Videos** | `identifyUser` is called |
| Voice notes in bug reports | Audio Data | `identifyUser` is called |
| Email field on the bug-report form (shown by default) | **Email Address** | always — the reporter typed it |
| `Luciq.identifyUser(withID:email:name:)` | User ID / Email Address / Name — whichever arguments are non-nil | always |

The two that surprise people:

- **Screenshots mean Photos or Videos.** Enabling repro-step screenshots (`Luciq.setReproStepsFor(.all, with: .enable)`) or Session Replay means the app now collects images of its own screens. For an app whose screens show names, balances or health data, that is a material disclosure — auto-masking reduces what the images contain, it does not remove the category.
- **The email field means Email Address, linked.** The bug-report form asks for an email by default. An app that says "no accounts, we don't collect email" contradicts itself the moment a reporter types one.

## Step 3 — offer the switches that shrink the list

Verified against LuciqSDK 19.11.0 (check them with *Check symbols against the SDK* on other versions). Offer each one; apply only what the user picks.

| To stop declaring… | Switch |
|---|---|
| Email Address (from bug reports) | `BugReporting.bugReportingOptions = [.emailFieldHidden]` — `.emailFieldOptional` still collects it when typed |
| Photos or Videos (repro steps) | `Luciq.setReproStepsFor(.all, with: .enabledWithNoScreenshots)` |
| Photos or Videos (attachments) | `BugReporting.enabledAttachmentTypes = []` and `BugReporting.autoScreenRecordingEnabled = false` — the report form then has no screenshot |
| Photos or Videos (Session Replay) | `SessionReplay.enabled = false` |
| Name / Email linked via identify | pass only an opaque ID: `Luciq.identifyUser(withID: id, email: nil, name: nil)` |
| Audio Data | no client switch in the 19.11.0 headers — keep declaring it while Bug Reporting is on, or ask Luciq support |

Switches that reduce *what is inside* the images but don't remove the category: `Luciq.setAutoMaskScreenshots([.textInputs, .labels, .media])`, `.luciq_privateView()` / `LuciqPrivateView { … }` in SwiftUI, `view.luciq_privateView = true` in UIKit.

## Usage-description strings

Keep `NSMicrophoneUsageDescription` and `NSPhotoLibraryUsageDescription` while Bug Reporting is enabled: voice notes and gallery attachments have no client-side off switch in 19.11.0, and iOS terminates an app that touches the microphone or photo library without the matching string. Write them in the app's voice — e.g. *"Record a voice note to attach to your bug report."*

## What goes in the hand-off

A short block, in plain words:

> **App Store privacy — update before your next submission.** With what we turned on, declare: Crash Data, Performance Data, Other Diagnostic Data, Product Interaction, Photos or Videos, Audio Data[, Email Address]. [Linked to the user: yes/no.] To check what's in your binary: Xcode → Organizer → your archive → *Generate Privacy Report*.

List only the rows that apply, and name any switch the user chose to leave on that keeps a sensitive type (usually Photos or Videos, or Email Address).
