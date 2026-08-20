#!/usr/bin/env python3
"""
Patch REAPER's reaper-menu.ini so Jason's three toolbar zones are laid out the
same way every time:

  LEFT   (docker 3, "Session")        - his own REAPER toggles, lifted off the
                                        main toolbar. Record/transport first.
  CENTRE (docker 6, "Grid Settings")  - grid divisions, then feel, then the
                                        bar tools (marker / tempo / MIDI render).
  RIGHT  (docker 5, "Nathaniel Tools")- the Lua tools that have no key.

ONE BUTTON, ONE PLACE. Every command below lives in exactly one zone; the guard
in _check_no_duplicates() stops the script loudly if that is ever broken.
Anything that already has a key Jason actually uses (Z, X, F, Opt+G, F14,
Cmd+Opt+R) is a KEY ONLY - no button.

MUST run while REAPER is closed (REAPER rewrites this file on quit).
Idempotent: running it twice changes nothing. Backs the file up first.

Usage: python3 apply_toolbar.py [path/to/reaper-menu.ini]
"""
import os, re, sys, shutil, time

INI = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Application Support/REAPER/reaper-menu.ini")

SEP = ("-1", "", None)   # a bare "-1" draws a real separator; "-1 <label>" draws a SEPAR button

# ---------------------------------------------------------------------------
# CATALOGUE - every command this system has ever put on a toolbar. Used only to
# sweep our own buttons back off Jason's Main toolbar. Placement is decided by
# the three zone lists further down.
# ---------------------------------------------------------------------------
CATALOGUE = [
  ("_RS70b23e69efd7b91020ba89e8d4544abdc7cd0773", "Script: Solo Focus.lua",              "nt_solo_focus.png"),
  ("_RS47e470b1f815b379e308f3a5880334082c203f27", "Script: Record Arm Toggle.lua",       "nt_record_arm.png"),
  ("_RSf33a8443194a2b78d99b0cc573318b004b0fe0f6", "Script: FX Float Toggle.lua",         "nt_fx_float.png"),
  ("_RS7403f7876dafe558afa4a4d96801885fe894f7c4", "Script: FX Open Close All.lua",       "nt_fx_all.png"),
  ("_RS315128d9dc42b05eadbbbfc2199bd140ff044e4d", "Script: Region Prev.lua",             "nt_region_prev.png"),
  ("_RSfbd8119451b590b59a820883c58822f28312b15a", "Script: Region Next.lua",             "nt_region_next.png"),
  ("_RS3e3d37cee699d29e819156f567875be6284ea8c1", "Script: Marker at Bar.lua",           "nt_marker_bar.png"),
  ("_RSf7b09088b1c6b6bf1a3e02c894c2616afb496a9b", "Script: Tempo at Bar.lua",            "nt_tempo_bar.png"),
  ("_RS7894b8b20be619fc9e182a197987c42c1b994dbc", "Script: MIDI Render.lua",             "nt_midi_render.png"),
  ("_RS6e3a6a5220585e88edb2599dcb39ff2e660666ae", "Script: Flush Paste.lua",             "nt_flush_paste.png"),
  ("_RSf06839d8a9ba0ae9b2fd8dbb6ea42965faad1d0b", "Script: Duplicate Track.lua",         "nt_duplicate_track.png"),
  ("_RSa3fc5d1453deba43ad330cab451e2355aec16fed", "Script: Unsolo Unselect.lua",         "nt_unsolo_unselect.png"),
  ("_RS4f379389f26945fd4ef7165c13447e527a89a3b4", "Script: Palette and Look.lua",        "nt_app_palette.png"),
  ("_RSba60274f69340b2f812fadfdfa53d903450380c8", "Script: Folders and Flow.lua",        "nt_app_folders.png"),
  ("_RS1cb3069be72c50172fd6497a5235bcceb285479e", "Script: Track Settings Transfer.lua", "nt_app_transfer.png"),
  ("_RS3b480c1a3973c4cab21a84663fae3a4c244a8174", "Script: Stem Print and Handoff.lua",  "nt_app_stems.png"),
  ("_RS63e8c07c47868ba7378219838fb02c0d8b3ce2e5", "Script: MIDI Batch Export.lua",       "nt_app_midi_export.png"),
  ("_RS7e681b9ea3d61c586f60c3323c6f9b1e81f78416", "Script: Open Dock.lua",               "nt_app_dock.png"),
  ("_RS7d0fd86d14096f7b7941abb53b93f367c81e6cd6", "Script: Instant Folder.lua",          "nt_instant_folder.png"),
  ("_RSa64fe569c8e612731bf7e3c0c957b076769a9762", "Script: Group Deck.lua",              "nt_app_groupdeck.png"),
  ("_RS3369903b90a8d86a8c382088066ca626cec0ff69", "Script: Trim Left No Overlap.lua",    "nt_trim_left.png"),
  ("_RS0260bf4e29964fd3e1f486c70f4d69c900d1c8cc", "Script: Trim Right No Overlap.lua",   "nt_trim_right.png"),
  ("_RS22cf425eb9b6c6f19f26a8cc44db19480018a687", "Script: Unoverlap Items.lua",         "nt_unoverlap.png"),
  ("40771",                                       "Track: Toggle all track grouping enabled", "nt_clutch.png"),
]

