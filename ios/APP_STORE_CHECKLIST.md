# ETUBU iOS — App Store / TestFlight checklist

## Product

Single-screen SwiftUI cluster over Capacitor (EV audio / IAP stay in the hidden WebView).

- **Primary data:** Tesla BLE via VIN ([swift-tesla-ble](https://github.com/shoujiaxin/swift-tesla-ble)) — read-only
- **Fallback:** OBD ELM327 BLE (menu → OBD fallback)
- **Disclaimer:** Third-party app; not affiliated with Tesla, Inc.

## Build

- [ ] Open `ios/App/App.xcworkspace`
- [ ] Resolve packages (TeslaBLE + SwiftProtobuf)
- [ ] App + Widgets `CURRENT_PROJECT_VERSION` = **9**
- [ ] Deployment: iOS **17.0**+
- [ ] Archive → TestFlight

## Permissions / Review notes

| Capability | Justification |
|------------|---------------|
| Bluetooth Always | VIN-matched Tesla vehicle BLE telemetry; optional OBD BLE fallback |
| Location When In Use | EV sound GPS sync in Capacitor layer |
| Background Audio | Keep EV driving audio while locked |
| Background bluetooth-central | Maintain Tesla / OBD BLE while driving |
| Live Activities | Speed / gear on Dynamic Island |

## Tesla pairing test

1. Enter 17-char VIN on cluster strip → **Pair**
2. Phone scans / connects in pairing mode
3. Tap Tesla NFC key card on center console
4. App reconnects in normal mode
5. Speed / gear / battery update on one screen
6. Force-quit → relaunch auto-reconnects with saved VIN (Keychain key)

## Cluster UI

- [ ] One full-screen surface (no floating Dashboard button)
- [ ] Landscape: dial + nav column + map wash; Pair pill clear of Dynamic Island
- [ ] Portrait: dial + gradient wash; EV Sound row lifted above home indicator
- [ ] Themes: Aurora / Plasma / Redline / Cyber Lime / … (settings sheet)
- [ ] Warn banner + corridor chip mirror Cap warn-reel / avg corridor when route active
- [ ] Live Activity compact island fits (ET + km/h)
- [ ] EV Sound + mix controls on same screen

## StoreKit

Restore accepts: `etubu.catalog.yearly`, `etubu.unlock.yearly`, `etubu.unlock.lifetime`, `etubu.ads.remove`

## Privacy

- VIN + BLE keys stored on-device (Keychain / UserDefaults); not uploaded
- `PrivacyInfo.xcprivacy` present
- `ITSAppUsesNonExemptEncryption` = false

## Not in this build

- Vehicle write commands (lock/climate/media)
- AdMob
- Map / turn-by-turn panels
