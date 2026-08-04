# Studio Mac handoff — install, audit and verify Nathaniel Tools

**For:** an agent with zero prior context, running on Jason Zac's **studio Mac mini**
(hostname `nphmacmini`, M4 Pro, REAPER 7.77).
**Written by:** the session that built this, on the **MacBook Pro** (REAPER 7.28), 4 Aug 2026.
**Repo:** https://github.com/jasonzacmusic/nathaniel-tools (public)

Everything below passed on the laptop. **None of it is proven on the studio machine**,
and the two machines differ in ways that matter — that is the entire point of this job.

---

## 0. HARD RULES — read before touching anything

1. **NEVER force-quit REAPER.** No `pkill`, no `kill -9`, no Force Quit.
   REAPER holds `reaper.ini` in memory and writes the whole file on quit; killing it
   mid-write truncates it. This already happened once on the laptop and Jason's
   preferences had to be restored from a month-old backup. Quit only with
   `osascript -e 'tell application "REAPER" to quit'`, then wait. If it will not quit,
   **stop and report** — do not force it.
2. **Never open, close or save Jason's own projects.** The studio machine runs a
   **452-track live session** with unsaved work. Build and test only in new project
   tabs or scratch projects you created yourself.
3. **Back up before you touch config:** copy `reaper.ini` and `reaper-kb.ini` first,
   and **check the backup is non-empty** — a 0-byte backup means damage already happened.
4. **Never restart Core Audio** (`killall coreaudiod`) while a DAW is running.
5. Jason is a **non-coder**. Never hand him terminal commands. Do the work, then report
   outcomes. His name is **Jason Zac** — never "Zak", "Zach" or "Jack".

---

## 1. What this is

A free suite of REAPER tools — ReaScript/Lua + ReaImGui — plus a live-performance rig
and a theme. Distributed free via ReaPack, in the spirit of the SWS extension. It was
called "NPH REAPER Suite" until 4 Aug 2026 and is now **Nathaniel Tools**; if you find
`NPH` anywhere outside `docs/`, it is a leftover and should be reported.

| Part | What it is |
|---|---|
| Speed layer (12 scripts) | Solo Focus, Record Arm Toggle, FX toggles, Region Next/Prev, Marker/Tempo at Bar, MIDI Render, Flush Paste, Duplicate Track, Unsolo & Unselect |
| Palette & Look | colour and name tracks from meaning |
| Folders & Flow | repair, build, dissolve and move track folders |
| Track Settings Transfer | Pro-Tools-style import session data across project tabs |
| Stem Print & Handoff | print stems, restore session state exactly |
| MIDI Batch Export | many `.mid` files at once with sequential names |
| **StageRig** | live patch switching — the MainStage replacement, v0 |
| **Theme** | 300 parameters, fully adjustable |

---

## 2. Baseline from the laptop — reproduce these numbers

| Check | Laptop result |
|---|---|
| `tests/harness.lua` in REAPER | **68 passed, 0 failed** |
| Full regression (suite + theme + StageRig) | **18 passed, 0 failed** |
| `tests/hierarchy_test.lua` (no REAPER needed) | **31 passed, 0 failed** |
| ReaPack index | 21 packages, 24 files |
| Theme parameters live | **300** (277 stock + 23 ours) |
| StageRig build | 5 patches, 18 instrument tracks, every one with an instrument |

**A different number is a finding, not a failure to hide.** REAPER 7.77 vs 7.28 is the
most likely source of divergence — say so explicitly if you see it.

---

## 3. Job 1 — install the way a real user would

Do **not** copy files by hand first. The whole point is to prove the public install path.

1. Confirm REAPER 7.77, and that **ReaPack**, **ReaImGui** and **SWS** are installed.
   Missing ReaPack/ReaImGui: install from
   `github.com/cfillion/reapack/releases` and `github.com/cfillion/reaimgui/releases`
   (arm64 `.dylib` into `~/Library/Application Support/REAPER/UserPlugins/`).
2. In REAPER: **Extensions → ReaPack → Import repositories…** and paste:
   ```
   https://raw.githubusercontent.com/jasonzacmusic/nathaniel-tools/main/index.xml
   ```
3. **Right-click the repository → Install All.** ReaPack has no automatic dependency
   resolution, and five packages need the **Shared Libraries** package — installing a
   single app on its own installs cleanly and then fails at run time.
4. Verify the install landed at
   `~/Library/Application Support/REAPER/Scripts/Nathaniel Tools/` with `scripts/`,
   `apps/` and `scripts/lib/` inside, and that the scripts appear in the Actions list.

**Report:** did ReaPack install cleanly, did every package arrive, and did anything
fail to register.

---

## 4. Job 2 — run the tests

Run `tests/harness.lua` from the Actions list (or via a `_RUN.lua` one-shot, §7).
It builds a scratch project **in its own tab**, deletes a track behind the app's back,
proves every accessor returns a clean default instead of faulting, then closes the tab
and returns to where it started. It never touches your open project.

Expect **68 passed, 0 failed**. Also run the pure-Lua suite (needs no REAPER):
`cd tests && LUA_PATH="../scripts/lib/?.lua;;" lua hierarchy_test.lua` → 31/31.

