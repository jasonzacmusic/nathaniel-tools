# NPH TECH BRIEF — The REAPER Suite

*(Previously circulated as `CLAUDE_CODE_BRIEF.md`. This is the current file. The
business half — YouTube, course, website, pricing — was split out into
`NPH_BUSINESS_BRIEF.md`; do not do both in one session.)*

**Owner:** Jason Zac / Nathaniel School of Music (music@nathanielschool.com)
**Machine:** Mac mini, macOS arm64, REAPER 7.77, registered to "Jason Zachariah"
**Working folder:** `/Users/nphmacmini/Documents/REAPER Media/`
**Date of handoff:** 25 July 2026
**Written by:** Claude Opus (Cowork session) for a fresh Claude Code session with zero prior context.

Read this file top to bottom before touching anything. Everything a previous
session learned the hard way is in here. Sections 1–4 are law. Section 5 is the
inventory. Section 6 is the work queue.

---

## 1. THE STANDING RULE

Verbatim, from the owner. It overrides normal cautious defaults:

> "Save it in your brain: always install, test, check everything, and then move on
> in life. Don't ask me for permission. Just use REAPER and move on."

Interpretation: do not ask "shall I install this?" Install it. Do not ask "shall I
run the test?" Run it. Do not present a plan and wait. Execute, verify with a real
REAPER run, then report what happened. He wants results, not check-ins.

The one thing he *does* want asked about is strategy and money — pricing, what to
build next, what to publish. Not mechanics.

---

## 2. THE VISION (so you know what you are building toward)

He is building a **suite of REAPER "inbuilt apps"** — ReaScript/Lua + ReaImGui —
that is meant to rival and then exceed the SWS extension in polish. Each app:

- is a **separate script** with its own **distinct, beautiful theme** (per-app accent colour)
- is **dockable**
- ships via a **ReaPack repository** he owns
- is pinned at **daw.nathanielschool.com**
- feeds a **REAPER course** at **learnmusic.nathanielschool.com**

The colour language already chosen:
green = structure · amber = delivery · violet = performance · teal = look.

The flagship, and the emotional centre of the project, is **StageRig** — a live
performance rig meant to *destroy MainStage*. He has years of real MainStage
concert files (MJ Tribute, Lagori, Rudy Wallang, Soul Circle Collective, and more)
sitting in his sessions folder and in his Google Drive. Those `.concert` files are
the spec. A **MainStage `.concert` importer is step one of StageRig** — locate the
files first (Drive search failed for the previous session; just ask him for a path
or use Spotlight via `mdfind -name .concert` on the Mac).

---

## 3. REAPER API TRAPS — hard-won, do not relearn these

### 3.1 `.ReaperKeyMap` import can NEVER modify an existing custom action
This is the single most important discovery of the whole project.

- Importing an `ACT` line whose **step count matches** an existing action of the
  same name → **complete no-op**. REAPER silently ignores it.
- Importing an `ACT` line whose **step count differs** → REAPER creates a **brand
  new action named `"Name (2)"`** with a fresh GUID. The original is untouched.
- **`KEY` lines always merge correctly.**

Consequence, and the architecture of the entire suite: **everything is a ReaScript,
and keymap imports contain KEY lines only.** Never try to fix a broken custom action
by importing a corrected version of it. Replace it with a script.

### 3.2 `reaper-kb.ini` grammar
```
ACT <flags> <section> "<guid32hex>" "<name>" <cmd> <cmd> ...
SCR <flags> <section> RS<hash> "<name>" <path>
KEY <mod> <key> <cmd> <section>
```
Field 1 is **flags**, field 2 is **section** (0 = Main, 32060 = MIDI Editor).
An earlier session got these backwards; they are correct here.

Modifier values for section 0:
`1` plain · `5` Shift · `9` Cmd · `13` Cmd+Shift · `17` Opt · `24`/`25` Cmd+Opt ·
`32`/`33` Control · `37` Control+Shift · `41` Cmd+Control · `57` Cmd+Opt+Control ·
`144` MIDI Note · `176` MIDI CC.
Virtual keys **96–105 = NumPad 0–9**.

### 3.3 Registering scripts programmatically
```lua
local cmd = reaper.AddRemoveReaScript(true, 0, path, true)   -- returns cmdID
local tok = reaper.ReverseNamedCommandLookup(cmd)            -- returns "RS<hash>"
```
Prefix `tok` with `_` to get the form used in KEY lines and `NamedCommandLookup`.

### 3.4 `Main_SaveProjectEx` writes the file but does NOT rebind the tab
**Corrected finding — an earlier draft of this brief had the mechanism wrong.**

`reaper.Main_SaveProjectEx(0, path, 0)` writes the `.RPP` to disk **immediately**
— the file appears with a fresh mtime while your script is still running. What it
does **not** do is rebind the current tab to that path. `EnumProjects(-1, "")`
keeps returning `""` and the title bar keeps saying `[unsaved project]` forever,
not just until the script returns. So any gate of the form
`if EnumProjects(-1,"") == RPP then …` will never fire, and any later
`Main_OnCommand(40026, 0)` still pops Save-As.

