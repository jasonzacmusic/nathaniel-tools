# StageRig v0 — the Lagori concert, rebuilt in REAPER

**Written 3 Aug 2026.** The source of truth is Jason's real, current concert:
`~/Music/MainStage/Lagori 2026 Minimal.concert` (last touched 21 Jul 2026), fully
decoded by `tools/concert_report.py` → `reports/Lagori 2026 Minimal.md` + `.json`.
The architecture below is the one locked in `NPH_TECH_BRIEF.md` §7 — it is not up
for relitigation.

---

## 1. What the decode found (this changes the odds)

The handoff feared a rig full of Logic-only sounds. The reality of the 2026 Minimal
concert is much friendlier:

| Sound in the concert | Patches using it | REAPER story |
|---|---|---|
| **Pianoteq 8** | 19 patches (every piano, EP, clav) | **Loads as-is.** Same plugin, same presets. Zero loss. |
| **Vintage B3** (Logic) | 10 patches | Substitute: **Arturia B-3 V** (owned, V Collection). |
| **Logic Sampler** (strings, horns, sitar, shenai, flute, choir, banjo, timpani) | 15 patches | Kontakt/UVI equivalents, or **resample the exact MainStage sound** (render each articulation, load in ReaSamplOmatic5000/sfz). |
| **Alchemy** (pads, synths, leads, sub bass) | 16 patches | **Omnisphere / ANA 2** (owned), or resample — the concert bundle ships its own `Alchemy Samples` folder. |
| Studio Horns | 1 patch | Session horns library or resample. |
| Pedalboard (Highway Star organ drive) | 1 patch | REAPER FX chain (drive + rotary). |

Roughly **40% of the rig ports losslessly** (Pianoteq), ~35% has owned substitutes
(B3 → Arturia, Alchemy → Omnisphere/ANA 2), and the rest is honest resampling work.
The mapping table lives in the importer and is **explicit and editable — never
guessed silently.** Every patch report states which substitute it got and which
sounds could not be mapped.

## 2. The five starting patches (v0 scope)

Chosen from the decoded setlist — the two Jason named, plus the three that exercise
every substitution class:

1. **Aasma** (the song patch he asked for) — Alchemy synths ×2, Sampler string
   section ×4, muted Pianoteq piano. *Hardest case: full orchestra + synth layers.*
2. **Humma Humma G → A** (the horns patch) — Sampler horn + horns-high, Vintage B3.
   *Horn-section resample + organ substitute, plus a transpose patch (G→A).* 
3. **BRAHMA Gm** — B3 grand organ + Pianoteq clav @118 BPM. *Organ substitute +
   per-patch tempo.*
4. **Upright** — solo Pianoteq @115 BPM. *The lossless baseline — must feel
   identical or nothing else matters.*
5. **Maari Kannu** — B3 + clav + double horn section @160/106 BPM. *Layered strips +
   Studio Horns.*

v0 is done when Jason can play these five back-to-back, switching instantly, blind,
and cannot tell the switching apart from MainStage. (Sounds may differ where
substitutes are honest; the *switching* may not.)

## 3. Architecture (locked — from the tech brief)

- **One REAPER project = one concert.** Patches are track folders. Tabs and
  subprojects were evaluated and rejected for live use.
- **Nothing that touches audio is created/destroyed/reconfigured mid-set.** All five
  patches instantiated at load; switching = unmute/mute + input routing only.
- **Setlist in project ExtState** (defensively parsed — corrupt state must never
  brick a show), decoupled from the timeline.
- **Switch order:** unmute B → gate A's input (JSFX) → let A ring 1.5–3 s or to
  −60 dB → mute A → note-offs + CC64=0 to A.
- **Note-tracker JSFX** on the master key input: held-note bitmap + sustain state,
  emits matching note-offs on switch, optional re-strike on B, replays CC64. This is
  what makes a mid-phrase change survivable. (Switch logic lives in JSFX at audio
  rate, NOT in Lua — `defer` ticks at ~15–30 ms and is only allowed to drive the UI.)
