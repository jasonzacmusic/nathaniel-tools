#!/usr/bin/env python3
"""
Patch REAPER's reaper-menu.ini so the Main toolbar carries the Nathaniel Tools
speed layer + apps with their own icons, and the Grid toolbar (Floating toolbar 1)
wears the matching text tiles.

MUST run while REAPER is closed (REAPER rewrites this file on quit).
Idempotent: running it twice changes nothing. Backs the file up first.

Usage: python3 apply_toolbar.py [path/to/reaper-menu.ini]
"""
import os, re, sys, shutil, time

INI = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Application Support/REAPER/reaper-menu.ini")

# installed-script command tokens on this Mac (ReaPack install paths) -------------
SPEED = [
  ("_RS70b23e69efd7b91020ba89e8d4544abdc7cd0773", "Script: Solo Focus.lua",          "nt_solo_focus.png"),
  ("_RS47e470b1f815b379e308f3a5880334082c203f27", "Script: Record Arm Toggle.lua",   "nt_record_arm.png"),
  ("_RSf33a8443194a2b78d99b0cc573318b004b0fe0f6", "Script: FX Float Toggle.lua",     "nt_fx_float.png"),
  ("_RS7403f7876dafe558afa4a4d96801885fe894f7c4", "Script: FX Open Close All.lua",   "nt_fx_all.png"),
  ("_RS315128d9dc42b05eadbbbfc2199bd140ff044e4d", "Script: Region Prev.lua",         "nt_region_prev.png"),
  ("_RSfbd8119451b590b59a820883c58822f28312b15a", "Script: Region Next.lua",         "nt_region_next.png"),
  ("_RS3e3d37cee699d29e819156f567875be6284ea8c1", "Script: Marker at Bar.lua",       "nt_marker_bar.png"),
  ("_RSf7b09088b1c6b6bf1a3e02c894c2616afb496a9b", "Script: Tempo at Bar.lua",        "nt_tempo_bar.png"),
  ("_RS7894b8b20be619fc9e182a197987c42c1b994dbc", "Script: MIDI Render.lua",         "nt_midi_render.png"),
  ("_RS6e3a6a5220585e88edb2599dcb39ff2e660666ae", "Script: Flush Paste.lua",         "nt_flush_paste.png"),
  ("_RSf06839d8a9ba0ae9b2fd8dbb6ea42965faad1d0b", "Script: Duplicate Track.lua",     "nt_duplicate_track.png"),
  ("_RSa3fc5d1453deba43ad330cab451e2355aec16fed", "Script: Unsolo Unselect.lua",     "nt_unsolo_unselect.png"),
]
APPS = [
  ("_RS4f379389f26945fd4ef7165c13447e527a89a3b4", "Script: Palette and Look.lua",        "nt_app_palette.png"),
  ("_RSba60274f69340b2f812fadfdfa53d903450380c8", "Script: Folders and Flow.lua",        "nt_app_folders.png"),
  ("_RS1cb3069be72c50172fd6497a5235bcceb285479e", "Script: Track Settings Transfer.lua", "nt_app_transfer.png"),
  ("_RS3b480c1a3973c4cab21a84663fae3a4c244a8174", "Script: Stem Print and Handoff.lua",  "nt_app_stems.png"),
  ("_RS63e8c07c47868ba7378219838fb02c0d8b3ce2e5", "Script: MIDI Batch Export.lua",       "nt_app_midi_export.png"),
  ("_RS7e681b9ea3d61c586f60c3323c6f9b1e81f78416", "Script: Open Dock.lua",               "nt_app_dock.png"),
]
EDIT = [
  ("_RS7d0fd86d14096f7b7941abb53b93f367c81e6cd6", "Script: Instant Folder.lua",             "nt_instant_folder.png"),
  ("_RSffddbe2a395301265b409c1b43d152c24c2315a6", "Script: Edit Group from Selection.lua",  "nt_edit_group.png"),
  ("40771",                                        "Track: Toggle all track grouping enabled","nt_clutch.png"),
  ("_RS3369903b90a8d86a8c382088066ca626cec0ff69", "Script: Trim Left No Overlap.lua",       "nt_trim_left.png"),
  ("_RS0260bf4e29964fd3e1f486c70f4d69c900d1c8cc", "Script: Trim Right No Overlap.lua",      "nt_trim_right.png"),
  ("_RS22cf425eb9b6c6f19f26a8cc44db19480018a687", "Script: Unoverlap Items.lua",            "nt_unoverlap.png"),
]
# key rebinds in reaper-kb.ini: (modifier code, key code, new token, label)
KEYS = [
  ("1", "90", "_RS3369903b90a8d86a8c382088066ca626cec0ff69", "Z: Trim Left No Overlap"),
  ("1", "88", "_RS0260bf4e29964fd3e1f486c70f4d69c900d1c8cc", "X: Trim Right No Overlap"),
  ("1", "70", "_RS7d0fd86d14096f7b7941abb53b93f367c81e6cd6", "F: Instant Folder"),
  ("17", "71", "_RSffddbe2a395301265b409c1b43d152c24c2315a6", "Opt+G: Edit Group from Selection"),
]
GRID_ICONS = {  # by command id in [Floating toolbar 1]
  "40781": "nt_grid_bar.png", "40780": "nt_grid_1_2.png", "40779": "nt_grid_1_4.png", "41214": "nt_grid_1_4t.png",
  "40778": "nt_grid_1_8.png", "40777": "nt_grid_1_8t.png", "40776": "nt_grid_1_16.png", "41213": "nt_grid_1_24.png",
  "41052": "nt_grid_rel.png", "41054": "nt_grid_rel.png", "40363": "nt_grid_click.png", "40705": "nt_grid_random_col.png",
  "_SWS_AWTOGGLESWING": "nt_grid_swing.png",
}

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

