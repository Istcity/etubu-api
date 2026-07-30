# ETUBU iOS — App Store / TestFlight checklist

## Build

- [ ] Open `ios/App/App.xcworkspace` (not `.xcodeproj`)
- [ ] App + EtubuWidgets `CURRENT_PROJECT_VERSION` match (currently **8**)
- [ ] Archive → Distribute → App Store Connect / TestFlight
- [ ] `ITSAppUsesNonExemptEncryption` = false (already in Info.plist)

## Permissions / Review notes

| Capability | Review justification |
|------------|----------------------|
| Location When In Use | Sync EV driving sounds and speed display with GPS |
| Bluetooth Always | Connect to ELM327 / OBD BLE adapters for live vehicle speed & telemetry dashboard |
| Background Audio | Keep EV driving audio session active while screen locked |
| Background Location (optional) | Continuous GPS sync during a drive session |
| Background bluetooth-central | Maintain / restore OBD BLE connection while driving |
| Live Activities | Show speed on Dynamic Island / Lock Screen during a drive |

## Native Dashboard (Dashla-style)

- [ ] Floating **Dashboard** button appears over Capacitor HUD
- [ ] Connect scans OBD BLE adapters; device picker lists candidates
- [ ] After first success, force-quit + reopen auto-reconnects (UUID persisted)
- [ ] Gauges update: km/h, RPM, coolant, voltage, throttle, engine load
- [ ] Disconnect clears remembered device when user taps Disconnect
- [ ] Live Activity updates while dashboard is connected (iOS 16.2+)

## StoreKit

Product IDs accepted by restore:

- `etubu.catalog.yearly` / `etubu.unlock.yearly` → yearly unlock
- `etubu.unlock.lifetime` → lifetime unlock
- `etubu.ads.remove` → ad-free

- [ ] Sandbox purchase yearly
- [ ] Sandbox purchase ad-free
- [ ] Restore purchases

## Screenshots / listing

- [ ] Landscape + portrait of native Dashboard (large speed + connection bar)
- [ ] Capacitor EV HUD still works after returning from Dashboard
- [ ] Privacy policy URL + EULA (standard Apple EULA OK)

## Not blocking this release

- AdMob still stubbed (`showBannerAds` → not wired)
- Tesla vehicle BLE (dongle-free) is future work; this build is **OBD BLE dashboard**