# ---------------------------------------------------------------------------
# KEY ONLY - these have a key Jason actually uses, so they get NO button.
#   Z  Trim Left No Overlap      X  Trim Right No Overlap
#   F  Instant Folder            Opt+G  Edit Group from Selection
#   F14 / Cmd+Opt+R  Render Safe
#   Cmd+Shift+G  the clutch (and the left zone already has "Enable grouping",
#                and Group Deck has a big CLUTCH switch of its own)
# ---------------------------------------------------------------------------
KEY_ONLY = {
  "_RS3369903b90a8d86a8c382088066ca626cec0ff69": "Z",
  "_RS0260bf4e29964fd3e1f486c70f4d69c900d1c8cc": "X",
  "_RS7d0fd86d14096f7b7941abb53b93f367c81e6cd6": "F",
  "_RSffddbe2a395301265b409c1b43d152c24c2315a6": "Opt+G",
  "_RS249501b53149bef6a583a0fd9304028ba8fd913a": "F14 / Cmd+Opt+R",
  "40771":                                       "Cmd+Shift+G",
}

# key rebinds in reaper-kb.ini: (modifier code, key code, new token, label)
KEYS = [
  ("1", "90", "_RS3369903b90a8d86a8c382088066ca626cec0ff69", "Z: Trim Left No Overlap"),
  ("1", "88", "_RS0260bf4e29964fd3e1f486c70f4d69c900d1c8cc", "X: Trim Right No Overlap"),
  ("1", "70", "_RS7d0fd86d14096f7b7941abb53b93f367c81e6cd6", "F: Instant Folder"),
  ("17", "71", "_RSffddbe2a395301265b409c1b43d152c24c2315a6", "Opt+G: Edit Group from Selection"),
  ("1",  "125", "_RS249501b53149bef6a583a0fd9304028ba8fd913a", "F14: Render Safe"),
  ("25", "82",  "_RS249501b53149bef6a583a0fd9304028ba8fd913a", "Cmd+Opt+R: Render Safe"),
]

# ---------------------------------------------------------------------------
# LEFT zone (docker 3, "Session") - Jason's own REAPER toggles, in the order he
# reaches for them: record/click first, then snap+grid, then the set-and-forget
# ones. REAPER's own theme icons are kept for these.
# ---------------------------------------------------------------------------
LEFT_ITEMS = [
  ("40364", "Enable metronome", None),
  ("41819", "Pre-roll: Toggle pre-roll on record", "toolbar_preroll_clock_record.png"),
  ("1157",  "Enable snapping", None),
  ("40145", "Show arrange view grid", None),
  ("1156",  "Enable grouping", None),
  ("40070", "Move envelope points with media items", None),
  ("40041", "Enable auto-crossfade", None),
  ("1135",  "Enable locking", None),
]