def main():
    text = open(INI, encoding="utf-8", errors="surrogateescape").read()
    bak = INI + ".bak-nt-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy(INI, bak)
    secs = parse(text)
    names = [n for n, _ in secs]
    changed = False

    # ---- Main toolbar: append speed layer + apps (skip tokens already present)
    if "Main toolbar" not in names:
        secs.append(("Main toolbar", ["default=58fbbc5960bcf836"]))
    for idx, (name, lines) in enumerate(secs):
        if name == "Main toolbar":
            d = items_of(lines); items = d.get("item", {}); icons = d.get("icon", {})
            # Jason's own buttons are everything that is not ours; keep them in order.
            ours = {t for t, _, _ in SPEED + APPS + EDIT} | {"-1"}
            keep_items, keep_icons = {}, {}
            k = 0
            for i in sorted(items):
                tok = items[i].split(" ", 1)[0]
                if tok in ours: continue
                keep_items[k] = items[i]
                if i in icons: keep_icons[k] = icons[i]
                if tok == "_RS7894b8b20be619fc9e182a197987c42c1b994dbc": keep_icons[k] = "nt_midi_render.png"
                k += 1
            # then ours, in three breathing groups: speed layer | editing | dock
            def sep():
                nonlocal k
                keep_items[k] = "-1 SEPARATOR"; k += 1
            sep()
            for tok, label, icon in SPEED:
                keep_items[k] = f"{tok} {label}"; keep_icons[k] = icon; k += 1
            sep()
            for tok, label, icon in EDIT:
                keep_items[k] = f"{tok} {label}"; keep_icons[k] = icon; k += 1
            sep()
            for tok, label, icon in APPS:
                if tok == "_RS7e681b9ea3d61c586f60c3323c6f9b1e81f78416":   # only Open Dock; the apps live in the docker
                    keep_items[k] = f"{tok} {label}"; keep_icons[k] = icon; k += 1
            if keep_items != items or keep_icons != icons: changed = True
            secs[idx] = (name, rebuild_section(lines, keep_items, keep_icons))
        if name == "Floating toolbar 1":
            d = items_of(lines); items = d.get("item", {}); icons = d.get("icon", {})
            for i, v in items.items():
                cmd = v.split(" ", 1)[0]
                if cmd in GRID_ICONS and icons.get(i) != GRID_ICONS[cmd]:
                    icons[i] = GRID_ICONS[cmd]; changed = True
            secs[idx] = (name, rebuild_section(lines, items, icons))
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
    """reaper.ini 'toolbar=<split> <docker>': the main toolbar's share of the top strip.
    0.5 = half the width = four cramped rows; 0.72 = one clean row at 2560 px."""
    ini = os.path.join(os.path.dirname(INI), "reaper.ini")
    if not os.path.exists(ini): return
    text = open(ini, encoding="utf-8", errors="surrogateescape").read()
    new = re.sub(r"^toolbar=0\.5+ (\d+)$", r"toolbar=0.72000000 \1", text, flags=re.M)
    if new != text:
        shutil.copy(ini, ini + ".bak-nt-" + time.strftime("%Y%m%d-%H%M%S"))
        open(ini, "w", encoding="utf-8", errors="surrogateescape").write(new)
        print("widened main toolbar split to 0.72")
    else:
        print("split unchanged")

if __name__ == "__main__":
    main()
    patch_keys()
    patch_split()