The fix is **three phases**, with the phase held in `SetExtState`/`GetExtState`/
`DeleteExtState("NPH_TEST","phase")` rather than inferred from project state:

1. build the project and `Main_SaveProjectEx(0, RPP, 0)`, then `return`
2. `Main_openProject("noprompt:" .. RPP)`, then `return`
3. now the tab really is bound — run the tests

Verified working: after phase 2 the title bar reads `_nph_test [proj 4/4]`.

### 3.5 `TimeMap_GetDividedBpmAtTime` lies
It reports the **project-start tempo regardless of the position you pass**, even
after `UpdateTimeline()`. It said 120 where the measure map said 140. Do not use it.

Use instead, in this order:
1. `TimeMap_GetMeasureInfo(0, m)` → `retval, qn_start, qn_end, num, den, tempo` — the **6th return is the tempo**
2. `TimeMap_GetTimeSigAtTime(proj, time)` → `num, den, tempo`
3. `Master_GetTempo()` as a last-resort fallback

### 3.6 The "tempo is very tough to lock" bug — measured, not guessed
**Corrected finding — an earlier draft of this brief had this completely wrong.**
It claimed `SetTempoTimeSigMarker(proj, -1, …)` stacks duplicates. It does not.

Measured in REAPER 7.77 (test pass 5, verbatim from the results file):
```
ptidx=-1 on an occupied bar: ok=true  2 -> 2 markers, bar6 now 150.0 bpm
PASS  Tempo: ptidx=-1 on an occupied bar REPLACES, does not stack
```
When the new marker lands on the **exact** position of an existing one, REAPER
replaces it cleanly. Marker count does not grow.

**The real mechanism behind his complaint** is the old custom action's step
`40256`, which inserts a tempo marker at the **raw, unquantized edit cursor**. Every
press lands a few milliseconds from the last one, so the tempo map accumulates
near-duplicates that all *look* like they are on the same bar and fight each other.
Quantizing the insert to the bar line removes the cause entirely. That is what
`NPH_Tempo at Bar.lua` does.

#### The `beatpos = 1e-11` trap — this one is real and it silently broke the fix
`GetTempoTimeSigMarker` returns `beatpos = 1e-11`, **not `0`**, for a marker
sitting exactly on a bar line. Verified dump:
```
[1] ok=true tpos=10.0 mpos=5 bpos=1e-11 bpm=140.0 sig=4/4 lin=false
```
So the obvious locate rule `if measurepos == bar and beatpos == 0` **never matches,
ever**, and the first version of the fix found nothing and inserted instead of
editing. Match with a tolerance, and cross-check on time:
```lua
local onBar = (mpos == bar and math.abs(bpos or 0) < 1e-6)
              or (tpos and math.abs(tpos - barTime) < 1e-3)
```
Verified in test pass 9: *"the new rule FINDS the marker on bar 6 (the old one
returned -1)"* PASS, *"and does NOT false-positive on empty bar 10"* PASS,
*"edit in place adds no marker"* PASS.

Prefer the **measure-based** form — `SetTempoTimeSigMarker(0, idx, -1, bar, 0, bpm, n, d, false)` —
so the marker stays welded to the bar line instead of drifting when upstream
tempos change. If that returns false (can happen for the project's first,
time-based marker) fall back to the time-based form.

### 3.6b Relative grid snap — identify commands, never assume them
`CF_GetCommandText(0, cmd)` (SWS) is the fastest way to find out what a numeric
command ID actually does. **Use it before theorising.** It cost me two wrong bug
theories not to.

Measured (test pass 8):
```
41052 = Item edit: Enable relative grid snap     <- a SETTER, idempotent, NOT a toggle
41053 = Item edit: Disable relative grid snap
41054 = Item edit: Toggle relative grid snap
1157  = Options: Toggle snapping                 <- this one DOES report toggle state
40145 = Options: Toggle grid lines
41051 = Item properties: Toggle take reverse
```
Reading its state:
- `GetToggleCommandState(41052)` and `GetToggleCommandStateEx(0, 41052)` both
  return **-1**. Any guard of the form `if GetToggleCommandState(41052) ~= 1` is
  therefore **always true**.
- It is **not in the project file** either — the `GRID` line was byte-identical
  across toggles (`GRID 273551 8 0.5 8 1 1 0 0` → unchanged). It is **global, not
  per-project**.
- The only readable source is SWS: `SNM_GetIntConfigVar("relsnap", 0)`.
  Other confirmed-valid SNM vars: `projmeasoffs`, `projfrbase`, `itemtimelock`.
  Ones that do **not** exist (they return your errvalue): `projgridflags`,
  `projgriddivmode`, `projsnapmode`, `gridflags`.

This meant the old Flush Paste chain's blind `41052` press was **harmless** —
because 41052 sets rather than toggles. Had anyone "helpfully fixed" it to 41054 it
would have flipped relative snap on every single press.

### 3.7 Bar/time conversion
```lua
local beats, measures, cml, fullbeats, cdenom = reaper.TimeMap2_timeToBeats(0, pos)
-- measures is a 0-BASED bar index
local _, qn = reaper.TimeMap_GetMeasureInfo(0, m)
local barTime = reaper.TimeMap2_QNToTime(0, qn)
```

