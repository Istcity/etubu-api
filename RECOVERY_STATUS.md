# ETUBU Recovery Status (2026-07-30)

Project was wiped; only an empty `.git` remained (no commits, no remotes).

## What was searched

| Avenue | Result |
|--------|--------|
| APFS local snapshots (`tmutil`) | **None** |
| Time Machine / `.MobileBackups` | **Not available** |
| Trash | **Permission denied / empty for etubu** |
| `find` / Spotlight for `EtubuClusterPresenter.swift` | **Not on disk** (before restore) |
| `App.xcworkspace` anywhere | **Not found** |
| Git objects in `/Users/sinan/Projects/etubu/.git` | **Empty** (no commits) |
| GitHub (`gh`) | **CLI not installed** |
| iCloud Drive | **No etubu project copy** |
| Cursor worktrees | **None found** |
| Cursor snapshot pack (`etubu-7becd670`, 37MB) | **Binary; no extractable `.swift` paths via strings** |

## What was recovered and restored under `/Users/sinan/Projects/etubu`

### Swift sources (36 files) — from Cursor agent transcripts
Extracted from `~/.cursor/projects/Users-sinan-Projects-etubu/agent-transcripts/` (Write tool calls + code citations).

Key files include:
- `ios/App/App/Cluster/EtubuClusterPresenter.swift`
- `ios/App/App/Cluster/EtubuClusterRootView.swift`
- `ios/App/App/Tesla/EtubuTeslaBleSession.swift`
- Full Cluster, Dashboard, OBD, Tesla, Widgets Swift modules

**Not recovered:** `EtubuPremiumGateView.swift` (mentioned but no full Write in transcripts).

### Web / Capacitor assets (129 files)
Copied from Xcode DerivedData built `Etubu.app/public/` → `public/`, `www/`, `ios/App/App/public/`.

Includes: `index.html`, all `js/`, `css/`, legal pages, audio assets metadata.

### Other files
- `capacitor.config.json` (from DerivedData build product)
- Fonts: `DMSans.ttf`, `Orbitron.ttf` (from DerivedData)
- `PrivacyInfo.xcprivacy`, `LaunchScreen.storyboard`, widget Assets JSON
- `ios/APP_STORE_CHECKLIST.md`, audio README/LICENSE

## IPA (`Etubu-1.0-build43-20260729-1713.ipa`)

- **Exists** on Desktop (61 MB).
- **Contains:** compiled binary, `public/` web bundle, Capacitor frameworks, widgets — **no Swift source**.
- Useful for: web JS/CSS/HTML/assets reference (same as DerivedData copy).

## Xcode artifacts still on disk (not source)

- **DerivedData** `App-bdhrhpufkpqynsfitabnkawkikjk`: built `.app`, `.swiftmodule`, SPM checkouts (`swift-tesla-ble`)
- **Archives**: many `EtubuWidgets` + one `ETUBU-1346-build3.xcarchive` (July 16)
- **Build log** `/tmp/etubu-build.log` (July 28): lists compile paths; project built before wipe

## Critical gaps — project will NOT build yet

1. **`ios/App/App.xcodeproj/project.pbxproj`** — not in transcripts as full file
2. **`ios/App/Podfile` / `Podfile.lock` / `Pods/`** — not recovered
3. **`package.json`** and root Capacitor/Node tooling
4. **Xcode workspace** `App.xcworkspace`
5. **Info.plist**, **Main.storyboard**, **Assets.xcassets** (images)
6. **1 Swift file:** `EtubuPremiumGateView.swift`
7. **Audio `.wav` loops** under `assets/audio/loops/` (README only)
8. **Git history** — none

## Estimated completeness

| Layer | Recovery |
|-------|----------|
| Native Swift logic | **~95%** (36/38 known files) |
| Web frontend (public/) | **~100%** (from last build) |
| Xcode/CocoaPods project | **~0%** |
| Git history | **0%** |
| **Overall rebuild viability** | **Partial** — Swift + web recoverable; must recreate Xcode project (or restore from backup elsewhere) |

## Recommended next steps

1. Recreate iOS shell: `npm init` + `@capacitor/core` + `npx cap add ios`, then merge restored Swift into `ios/App/App/`
2. Add SPM package `https://github.com/shoujiaxin/swift-tesla-ble`
3. Check TestFlight / App Store Connect for build 43 metadata
4. Install `gh` and search GitHub org for any pushed remote
5. Enable Time Machine for future protection

