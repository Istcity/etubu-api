# Hazard sources — EGM / official vs OSM

Etubu merges road hazards from **official institutional feeds first**, with **OpenStreetMap Overpass** as complementary / fallback so the two layers do not cut or override each other.

## Priority rules

| Situation | Mode | Behavior |
|-----------|------|----------|
| Inside Turkey + EGM/seed/official enforcement present | **Supplement** | Official radars, corridors, roadworks stay authoritative. OSM only fills gaps (crossings, lights, bumps, stop/yield, and OSM radars **not** within ~70 m of an official enforcement point). |
| Outside Turkey / non-TR region | **Led** | OSM drives radar/corridor/local hazards (intl). |
| EGM empty / failed / unavailable | **Led** | OSM activates fully for these categories. |

**Dedupe:** same-type family within **~70 m** → keep official (non-`osm-` / non-`osmhz-` id). Different types may coexist.

Official construction / tümsek / roadworks from EGM remain authoritative when present.

## Live OSM refresh

Around the vehicle: refetch when moved **≥150 m** or every **60 s**.

| Type | Warn | Urgent |
|------|------|--------|
| Radar / speed camera / corridor | 350 m | 120 m |
| Railway crossing | 250 m | 80 m |
| Traffic light | 100 m | 35 m |
| Stop / Yield | 80 m | 25 m |
| Pedestrian crossing / Speed bump | 60 m | 20 m |

## Native stack

- `EtubuHazardMerge` — mode + proximity merge
- `EtubuOsmHazardsMonitor` — live multi-type Overpass
- `EtubuLiveRadarMonitor` — longer-range cameras/corridors + TR seeds (merge via official-primary)
- `EtubuTrafikAPI.mergeOfficialWithOsm` / `EtubuRouteBridge` enrich — route polyline merge
- `EtubuDriveWarnings` — approach stages from per-kind thresholds + warn voice

## Cap mirror

- `public/js/osm-hazards.js` — same rules + `setOfficialPoints`
- `public/js/route-guard.js` — `mergeHazards` proximity dedupe (official first)

## GPS indicator (cluster top bar)

| State | Chip | Maestro id |
|-------|------|------------|
| Real GPS | 📍 GPS ✓ (green) | `etubu.gps.ok` |
| No permission | 📍 İzin yok (red) | `etubu.gps.denied` |
| Simulation | 📍 Sim (orange) | `etubu.gps.sim` |

Denied / Tesla-sim env auto-simulates around **Bağcılar, Istanbul**. Maestro `simctl location` Istanbul fixes still win → **GPS ✓** (sim does not override real authorized fixes).
