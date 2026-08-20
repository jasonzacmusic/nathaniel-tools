#!/usr/bin/env python3
"""
Patch REAPER's reaper-menu.ini so Jason's toolbars are laid out the same way
every time. TWO toolbars at the top, and the top-right pane left empty:

  LEFT   (docker 3, "Session + Tools") - his own REAPER toggles, then the
                                         Nathaniel Tools that have no key.
  CENTRE (docker 6, "Grid Settings")   - plain divisions, then the triplet
                                         toggle + rel + swing, then the bar
                                         tools (marker / tempo / MIDI render).
  RIGHT  (docker 5)                    - DELIBERATELY EMPTY. Held clear so the
                                         Click Strip docks up here with the
                                         toolbars instead of floating over the
                                         arrange view.

The two toolbars are spread across the window (see zone_width_shares): each
gets the width of its own buttons plus the same amount of air, and docker 5
keeps a clear third on the right. Inside a strip, groups are parted by a bare
"-1" separator - never "-1 <label>", which REAPER draws as a dead SEPAR button.

ONE BUTTON, ONE PLACE. Every command below lives in exactly one strip; the guard
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
  ("_RS9871b9cf53b4c07d6def31e7a7b16ebb2a5dc670", "Script: Triplet Grid Toggle.lua",     "nt_grid_triplet.png"),
]

TRIPLET_TOGGLE = "_RS9871b9cf53b4c07d6def31e7a7b16ebb2a5dc670"

# ---------------------------------------------------------------------------
# Scripts that must be REGISTERED before REAPER will admit they exist. Without
# an SCR line in reaper-kb.ini the toolbar button is a dead square.
#   (token WITHOUT the leading underscore, menu name, path under Scripts/)
# ---------------------------------------------------------------------------
SCRIPTS = [
  ("RS9871b9cf53b4c07d6def31e7a7b16ebb2a5dc670",
   "Custom: Triplet Grid Toggle.lua",
   "Nathaniel Tools/scripts/Triplet Grid Toggle.lua"),
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
# LEFT zone (docker 3, "Session + Tools") - two things on one strip:
#
#   SESSION_ITEMS - Jason's own REAPER toggles, in the order he reaches for
#                   them: record/click first, then snap+grid, then the
#                   set-and-forget ones. REAPER's own theme icons are kept.
#   TOOL_ITEMS    - the Nathaniel Tools that have no key. These used to have
#                   their own strip in docker 5; docker 5 is now kept clear for
#                   the Click Strip, so they moved here. Nothing was lost - the
#                   left strip had 809 px of room for 8 small buttons.
#
# The two halves are parted by a bare separator, and the tools keep their own
# internal grouping: everyday toggles | the repair tool | the two windows.
# ---------------------------------------------------------------------------
SESSION_ITEMS = [
  ("40364", "Enable metronome", None),
  ("41819", "Pre-roll: Toggle pre-roll on record", "toolbar_preroll_clock_record.png"),
  ("1157",  "Enable snapping", None),
  ("40145", "Show arrange view grid", None),
  ("1156",  "Enable grouping", None),
  ("40070", "Move envelope points with media items", None),
  ("40041", "Enable auto-crossfade", None),
  ("1135",  "Enable locking", None),
]
TOOL_ITEMS = [
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
LEFT_ITEMS = SESSION_ITEMS + [SEP] + TOOL_ITEMS

# ---------------------------------------------------------------------------
# CENTRE zone (docker 6, "Grid Settings") - three groups with a real gap
# between them: plain divisions | triplet + rel + swing | bar tools.
#
# The three fixed triplet buttons (1/4T, 1/8T, 1/24) are GONE. One T button now
# flips whatever division he is on into triplets and back - 1/8 becomes 1/12,
# press again and it is 1/8 again - the way Logic does it. Works bar to 1/32.
# 41052 "Enable relative grid snap" also went: 41054 is the same switch.
# The metronome cog (40363) and random colours (40705) left the grid strip -
# neither is a grid control.
# ---------------------------------------------------------------------------
CENTRE_ITEMS = [
  ("40781", "Bar",  "nt_grid_bar.png"),
  ("40780", "1/2",  "nt_grid_1_2.png"),
  ("40779", "1/4",  "nt_grid_1_4.png"),
  ("40778", "1/8",  "nt_grid_1_8.png"),
  ("40776", "1/16", "nt_grid_1_16.png"),
  ("40775", "1/32", "nt_grid_1_32.png"),
  SEP,
  (TRIPLET_TOGGLE, "Script: Triplet Grid Toggle.lua", "nt_grid_triplet.png"),
  ("41054", "Item edit: Toggle relative grid snap", "nt_grid_rel.png"),
  ("_SWS_AWTOGGLESWING", "SWS/AW: Toggle swing grid", "nt_grid_swing.png"),
  SEP,
  ("_RS3e3d37cee699d29e819156f567875be6284ea8c1", "Script: Marker at Bar.lua", "nt_marker_bar.png"),
  ("_RSf7b09088b1c6b6bf1a3e02c894c2616afb496a9b", "Script: Tempo at Bar.lua",  "nt_tempo_bar.png"),
  ("_RS7894b8b20be619fc9e182a197987c42c1b994dbc", "Script: MIDI Render.lua",   "nt_midi_render.png"),
]

# ---------------------------------------------------------------------------
# RIGHT zone (docker 5) - DELIBERATELY EMPTY.
#
# Docker 5 is the top-right pane. It is held clear so the Click Strip can be
# docked there, up with the toolbars, instead of floating over the arrange view
# where it sat on top of the timeline. The old "Nathaniel Tools" strip
# (Floating toolbar 3) that used to live here is emptied and hidden, and its
# buttons moved onto the left strip as TOOL_ITEMS - see above.
# ---------------------------------------------------------------------------
RIGHT_ITEMS = []

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

# ---------------------------------------------------------------------------
# HOW WIDE EACH ZONE IS - "use the width of my display".
#
# REAPER keeps the side-by-side split of the top-edge dockers in reaper.ini as
# dockerwprio<N> (width share) and dockerpprio<N> (left-to-right order). The
# three shares always add up to 3.0.
#     docker 3 = LEFT (Session + Tools)   docker 6 = CENTRE (Grid)
#     docker 5 = RIGHT - held clear for the Click Strip
#
# There are only TWO toolbars now. Docker 5's third of the window is reserved
# so the Click Strip drops straight into the top-right and pushes nothing out
# of the way; the two toolbars share what is left, each getting the width of
# its own buttons plus the same amount of air, with the left strip starting
# hard against the left edge.
# ---------------------------------------------------------------------------
ZONE_DOCKER = {"3": "LEFT", "6": "CENTRE", "5": "CLICK"}
ZONE_ORDER  = {"3": "0.18750000", "6": "0.37500000", "5": "0.50000000"}  # left -> right
BUTTON_W, SEPARATOR_W, WINDOW_W = 30, 10, 2557   # logical px; his REAPER window
CLICK_STRIP_SHARE = 1.0     # docker 5 = one clear third of the window

def zone_width_shares():
    """-> (share per docker summing to 3.0, button px per docker, air px)."""
    rows_for = {d: rows for d, rows in (("3", LEFT_ITEMS), ("6", CENTRE_ITEMS), ("5", RIGHT_ITEMS)) if rows}
    content = {d: sum(SEPARATOR_W if t == "-1" else BUTTON_W for t, _, _ in rows)
               for d, rows in rows_for.items()}
    reserved = {d: CLICK_STRIP_SHARE for d in ("3", "6", "5") if d not in content}
    room = WINDOW_W * (1.0 - sum(reserved.values()) / 3.0)
    used = sum(content.values())
    air = max((room - used) / len(content), 40.0)   # same breathing room after each group
    shares = {d: 3.0 * (c + air) / WINDOW_W for d, c in content.items()}
    shares.update(reserved)
    for d in reserved:
        content[d] = 0
    return shares, content, air

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

    # ---- Floating toolbar 3: emptied. Its buttons are on the left strip now
    #      and docker 5 is kept clear for the Click Strip.
    nt_items, nt_icons = numbered(RIGHT_ITEMS)
    nt_section = rebuild_section(["title=Nathaniel Tools"], nt_items, nt_icons)
    # ---- LEFT zone (Floating toolbar 4): session toggles + the tools
    left_items, left_icons = numbered(LEFT_ITEMS)
    left_section = rebuild_section(["title=Session + Tools"], left_items, left_icons)

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
    """reaper.ini: two toolbars at the top - the left strip in docker 3 and the
    grid strip in docker 6 - and docker 5 (top right) left FREE so the Click
    Strip can dock there instead of floating over the arrange view."""
    ini = os.path.join(os.path.dirname(INI), "reaper.ini")
    if not os.path.exists(ini): return
    text = open(ini, encoding="utf-8", errors="surrogateescape").read()
    new = re.sub(r"^toolbar=0\.\d+ (\d+)$", r"toolbar=0.50000000 \1", text, flags=re.M)
    # toolbar:3 gives up docker 5 entirely, and is hidden so it cannot come
    # back as a window floating over the timeline.
    new = re.sub(r"^toolbar:3=.*\n", "", new, flags=re.M)
    if re.search(r"^\[toolbar:3\]", new, flags=re.M):
        sec_start = new.index("[toolbar:3]")
        sec_end = new.find("\n[", sec_start + 1)
        if sec_end < 0: sec_end = len(new)
        body = new[sec_start:sec_end]
        body = re.sub(r"^wnd_vis=\d+$", "wnd_vis=0", body, flags=re.M)
        if "wnd_vis=" not in body: body += "\nwnd_vis=0"
        new = new[:sec_start] + body + new[sec_end:]
    new = re.sub(r"^dockersel15=toolbar:3\n", "", new, flags=re.M)
    new = re.sub(r"^dockersel5=.*\n", "", new, flags=re.M)
    new = re.sub(r"^toolbar:1=.*$", "toolbar:1=0.50000000 6", new, flags=re.M)   # grid strip: middle pane
    # docker 5 stays a TOP pane (mode 2) even with nothing in it - that is what
    # makes it the top-right slot the Click Strip docks into.
    if re.search(r"^dockermode5=", new, flags=re.M):
        new = re.sub(r"^dockermode5=.*$", "dockermode5=2", new, flags=re.M)
    else:
        new = re.sub(r"^(dockermode4=.*)$", r"\1\ndockermode5=2", new, count=1, flags=re.M)
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
    # ---- spread the two toolbars, keep the right third clear --------------
    shares, content, air = zone_width_shares()
    for d in ("3", "6", "5"):
        for key, val in (("dockerwprio", f"{shares[d]:.8f}"), ("dockerpprio", ZONE_ORDER[d])):
            if re.search(rf"^{key}{d}=", new, flags=re.M):
                new = re.sub(rf"^{key}{d}=.*$", f"{key}{d}={val}", new, flags=re.M)
            else:
                # loud, not silent: never let a missing key pass as "applied"
                print(f"WARNING: {key}{d} not found in reaper.ini - zone width not set")
        px = round(shares[d] / 3.0 * WINDOW_W)
        pct = f"{shares[d]/3.0*100:.0f}% of the window"
        if content[d]:
            print(f"  {ZONE_DOCKER[d]:6s} docker {d}: {content[d]:4d} px of buttons "
                  f"+ {round(air)} px of air = {px} px ({pct})")
        else:
            print(f"  {ZONE_DOCKER[d]:6s} docker {d}: EMPTY, {px} px held clear "
                  f"for the Click Strip ({pct})")

    if new != text:
        shutil.copy(ini, ini + ".bak-nt-" + time.strftime("%Y%m%d-%H%M%S"))
        open(ini, "w", encoding="utf-8", errors="surrogateescape").write(new)
        print("reaper.ini: two toolbars spread across the window, docker 5 left free")
    else:
        print("reaper.ini unchanged")


def patch_scripts():
    """REAPER only knows a script exists if reaper-kb.ini carries an SCR line
    for it. Without that the toolbar button is a dead square."""
    kb = os.path.join(os.path.dirname(INI), "reaper-kb.ini")
    if not os.path.exists(kb): return
    text = open(kb, encoding="utf-8", errors="surrogateescape").read()
    out = text.split("\n"); changed = False
    for tok, desc, path in SCRIPTS:
        if tok in text:
            continue
        if not os.path.exists(os.path.join(os.path.dirname(INI), "Scripts", path)):
            print(f"WARNING: {path} is not installed - not registering {desc}")
            continue
        idx = max((i for i, l in enumerate(out) if l.startswith("SCR ")), default=len(out) - 1)
        out.insert(idx + 1, f'SCR 4 0 {tok} "{desc}" "{path}"')
        changed = True
        print("registered", desc)
    if changed:
        shutil.copy(kb, kb + ".bak-nt-" + time.strftime("%Y%m%d-%H%M%S"))
        open(kb, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(out))
    else:
        print("scripts already registered")

if __name__ == "__main__":
    patch_scripts()   # register new scripts BEFORE putting them on a toolbar
    main()
    patch_keys()
    patch_split()
