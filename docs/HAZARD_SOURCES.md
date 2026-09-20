# Hazard sources — OSM primary

> Tam ürün kuralları (canlı telemetri, uyarı kapısı, Ev/İş, ses): [`docs/LIVE_ROUTE_RULES.md`](LIVE_ROUTE_RULES.md)

Etubu yol uyarılarını **OpenStreetMap Overpass** üzerinden alır.

Türkiye hız koridorları **ulusal cache** ile gelir (rota başına EGM createRoute yok):

1. Gömülü `etubu-tr-corridors.json` — EGM SpeedTunnels (omurga harvest) + Overpass `average_speed` + seed
2. Haftalık Overpass tile yenileme (arka plan)
3. createRoute başarılı olursa SpeedTunnels **bonus** olarak cache’e yazılır (zorunlu değil)

Aynı-il / OSRM rotalarında da `EtubuTrCorridorStore.alongRoute` koridorları yapıştırır.

## Priority rules

| Situation | Mode | Behavior |
|-----------|------|----------|
| Her bölge | **OSM led** | Radar, koridor, ışık, tünel, viraj, tırmanış, yol şartı, şarj OSM’den. |
| TR dil veya GPS TR | **TR corridor cache** | Ulusal EGM+OSM koridor pinleri (`egm-cor-*` / `osm-trcor-*`). |

**Dedupe:** same-type family within **~120 m** (EGM tercih).

## Live OSM refresh

Around the vehicle: refetch when moved **≥150 m** or every **60 s**.

| Type | Warn | Urgent |
|------|------|--------|
| Radar / speed camera / corridor | 350 m | 120 m |
| Railway crossing | 250 m | 80 m |
| Tunnel / mountain climb | 400 m | 90 m |
| Winding / road condition / animal | 280 m | 80 m |
| Traffic light | 100 m | 35 m |
| Stop / Yield | 80 m | 25 m |
| Pedestrian crossing / Speed bump | 60 m | 20 m |
| Charge station | 5 km | 400 m |
| Weather (Open-Meteo / MGM) | 8 km | 1.5 km |

## Native stack

- `EtubuHazardMerge` — proximity merge (OSM led)
- `EtubuOsmHazardsMonitor` — live multi-type Overpass
- `EtubuLiveRadarMonitor` — longer-range cameras/corridors + TR cache
- `EtubuTrCorridorStore` — TR corridors, weekly OSM tiles
- `EtubuWeatherMonitor` — Open-Meteo + optional MGM
- `EtubuRouteBridge` enrich — polyline OSM (kamera + tünel/hemzemin/viraj/tırmanış) + charge + weather
- `EtubuRouteBridge.search` — Photon dünya adres; Nominatim yedek; Ev/İş pin-first
- `EtubuDriveWarnings` — approach stages; **app route OR Tesla nav**

## Cap mirror

- `public/js/osm-hazards.js`
- `public/js/route-guard.js`

## GPS indicator (cluster top bar)

| State | Chip | Maestro id |
|-------|------|------------|
| Real GPS | 📍 GPS ✓ (green) | `etubu.gps.ok` |
| No permission | 📍 İzin yok (red) | `etubu.gps.denied` |
| Simulation | 📍 Sim (orange) | `etubu.gps.sim` |
