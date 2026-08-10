# Tesla BLE telemetry field map

Etubu uses `swift-tesla-ble` (`TeslaVehicleClient`) Infotainment `getVehicleData` — not Fleet streaming.

## Poll architecture

| Loop | Rate (moving) | Query | Fields |
|------|---------------|-------|--------|
| Drive | ~10–12 Hz (`85 ms` sleep) | `fetchDrive()` / `.driveOnly` | speed, gear, power, odo, active route |
| Extras | ~0.7–1.5 Hz (every tick while driving) | `.categories([.charge,.climate,.tirePressure,…])` | SoC, range, temps, TPMS, closures, media |

Extras failures **never** cancel the drive loop (previously a combined `try` caused reconnect storms and “half-live” speed).

**Boot:** tire + charge/climate fire as **parallel** requests with up to **3 retries** (wake between attempts).

**Drive:** charge + climate + tires on **every** extras tick (not every 2nd). Closures/media stay lower cadence.

Infotainment asleep → empty charge/climate/TPMS: `wakeVehicle` on connect and after **~8 missing extras ticks** (also capped ~18 s).

## Field map (protobuf → UI)

| UI | Source | Notes |
|----|--------|-------|
| Speed km/h | `DriveState.speedMph` × 1.60934 | Dial display steps ≤1 km/h toward target @ 20 Hz |
| Gear | `shiftState` | Unset + moving ≥3 → treat as `D`; P/N + &lt;3 → park-gate 0 |
| Power kW | `powerKW` | Reject \|kw\| &gt; 800 |
| SoC % | `ChargeState.batteryLevel` | SPM maps unset→0; accept 0 only if charging or range present |
| Range km | `estBatteryRangeMiles` ?? `batteryRangeMiles` | × 1.60934; ignore ≤0.5 mi |
| Outside/inside °C | `ClimateState.*TempCelsius` | Exact ~0.0 alone = unset; if the **other** side is a real temp, keep **0°C** |
| TPMS psi | `TirePressureState.*.pressureBar` | bar / kPa / psi normalize via `tireRawToPsi` |
| Closures / media | closures + media categories | Lower priority cadence |

## Corridor average (native + Cap)

Display blend (not blank on entry):

- Entry: show **vehicle speed** immediately
- Progress `p = traveled/length`: `histW = 0.5 + 0.4·p` (50%→90% historical), rest instant
- **YAVAŞLA** uses `corridorTrueAvg` = distance/time only (≥35 m & ~4.3 s), not the blend alone

## UI epochs

`chargeEpoch` / `tpmsEpoch` / `climateEpoch` bump on every successful extras apply so SwiftUI can refresh even when values are unchanged.

## Audio duck (alerts over car BT)

`AppDelegate.activateAlertDuckSession()` → `.playback` + `.duckOthers` + `.allowBluetoothA2DP`  
`deactivateAlertDuckSession()` → `setActive(false, .notifyOthersOnDeactivation)` then restore drive mix.

All warn TTS clips + beeps go through this path so YouTube Music / other A2DP apps duck briefly.