# ---------------------------------------------------------------------------
# CENTRE zone (docker 6, "Grid Settings") - divisions in musical order, then
# feel, then the bar tools, then colour.
# 41052 "Enable relative grid snap" was dropped: 41054 right next to it is the
# same setting (same icon, same job) - one switch, one button.
# ---------------------------------------------------------------------------
CENTRE_ITEMS = [
  ("40781", "Bar",          "nt_grid_bar.png"),
  ("40780", "1/2",          "nt_grid_1_2.png"),
  ("40779", "1/4",          "nt_grid_1_4.png"),
  ("41214", "1/4 Triplet",  "nt_grid_1_4t.png"),
  ("40778", "1/8",          "nt_grid_1_8.png"),
  ("40777", "1/8 Triplet",  "nt_grid_1_8t.png"),
  ("40776", "1/16",         "nt_grid_1_16.png"),
  ("41213", "1/16 Triplet", "nt_grid_1_24.png"),
  SEP,
  ("41054", "Item edit: Toggle relative grid snap", "nt_grid_rel.png"),
  ("_SWS_AWTOGGLESWING", "SWS/AW: Toggle swing grid", "nt_grid_swing.png"),
  ("40363", "Options: Show metronome/pre-roll settings", "nt_grid_click.png"),
  SEP,
  ("_RS3e3d37cee699d29e819156f567875be6284ea8c1", "Script: Marker at Bar.lua", "nt_marker_bar.png"),
  ("_RSf7b09088b1c6b6bf1a3e02c894c2616afb496a9b", "Script: Tempo at Bar.lua",  "nt_tempo_bar.png"),
  ("_RS7894b8b20be619fc9e182a197987c42c1b994dbc", "Script: MIDI Render.lua",   "nt_midi_render.png"),
  SEP,
  ("40705", "Item: Set to random colors", "nt_grid_random_col.png"),
]

# ---------------------------------------------------------------------------
# RIGHT zone (docker 5, "Nathaniel Tools") - the pane is only ~450 px wide at
# 2560, so this stays short. Everyday toggles first, then the one repair tool,
# then the two windows. Anything with a key Jason uses is NOT here.
# ---------------------------------------------------------------------------
RIGHT_ITEMS = [
  ("_RS70b23e69efd7b91020ba89e8d4544abdc7cd0773", "Script: Solo Focus.lua",        "nt_solo_focus.png"),
  ("_RS47e470b1f815b379e308f3a5880334082c203f27", "Script: Record Arm Toggle.lua", "nt_record_arm.png"),
  ("_RSf33a8443194a2b78d99b0cc573318b004b0fe0f6", "Script: FX Float Toggle.lua",   "nt_fx_float.png"),
  ("_RS7403f7876dafe558afa4a4d96801885fe894f7c4", "Script: FX Open Close All.lua", "nt_fx_all.png"),
  SEP,
  ("_RS22cf425eb9b6c6f19f26a8cc44db19480018a687", "Script: Unoverlap Items.lua",   "nt_unoverlap.png"),
  SEP,
  ("_RSa64fe569c8e612731bf7e3c0c957b076769a9762", "Script: Group Deck.lua",        "nt_app_groupdeck.png"),
  ("_RS7e681b9ea3d61c586f60c3323c6f9b1e81f78416", "Script: Open Dock.lua",         "nt_app_dock.png"),
]

