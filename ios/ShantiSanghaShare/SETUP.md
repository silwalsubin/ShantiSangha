# ShantiSanghaShare — Xcode target setup

Files already scaffolded in this folder:

- `ShareViewController.swift` — no-UI handler that grabs text/URL/image,
  writes to the App Group, opens `shantisangha://share`, then exits.
- `Info.plist` — accepts text + web URLs + web pages + a single image.
  Wires `NSExtensionPrincipalClass` to `ShareViewController` (no storyboard).
- `ShantiSanghaShare.entitlements` — App Group only.

The Xcode project (`ShantiSangha.xcodeproj`) does **not** yet contain
a Share Extension target. Add it once, then build & run on a real
device or simulator that supports the Share Sheet.

## One-time setup in Xcode

1. Open `ios/ShantiSangha.xcodeproj`.
2. **File → New → Target…** → iOS → **Share Extension**.
3. Fill in:
   - Product Name: `ShantiSanghaShare`
   - Bundle Identifier (after creation): `com.shantisangha.app.ShantiSanghaShare`
   - Language: Swift
   - Embed in: `ShantiSangha`
   - Activate scheme: No (keep main app scheme primary)
4. Click **Finish**. Xcode will generate a `ShantiSanghaShare/` group with
   `ShareViewController.swift`, `MainInterface.storyboard`, `Info.plist`.
5. **Replace Xcode's generated files with the scaffolded ones:**
   - In Finder, delete Xcode's generated `ShareViewController.swift`,
     `MainInterface.storyboard`, and `Info.plist` from
     `ios/ShantiSanghaShare/`. Empty the trash.
   - In Xcode's Project Navigator, the three rows will turn red. Remove
     them (right-click → Delete → Remove Reference).
   - Drag the existing `ShareViewController.swift` and `Info.plist`
     from this folder back into the `ShantiSanghaShare` group, target =
     `ShantiSanghaShare` only.
6. **Build settings on the `ShantiSanghaShare` target:**
   - Set `Info.plist File` (`INFOPLIST_FILE`) →
     `ShantiSanghaShare/Info.plist`
   - Turn off `Generate Info.plist File` (`GENERATE_INFOPLIST_FILE = NO`)
   - Set `iOS Deployment Target` to match the main app
7. **Capabilities → Signing & Capabilities → ShantiSanghaShare target:**
   - Click **+ Capability → App Groups**
   - Check `group.com.shantisangha.app` (same group the main app + widget use)
   - Set the entitlements file path on the target to
     `ShantiSanghaShare/ShantiSanghaShare.entitlements` (you can drop the
     file Xcode auto-created and point Build Settings →
     `CODE_SIGN_ENTITLEMENTS` at the scaffolded one).
   - Confirm the team / signing certificate matches the main app.
8. **General → Frameworks and Libraries** on the main `ShantiSangha`
   app target: the wizard will already have added
   `ShantiSanghaShare.appex` under **Embed Foundation Extensions**.
   Confirm it's there.
9. Build & run the main app on device or simulator.

## Testing

- In Safari, long-press a paragraph → **Share** → scroll the share sheet
  to **More**, enable **ShantiSangha**.
- Pick **ShantiSangha** from the share sheet. The main app should open,
  and the assistant chat composer should already contain the shared
  text. Tap send (or edit first — e.g. add "make this a reminder for
  next Friday").

## Notes

- Text and URLs work end-to-end. **Images** are accepted (so we show
  up in Photos' share sheet) but the assistant chat is text-only for
  now — sharing a photo currently drops a `[shared image]` breadcrumb
  in the composer that the user can replace with a description. Real
  image-in-chat needs a multimodal pass on the backend.
- The share extension does not require the user to be signed in; the
  text is only handed off to the main app, which already enforces
  auth.
- Shared payloads sitting in the App Group older than 1 hour are
  discarded on next launch (see `DeepLinkRouter.staleAfter`).
