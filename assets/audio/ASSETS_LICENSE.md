# ETUBU audio asset licenses

Keep this file updated when adding or replacing loops under `assets/audio/`.

## Runtime policy

- Prefer **CC0** for commercial App Store / web distribution.
- **CC-BY** allowed with attribution in this file (and Settings → Credits when shown).
- **CC-BY-NC** is **not** shipped (non-commercial).
- EV audio plays **foreground only** (no background audio mode required).

## Band pack (`loops/bands/`) — Jul 2026

| File | Role | Source | License |
|------|------|--------|---------|
| `ev_idle.wav` | EV idle | Freesound [348857](https://freesound.org/s/348857/) mickboere — hover vehicle idle | **CC0** |
| `ev_idle_alt.wav` | EV idle alt | Freesound [843123](https://freesound.org/s/843123/) fnakez — engine idle cut | **CC0** |
| `ev_mid.wav` | EV mid | Chalmers-derived `ev_id3_body_loop` (ETUBU EQ) | Research example / processed |
| `ev_high.wav` | EV high | Chalmers-derived `ev_modely_rev_body_loop` (ETUBU EQ) | Research example / processed |
| `ice_idle.wav` | ICE idle | Freesound [349170](https://freesound.org/s/349170/) iridiuss — car engine idle | **CC0** |
| `ice_idle_v8.wav` | V8 idle | Freesound [636066](https://freesound.org/s/636066/) lumamorph — eight-cylinder idling | **CC-BY 4.0** — credit lumamorph / Freesound |
| `ice_mid.wav` | ICE mid | Freesound [325809](https://freesound.org/s/325809/) soundjoao — motor loop 3 | **CC0** |
| `ice_mid_alt.wav` | ICE mid alt | Freesound [481719](https://freesound.org/s/481719/) craigsmith — old car engine | **CC0** |
| `ice_high.wav` | ICE high | Freesound [766323](https://freesound.org/s/766323/) edenfallen — car accelerating loop | **CC-BY 4.0** — credit edenfallen / Freesound / OWSFX |
| `diesel_idle.wav` | Diesel idle | Freesound [152908](https://freesound.org/s/152908/) mlteenie — London bus idling | **CC-BY 4.0** — credit mlteenie / Freesound |
| `diesel_mid.wav` / `diesel_high.wav` | Diesel mid/high | ETUBU `diesel_thump_loop` / `combustion_rich_loop` | ETUBU |

### Not used (unsuitable / NC)

| Download | Reason |
|----------|--------|
| `278189__debsound__rally-car-idle-loop-05` | **CC-BY-NC** — not for commercial app |
| `278188__…rally-car-idle-loop-14` | Same family; skipped |
| `675725__…bearing-knocking-bad…` | Damaged-engine SFX |
| `410528__…steampunkcartoon` | Non-vehicle cartoon |
| `594215__…steam-engine…` | Steam, not road vehicle |

## Older loops (`loops/*.wav`)

| Asset / family | Source | License note |
|----------------|--------|----------------|
| `ev_id3_*`, `ev_modely_*`, `ev_hum_*` | Chalmers AVAS research examples, body-EQ’d | https://www.ta.chalmers.se/research/vibroacoustic-group/audio-examples/electricvehiclesounds/ |
| `ref_*` | ETUBU original synthesis | ETUBU |

## CC-BY credit line (copy for Credits UI)

> Engine samples: lumamorph, edenfallen, mlteenie — via Freesound.org (CC BY 4.0).  
> Additional loops: mickboere, fnakez, iridiuss, soundjoao, craigsmith (CC0).  
> EV body layers adapted from Chalmers University open research AVAS examples.

## Sync

```bash
npm run cap:sync
```