### 3.8 His REAPER has a default track FX chain
**Every newly inserted track already carries `VST3: Eiosis AirEQ Premium (Eiosis)`.**
Any test that counts FX must probe it at runtime:
```lua
local FXPER = reaper.TrackFX_GetCount(someBareTrack)
```
Two "failures" in test pass 1 were this, not bugs.

### 3.9 Crash safety — this is why Track Settings Transfer used to crash
- `reaper.ValidatePtr2(proj, ptr, "MediaTrack*")` is the **only** defence against
  dangling pointers after the user deletes tracks, undoes, or reorders.
- `reaper.GetTrackGUID(track)` is the **only** stable identity across
  delete / undo / reorder / project-tab switching. Never cache raw `MediaTrack*`
  across defer cycles. Cache GUIDs, resolve to pointers each frame, validate.

### 3.10 `itemtimelock` / project timebase trap
`itemtimelock = 0` means the project timebase is **Time**, not Beats. His projects
are set this way, and his arrange grid division is `0.125` (1/8 note). This is why
BR-based marker snapping obeyed the 1/8 grid instead of bar lines. App #5
(Sections and Time) should surface a per-track timebase view so this stops biting.

### 3.11 Useful API reference used throughout
`GetSet_LoopTimeRange2` · `EnumProjectMarkers3` (returns `retval, isrgn, pos, rgnend, name, idx`) ·
`GetPlayState() & 1` · `GetPlayPosition()` · `IsProjectDirty(0)` ·
`EnumProjects(-1, "")` → `ReaProject, path` ·
`TrackFX_GetFloatingWindow(tr, fx)` · `TrackFX_Show(tr, fx, 3 = float, 2 = hide float)`.

---

## 4. TESTING METHODOLOGY — use this, it works

### 4.1 The file-based Lua harness beats driving the UI
Do not try to verify script behaviour by taking screenshots and reading the
ReaScript console. **The console is effectively unreadable via screenshot.**

Instead: there is a permanent **execution slot** on the Mac at
`/Users/nphmacmini/Documents/REAPER Media/_harvest_scripts.lua`
registered as Command ID `_RSaed0646d7d7829709496637aee256abbfb8b5198`, with **no
key binding**. Overwrite that file with whatever test you want to run, then run it
from the Actions window. The script calls
`Main_OnCommand(NamedCommandLookup("_RS…"), 0)` for each script under test, asserts
project state, and **writes PASS/FAIL lines to a text file**. Then read the text file.

Files are the only reliable channel between REAPER and you.

### 4.2 Running it from the Actions window
Open Actions, filter, single-click the row, click **Run**.

- **Filter with the shortest possible string.** `vest` works. `harvest` failed
  repeatedly. See 4.3.
- **Single-click the row, then click the Run button.** A double-click runs the
  script twice.
- Approximate coordinates observed on his screen: the filtered row sits near
  **(280, 424)**; the **Run** button near **(999, 699)**. Screenshot to confirm
  before clicking — window position drifts.

### 4.3 Wispr Flow keystroke hazard
**Wispr Flow (voice dictation) runs on his Mac and intercepts/injects keystrokes.**
Screenshots report: `"Wispr Flow" was open and got hidden before this screenshot
(not in the session allowlist)`.

Observed damage: typing `harvest` into the Actions filter produced `arest`, then
`havet`; per-character typing produced `did you fini` and triggered a spurious
"Dynamic split items" modal. Mitigations:
- shortest possible filter strings
- always screenshot-verify the field before clicking Run
- **if you can, quit Wispr Flow before an automated run** — it removes the whole
  class of failure

### 4.4 Other UI gotchas
- `computer_open_application` takes **`app`**, not `text`.
- `computer_resolve_access` needs `apps: ["REAPER"]` — REAPER is granted at `full` tier.
- The `Write` tool rejects with "File has been modified since read" after a Bash
  `cp` — `Read` the file first.
- Clipboard write is not granted (`clipboardWrite` would need `request_access`).

### 4.5 Cloud vs device filesystems
In the Cowork session the container's bash **cannot see the Mac**. Transfers went
through `device_list_dir` / `device_stage_files` / `device_commit_files`.
**In Claude Code running on the Mac this problem disappears** — that is a large
part of why the move to Claude Code is the right call.

**Trap: the `/mnt/user-data/uploads/` mount serves a STALE CACHED COPY.**
`device_stage_files` reported `_test_results3.txt` at 1572 bytes while `cat` of the
staged path returned the previous run's 61-byte content, and the `Read` tool
answered *"Wasted call — file unchanged since your last Read"*. Reading a file the
Mac just rewrote through that mount will silently give you the previous run's
results and you will draw conclusions from stale data. The only reliable read is
`device_bash`:
```bash
cat "$(echo /sessions/*/mnt)/REAPER Media/_test_results3.txt"
```
Note `device_bash` cannot resolve `/Users/nphmacmini/…` — the mount root is
`/sessions/<session-id>/mnt/REAPER Media/`. It also cannot `rm`; move unwanted
files into a `_to_delete/` subfolder instead.

**Always verify a run actually happened before reading its output.** Compare the
results file's mtime against the script's via `device_bash`. One pass silently did
not run (the Actions row had lost focus) and the results file still held the
previous pass — `_harvest_scripts.lua` 08:31 vs `_test_results3.txt` 08:30 was the
tell.