- **One deferred state machine owns transitions.** UI/MIDI/OSC post intents to a
  queue; nothing acts directly.
- **Budget: 2 simultaneously active patches.** Idle patches never taken offline.
- **Stage view:** violet, dark, huge type, CURRENT + NEXT, BPM flasher, big touch
  targets, ~30 fps, PANIC (soft = gate+fade, hard = mute all) sub-100 ms.

## 4. Live loops — the Ableton answer (Loop Deck)

Requirement: trigger loops pre-recorded from his own REAPER sessions, live,
trustworthy.

**v0 design (native, no third-party dependency):**
- Loops are **rendered stems at show tempo** — no time-stretch on stage, ever.
- Each song folder gets a `LOOPS` child folder; each loop is an item on its own
  track, pre-loaded (RAM preview forced by playing the project once at load).
- Launch = quantized to the next bar: the app arms the unmute at bar boundary using
  the note-tracker JSFX clock, so a sloppy pad press still lands tight.
- Pad grid UI with count-in flash; one PANIC pad; loops all at the same sample rate
  as the interface — checked at load, refused otherwise.
- **Playtime 2 (€64) is the fallback**, not the plan: it is the only real clip
  launcher for REAPER but has no gigging track record; we build the narrow,
  trustworthy thing instead of depending on it.

## 5. The on-stage REAPER profile (settings that make it trustworthy)

Run the show under a dedicated profile: `reaper -cfgfile StageRig.ini` — the studio
config is never touched.

- Audio device **never closed** when inactive; "Run FX when audio is stopped" ON.
- **Anticipative FX OFF** for the live profile (it is auto-bypassed on monitored
  tracks anyway — no savings, only risk).
- **"Do not process muted tracks" OFF** — muted patches must keep processing so
  tails ring out on switch (this is the MainStage behaviour we are matching).
- Track mute fade ~**100 ms** (kills clicks on switch).
- Undo OFF, autosave OFF during the set, plugin re-scan on launch OFF,
  notifications/screensaver off, Wi-Fi off.
- Buffer target: **128 samples @ 44.1 kHz (~2.9 ms)** — every plugin tested at that
  buffer before it is allowed in a patch.
- Pre-show gate: the Rig Doctor proof — sample `GetPlayPosition` twice and confirm
  the cursor advanced. Never trust `audio_is_running`.

## 6. Honest weaknesses (stated up front, always)

- REAPER has no sample-accurate patch-crossfade primitive; we approximate with the
  gate-and-ring sequence.
- Lua decision latency ~15–30 ms — acceptable for patch switching only because the
  note path is JSFX; never put note logic in Lua.
- ExtState is a text blob; the loader validates or falls back to "flat setlist, all
  patches" — a corrupt file may lose the set order but may never lose sound.
- A faithful **sonic** clone of Logic-only sounds is impossible (licensing fact);
  substitution is explicit and per-patch.

## 7. Build order

1. `tools/stagerig_import.py` — evolve `concert_report.py`: emit a `.RPP` with the
   five patch folders, named tracks, FX stubs (Pianoteq/B-3 V inserted where owned),
   routing, and the ExtState setlist. Unmappable sounds become clearly named empty
   tracks (`[NEEDS SOUND] Horns High`).
2. `NPH/jsfx/nph_note_tracker.jsfx` — the note/sustain tracker + input gate.
3. `apps/StageRig.lua` (violet) — stage view + state machine + setlist editor, on
   `nph_safe`.
4. Loop Deck pads inside StageRig (same window, second tab).
5. Rehearsal gate: the five patches, blind switching test, then the eight-gate stage
   test from the tech brief. **It is a demo until real paid gigs retire the backup
   rig.**

## 6b. What we do NOT build

The existing NSM Bridge (MainStage→REAPER MIDI) stays as-is for the current hybrid
rig; StageRig does not depend on it and does not extend it.
