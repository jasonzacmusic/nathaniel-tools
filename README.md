# NPH REAPER Suite

Dockable ReaImGui apps and a keyboard speed layer for REAPER, built by a working producer
for his own sessions.

**Jason Zac** · [Nathaniel School of Music](https://www.nathanielschool.com) ·
[daw.nathanielschool.com](https://daw.nathanielschool.com)

> These exist because his own sessions were slow, not because anyone surveyed a market.
> Every app in here replaces a REAPER custom action that was quietly doing the wrong thing.

**Status:** 68 automated checks passing, 0 failing, against REAPER 7.77 on macOS arm64.

---

## What's in it

### Apps (dockable, ReaImGui, one accent colour each)

| App | Colour | What it does |
|---|---|---|
| **Folders & Flow** | green | Fix, build, dissolve, move and isolate track folders. Repairs a session whose folder maths has gone wrong. |
| **Palette & Look** | violet | Colour and name tracks from *meaning* — rules, palettes, families, live watcher. |
| **Track Settings Transfer** | violet | Pro-Tools style "Import Session Data" across project tabs, in both directions. |
| **Stem Print & Handoff** | amber | Print stems in several modes and restore the session exactly afterwards. |
| **MIDI Batch Export** | amber | Export many MIDI items/regions as separate `.mid` files with pattern-based sequential names. |

### The speed layer (12 scripts, keyboard-bound)

Solo Focus · Record Arm Toggle · FX Float Toggle · FX Open/Close All · Region Next/Prev ·
Marker at Bar · Tempo at Bar · MIDI Render · Flush Paste · Duplicate Track · Unsolo & Unselect

Each one replaced a custom action that had a real, diagnosed bug — a pan-destroying step, a
global preference being toggled on every press, a marker snapping to the arrange grid
instead of the bar line. The root causes are documented in `docs/NPH_TECH_BRIEF.md`.

### The shared spine

- **`NPH/lib/nph_safe.lua`** — pointer safety and stable identity. The reason these apps
  cannot crash REAPER.
- **`NPH/lib/nph_hierarchy.lua`** — folder maths. Converts REAPER's `I_FOLDERDEPTH` integers
  to nesting levels, edits there, and regenerates. Well-formed output by construction.

---

## Two things that make this different from a folder of scripts

### 1. It cannot crash REAPER

REAPER frees a `MediaTrack*` the instant the track is deleted. Handing a freed pointer to
any REAPER API faults inside REAPER's own C++, and **Lua `pcall` cannot catch it** — the
host process dies, taking unsaved projects with it. Wrapping your draw loop in `pcall` is
false comfort.

Every app here stores **track GUIDs**, resolves them to pointers immediately before use,
validates with `ValidatePtr2`, and never holds a pointer across a defer frame. The test
suite deletes a track behind an app's back and asserts that every accessor returns a clean
default instead of faulting.

### 2. Folder edits are well-formed by construction

Folder scripts go wrong because they edit `I_FOLDERDEPTH` in place: a local edit that looks
right leaves the arithmetic unbalanced further down, and REAPER silently swallows the rest
of the session into a folder.

`nph_hierarchy` never edits depths. It converts to levels, edits there, and regenerates
every depth. The output always balances — it is not possible for the app to leave a folder
hanging open.

---

## Install

Requires **[ReaImGui](https://github.com/cfillion/reaimgui)** and
**[SWS](https://sws-extension.org)**.

Until the ReaPack repository is live:

1. Copy `NPH/` and `apps/` somewhere REAPER can see them.
2. *Actions → Show action list → New action… → Load ReaScript*, and pick each app.
3. Or run `tests/harness.lua` once — it registers everything for you and verifies the install.

Every script carries ReaPack metadata headers already, so publishing is a matter of wiring
`reapack-index` into CI.

---

## Testing

```bash
lua tests/hierarchy_test.lua      # 31 checks, no REAPER needed
```

Inside REAPER, run `tests/harness.lua` from the action list — 68 checks including live
crash-safety. It builds its scratch project **in its own tab** and closes it afterwards, so
it never touches the project you had open. Results land in `_nph_results.txt`.

> Edit `BASE` at the top of `harness.lua` to point at your install path.

---

## Two REAPER API traps documented here

Both cost real debugging time. Neither is in the official docs.

1. **`GetProjectStateChangeCount` does not detect track changes.** Measured in 7.77: it
   stayed on `8` across insert, rename *and* delete. Any change-watchdog built on it never
   fires. Use a track-list signature instead.
2. **`ValidatePtr2` rejects `0`** — even though `0` is ReaScript's shorthand for "the
   current project". Guards must special-case it or they return false for everything.

More in `docs/NPH_TECH_BRIEF.md`.

---

## Licence

MIT — see `LICENSE`.