Syntax check before installing anything: `luac5.4 -p <file>`.

---

## 5. CURRENT STATE — inventory and ledger

### 5.1 The 12 speed-layer scripts
All live in `/Users/nphmacmini/Documents/REAPER Media/NPH/`, all registered.
Authoritative map is `_register.txt`:

```
NPH_Solo Focus.lua           cmd 55885     _RS533bc7a18dffdf54bc42d5d9adefb880e9cf62de
NPH_Record Arm Toggle.lua    cmd 55886     _RS268630c3a15f277043c45f059827a25fa7471ab4
NPH_FX Float Toggle.lua      cmd 55887     _RS8d5c113ed44383702a49d6c52552fd87733c93e6
NPH_FX Open Close All.lua    cmd 55888     _RSc36afb1f4ea0cf8f68b2ada12abb0d8b4d4e3783
NPH_Region Next.lua          cmd 55889     _RS85008a203cd065e20a9d48c81552a5cf60084efa
NPH_Region Prev.lua          cmd 55890     _RS6bcbc85d288be9422448dc8ac7ad61cfd5cb4b52
NPH_Marker at Bar.lua        cmd 55891     _RS61e0a7e30914c6be0091573562f0c144e831e5e6
NPH_Tempo at Bar.lua         cmd 55892     _RS0bb0d4205ed51a7a03ea6902879ece4da76dea1a
NPH_MIDI Render.lua          cmd 55893     _RSf4f34fceaa51f44e1e1ff17fbd978a3ef302cff6
NPH_Flush Paste.lua          cmd 55894     _RS8a1922a2686132cd22f5b6617875f52c14ef4939
NPH_Duplicate Track.lua      cmd 55895     _RS51cab0ca51c65b37df027d64b8e95b2e9a94aeb0
NPH_Unsolo Unselect.lua      cmd 55896     _RSa171766c8d9609767b1b3e2275eff8d3d848c237
```
Plus `Track Settings Transfer.lua` at **cmd 55876** (v4, installed, never exercised).
The harness execution slot is `_harvest_scripts.lua` =
`_RSaed0646d7d7829709496637aee256abbfb8b5198`.

> **The numeric cmd IDs above are STALE. The `_RS…` GUID tokens are authoritative.**
> A live run resolved `marker=55890 flush=55893` where `_register.txt` records
> 55891/55894 — they have drifted by one. Always resolve with
> `reaper.NamedCommandLookup("_RS…")`, never hard-code the integer.

### 5.2 The 16 key bindings (already imported and screenshot-verified)
```
A                      Solo Focus
Shift+A                Record Arm Toggle
Cmd+Opt+Ctrl+U         Record Arm Toggle
MIDI CC 75             Record Arm Toggle
NumPad 6               FX Float Toggle
Shift+F                FX Open Close All
MIDI CC 76             FX Open Close All
N                      Region Next
B                      Region Prev
M                      Marker at Bar
MIDI CC 23             Marker at Bar
Cmd+Shift+T            Tempo at Bar
Shift+Ctrl+M           MIDI Render
Cmd+Ctrl+V             Flush Paste
Shift+D                Duplicate Track
E                      Unsolo & Unselect
```
Raw KEY lines are in `/home/claude/NPH_Bindings.ReaperKeyMap` (container) — if you
need them again, regenerate from `_register.txt` + this table.

### 5.3 What each script fixed
| His complaint | Root cause found | Key | Test status |
|---|---|---|---|
| "Solo selected doesn't work" | `_SWS_SELTRKWITEM` cleared track selection when no item was selected | `A` | 3/3 PASS |
| "Record toggle doesn't work at all" | it had **no key binding anywhere** | `Shift+A` | 3/3 PASS |
| XOR Record Arm destroyed pan | ran `_XENAKIOS_PANTRACKSCENTER` | `Shift+A` | PASS, pan byte-identical |
| XOR Float FX could only open | targeted last-touched track; `_S&M_WNCLS3` ran first | `NumPad 6` | 3/3 PASS |
| Open/Close ALL inverted | 8 independent toggles instead of one decision | `Shift+F` | 5/5 PASS |
| Region Switch flipped a global pref | step 2 was `_BR_OPTIONS_MOVE_CUR_ON_TIME_SEL` | `N` / `B` | 7/7 PASS |
| Markers not on bars | BR snap obeyed the 1/8 arrange grid | `M` | 4/4 PASS |
| Tempo "very tough to lock" | `40256` at raw cursor + the two API bugs in §3.5/§3.6 | `Cmd+Shift+T` | **fix installed, NOT yet verified** |
| Unsolo & Unselect | — | `E` | 4/4 PASS |
| Duplicate Track kept automation | `40065` cleared only the *selected* envelope | `Shift+D` | 7/7 PASS |
| MIDI Render bypassed the guard | — | `Shift+Ctrl+M` | guard PASS; modal `40849` is hand-verify only |
| Flush Paste popped Save-As | step 5 was `40022` instead of `40026` | `Cmd+Ctrl+V` | **code fixed, NOT yet verified** |