---

## 5. Job 3 — StageRig on the machine that matters

This is the real reason for the handoff. The laptop has no console and no stage.

1. **Regenerate the rig from a concert on this machine.** The concerts live in
   `~/Music/MainStage/`. The laptop used `Lagori 2026 Minimal.concert` with patches
   `Aasma`, `Humma Humma`, `BRAHMA Gm`, `Upright`, `Maari Kannu`:
   ```
   python3 tools/stagerig_spec.py "<concert path>" \
     --patches "Aasma" "Humma Humma" "BRAHMA Gm" "Upright" "Maari Kannu" \
     --out stagerig/rig.json
   ```
2. **Re-check the substitutions against THIS machine's plugins.** `stagerig/substitutions.json`
   was built from what the *laptop* can load, and that is machine-specific. On the laptop:
   Pianoteq 8, Omnisphere, BBC Symphony Orchestra, Kontakt 7, SOLO (Taqs.im), ANA 2 and
   Keyscape all load — but **Analog Lab V, Vital, Syntronik and Axxess are scanned yet
   refuse to instantiate**, so there is no B3 and Omnisphere stands in for ten organ parts.
   **Probe, do not assume:** ask `TrackFX_AddByName` for each name on a scratch track and
   record what actually loads. If a real organ works here, update `substitutions.json`
   and rebuild — that is a genuine improvement to report.
3. **Build into an empty project tab** with `scripts/StageRig Build.lua`. It refuses to
   run into a project that already has tracks, deliberately.
4. **Then do what the laptop could not:** open `apps/StageRig.lua`, connect Jason's
   controller, and actually **switch patches while playing**. Verify:
   - a chord held through a switch **rings out** and is not chopped
   - no stuck notes after switching (the note-tracker flushes note-offs and CC64)
   - PANIC and ALL OFF respond fast
   - switching mid-phrase is survivable
   - measure the switch latency if you can

**Report honestly.** StageRig is v0. It is a demo until Jason plays real paid shows on
it and stops carrying a backup rig — do not call it a MainStage replacement before then.

---

## 6. Job 4 — the theme

1. Copy `themes/Nathaniel Tools.ReaperThemeZip` to
   `~/Library/Application Support/REAPER/ColorThemes/` and load it.
   **Load it with `reaper.OpenColorThemeFile(path)`** — editing `lastthemefn` in
   `reaper.ini` does *not* work.
2. Verify with `python3 tools/theme/analyse_theme.py "themes/Nathaniel Tools.ReaperThemeZip"`
   → expect **300 parameters**.
3. Open **Options → Themes → Theme development / tweaking** and confirm the 23
   `Nathaniel:` parameters appear and actually do something.
4. **Look at it on the studio monitors and say whether it is any good.** The laptop
   verified the colours are *correct*; nobody has judged whether they are *nice*. Jason
   likes the ReaperTips theme — compare against it and report honestly.

⚠️ **If you add theme parameters, APPEND them at the end, never insert.** REAPER stores
theme settings as positional `param<N>` indices in `reaper-themeconfig.ini`, so inserting
one silently corrupts every existing user's saved settings. Undocumented; verified.

⚠️ **Never re-save a theme PNG through an image library.** REAPER's stretch guides are
magenta/yellow pixels in a 1px border, not 9-slice — re-encoding destroys them. All 1226
images are byte-identical to the stock theme and must stay that way.

---

## 7. How to run a script when the GUI is awkward

Drop a file named `_RUN.lua` into
`~/Library/Application Support/REAPER/Scripts/Nathaniel Tools/`.
`__startup.lua` runs it once on the next REAPER launch and deletes it, so a forgotten
probe can never linger. Write results to a **text file** and read that — REAPER's
console is unreliable to read any other way. There is a safe restart helper (graceful
quit only, never a kill) at `scratchpad/reaper_cycle.sh` in the laptop session.

---

## 8. Known-open, and worth your attention

- **No key/velocity zones or transpose yet.** The concert files carry splits, velocity
  layers and the Humma Humma G→A transpose; StageRig does not import them.
- **No hands-free switching.** Patch changes are clicks; a footswitch or program-change
  binding is the obvious next step, and the studio machine is where to build it.
- **Loop Deck** (Ableton-style loop triggering) is specced, not built.
- **Sections & Time** app is not built.
- **Presets are defaults.** Every StageRig track loads its plugin with a default patch;
  choosing the real sounds is Jason's ear, not code.
- **`daw.nathanielschool.com` is occupied** by a different product of Jason's ("DAW
  Mentor"), so the suite's site is on a temporary address pending his decision.

---

## 9. What to send back

A short, honest report:
1. Did the ReaPack install work end to end on 7.77?
2. Test numbers — and any that differ from §2, with the reason.
3. Anything that behaves differently on 7.77 vs 7.28.
4. StageRig: **does patch switching actually feel right under the hands?**
5. Which plugins really load here, and whether a proper B3 is available.
6. Your judgement on the theme.
7. Anything you had to fix, as a pushed commit with a clear message.
