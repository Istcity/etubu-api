# Tesla BLE telemetry field map

Etubu uses a **vendored** `swift-tesla-ble` (`ios/Vendor/swift-tesla-ble`) Infotainment `getVehicleData` — not Fleet streaming.

## Poll architecture

| Loop | Rate (moving) | Query | Fields |
|------|---------------|-------|--------|
| Drive | **~3 Hz** (`280 ms`) | `fetchDrive()` / `.driveOnly` | speed, gear, power, odo, active route |
| Extras | **~1 Hz sequential** | `.charge` every tick; climate / TPMS / location rotate | SoC, temps, TPMS, vehicle GPS |
| VCSEC | **~0.4 Hz** | `GET_STATUS` | lock, presence |

Handshake / NFC pair / lock-unlock commands are untouched. After session is up, VCSEC GET_STATUS runs on the existing signed counter path.

12 Hz drive polling starved extras and dropped Infotainment. Tesla BLE is one in-flight signed request; extras are sequential so a TPMS hit cannot mask frozen SoC.

**Reconnect:** after first successful pair, never mint a new key / never ask for NFC card.

Speed: BLE `speedFloat` (mph) while fresh; else GPS (3-of-4 confirm × ~1.264). Dial still steps **±1 km/h @ 20 Hz**.

TPMS: bar/kPa/psi normalize; warning if **< 2.5 bar**.

Free-drive alerts: only TPMS < 2.5 bar or SoC < 5%. Route active → full hazard/corridor set; overlays auto-dismiss when passed.

OLED stealth: pitch-black speed-only HUD; tap wakes 10 s; analog/digital in Settings. Maestro launch args skip stealth.

Extras failures **never** cancel the drive loop.

**Boot:** sequential charge → climate → tires → location (up to 3 retries).

**Drive:** SoC every extras tick; climate / TPMS / location rotate. Closures/media stay lower cadence.

Infotainment asleep → empty charge/climate: `wakeVehicle` on connect and after **~4 missing charge ticks** (capped ~16 s). Healer does **not** treat TPMS-only extras as healthy SoC.

## Field map (protobuf → UI)

| UI | Source | Notes |
|----|--------|-------|
| Speed km/h | BLE drive while fresh (&lt;2.2 s); else confirmed GPS | GPS = reported + haversine; 3 of last 4 agree; × ~1.264 (web 22%) |
| Gear | `shiftState` | Unset + moving ≥3 → treat as `D`; P/N + &lt;3 → park-gate 0 |
| Power kW | `powerKW` | Reject \|kw\| &gt; 800 |
| SoC % | `usableBatteryLevel` ?? `batteryLevel` | Mapper preserves optionals (unset ≠ 0). Live only after BLE confirm — disk cache never shown as live |
| Range km | `estBatteryRangeMiles` ?? `batteryRangeMiles` | × 1.60934; ignore ≤0.5 mi; optionals preserved |
| Outside/inside °C | `ClimateState.*TempCelsius` | Optionals preserved; exact ~0.0 alone = unset; if other side real, keep **0°C** |
| Arrival energy % | `activeRouteEnergyAtArrival` (vehicle) else SoC×(1−remain/range) | Chrome chip right of Settings |
| Nav dest coords | `activeRouteCoordinates` | Plan with Tesla pin; Home/Work use saved charge-state pins — **never Nominatim garbage** |
| Home/Work pins | `ChargeState.homeLocation` / `workLocation` | Cached for ambiguous dest labels |
| TPMS psi | `TirePressureState.*.pressureBar` | bar / kPa / psi normalize via `tireRawToPsi` |

## UI epochs / live flags

`chargeEpoch` / `tpmsEpoch` / `climateEpoch` bump on every successful extras apply.

`liveChargeConfirmed` / `liveClimateConfirmed` gate display so restored UserDefaults SoC/temps are not treated as live.

## Auto-reconnect

After one-time VIN pair (`pairedConfirmed` + Keychain key): bootstrap on launch, **foreground**, and **BT poweredOn**. Disconnect while paired **keeps retrying** (exponential backoff, cap 12 s) until the session is healthy or the user stops. Attempt counter resets on a successful connect.

## Exit

Settings → **Çıkış / Exit** (`etubu.app.exit`): end Live Activity, disconnect BLE, stop audio, `exit(0)`.

## Corridor average (native + Cap)

Display:

- Entry: show **vehicle speed** immediately (anlık)
- After ≥50 m and ~5 s: show **true** distance/time average (what the camera uses)
- Chip also shows instant km/h, limit, and remaining distance
- **YAVAŞLA** when `trueAvg > limit + 2`; clears when `trueAvg ≤ limit` (hysteresis)

## Audio duck (alerts over car BT)

`AppDelegate.activateAlertDuckSession()` → `.playback` + `.voicePrompt` + `.duckOthers` + `.allowBluetoothA2DP`  
Duck stays ~1.2 s after the last beep so A2DP actually carries the tone over YouTube/Apple Music. Beeps use in-memory WAV `AVAudioPlayer` (not `AVAudioEngine`).