**52 assertions run across two harness passes.** Every FAIL in passes 1 and 2 was
either a bad assertion of mine or the Eiosis default-FX-chain artefact, with two
exceptions — which turned out to be the two genuine REAPER API bugs in §3.5 and §3.6.

### 5.4 The honesty ledger — what is NOT proven
**First, what IS proven.** The harness has now been run nine times — 82 assertions
across four scoring passes — and the last three scoring passes were clean:

| pass | result | what it settled |
|---|---|---|
| 4 | 11 passed, **5 failed** | exposed that my tempo-stacking and relative-snap theories were BOTH wrong |
| 5 | **18 passed, 0 failed** | `ptidx=-1` REPLACES, does not stack; `beatpos = 1e-11` |
| 6 | diagnostic | `relsnap` is global, not in the project `GRID` line |
| 8 | diagnostic | `CF_GetCommandText` → 41052 is *Enable*, not *Toggle* |
| 9 | **12 passed, 0 failed** | both shipped fixes verified end to end |

Pass 9 highlights: Flush Paste turns relative snap back ON across three presses
including one disabled behind its back, clears the track selection, and saves with
`IsProjectDirty(0) == 0` and **no dialog**; the tempo locate rule finds the marker
on bar 6, does not false-positive on empty bar 10, edits in place without growing
the marker count, and bar 6 still starts at exactly 10.000 s.

---

### UPDATE — 3 August 2026 (Claude Code session, REAPER 7.77, empty scratch project)

**A full line-by-line audit of all 16 files was run. Nine defects were found and fixed.
Three of them could crash REAPER outright.**

The single most important finding: **the pointer-safety work described in §3.9 existed
in Track Settings Transfer ONLY.** It was never carried across to the other two apps.

| # | File | Defect | Status |
|---|---|---|---|
| 1 | `Palette and Look.lua` | `rows` cached raw `MediaTrack*` and dereferenced it every frame in the UI table (`trackU32(row.track)`, `setCol(row.track, ...)`). Deleting/undoing/reordering a track with the window open = guaranteed hard crash. The surrounding `pcall(frame)` is false comfort — it cannot catch a native fault. | **FIXED** — GUID rows, per-frame `liveMap()` + `ValidatePtr2`, tombstone display, state-change watchdog |
| 2 | `Stem Print and Handoff.lua` | Same stale-pointer bug. Worse: `restoreAll()` ran **outside** the `pcall` and wrote through pointers captured *before* a multi-minute render, so a fault mid-restore left tracks stuck at unity gain / centre pan. | **FIXED** — GUID snapshots re-resolved after render; vanished tracks skipped and reported |
| 3 | `Track Settings Transfer.lua` | **The reported "import from another session doesn't work one way" bug.** Picking a new source removed it from `targetSel` but nothing replaced it → zero targets → `ensureFocus()` nulled `focusTarget` → the whole row list vanished behind "Select a target project above." Symptom was direction-asymmetric, exactly as described. | **FIXED** — swap semantics (old source inherits target slot) + a `<-> Swap` button |
| 4 | `NPH_Duplicate Track.lua` | Cleared `I_RECARM` on **every track in the project** and never restored it. On the 452-track live rig, one press silently destroys the record setup. | **FIXED** — arm state snapshotted by GUID and restored; only the new duplicates stay armed |
| 5 | `NPH_Solo Focus.lua` | `AUDITION = true` moved the edit cursor to the **mouse position** and started playback on every solo press. | **FIXED** — defaults to `false`, flag documented at the top |
| 6 | `NPH_Flush Paste.lua` | `40026` on a never-saved project opens **Save As** — the exact modal the rewrite existed to remove. | **FIXED** — guards on the project having a path, explains itself instead |
| 7 | Toolbar (`reaper-menu.ini`) | `Main toolbar item_21` still points at the ORIGINAL `Custom: Midi Render` = `_SWS_SAFETIMESEL 40849`. The *key* was migrated; the *button* never was. Verified: this is the **only** one of the 14 old custom actions still reachable from any key or toolbar. | **NEEDS A CLICK** — cannot be edited while REAPER is running (it rewrites the file on quit) |
| 8 | — | No way to export N MIDI files at once with sequential names. `40849` is single-file and modal. | **BUILT** — `NPH/NPH_MIDI Batch Export.lua`, writes SMF bytes directly |
| 9 | — | Pointer safety was per-app folklore, not shared code. | **BUILT** — `NPH/lib/nph_safe.lua` |

**Also found:** `Stem Print and Handoff.lua` was **never registered as an action** — which is
why its crash was never hit. It has effectively never been run.

**New/changed files**
```
NPH/lib/nph_safe.lua              NEW  shared pointer-safety + GUID identity spine
NPH/NPH_MIDI Batch Export.lua     NEW  batch SMF export, amber, dockable
NPH_AUDIT_REPORT.html             NEW  the findings report for Jason
_harvest_scripts.lua              REWRITTEN as an install+verify harness
```


### 3 Aug 2026 (later) — Folders & Flow shipped, repo published