# ---------------------------------------------------------------------------
# MAIN toolbar - Jason's own buttons stay exactly as he arranged them. The only
# things removed are ours (they live in a zone now) and buttons that say the
# same thing twice:
#   * an id that appears twice in the section (he had 41846 on it twice)
#   * MAIN_TWINS: a second button for something already on the same strip
# ---------------------------------------------------------------------------
MAIN_TWINS = {
  # 41156 "Selecting one grouped item selects group" is already on this strip.
  "_SWS_TOGSELGROUP": "same switch as 41156, which is two buttons along",
}

ALL_OURS = ({t for t, _, _ in CATALOGUE}
            | {t for t, _, _ in LEFT_ITEMS}
            | {t for t, _, _ in CENTRE_ITEMS}
            | {t for t, _, _ in RIGHT_ITEMS}
            | {"-1"})


def _check_no_duplicates():
    """One button, one place. Fail loudly rather than quietly shipping a dupe."""
    seen = {}
    for zone, rows in (("LEFT", LEFT_ITEMS), ("CENTRE", CENTRE_ITEMS), ("RIGHT", RIGHT_ITEMS)):
        for tok, label, _ in rows:
            if tok == "-1":
                continue
            if tok in seen:
                raise SystemExit(f"DUPLICATE BUTTON: {tok} ({label}) is on both the "
                                 f"{seen[tok]} and {zone} toolbars - pick one.")
            seen[tok] = zone
            if tok in KEY_ONLY:
                raise SystemExit(f"DUPLICATE: {tok} ({label}) is on the {zone} toolbar AND on "
                                 f"the key {KEY_ONLY[tok]} - keep the key, drop the button.")
    return seen


def parse(text):
    """-> list of (section_name or None, [lines])"""
    sections, cur, name = [], [], None
    for ln in text.split("\n"):
        m = re.match(r"^\[(.*)\]\s*$", ln)
        if m:
            sections.append((name, cur)); name, cur = m.group(1), []
        else:
            cur.append(ln)
    sections.append((name, cur))
    return sections

def unparse(sections):
    out = []
    for name, lines in sections:
        if name is not None: out.append(f"[{name}]")
        out.extend(lines)
    return "\n".join(out)

def items_of(lines):
    d = {}
    for ln in lines:
        m = re.match(r"^(item|icon)_(\d+)=(.*)$", ln)
        if m: d.setdefault(m.group(1), {})[int(m.group(2))] = m.group(3)
    return d

def rebuild_section(lines, items, icons, keep_other=True):
    other = [ln for ln in lines if not re.match(r"^(item|icon)_\d+=", ln) and ln.strip() != ""]
    out = []
    # keep 'default=' / 'title=' lines first as they were
    head = [ln for ln in other if ln.startswith("default=") or ln.startswith("title=")]
    rest = [ln for ln in other if ln not in head]
    out.extend(head)
    for i in sorted(icons): out.append(f"icon_{i}={icons[i]}")
    for i in sorted(items): out.append(f"item_{i}={items[i]}")
    out.extend(rest)
    out.append("")
    return out

def numbered(rows):
    """[(tok,label,icon)] -> (items dict, icons dict) with tidy 0..n indices."""
    items, icons = {}, {}
    for k, (tok, label, icon) in enumerate(rows):
        items[k] = f"{tok} {label}".rstrip()
        if icon: icons[k] = icon
    return items, icons


