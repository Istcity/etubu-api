# ETUBU driving samples

## Runtime loops (`loops/`)

The audio engine loads WAV loops from `loops/` (`SAMPLE_BASE` in `js/audio-engine.js`).
Each voice prefers **three bands** (`loops.idle` / `mid` / `high`) crossfaded by vehicle speed,
with `playbackRate` clamped to **0.85–1.3**. Legacy `drive` / `drive2` still work as fallback.

See **[ASSETS_LICENSE.md](./ASSETS_LICENSE.md)** for licenses and Freesound / CC0 drop-in guidance.

### Chalmers-derived EV body

Body-EQ’d loops from open research AVAS examples (Chalmers University of Technology,
Applied Acoustics):

https://www.ta.chalmers.se/research/vibroacoustic-group/audio-examples/electricvehiclesounds/

Sources include VW ID.3 and Tesla Model Y AVAS / tire tracks, plus indoor design
examples. Originals also live under `avas/` and legacy `samples/` MP3s.

### Reference-inspired banks (`ref_*`)

Original synthesized loops (not licensed packs). Three catalog groups:

| Group | Lesson | Files |
|-------|--------|-------|
| **Simülasyon** | RevHeadz — load / gear feel | `ref_sim_load_throttle.wav`, `ref_sim_shift_cage.wav` |
| **Prosedürel** | Engine Sound Generator — math / piston | `ref_proc_piston_sigma.wav`, `ref_proc_intake_eq.wav` |
| **Studio Bank** | REV / Igniter — dense layered texture | `ref_grain_ramp_forge.wav`, `ref_grain_stage_cut.wav` |

Trademarked product audio is not embedded; characters are ETUBU originals.

### Engine design notes

- Prefer **multiple real loops + crossfade** over stretching one sample across all RPMs.
- Cap / iOS drive updates are throttled (~120 ms); `powerKw` feeds regen/throttle natively.
- Keep EV audio **foreground-only** (no background audio mode required for App Store).