---

# Phase 2 — Project rebuild (2026-07-30, same day)

**Result: `** BUILD SUCCEEDED **`** for both `iphonesimulator` and `iphoneos` SDKs, scheme `Etubu`, workspace `ios/App/App.xcworkspace`.

## Key discovery: leftover DerivedData was a goldmine

Before rebuilding, `~/Library/Developer/Xcode/DerivedData/App-bdhrhpufkpqynsfitabnkawkikjk` (the last real build, July 28-30) still had:
- The **built `Etubu.app`** with a real (non-recovered) **`Info.plist`** — gave the exact bundle id, permission strings, background modes, URL scheme, orientations, `MinimumOSVersion 17.0`, Live Activity keys.
- **`embedded.mobileprovision`** → confirmed entitlements (`com.apple.developer.applesignin`, team id `R9VURFRPRC`) needed for Sign in with Apple.
- **`SourcePackages/checkouts/swift-tesla-ble`** — the **exact pinned SPM checkout** (tag `v1.0.0`, commit `68696f6`) used by the last successful build, which let me verify the restored `EtubuTeslaBleSession.swift` calls match the real package API (`TeslaVehicleClient`, `KeychainTeslaKeyStore`, `KeyPairFactory`, etc.) instead of guessing.
- Confirmed target/product name was **`Etubu`** (not `App`) — `App.xcodeproj` is just the project filename; the actual scheme/product/module is `Etubu`, and the widget extension target is `EtubuWidgets`.

## What was created

