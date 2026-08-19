# Nathaniel Tools

Dockable ReaImGui apps and a keyboard speed layer for REAPER, built by a working producer
for his own sessions.

**Jason Zac** · [Nathaniel School of Music](https://www.nathanielschool.com) ·
[daw.nathanielschool.com](https://daw.nathanielschool.com)

> These exist because his own sessions were slow, not because anyone surveyed a market.
> Every app in here replaces a REAPER custom action that was quietly doing the wrong thing.

**Status:** 68 in-REAPER checks + 57 pure-Lua checks passing, 0 failing, against REAPER 7.77 / ReaImGui 0.10 on macOS arm64. Installed and verified end-to-end through ReaPack on the studio Mac, 19 Aug 2026.

**Plain-English user guide:** [docs/USER_GUIDE.md](docs/USER_GUIDE.md) (also on the site at `/guide`).

---

## What's in it

### Apps (dockable, ReaImGui, one accent colour each)

| App | Colour | What it does |
|---|---|---|
| **Palette & Look** | teal | Colour and name tracks from what they *are* — families, your own rules, palettes, live watcher. |
| **Folders & Flow** | green | Build, fix, dissolve, move and isolate track folders. Repairs a session whose folder maths has gone wrong. |
| **Track Settings Transfer** | green | Pro-Tools style "Import Session Data" across project tabs. Guesses stay unticked; transfer asks first. |
| **Stem Print & Handoff** | amber | Print stems (raw / inserts / fully wet / front-end), build a plugin-free handoff tab with the files on it, restore the session exactly. |
| **MIDI Batch Export** | amber | Export many MIDI items/regions as separate `.mid` files with pattern-based sequential names, tempo and time signature included. |
| **StageRig** | violet | Live patch switching that lets the outgoing patch ring out. Footswitch scripts `StageRig Next` / `StageRig Panic`. Early. |

All six windows share one look and one behaviour (`scripts/lib/nt_ui.lua`): header, sections,
one primary button, a status line that always says what happened (with a log), confirmation
before anything destructive, drag-paint tick columns, plain-English tooltips.

### The speed layer (12 scripts, keyboard-bound)

Solo Focus · Record Arm Toggle · FX Float Toggle · FX Open/Close All · Region Next/Prev ·
Marker at Bar · Tempo at Bar · MIDI Render · Flush Paste · Duplicate Track · Unsolo & Unselect

Each one replaced a custom action that had a real, diagnosed bug — a pan-destroying step, a
global preference being toggled on every press, a marker snapping to the arrange grid
instead of the bar line. The root causes are documented in `docs/TECH_BRIEF.md`.

### The shared spine

- **`scripts/lib/nt_safe.lua`** — pointer safety and stable identity. The reason these apps
  cannot crash REAPER.
- **`scripts/lib/nt_hierarchy.lua`** — folder maths. Converts REAPER's `I_FOLDERDEPTH` integers
  to nesting levels, edits there, and regenerates. Well-formed output by construction.
- **`scripts/lib/nt_ui.lua`** — the design system: tokens, fonts (ReaImGui 0.9 and 0.10),
  window/header/button/segmented/table/status/confirm/empty. Every window uses it.
- **`scripts/lib/nt_imgui.lua`** — bridges the enum constants ReaImGui renamed between releases.

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

`nt_hierarchy` never edits depths. It converts to levels, edits there, and regenerates
every depth. The output always balances — it is not possible for the app to leave a folder
hanging open.

---

## Install

Requires **[ReaImGui](https://github.com/cfillion/reaimgui)** and
**[SWS](https://sws-extension.org)**.

### With ReaPack (recommended)

This repository **is** a ReaPack repository. In REAPER:

1. **Extensions → ReaPack → Import repositories…**
2. Paste this URL and click OK:

```
https://github.com/jasonzacmusic/nathaniel-tools/raw/main/index.xml
```

3. **Extensions → ReaPack → Browse packages…**, filter on `Nathaniel Tools`, and install what you want.

Every package is signed with a SHA-256 checksum and every download is pinned to a git
commit, so an installed version can never change underneath you. Updates arrive through
**Extensions → ReaPack → Synchronize packages**.

### By hand

1. Copy `scripts/` and `apps/` somewhere REAPER can see them.
2. *Actions → Show action list → New action… → Load ReaScript*, and pick each app.
3. Or run `tests/harness.lua` once — it registers everything for you and verifies the install.

---

## Publishing (maintainer notes)

`index.xml` at the repository root is the ReaPack index. It is rebuilt automatically by
`.github/workflows/reapack.yml` on every push to `main`, and can be rebuilt by hand:

```bash
python3 tools/build_index.py --check   # validate headers, write nothing
python3 tools/build_index.py           # rebuild index.xml
```

`tools/build_index.py` is a dependency-free implementation of the
[ReaPack Index Format](https://codeberg.org/cfillion/reapack/wiki/Index-Format) — Python 3
and `git`, nothing else, and byte-identical output on any machine. CI also runs cfillion's
own [`reapack-index`](https://github.com/cfillion/reapack-index) in `--check` mode as a
second opinion on the headers.

Two rules for anything new that lands in `scripts/` or `apps/`:

- Every `.lua` / `.jsfx` file needs a metadata header with at least `@version`, or it
  fails the build. See the
  [Packaging Documentation](https://github.com/cfillion/reapack-index/wiki/Packaging-Documentation).
- Shared libraries carry `@noindex` and are listed in the `@provides` of the script that
  needs them, so they install alongside it instead of appearing as their own package.

Files must live in a subdirectory — ReaPack never indexes files at the repository root,
and the directory name becomes the category shown in ReaPack.

---

## Testing

```bash
lua tests/hierarchy_test.lua      # 57 checks, no REAPER needed
```

Inside REAPER, run `tests/harness.lua` from the action list — 68 checks including live
crash-safety. It builds its scratch project **in its own tab** and closes it afterwards, so
it never touches the project you had open. Results land in `_nt_results.txt`.

> Edit `BASE` at the top of `harness.lua` to point at your install path.

---

## Two REAPER API traps documented here

Both cost real debugging time. Neither is in the official docs.

1. **`GetProjectStateChangeCount` does not detect track changes.** Measured in 7.77: it
   stayed on `8` across insert, rename *and* delete. Any change-watchdog built on it never
   fires. Use a track-list signature instead.
2. **`ValidatePtr2` rejects `0`** — even though `0` is ReaScript's shorthand for "the
   current project". Guards must special-case it or they return false for everything.

More in `docs/TECH_BRIEF.md`.

---

## Licence

MIT — see `LICENSE`.