def main():
    _check_no_duplicates()
    text = open(INI, encoding="utf-8", errors="surrogateescape").read()
    bak = INI + ".bak-nt-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy(INI, bak)
    secs = parse(text)
    names = [n for n, _ in secs]
    changed = False

    if "Main toolbar" not in names:
        secs.append(("Main toolbar", ["default=58fbbc5960bcf836"]))
    if "Floating toolbar 1" not in names:
        secs.append(("Floating toolbar 1", ["default=2bcb4157b56ed885", "title=Grid Settings"]))

    for idx, (name, lines) in enumerate(secs):
        # ---- MAIN toolbar: his buttons only, each said once ----------------
        if name == "Main toolbar":
            d = items_of(lines); items = d.get("item", {}); icons = d.get("icon", {})
            keep_items, keep_icons, seen = {}, {}, set()
            k = 0
            for i in sorted(items):
                tok = items[i].split(" ", 1)[0]
                if tok in ALL_OURS: continue          # ours - it lives in a zone now
                if tok in MAIN_TWINS: continue        # a second button for the same switch
                if tok in seen: continue              # literally the same button twice
                seen.add(tok)
                keep_items[k] = items[i]
                if i in icons: keep_icons[k] = icons[i]
                k += 1
            if keep_items != items or keep_icons != icons: changed = True
            secs[idx] = (name, rebuild_section(lines, keep_items, keep_icons))

        # ---- CENTRE zone: grid + feel + bar tools, rebuilt in fixed order ---
        if name == "Floating toolbar 1":
            items, icons = numbered(CENTRE_ITEMS)
            new_sec = rebuild_section(lines, items, icons)
            if new_sec != lines: changed = True
            secs[idx] = (name, new_sec)

    # ---- RIGHT zone (Floating toolbar 3) and LEFT zone (Floating toolbar 4)
    nt_items, nt_icons = numbered(RIGHT_ITEMS)
    nt_section = rebuild_section(["title=Nathaniel Tools"], nt_items, nt_icons)
    left_items, left_icons = numbered(LEFT_ITEMS)
    left_section = rebuild_section(["title=Session"], left_items, left_icons)

    for want_name, want_sec in (("Floating toolbar 3", nt_section), ("Floating toolbar 4", left_section)):
        replaced = False
        for idx, (name, lines) in enumerate(secs):
            if name == want_name:
                if lines != want_sec: changed = True
                secs[idx] = (name, want_sec); replaced = True
        if not replaced:
            at = max(i for i, (n, _) in enumerate(secs) if n and n.startswith("Floating toolbar")) + 1
            secs.insert(at, (want_name, want_sec)); changed = True

    new = unparse(secs)
    if changed or new != text:
        open(INI, "w", encoding="utf-8", errors="surrogateescape").write(new)
        print("patched", INI, "backup", bak)
    else:
        print("nothing to change")

def patch_keys():
    kb = os.path.join(os.path.dirname(INI), "reaper-kb.ini")
    if not os.path.exists(kb): return
    text = open(kb, encoding="utf-8", errors="surrogateescape").read()
    shutil.copy(kb, kb + ".bak-nt-" + time.strftime("%Y%m%d-%H%M%S"))
    lines = text.split("\n"); out = []; done = set(); changed = False
    for ln in lines:
        m = re.match(r"^KEY (\d+) (\d+) (\S+) (\d+)(.*)$", ln)
        if m:
            for mod, key, tok, label in KEYS:
                if m.group(1) == mod and m.group(2) == key and m.group(4) == "0":
                    if m.group(3) != tok:
                        ln = f"KEY {mod} {key} {tok} 0"; changed = True
                    done.add((mod, key))
        out.append(ln)
    for mod, key, tok, label in KEYS:
        if (mod, key) not in done:
            # add after the last KEY line
            idx = max(i for i, l in enumerate(out) if l.startswith("KEY ")) if any(l.startswith("KEY ") for l in out) else len(out)
            out.insert(idx + 1, f"KEY {mod} {key} {tok} 0"); changed = True
    if changed:
        open(kb, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(out))
        print("patched keys in", kb)
    else:
        print("keys already set")

