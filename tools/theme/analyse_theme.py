#!/usr/bin/env python3
"""analyse_theme.py — read any REAPER theme and report how customisable it is.

Point it at a .ReaperThemeZip (or an unpacked folder) and it reports the three
things that decide whether you can bend a theme to your taste:

  1. PARAMETERS  - `define_parameter` lines in rtconfig.txt. This is the entire
     customisation surface. Whatever is not declared here cannot be changed from
     the theme adjuster window, no matter what it looks like on screen.
  2. COLOURS     - the .ReaperTheme entries, and how many are distinct.
  3. IMAGES      - how much of the look is painted into PNGs. Every pixel of
     look that lives in a PNG is a pixel you cannot recolour with a parameter.

The reason this exists: "I can't customise this theme" is a real complaint with
a precise, checkable cause, and guessing at it wastes days. Run this on the
theme you like and the theme you have, and the difference tells you what to
build.

Measured with this tool, 2026-08-04:
    Default 7.0   277 parameters, incl. live per-channel colour controls
    ReaperTips    62 parameters (+29 commented out), almost all LAYOUT
That is the answer to why ReaperTips resists recolouring: it is hand-painted,
not parametric. Its knobs move things; they do not repaint them.

Usage:
    python3 analyse_theme.py "/path/to/Theme.ReaperThemeZip" [more...]
"""

import collections
import os
import re
import sys
import tempfile
import zipfile


def unpack(path: str) -> str:
    if os.path.isdir(path):
        return path
    d = tempfile.mkdtemp(prefix="themestudy_")
    with zipfile.ZipFile(path) as z:
        z.extractall(d)
    return d


def find(root: str, suffix: str):
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn.lower().endswith(suffix):
                yield os.path.join(dp, fn)


PARAM = re.compile(r"^\s*define_parameter\s+(\S+)\s+'([^']*)'\s*(.*)$", re.M)
PARAM_OFF = re.compile(r"^\s*;\s*define_parameter\s", re.M)
COLOUR = re.compile(r"^([A-Za-z_0-9]+)=(-?\d+)\s*$", re.M)


def analyse(path: str):
    root = unpack(path)
    name = os.path.basename(path.rstrip("/"))
    print("=" * 72)
    print(name)
    print("=" * 72)

    # --- parameters: the customisation surface -----------------------------
    rt = next(iter(find(root, "rtconfig.txt")), None)
    if not rt:
        print("  no rtconfig.txt - colour-only theme (no layout, no parameters)")
    else:
        src = open(rt, encoding="utf-8", errors="replace").read()
        params = PARAM.findall(src)
        disabled = len(PARAM_OFF.findall(src))
        print(f"\nPARAMETERS  {len(params)} active, {disabled} commented out")

        areas = collections.Counter()
        colourish = 0
        for _, desc, _rest in params:
            areas[desc.split(":")[0].strip() if ":" in desc else "(ungrouped)"] += 1
            if re.search(r"colou?r|tint|bright|opacity|dim|shade|hue|sat", desc, re.I):
                colourish += 1
        for area, n in areas.most_common(12):
            print(f"    {n:4d}  {area}")
        print(f"\n    of those, {colourish} affect COLOUR; "
              f"{len(params) - colourish} only move or resize things")

        adj = re.search(r"adjuster_script\s+\"([^\"]+)\"", src)
        print(f"    adjuster: {adj.group(1) if adj else '(none)'}")
        print(f"    rtconfig: {len(src.splitlines())} lines")

    # --- colours -----------------------------------------------------------
    tf = next(iter(find(root, ".reapertheme")), None)
    if tf:
        entries = COLOUR.findall(open(tf, encoding="utf-8", errors="replace").read())
        vals = [v for _, v in entries]
        print(f"\nCOLOURS     {len(entries)} entries, {len(set(vals))} distinct values")

    # --- images ------------------------------------------------------------
    pngs = list(find(root, ".png"))
    total = sum(os.path.getsize(p) for p in pngs)
    print(f"\nIMAGES      {len(pngs)} PNGs, {total / 1024 / 1024:.1f} MB")
    print("            every pixel of look that lives here cannot be")
    print("            recoloured by a parameter\n")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for p in sys.argv[1:]:
        analyse(p)
