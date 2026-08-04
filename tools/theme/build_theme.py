#!/usr/bin/env python3
"""build_theme.py — generate a complete REAPER colour theme from a small spec.

WHY THIS EXISTS

A REAPER `.ReaperTheme` is ~400 individual colour entries. Editing them by hand
is not the hard part; keeping them *coherent* is. Change the background and you
have to re-balance every text, border, meter and envelope colour against it, or
the theme ends up with unreadable corners nobody notices until they are mixing
at 2am.

So this does not ask you for 400 colours. It asks for about a dozen decisions
and derives the rest, preserving the contrast relationships that Cockos'
designers already got right in the stock theme.

HOW IT WORKS

The stock Default 7.0 theme is the structural base: it supplies the full key
list, and — more importantly — the *lightness* of every entry. That lightness
is the accessibility work. We keep it and re-map hue and saturation toward the
brand palette, then apply explicit overrides for the entries whose meaning we
actually know (backgrounds, cursor, selection, meters, text).

Non-colour entries (`*_drawmode`, `*_flags`, blend modes) are copied verbatim.
They are not colours and re-mapping them would corrupt the theme silently.

ENCODING - and the trap in it

There are TWO byte orders in play, and they are not the same. Probing the API
alone is not enough to get this right; the first version of this tool did that
and produced a theme where every colour was mirrored (violet came out pink).

    reaper.ColorToNative(255,0,0) = 16711680 = 0xFF0000     <- native is 0xRRGGBB
    but a .ReaperTheme FILE stores                              0xBBGGRR

Proven by writing col_cursor = 0x8A5CF0 into the file and asking REAPER what it
had loaded: GetThemeColor returned 0xF05C8A. So REAPER swaps R and B when
reading the file, i.e. the file is blue-first. This tool reads and writes in
file order; the palette JSON is plain #RRGGBB as a human would expect.

A few entries are negative: the high bit is a flag, not colour data, so those
are passed through untouched.

LICENCE NOTE
The base used here is the stock theme that ships with REAPER. The ReaperTips
theme was studied for structure only — it is CC BY-NC-SA, so adapting its files
would bind this theme to NonCommercial+ShareAlike forever. None of its assets
are read or copied by this tool.

Usage:
    python3 build_theme.py --palette palettes/nsm-dark.json --out "NSM Dark.ReaperTheme"
"""

import argparse
import colorsys
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BASE = os.path.expanduser(
    "~/Library/Application Support/REAPER/ColorThemes/Default_7.0.ReaperThemeZip")

# Entries that are not colours. Re-mapping these corrupts the theme.
NOT_A_COLOUR = re.compile(
    r"(drawmode|_flags|_mode|blendmode|^version$|^ui_img|_img$|font|_size$)", re.I)


# ---------------------------------------------------------------------------
# colour helpers - REAPER native int is 0xRRGGBB
# ---------------------------------------------------------------------------

def to_rgb(v: int):
    """Decode a .ReaperTheme integer. The file stores 0xBBGGRR."""
    return (v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF)


def to_native(r: int, g: int, b: int) -> int:
    """Encode for the .ReaperTheme file: 0xBBGGRR."""
    clamp = lambda x: max(0, min(255, int(round(x))))
    return (clamp(b) << 16) | (clamp(g) << 8) | clamp(r)


def hex_to_rgb(s: str):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def rgb_to_hls(r, g, b):
    return colorsys.rgb_to_hls(r / 255, g / 255, b / 255)


def hls_to_rgb(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, max(0.0, min(1.0, l)), max(0.0, min(1.0, s)))
    return r * 255, g * 255, b * 255


def mix(c1, c2, t: float):
    return tuple(a + (b - a) * t for a, b in zip(c1, c2))


# ---------------------------------------------------------------------------
# the theme file
# ---------------------------------------------------------------------------

def read_base(path: str) -> list:
    """Return the base theme's lines. Accepts a .ReaperTheme or a .ReaperThemeZip."""
    if path.lower().endswith(".reaperthemezip"):
        import zipfile
        with zipfile.ZipFile(path) as z:
            name = next((n for n in z.namelist() if n.lower().endswith(".reapertheme")), None)
            if not name:
                sys.exit(f"no .ReaperTheme inside {path}")
            return z.read(name).decode("utf-8", "replace").splitlines()
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read().splitlines()


def build(base_lines: list, spec: dict):
    pal = {k: hex_to_rgb(v) for k, v in spec["palette"].items()}
    overrides = spec.get("overrides", {})
    tint = spec.get("tint", {})

    accent_h, _, accent_s = rgb_to_hls(*pal["accent"])
    hue_pull = float(tint.get("hue_pull", 0.75))       # how far toward brand hue
    sat_scale = float(tint.get("saturation", 1.0))
    sat_floor = float(tint.get("saturation_floor", 0.0))
    neutral_below = float(tint.get("treat_as_neutral_below", 0.10))

    out, changed, copied, forced = [], 0, 0, 0

    for line in base_lines:
        m = re.match(r"^([A-Za-z_0-9]+)=(-?\d+)\s*$", line)
        if not m:
            out.append(line)
            continue
        key, raw = m.group(1), int(m.group(2))

        # explicit, human-decided colours win
        if key in overrides:
            out.append(f"{key}={to_native(*hex_to_rgb(overrides[key]))}")
            forced += 1
            continue

        # flags, drawmodes and negative sentinels pass through untouched
        if NOT_A_COLOUR.search(key) or raw < 0:
            out.append(line)
            copied += 1
            continue

        r, g, b = to_rgb(raw)
        h, l, s = rgb_to_hls(r, g, b)

        if s <= neutral_below:
            # A grey. Greys carry the UI's structure, so keep the lightness and
            # only lean it toward the brand's neutral ramp - this is what makes
            # a theme read as one family rather than a recoloured default.
            nr, ng, nb = mix((r, g, b), pal["neutral"], float(tint.get("neutral_pull", 0.5)))
            # re-impose the original lightness so contrast survives the mix
            nh, _, ns = rgb_to_hls(nr, ng, nb)
            r2, g2, b2 = hls_to_rgb(nh, l, ns)
        else:
            # A saturated colour: pull its hue toward the accent, keep lightness.
            nh = h + (accent_h - h) * hue_pull
            ns = max(sat_floor, min(1.0, s * sat_scale))
            r2, g2, b2 = hls_to_rgb(nh % 1.0, l, ns)

        out.append(f"{key}={to_native(r2, g2, b2)}")
        changed += 1

    return out, {"derived": changed, "verbatim": copied, "explicit": forced}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--palette", required=True)
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    with open(args.palette) as fh:
        spec = json.load(fh)

    if not os.path.exists(args.base):
        sys.exit(f"base theme not found: {args.base}")

    lines, stats = build(read_base(args.base), spec)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    print(f"theme:    {spec.get('name', '(unnamed)')}")
    print(f"base:     {os.path.basename(args.base)}")
    print(f"entries:  {stats['explicit']} set by hand · {stats['derived']} derived · "
          f"{stats['verbatim']} copied verbatim (flags/drawmodes)")
    print(f"written:  {args.out}")


if __name__ == "__main__":
    main()
