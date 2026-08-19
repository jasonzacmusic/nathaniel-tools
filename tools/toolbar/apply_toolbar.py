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
            present = " ".join(items.values())
            nxt = (max(items) + 1) if items else 0
            # give his existing MIDI Render button our icon if it is the installed script
            for i, v in list(items.items()):
                if v.startswith("_RS7894b8b20be619fc9e182a197987c42c1b994dbc"): icons[i] = "nt_midi_render.png"
            for tok, label, icon in SPEED + APPS:
                if tok in present: continue
                items[nxt] = f"{tok} {label}"; icons[nxt] = icon; nxt += 1; changed = True
            secs[idx] = (name, rebuild_section(lines, items, icons))
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

if __name__ == "__main__":
    main()
