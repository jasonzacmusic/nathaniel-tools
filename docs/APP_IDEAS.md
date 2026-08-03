# NPH Suite — new app ideas

**Written 3 Aug 2026, from Jason's actual friction** — his ~80 riff/tutorial project
folders, ~50 videos a year, the lesson pipeline, the live rig, and the custom actions
he already runs all day. Nothing here is a feature-list idea; each one names the real
task it removes.

Colour language (locked): **green = structure · amber = delivery · violet = performance
· teal = look.**

---

## Already queued (from the tech brief — build these first)

| App | Colour | Status |
|---|---|---|
| Sections & Time | green | queued — absorbs Marker at Bar, Tempo at Bar, Region Next/Prev; adds Jason's named marker types (`C202`, `V218`, `V127.3`) and the per-track timebase view that kills the `itemtimelock` trap |
| StageRig | violet | flagship — see `STAGERIG_SPEC.md` |
| Drag-paint retrofit | teal | Palette & Look still lacks the contiguous drag-select every app is supposed to have |
| Gain matching in Stem Print | amber | render pass is safe; matching never built |

---

## New ideas, in value order

### 1. Loop Deck (violet) — the Ableton answer
Trustworthy live triggering of loops and backing stems that came out of his own REAPER
sessions. A pad grid (ReaImGui, huge touch targets) where each pad = a pre-rendered
stem/loop; launch is quantized to the bar; everything pre-loaded into RAM at set load;
one PANIC pad. Companion to StageRig but works alone in rehearsals.
*Why trust it:* no time-stretch, no disk streaming mid-show, no tempo detection on
stage — loops are rendered at show tempo beforehand, the app only unmutes on the grid.
**Feeds:** course module 8, the live video, and every gig.

### 2. Riff Vault (teal) — the 80-folder problem
He has ~80 dated Riffs/Tutorials/Freestyle project folders and no way to find anything
in them. A browser over those folders: search by name, tempo, key; preview the MIDI;
one click imports the riff's tracks into the current project tab. Index built once,
refreshed in the background, stored as JSON next to the folders.
**Feeds:** the weekly riff content pipeline, lesson prep, and it becomes a genuinely
novel demo video ("my whole riff history is searchable inside REAPER").

### 3. Session Prep (green) — the ritual as one press
The full "boring part" — import, name, colour, folder, mark sections, set tempo — as a
guided one-window flow driven by a saved profile. It is literally the subject of
YouTube video #1; the app is the video's punchline ("and now it's one button").
**Feeds:** course modules 1–4, video #1.

### 4. Lesson Export (amber) — the pipeline handoff
One press: render stems, export MIDI per track (the Batch Export engine already
exists), dump markers/regions as CSV, dump the tempo map — into one dated folder ready
for the B-roll/visualizer pipeline. Today this is five manual steps done ~50 times a
year.
**Feeds:** every YouTube lesson; directly reuses `NPH_MIDI Batch Export.lua`.

### 5. Rig Doctor (violet) — the pre-show gate
A checklist app that *proves* the rig instead of trusting it: audio device present and
at the expected buffer/sample-rate, CPU headroom test tone, plugin-list delta since
last show, and the house-rule audio proof (sample `GetPlayPosition` twice and confirm
the cursor actually advanced — never trust `audio_is_running`). Green board = walk on
stage.
**Feeds:** StageRig credibility; also a strong "this is broken and here is why" video.

### 6. Handoff Pack (amber) — collaboration in one file
Zip the project with only the media it actually uses, plus a plugin manifest (what's
needed, what's missing on the receiving machine). The receiving half shows what won't
load before the session opens.
**Feeds:** course module 7 verbatim.

### 7. Archive Intake (green) — for the studio mini
Batch-import the class MIDI archives: point at a folder of `.mid`, get one organised,
tempo-mapped, colour-coded project per class with named regions. Pairs with Riff Vault.
**Feeds:** the teaching archive; only worth building after 1–4 ship.

---

## The rule for all of them

Every app builds on `NPH/lib/nph_safe.lua` (GUID identity, validated pointers, the
signature watchdog) — the class of crash we paid for in Palette & Look must stay
extinct. Every app gets drag-paint selection, a dependency gate via `nph_safe.require`,
ReaPack headers, and its accent colour. No app ships until the harness passes on a
machine that is not the machine it was written on.