**Folders & Flow (App #4, green) is built, registered and verified.** It is the first app
built on the shared spine from the start.

The design decision that matters: it **never edits `I_FOLDERDEPTH` directly.** It converts
depths to nesting LEVELS, edits there, then regenerates every depth from the levels. The
output is well-formed by construction, so the "unclosed folder swallows the rest of the
session" bug is not reachable from this app. Maths lives in `NPH/lib/nph_hierarchy.lua`,
covered by 31 pure-Lua checks that run without REAPER (`tests/hierarchy_test.lua`).

Features: repair folder maths · make folder from ticked · indent / outdent · remove from
folder · dissolve (children promote, nothing deleted) · move a whole subtree up/down ·
isolate a folder · auto-group adjacent tracks by shared first word · contiguous drag-paint
selection. `_SWS_UNFOLDER` and `_SWS_MOVETRACKUP/DOWN` are absent on this install, so none
of it leans on SWS.

**A real bug the harness caught:** `makeFolder` originally incremented child levels
relatively. On tracks that were ALREADY nested, sanitize then clamped inconsistently and the
new folder silently swallowed everything after it. Fixed by shifting children so the
shallowest sits one below the parent (preserving their relative nesting) and explicitly
popping anything after the range back out to the parent's level. Regression test added.

**Harness now: 68 passed, 0 failed.**

**Published:** `https://github.com/jasonzacmusic/nph-reaper-suite` (PRIVATE).
Every script carries ReaPack metadata headers (`@description @version @author @link
@donation @about @provides @changelog`). Verified by cloning back from GitHub and re-running
the pure-logic suite from the clone: 31/31.

**`docs/FABLE_HANDOFF.md`** is the brief for the second machine. It includes the decoded
MainStage `.concert` format and the honest blocker for the StageRig challenge:

> The patches use Logic/MainStage built-in instruments (`Splendid Grand`, Vintage EP/B3).
> Those are Logic-only AUs and REAPER cannot load them. A faithful sonic recreation is NOT
> achievable. Importing the STRUCTURE — setlist order, patch names, zones, CC maps, routing
> — and mapping each Logic instrument onto something Jason already owns (Pianoteq, Keyscape,
> Omnisphere, Arturia V) is achievable and is worth more.

Current concert: `/Users/nphmacmini/Music/MainStage/NSM Tribute Night.concert`, 8 numbered
patches. Format is fully readable: `base.plistZ` = zlib + NSKeyedArchiver, `data.plist` =
binary plist, each `.patch` is itself a folder holding a `.cst` channel strip.

---

### VERIFIED LIVE — 55 passed, 0 failed (3 Aug 2026, REAPER 7.77)

Two further defects were found *during* live testing, both of which had been shipped
and never noticed:

| # | Defect | Status |
|---|---|---|
| 10 | **`GetProjectStateChangeCount` does not detect track changes.** Probed directly: it stayed on `8` across insert, rename AND delete. Every watchdog in the suite was built on it, so **none of them had ever fired** — including Track Settings Transfer's "Auto-sync", which its own header claims rebuilds on add/delete/rename. | **FIXED** — all apps now diff a cheap track-list signature (count + GUID + name + folder depth), throttled to 4Hz |
| 11 | `nph_safe.projAlive(0)` returned **false**. `0` is ReaScript's standard shorthand for "the current project", but `ValidatePtr2` rejects it. Any future app using the ordinary `0` idiom would have had every guard silently return false and do nothing. | **FIXED** — caught by the harness on its first run |

**Live proof, not inference.** With Palette & Look open on its Tracks tab I deleted a
track through the API. Old code: guaranteed hard crash. Observed: the row rendered as a
red `(deleted)` tombstone, REAPER kept running; after the watchdog fix the row simply
disappeared and a renamed track updated instantly. `Stem Print and Handoff.lua` and
`NPH_MIDI Batch Export.lua` are now **registered** (they were not before).

The harness `_harvest_scripts.lua` is now the standing regression gate: it registers all
16 scripts, compiles each, builds a 5-track scratch project **in its own tab**, deletes a
track behind the app's back, asserts every safe accessor returns a clean default rather
than faulting, checks `projSignature` moves on delete, exercises `normaliseFolders`, then
closes the tab and returns to the tab you started on. Result file: `_nph_results.txt`.

**Only one thing could not be done from outside REAPER:** repointing the toolbar's
`Midi Render` button. REAPER holds `reaper-menu.ini` in memory and rewrites it on quit,
so an external edit is discarded. Right-click the button → Customize toolbar → Change
action → `Script: NPH_MIDI Render.lua`.

---

**Verification status of the earlier claims — read this honestly.**
All 16 files compile (`luac -p`, clean). The SMF writer was proven by generating a file and
parsing it back with an independent reader: chunk lengths, tempo, time-signature and every
note's pitch and delta survive exactly. **The crash fixes were NOT exercised live** — screen
control was declined and the MCP bridge stopped responding mid-session. They are correct by
construction and reviewed line by line, but the honest label is *reviewed, not yet run*.

To close that gap: run `Custom: _harvest_scripts.lua` from the Actions list. It registers every
script, compiles each one, checks the environment, exercises `nph_safe`, and writes PASS/FAIL
to `_nph_results.txt`.

**Still open from the original queue:** items 5 (rest of the shared spine — `nph_names`,
`nph_hierarchy`, `nph_time`), 6 (Folders and Flow), 7 (Sections and Time), 9 (StageRig),
10 (ReaPack packaging). The drag-paint retrofit into Palette and Look is also still open.

---

**Now, what is NOT proven:**

1. **The three modal actions have never been hand-verified:** the `Cmd+Shift+T`
   tempo input box, `Shift+Ctrl+M` MIDI Render (`40849`), and `Cmd+Ctrl+V` Flush
   Paste in a real saved project (must save with **no** dialog).
3. **Track Settings Transfer v4** (the crash fix) is installed as cmd 55876 and has
   **never been exercised in REAPER**. Test: two project tabs, delete tracks from
   source and from target mid-session, close a tab, confirm no crash and that ticks
   and remaps survive auto-resync.
4. **Palette and Look** has large untested surfaces: Name from items, Name+Colour,
   numbering, the Palettes tab, the Tools tab, the Tracks tab Now→Want flow, the
   LIVE watcher, Dock, Export to SWS.
5. **Stem Print and Handoff** has an unverified render pass.
6. `Duplicate: duplicate name = 'TEST 4'` — REAPER keeps the source name verbatim.
   Auto-incrementing is a wanted improvement, not a bug.

### 5.5 Actions-window orphans to delete
Leftovers from the failed `.ReaperKeyMap` experiments (see §3.1). Delete these:
`Custom: Solo Selected Items (2)`, `Custom: XOR Record Arm (2)`,
`Custom: Region Switch (2)`, `Custom: Region Switch Back`, `Custom: Jason Auto`,
`Custom: Auto Select`.
Also clean up: `_test_results*.txt`, `_nph_test.RPP*`, and any disposable test tabs.

### 5.6 Files on the Mac (`/Users/nphmacmini/Documents/REAPER Media/`)
Scripts: `NPH/` (12 scripts), `Palette and Look.lua`, `Track Settings Transfer.lua`,
`Stem Print and Handoff.lua`, `_harvest_scripts.lua`, both `.ReaperKeyMap` files.
Diagnostics: `_register.txt`, `_test_results.txt`, `_test_results2.txt`,
`_action_audit.txt`, `_kb_dump.txt`, `_harvested_scripts.md` (149 KB — every custom
action he had), `_probe.txt`, `_sws_config.md`, `_track_dump.txt`, `_verify.txt`.
Also: `_nph_test.RPP`.

**And hundreds of real session folders** — Lagori, Rudy Wallang, Sly Fly Blues,
Soul Circle Collective Choir, MJ Tribute Live Rig, bootcamps, and ~80 dated
Riffs/Tutorials/Freestyle folders. **These are the raw material for the course.**
(`MJ Tribute Live Rig/` currently holds only `_build_rig.lua` and a 108-byte stub `.RPP`.)

### 5.7 Design documents (currently in the Cowork container — re-create or ask for them)
- `StageRig — MainStage Killer Design.md` (8.6 KB) — summarised in §7 below
- `REAPER Suite — Ideation Board.md` (6.3 KB)
- `NPH_JARVIS_ARCHITECTURE.md` (20 KB)
- `NPH_DAW_Masterplan.html` — the 15-slide deck delivered alongside this brief

---

## 6. THE WORK QUEUE — do these in order

**1. ~~Run the automated harness.~~ DONE — pass 9 came back 12 passed, 0 failed.**
The harness slot `_harvest_scripts.lua` on the Mac still holds the pass-9 script;
re-run it any time you touch `NPH_Flush Paste.lua` or `NPH_Tempo at Bar.lua` as a
regression gate. It needs the `_nph_test.RPP` scratch project as the active tab.
Read the result with `device_bash`/local `cat`, never through a cached mount, and
check the mtime advanced first (§4.5).

**2. Hand-verify the three modal actions.** *This is now the first real job* —
they cannot be automated because they open modal dialogs, and they are the only
things standing between "tested" and "signed off". `Cmd+Shift+T` on a bar that already has
a tempo marker (the dialog title should say "editing" and the marker count must not
grow). `Shift+Ctrl+M` with and without a time selection. `Cmd+Ctrl+V` in a real
saved project — **no Save-As dialog is the pass condition**.

**3. Test Track Settings Transfer v4 for crashes** (see §5.4 item 3).

**4. Clean up the orphans** (§5.5).

**5. Extract the shared spine.** Create `nph_ui.lua`, `nph_names.lua`,
`nph_hierarchy.lua`, `nph_time.lua`. First job for `nph_ui.lua`: lift the
**contiguous mouse-drag select/deselect** (`paintApply` / band pattern) out of
Track Settings Transfer v4 — it exists only there — and retrofit it into Palette
and Look. He explicitly asked for drag-paint selection in **every** app. Verify
Palette and Look still behaves byte-identically after the refactor.

**6. Build App #4 — Folders and Flow** (green). Preserve his non-traditional
shortcuts: `F` = `_SWS_MAKEFOLDER`, `` ` `` = `1042 41665`. Add: remove a track from
a folder, fix wrong nesting, promote/demote, dissolve, move subtree, focus/isolate,
auto-build folders from track names. **`_SWS_UNFOLDER` and `_SWS_MOVETRACKUP/DOWN`
do not exist on his install** — implement with `I_FOLDERDEPTH` arithmetic.

**7. Build App #5 — Sections and Time** (green). Revive `NPH_RIFF_Marker.lua`
(remove its `do return end` guard). Absorb Marker at Bar, Tempo at Bar, Region
Next/Prev. Add named marker types (`C202`, `V218`, `V127.3`). Surface the
`itemtimelock` timebase trap with a per-track timebase view.

**8. Verify App #2 — Render and Deliver / Stem Print.** Then add gain matching.

**9. Build StageRig** (violet) — §7.

**10. Package for release — the *technical* half of publishing.** Add the ReaPack
metadata headers to every script (`@description @version @author @about @changelog
@provides @link @donation`), create the git repo `nathanielschool/reaper-suite`, and
wire `reapack-index` into a GitHub Action so `index.xml` rebuilds on every push.
**Verify the header spec at `codeberg.org/cfillion/reapack` first** — the ReaPack
GitHub wiki was archived on 3 June 2026 and reapack.com now carries end-user docs
only. Stop at a working `index.xml` that a test REAPER install can subscribe to.

Everything past that point — pricing, the landing page, the free/pro split, the
course, YouTube — is **not your job in this session.** It is in
`NPH_BUSINESS_BRIEF.md`.

---

## 7. STAGERIG — the flagship

### Hard architectural rules (already decided, do not relitigate)
- **Nothing that touches audio is created, destroyed, or reconfigured mid-set.**
  Everything that will ever make sound is instantiated at load.
- **One REAPER project = one concert.** Songs/patches are **tracks inside folders**.
  Project tabs and subprojects were both evaluated and **rejected** for live
  switching — the switch latency and state loss are unacceptable.
- **The setlist lives in project ExtState**, decoupled from the timeline, so
  reordering the set does not touch audio routing.

### The switch operation, in order
1. **Unmute B first** (the incoming patch)
2. **Gate A's input** via a JSFX (stop new notes reaching the outgoing patch)
3. **Let A ring** 1.5–3 s, or until below −60 dB, then mute
4. **Send note-offs and CC64 = 0** to A

### The note-tracker JSFX
Sits on the master key input. Maintains a held-note bitmap plus sustain state. On
switch it emits matching note-offs, can optionally re-strike held notes on the
incoming patch, and replays CC64. This is what makes a mid-phrase patch change
survivable.

### Concurrency
**One deferred state machine owns all transitions.** UI, MIDI, and OSC handlers do
not act — they **post intents to a queue**. This design kills roughly 90% of the
race conditions that plague naive live-switching scripts.

### Resource policy
Anticipative FX **off**. Never take idle patches offline. Budget for **2
simultaneously active patches** at all times.

### Stage view
Dark, huge type, **CURRENT + NEXT**, BPM flasher, big touch targets, ~30 fps
throttled redraw. PANIC in soft and hard flavours, sub-100 ms.

### Honest weaknesses (state these to him, don't hide them)
- REAPER has **no native sample-accurate patch-crossfade primitive**.
- `reaper.defer` runs at UI cadence → **~15–30 ms decision latency**.
- ExtState needs defensive loading (corrupt/partial state must not brick a show).

### The eight-gate stage test
StageRig may not be called a MainStage killer until it passes a real gig. The claim
is earned only when **a working keyboardist plays real paid shows on it and stops
carrying a backup rig.** Everything before that is a demo.

### Step one
**Write the MainStage `.concert` importer.** His existing concerts are the
specification — they encode exactly what he needs. Find them:
```bash
mdfind -name '.concert'
mdfind "kMDItemFSName == '*.concert'"
```
A `.concert` is a bundle/package — inspect its internals rather than guessing.

---

## 8. SCOPE OF THIS FILE — and where the business work lives

**This file is the TECH brief and nothing else.** It covers the REAPER workflow: the
API traps, the test methodology, the inventory, the build queue, StageRig.

Publishing, pricing, ReaPack distribution, the YouTube channel, the course, and
daw.nathanielschool.com are deliberately **not** in here. They live in a separate
document, `NPH_BUSINESS_BRIEF.md`, in the same folder. Do not mix the two in one
session — the owner asked explicitly for them to be kept apart, and they need
different modes of working (one is engineering with a test harness, the other is
writing and design with no correctness gate).

If you are in a session that starts with this file, you are doing engineering.
Every claim you make should be backed by a harness run or a REAPER screenshot.

---

## 9. WHY CLAUDE CODE / A LOCAL AGENT IS THE RIGHT TOOL FOR THIS

He said it himself: *"I think co-work may not be the greatest because you're taking
too much time to compact the conversation."* He is right. The Cowork session spent a
substantial share of its budget re-summarising itself, and every file transfer to
the Mac was a three-step bridge dance.

On his machine you have direct filesystem access, real `git`, the ability to run
`luac5.4 -p` and REAPER-adjacent tooling in one place, and no context-compaction
tax on long build sessions. Use chat for strategy and taste; do the building here.

**First job of your first session:** the three hand-verifications in §6 item 2. The
automated harness is already green (12 passed, 0 failed). Those three modal actions
are the only untested things standing between the speed layer and "signed off".
