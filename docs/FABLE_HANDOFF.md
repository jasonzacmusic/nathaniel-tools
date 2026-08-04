# Handoff brief — for a fresh agent (Claude Fable) on the second machine

**From:** the Claude Code session that audited and hardened this suite, 3 Aug 2026
**For:** Jason Zac / Nathaniel School of Music
**Machine assumed:** a Mac with REAPER 7.x, ReaImGui and SWS installed

You have three jobs, in this order. Do not skip job 1 — it is what tells you whether
anything else here can be trusted.

---

## Job 1 — Verify what is claimed

Everything in this repo was tested, but **you should not take that on faith.** Reproduce it.

### 1a. The pure-logic tests run anywhere, no REAPER needed

```bash
cd tests
lua hierarchy_test.lua
```
Expected: `31 passed, 0 failed`. This covers the folder-nesting maths — the levels ⇄ depths
round trip, the operations, and specifically the case where a folder is left hanging open
and swallows the rest of the session.

### 1b. The REAPER harness

Copy the repo so the scripts sit where REAPER can see them, then in REAPER:
*Actions → Show action list → New action… → Load ReaScript* → pick `tests/harness.lua`,
select it, click **Run**. It writes `_nph_results.txt` next to itself.

Expected: **68 passed, 0 failed.**

The harness builds a scratch project **in its own tab**, deletes a track behind the app's
back, deliberately touches the freed pointer, and asserts every accessor returns a clean
default rather than faulting. Then it closes the tab and returns to the tab you started on.
It never touches the project you had open.

> **Edit the paths first.** `harness.lua` has `BASE` hard-coded to
> `/Users/nphmacmini/Documents/REAPER Media/`. Point it at wherever you put the files.

### 1c. Two REAPER API traps this suite paid for — do not relearn them

1. **`GetProjectStateChangeCount` does not detect track changes.** Probed directly in
   7.77: it stayed on `8` across insert, rename *and* delete. Every watchdog built on it
   silently never fires — which looks like "the app doesn't refresh", not like a bug. All
   three apps here shipped with that dead watchdog before it was caught. Use
   `nt_safe.projSignature()` instead, on a ~4Hz throttle.
2. **`ValidatePtr2` rejects `0`**, even though `0` is ReaScript's standard shorthand for
   "the current project". Any safety guard must special-case it or every check returns
   false and the app quietly does nothing.

### 1d. The rule that keeps REAPER alive

REAPER frees a `MediaTrack*` the instant the track is deleted. Handing a freed pointer to
any REAPER API faults inside REAPER's own C++, and **Lua `pcall` cannot catch it** — the
host dies, taking unsaved projects with it. A `pcall` around your draw loop is false comfort.

> **Store GUIDs. Resolve to a pointer immediately before use. Validate. Use. Discard.
> Never hold a pointer across a defer frame.**

That is what `Nathaniel Tools/lib/nt_safe.lua` exists to enforce. Build every new app on it.

---

## Job 2 — Review and extend

Read `docs/TECH_BRIEF.md` end to end first; it holds every API trap already paid for.

**Known-open work, roughly in value order:**

| | What | Notes |
|---|---|---|
| 1 | **Sections & Time** (green) | Absorb Marker at Bar, Tempo at Bar, Region Next/Prev into one app. Add named marker types the way Jason labels things (`C202`, `V218`, `V127.3`). Surface per-track timebase — `itemtimelock = 0` on his projects and that trap bites repeatedly. |
| 2 | **Drag-paint retrofit** | Contiguous mouse-drag select/deselect exists in Track Settings Transfer and Folders & Flow. Jason wants it in **every** app — Palette & Look still lacks it. Standing requirement, not a nice-to-have. |
| 3 | **Rest of the shared spine** | `nt_names.lua` (the role/similarity engine is currently duplicated between Palette & Look and Track Settings Transfer) and `nt_time.lua` (bar/tempo maths). |
| 4 | **ReaPack packaging** | Headers are already on every script. What remains: wire `reapack-index` into a GitHub Action so `index.xml` rebuilds on push. **Verify the header spec at `codeberg.org/cfillion/reapack` first** — the ReaPack GitHub wiki was archived 3 June 2026. |
| 5 | **Gain matching in Stem Print** | Its render pass now restores state safely, but gain matching was never built. |

**Creative brief:** Jason explicitly wants new app ideas. He is a working producer and
educator — roughly 50 videos a year, private lessons, a live rig, ~80 riff/tutorial project
folders. Ideas should come from *his actual friction*, not from a feature list. Read the
custom actions in his `reaper-kb.ini` and his toolbar in `reaper-menu.ini` — that is a
record of what he really does all day, and it is where the last four apps came from.

---

## Job 3 — THE CHALLENGE: rebuild his MainStage rig in REAPER

This is the flagship. Jason has years of real MainStage concert files from real paid gigs,
and wants to know whether REAPER can replace MainStage on the live laptop.

### What you have to work with

**120 `.concert` files.** The current one — last touched 26 July 2026 — is:

```
/Users/nphmacmini/Music/MainStage/NSM Tribute Night.concert
```

### The `.concert` format, already decoded

A `.concert` is a **bundle (a folder)**, not a single file:

```
NSM Tribute Night.concert/
├── base.plistZ              zlib-compressed NSKeyedArchiver plist
├── data.plist               Apple BINARY plist  (plutil -p reads it)
├── workspace.layout/
│   ├── setupZ.layout
│   └── layoutPreview.jpg
└── Concert.patch/
    ├── data.plist
    ├── Master.cst           channel strip
    ├── Metronome.cst
    ├── Output 1-2.cst
    ├── 1.0s Villa Bathroom.cst      reverb impulse presets
    ├── 1.3s Diffuse Hall.cst
    ├── 1.8s Large and Bright.cst
    ├── 3.9s Prince Hall One.cst
    ├── 1 PIANO_ARENA.patch/         each .patch is ALSO a folder:
    │   ├── data.plist               ├─ data.plist
    │   └── Piano Arena — Splendid Grand.cst
    ├── 2 GOSPEL_ORGAN.patch/
    ├── 3 MELLOTRON_PSYCH.patch/
    ├── 4 DX_EP_80S.patch/
    ├── 5 RHODES_SOUL.patch/
    ├── 6 ORCH_HIT.patch/
    ├── 7 SPACE_PAD.patch/
    └── 8 LEAD_MONO.patch/
```

**Everything in it is readable.** Confirmed:
- `base.plistZ` → `zlib.decompress()` → a valid `NSKeyedArchiver` plist
- `data.plist` → `plutil -p` prints it directly
- patches are **numbered in setlist order** in their own filenames — that is your setlist

Python starter:
```python
import zlib, plistlib, subprocess
raw = open("base.plistZ","rb").read()
plist = plistlib.loads(zlib.decompress(raw))          # NSKeyedArchiver
data  = plistlib.loads(open("data.plist","rb").read()) # binary plist
```

### The honest blocker — read this before you promise anything

The patches use **Logic/MainStage built-in instruments** — `Splendid Grand`, Vintage EP/B3,
and friends. **Those are Logic-only Audio Units. They do not exist outside Logic and REAPER
cannot load them.** No importer can fix that; it is a licensing and bundling fact.

So a faithful "open his concert in REAPER and it sounds identical" is **not achievable.**
What *is* achievable, and worth far more:

> Import the **structure** — setlist order, patch names, key/velocity zones, MIDI CC
> mappings, output routing, reverb sends — and **map each Logic instrument onto something
> Jason already owns.**

He owns **Pianoteq 8/9, Keyscape, Omnisphere, Arturia V Collection, ANA 2, UVI Workstation,
Lounge Lizard, Vintage/Electric pianos** (visible in his plugin list and his FX toolbar).
Build the mapping table as an explicit, editable part of the importer — never guess silently.
Tell Jason exactly which patch got which substitute and which ones you could not map.

### The architecture is already decided — do not relitigate it

From `docs/TECH_BRIEF.md` §7:

- **Nothing that touches audio is created, destroyed or reconfigured mid-set.** Everything
  that will ever make sound is instantiated at load.
- **One REAPER project = one concert.** Songs/patches are *tracks inside folders*. Project
  tabs and subprojects were both evaluated and **rejected** — switch latency and state loss
  are unacceptable live.
- **The setlist lives in project ExtState**, decoupled from the timeline, so reordering the
  set never touches audio routing.
- **Switch order:** unmute B first → gate A's input via JSFX → let A ring 1.5–3 s (or until
  below −60 dB) → mute A → send note-offs and CC64=0 to A.
- **One deferred state machine owns all transitions.** UI, MIDI and OSC handlers post
  intents to a queue; they never act directly. This kills ~90% of the race conditions that
  plague naive live-switching scripts.
- **Budget for 2 simultaneously active patches.** Anticipative FX off. Never take idle
  patches offline.

**Honest weaknesses to state up front, not bury:** REAPER has no native sample-accurate
patch-crossfade primitive; `reaper.defer` runs at UI cadence so decision latency is
~15–30 ms; ExtState needs defensive loading so a corrupt setlist cannot brick a show.

### The bar for calling it done

It is not "a MainStage killer" because a demo worked. The claim is earned only when
**a working keyboardist plays real paid shows on it and stops carrying a backup rig.**
Everything before that is a demo — label it as one.

**Suggested first deliverable:** a read-only `.concert` *reporter*. Point it at
`NSM Tribute Night.concert` and have it print the setlist, every patch, every channel strip,
every plugin referenced, and — critically — **which plugins have no REAPER equivalent.**
That single report tells Jason whether the whole idea is viable, costs a day rather than a
month, and cannot break anything.

---

## House rules that apply to any agent working for Jason

- **Never quit, close or save his REAPER project.** He runs a 452-track live session with
  unsaved work. The only REAPER recovery action ever permitted is the audio-device reinit
  script.
- **Never restart Core Audio** (`killall coreaudiod`) while a DAW is running. Check
  `pgrep -x REAPER` first. It severs the audio device and freezes REAPER while its internal
  "is running" flag still reads true.
- **Never trust `audio_is_running` or `get_play_state` to prove audio works.** Sample
  `get_play_position` twice with a gap and confirm the cursor actually advanced.
- He is a **non-coder**. Never hand him terminal commands. Do the work, or hand it to an
  agent that can. Report outcomes, not plans.
- His name is **Jason Zac**. Never "Zak", "Zach" or "Jack".