- **`package.json`** — Capacitor 8.4.2 core/cli/ios + `@capacitor/app`, `@capacitor/geolocation`, `@capacitor/haptics`, `@capacitor/splash-screen`, `@capacitor/status-bar` (matches `capacitor.config.json` `packageClassList`). `npm install` run, `node_modules/` present.
- **`ios/App/App.xcodeproj` + `App.xcworkspace` + `Podfile` + `Pods/`** — scaffolded via `npx cap add ios --packagemanager Cocoapods` in a scratch dir, then merged in. Target renamed `App` → **`Etubu`** (product name follows via `$(TARGET_NAME)`), deployment target bumped to iOS **17.0** everywhere, Podfile target renamed to match, `pod install` re-run successfully.
- **`ios/App/App/Info.plist`** (real, text — replaces the old binary `Info.plist.recovered`, which was deleted) — rebuilt from the DerivedData-extracted built plist, stripped of build-only keys (`DT*`, `BuildMachineOSBuild`, `CFBundleIcons*` — Xcode auto-generates those from the asset catalog), keeps all real permission strings, `UIBackgroundModes`, `NSSupportsLiveActivities(FrequentUpdates)`, fonts, orientations, URL scheme.
- **`ios/App/App/App.entitlements`** — new, `com.apple.developer.applesignin: [Default]` (needed by `EtubuNativePlugin.signInWithApple`), wired via `CODE_SIGN_ENTITLEMENTS`.
- **`ios/App/App/Assets.xcassets/AppIcon.appiconset`** — real 1024×1024 icon from `public/assets/brand/AppIcon-1024.png` (single-size modern app icon).
- **`ios/App/App/Assets.xcassets/EtubuLogo.imageset/logo-horizontal.png`** — the imageset only had a `Contents.json` with no actual image file; copied `public/assets/brand/logo-horizontal.png` in to fix the missing launch-screen logo.
- **`ios/App/App/Assets.xcassets/Splash.imageset`** — default Capacitor splash asset (for the `SplashScreen` plugin).
- **`ios/App/App/Base.lproj/Main.storyboard`** — Capacitor's default `CAPBridgeViewController` scene (was missing; `LaunchScreen.storyboard` was already restored and kept as-is).
- **`ios/App/App/config.xml`** — default Cordova/Capacitor config (bundle resource, referenced by Capacitor's public-file copy step).
- **`ios/App/EtubuWidgets/`** target — new WidgetKit **app-extension** target added to the `.xcodeproj` (product type `com.apple.product-type.app-extension`, bundle id `com.etubu.app.EtubuWidgets`, `Info.plist` with `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, own `Assets.xcassets/EtubuLogo.imageset`), embedded into the `Etubu` app target via a Copy Files ("Embed Foundation Extensions", `.appex` destination) build phase + `add_dependency`. Links `WidgetKit`/`SwiftUI`/`ActivityKit` explicitly.
- **SPM dependency** `https://github.com/shoujiaxin/swift-tesla-ble` (`upToNextMajorVersion 1.0.0`) added to the `Etubu` target's package references — resolves to the same pinned `v1.0.0` tag confirmed from DerivedData.
- All 36 restored Swift files (Cluster/Dashboard/OBD/Tesla + root) wired into the `Etubu` target's Compile Sources; `Fonts/*.ttf` + `PrivacyInfo.xcprivacy` wired into Copy Bundle Resources.
- All project-file surgery was done with the Ruby **`xcodeproj`** gem (already available locally) — no hand-edited `pbxproj` text.

## Black-screen fix — confirmed already correct, no change needed

Task asked to set `wv.alpha = 1` (not `0.01`) and avoid `isHidden` in `EtubuClusterPresenter.hideCapacitorChrome()`. The **restored file already had the correct values** (`wv.isHidden = false`, `wv.alpha = 1`, with an explicit comment "CRITICAL: do not set isHidden = true — that stalls WKWebView JS"). Cluster is hosted as a child view controller inside `root.view` (not a second `UIWindow`), also as required. No source change was needed for this item — it was verified, not fixed.

## Premium gate

`EtubuPremiumManager.frozenOpen = true` and nothing in the codebase references `EtubuPremiumGateView` — no stub was needed.

## Compile bugs found and fixed in the restored Swift (pre-existing issues in the transcript-recovered sources, unrelated to the Xcode-project recreation)

These were real bugs in the recovered `.swift` files themselves (likely captured from an earlier revision in the AI transcripts than what last actually shipped). Fixed pragmatically, reusing existing patterns in each file:

1. **`ios/App/EtubuWidgets/EtubuDriveAttributes.swift`** was a stale/older copy (46 lines, missing `routeActive`, `routeSummaryLine`, `radarCount`, etc.) vs. the App target's fuller copy (88 lines) that `EtubuLiveActivityWidget.swift` actually needs. → Synced widget copy to match the App copy exactly.
2. **`EtubuClusterAudioBridge`** was missing `pushDrive(kmh:powerKw:source:)` (called from `EtubuTeslaBleSession`) and `setPremium(_:)` (called from `EtubuPremiumManager`) → added both, following the file's existing `evalJS(...)` bridging pattern.
3. **`EtubuDashboardPresenter`** was a bare `enum` but used `@objc` static selectors + `#selector` for a `UIButton` target, which Swift disallows on enums → changed to `final class EtubuDashboardPresenter: NSObject` (all members stay `static`).
4. **`EtubuCutoutFX.swift`** had `frag(_:)` declared twice (duplicate private extension) → removed the duplicate.
5. **`ClusterTheme`** was missing `gaugeFont` / `uiFont` used by `EtubuClusterFonts.setTheme(_:)` → added as constant `"Orbitron"` / `"DM Sans"` (matches the pre-existing defaults, no visual change).
6. **`EtubuTeslaBleSession.applyDrive`** passed `drive.powerKW` (`Int?`) to the new `pushDrive` — typed the new method `Int?` to match instead of `Double?`.
7. **`EtubuDriveWarnings`** was missing a static `armRouteHazardHook()` (called from `EtubuRouteBridge.plan`) → added as `shared.startPolling()`, wrapped in `Task { @MainActor in … }` at the call site (the enclosing static func isn't actor-isolated).
8. **`EtubuRouteBridge`** was missing `needsDistrictPick(text:completion:)` (called 4× from `EtubuRoutePickerView` to ask the user to disambiguate a city with multiple districts) → implemented using the same JS place-index helpers (`__etubuPlaceItems`, `__etubuFold`) already embedded in the file.
9. **`EtubuRouteBriefChipsView`** (SwiftUI view, radar/corridor/control/charge/weather pill row) referenced twice from `EtubuRoutePickerView` but never defined anywhere → created `ios/App/App/Cluster/EtubuRouteBriefChipsView.swift`, mirroring the equivalent chip row already implemented in `EtubuWidgets/EtubuLiveActivityWidget.swift`.

## Remaining known gaps / follow-ups

- No `DEVELOPMENT_TEAM` is set (builds above used `CODE_SIGNING_ALLOWED=NO`); opening in Xcode and picking a team will be needed for on-device runs / TestFlight.
- `assets/audio/loops/*.wav` are still not recovered (README-only, per Phase 1).
- Git history is still empty — nothing has been committed in this session (not requested).