def patch_split():
    """reaper.ini: main toolbar keeps half the strip (his two tidy rows); the
    Nathaniel Tools toolbar (toolbar:3) is docked into the top toolbar docker
    (docker 3, where the Grid toolbar lives) at the right-hand split."""
    ini = os.path.join(os.path.dirname(INI), "reaper.ini")
    if not os.path.exists(ini): return
    text = open(ini, encoding="utf-8", errors="surrogateescape").read()
    new = re.sub(r"^toolbar=0\.\d+ (\d+)$", r"toolbar=0.50000000 \1", text, flags=re.M)
    if re.search(r"^toolbar:3=", new, flags=re.M):
        new = re.sub(r"^toolbar:3=.*$", "toolbar:3=0.50000000 5", new, flags=re.M)
    else:
        new = re.sub(r"^(toolbar:1=.*)$", r"\1\ntoolbar:3=0.50000000 5", new, count=1, flags=re.M)
    # [toolbar:3] section: docked + visible
    if re.search(r"^\[toolbar:3\]", new, flags=re.M):
        sec_start = new.index("[toolbar:3]")
        sec_end = new.find("\n[", sec_start + 1)
        if sec_end < 0: sec_end = len(new)
        body = new[sec_start:sec_end]
        body2 = re.sub(r"^dock=\d+$", "dock=1", body, flags=re.M)
        body2 = re.sub(r"^wnd_vis=\d+$", "wnd_vis=1", body2, flags=re.M)
        if "dock=" not in body2: body2 += "\ndock=1"
        if "wnd_vis=" not in body2: body2 += "\nwnd_vis=1"
        new = new[:sec_start] + body2 + new[sec_end:]
    else:
        new = new.rstrip("\n") + "\n[toolbar:3]\ndock=1\nwnd_height=81\nwnd_left=0\nwnd_top=64\nwnd_vis=1\nwnd_width=385\n"
    new = re.sub(r"^dockersel15=toolbar:3\n", "", new, flags=re.M)
    new = re.sub(r"^toolbar:1=.*$", "toolbar:1=0.50000000 6", new, flags=re.M)   # grid strip: middle pane
    # docker 5 = its own pane at the TOP (mode 2, like the grid's docker 3), so the
    # three strips sit side by side instead of as tabs
    if re.search(r"^dockermode5=", new, flags=re.M):
        new = re.sub(r"^dockermode5=.*$", "dockermode5=2", new, flags=re.M)
    else:
        new = re.sub(r"^(dockermode4=.*)$", r"\1\ndockermode5=2", new, count=1, flags=re.M)
    new = re.sub(r"^dockersel5=.*\n", "", new, flags=re.M)
    if re.search(r"^toolbar:4=", new, flags=re.M):
        new = re.sub(r"^toolbar:4=.*$", "toolbar:4=0.50000000 3", new, flags=re.M)
    else:
        new = re.sub(r"^(toolbar:1=.*)$", r"\1\ntoolbar:4=0.50000000 3", new, count=1, flags=re.M)
    if re.search(r"^dockermode6=", new, flags=re.M):
        new = re.sub(r"^dockermode6=.*$", "dockermode6=2", new, flags=re.M)
    if re.search(r"^\[toolbar:4\]", new, flags=re.M):
        a = new.index("[toolbar:4]"); b = new.find("\n[", a + 1); b = len(new) if b < 0 else b
        body = new[a:b]
        body = re.sub(r"^dock=\d+$", "dock=1", body, flags=re.M); body = re.sub(r"^wnd_vis=\d+$", "wnd_vis=1", body, flags=re.M)
        new = new[:a] + body + new[b:]
    else:
        new = new.rstrip("\n") + "\n[toolbar:4]\ndock=1\nwnd_height=42\nwnd_left=0\nwnd_top=1346\nwnd_vis=1\nwnd_width=420\n"
    if new != text:
        shutil.copy(ini, ini + ".bak-nt-" + time.strftime("%Y%m%d-%H%M%S"))
        open(ini, "w", encoding="utf-8", errors="surrogateescape").write(new)
        print("reaper.ini: main toolbar split 0.5, Nathaniel Tools toolbar in its own top docker (5)")
    else:
        print("reaper.ini unchanged")

if __name__ == "__main__":
    main()
    patch_keys()
    patch_split()
