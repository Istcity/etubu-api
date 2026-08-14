# Tesla BLE telemetry field map

Etubu uses a **vendored** `swift-tesla-ble` (`ios/Vendor/swift-tesla-ble`) Infotainment `getVehicleData` — not Fleet streaming.

## Poll architecture

| Loop | Rate (moving) | Query | Fields |
|------|---------------|-------|--------|
| Drive | ~10–12 Hz (`85 ms` sleep) | `fetchDrive()` / `.driveOnly` | speed, gear, power, odo, active route (+ coords / energy@arrival) |
| Extras | **1 Hz** | `.categories([.charge,.climate,.tirePressure,…])` | SoC, range, temps, TPMS, closures, media |
| VCSEC | **1 Hz** | `InformationRequest.GET_STATUS` (`VehicleQuery.bodyControllerState`) | lock, user presence, sleep — handshake unchanged |

Handshake / NFC pair / lock-unlock commands are untouched. After session is up, VCSEC GET_STATUS runs on the existing signed counter path.

Speed: `speedFloat` (mph) with integer `speed` fallback → × 1.60934. Dial still steps **±1 km/h @ 20 Hz**.

TPMS: bar/kPa/psi normalize; warning if **< 2.5 bar**.

Free-drive alerts: only TPMS < 2.5 bar or SoC < 5%. Route active → full hazard/corridor set; overlays auto-dismiss when passed.

OLED stealth: pitch-black speed-only HUD; tap wakes 10 s; analog/digital in Settings. Maestro launch args skip stealth.

Extras failures **never** cancel the drive loop.

**Boot:** tire + charge/climate fire as **parallel** requests with up to **3 retries** (wake between attempts).

**Drive:** charge + climate + tires + **location** on **every** extras tick. Closures/media/software/schedule stay lower cadence.

Infotainment asleep → empty charge/climate/TPMS: `wakeVehicle` on connect and after **~4 missing extras ticks** (also capped ~12 s). Background healer re-bootstraps extras every ~12 s as if newly connected.

## Field map (protobuf → UI)

| UI | Source | Notes |
|----|--------|-------|
| Speed km/h | `DriveState.speedMph` × 1.60934 | **Nil mph keeps prior km/h** (never publish 0). Dial steps **±1 km/h @ 20 Hz** toward vehicle target |
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

`AppDelegate.activateAlertDuckSession()` → `.playback` + `.duckOthers` + `.allowBluetoothA2DP`  
`deactivateAlertDuckSession()` → `setActive(false, .notifyOthersOnDeactivation)` then restore drive mix.

All warn beeps go through this path so YouTube Music / other A2DP apps duck briefly. TTS is disabled.
