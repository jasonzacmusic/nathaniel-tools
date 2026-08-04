#!/usr/bin/env python3
"""package_theme.py — assemble the Nathaniel Tools .ReaperThemeZip.

WHAT IT DOES

Takes three inputs and welds them into one installable theme:

    1. REAPER's stock Default 7.0 theme  - the image set and the base rtconfig
    2. palettes/<name>.json              - about a dozen colour decisions
    3. src/rtconfig_nathaniel.txt        - our appended WALTER block

and writes `themes/Nathaniel Tools.ReaperThemeZip`. Run it again after any
palette edit; the output is deterministic, so an unchanged palette produces a
byte-identical zip and git stays quiet.

THREE THINGS THIS FILE EXISTS TO GET RIGHT

1. IMAGE BYTES ARE COPIED, NEVER PROCESSED.
   REAPER does not use 9-slice scaling. It reads magenta and yellow guide
   pixels out of a 1px border that is never drawn, and those pixels decide how
   the image stretches. Any resample, any rescale, any trip through an imaging
   library's colour management shifts those pixels off their exact values and
   the image stretches wrongly - subtly, on some elements, at some sizes. So
   every PNG here is moved as an opaque blob. No image library is imported and
   none ever should be.

2. THE IMAGE FOLDER AND ui_img MUST AGREE.
   A .ReaperThemeZip is a .ReaperTheme file plus a sibling folder of images,
   and the only thing binding them is the single line `ui_img=<foldername>`
   inside the .ReaperTheme. Rename the folder without updating that key and the
   theme loads with no graphics at all - the most common packaging mistake
   there is. We rename the folder (it carries the theme's name to the user) and
   rewrite ui_img in the same step so the two cannot drift apart.
   The `150/` and `200/` subfolders inside it are REAPER's HiDPI mechanism -
   whole alternate image sets chosen by layout variants and misc_dpi_translate,
   not filename suffixes - so the folder structure is preserved exactly.

3. PARAMETER ORDER IS VERIFIED, NOT TRUSTED.
   Theme parameter values persist to reaper-themeconfig.ini as positional
   indices. If our rtconfig ever stops beginning with Default 7.0's 277
   parameters in Default 7.0's order, every setting a user has saved shifts by
   one and silently corrupts. Nothing in REAPER warns about this, so the check
   lives here and fails the build.

Usage:
    python3 package_theme.py                       # defaults, writes themes/
    python3 package_theme.py --palette palettes/nsm-dark.json
    python3 package_theme.py --check-only          # verify without writing
"""

import argparse
import io
import json
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_theme  # noqa: E402  - sibling module, same directory

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

DEFAULT_BASE = os.path.expanduser(
    "~/Library/Application Support/REAPER/ColorThemes/Default_7.0.ReaperThemeZip")

THEME_NAME = "Nathaniel Tools"
IMG_FOLDER = "Nathaniel_Tools"            # no spaces: this is a path AND a key

# The adjuster window. We keep REAPER's own, deliberately.
#
# Default_7.0_theme_adjuster.lua ships inside REAPER (7.17+) and every install
# already has it, so referencing it means the adjuster works the moment the
# theme is applied - no second download, no install step a non-technical user
# has to be walked through.
#
# It also handles a theme it does not recognise correctly. Reading its source:
# switchTheme() tests `string.sub(themeTitle,1,11) ~= 'Default_7.0'`, and for
# anything else it turns off Cockos' hand-drawn pages and turns on its GLOBAL
# and THEME CONTROLS pages - and THEME CONTROLS is a loop over
# ThemeLayout_GetParameter(i) that builds a real control for every parameter it
# finds: a toggle for 0..1, a knob plus spinner plus readout for everything
# else. So all 300 of ours get a working control, including the 23 appended
# below Cockos' 277.
#
# What we give up is Cockos' prettier per-panel pages. Getting those back means
# shipping our own fork of a 5,354-line LGPL script, which cannot travel inside
# a .ReaperThemeZip - it would need a ReaPack package alongside. Worth doing
# when this ships as a product; not worth an install step now.
ADJUSTER = None

PARAM = re.compile(r"^\s*define_parameter\s+(\S+)\s+'([^']*)'\s*(.*?)\s*$", re.M)

# One fixed timestamp for every entry. Zip stores mtimes, so without this the
# same inputs would produce a different file every run and every rebuild would
# look like a change in git.
FIXED_DATE = (2026, 8, 4, 0, 0, 0)


def read_base(path):
    """Pull the three things we need out of the stock theme zip."""
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        theme = next((n for n in names if n.lower().endswith(".reapertheme")), None)
        rtcfg = next((n for n in names if n.lower().endswith("rtconfig.txt")), None)
        if not theme or not rtcfg:
            sys.exit(f"{path} is not a complete theme (missing .ReaperTheme or rtconfig.txt)")
        img_root = rtcfg.rsplit("/", 1)[0]
        images = [n for n in names
                  if n.startswith(img_root + "/") and n != rtcfg and not n.endswith("/")]
        return {
            "zip": path,
            "theme_lines": z.read(theme).decode("utf-8", "replace").splitlines(),
            "rtconfig": z.read(rtcfg).decode("utf-8", "replace"),
            "img_root": img_root,
            "image_names": sorted(images),
        }


def params_of(src):
    """(name, description) for every define_parameter, in declaration order."""
    return [(m[0], m[1]) for m in PARAM.findall(src)]


def check_append_only(base_src, ours_src):
    """Our parameters must START with the base's, unchanged and in order.

    This is the whole reason the check exists: reaper-themeconfig.ini keys
    settings by position, so a reorder is a silent data corruption, not an
    error anyone would see.
    """
    base = params_of(base_src)
    ours = params_of(ours_src)
    if len(ours) < len(base):
        sys.exit(f"FAIL: {len(ours)} parameters, fewer than the base's {len(base)} - "
                 "parameters may only be appended, never removed")
    for i, (b, o) in enumerate(zip(base, ours)):
        if b != o:
            sys.exit(f"FAIL: parameter #{i} changed from {b[0]!r} ('{b[1]}') "
                     f"to {o[0]!r} ('{o[1]}').\n"
                     "      Parameter order is positional in reaper-themeconfig.ini. "
                     "Append at the end of\n"
                     "      src/rtconfig_nathaniel.txt instead; never insert or reorder.")
    return len(base), len(ours)


def build_rtconfig(base_src, extra_src):
    """Base rtconfig verbatim, our block appended. Optionally repoint the adjuster."""
    if not re.search(r"^\s*adjuster_script\s", base_src, re.M):
        sys.exit("base rtconfig has no adjuster_script line - the theme would have no adjuster")

    src = base_src
    if ADJUSTER:
        src = re.sub(r"^(\s*)adjuster_script\s+\"[^\"]*\"",
                     lambda m: f'{m.group(1)}adjuster_script "{ADJUSTER}"',
                     src, count=1, flags=re.M)
    return src + "\n\n" + extra_src


def build_colours(base_lines, palette_path):
    """Derive the .ReaperTheme, then bind it to our image folder."""
    with open(palette_path) as fh:
        spec = json.load(fh)
    lines, stats = build_theme.build(base_lines, spec)

    # ui_img is the ONLY link between the colour file and the image folder.
    patched, found = [], False
    for line in lines:
        if line.startswith("ui_img="):
            patched.append(f"ui_img={IMG_FOLDER}")
            found = True
        else:
            patched.append(line)
    if not found:
        sys.exit("base .ReaperTheme has no ui_img key - the images would not load")
    return "\n".join(patched) + "\n", stats, spec


def write_zip(out_path, theme_text, rtconfig_text, base, quiet=False):
    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    buf = io.BytesIO()
    with zipfile.ZipFile(base["zip"]) as src, \
            zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:

        def put(name, data):
            info = zipfile.ZipInfo(name, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            out.writestr(info, data)

        put(f"{THEME_NAME}.ReaperTheme", theme_text.encode("utf-8"))
        put(f"{IMG_FOLDER}/rtconfig.txt", rtconfig_text.encode("utf-8"))

        prefix = base["img_root"] + "/"
        for name in base["image_names"]:
            # Verbatim. Decompress-then-recompress preserves the bytes exactly;
            # what must never happen is decoding the PNG - the magenta/yellow
            # stretch guides do not survive a round trip through an image
            # library.
            put(IMG_FOLDER + "/" + name[len(prefix):], src.read(name))

    with open(out_path, "wb") as fh:
        fh.write(buf.getvalue())
    if not quiet:
        print(f"images:   {len(base['image_names'])} copied byte-for-byte "
              f"(incl. the 150/ and 200/ HiDPI sets)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--palette", default=os.path.join(HERE, "palettes", "nsm-dark.json"))
    ap.add_argument("--extra", default=os.path.join(REPO, "themes", "src", "rtconfig_nathaniel.txt"))
    ap.add_argument("--out", default=os.path.join(REPO, "themes", f"{THEME_NAME}.ReaperThemeZip"))
    ap.add_argument("--check-only", action="store_true",
                    help="run the parameter-order check and stop")
    args = ap.parse_args()

    for p in (args.base, args.palette, args.extra):
        if not os.path.exists(p):
            sys.exit(f"missing input: {p}")

    base = read_base(args.base)
    extra = open(args.extra, encoding="utf-8").read()
    rtconfig = build_rtconfig(base["rtconfig"], extra)

    n_base, n_ours = check_append_only(base["rtconfig"], rtconfig)
    print(f"parameters: {n_base} inherited from Default 7.0, in order, unchanged "
          f"+ {n_ours - n_base} appended = {n_ours}")

    if args.check_only:
        return

    theme_text, stats, spec = build_colours(base["theme_lines"], args.palette)
    print(f"colours:  {stats['explicit']} set by hand · {stats['derived']} derived · "
          f"{stats['verbatim']} copied verbatim (flags/drawmodes/fonts)")

    write_zip(args.out, theme_text, rtconfig, base)
    print(f"theme:    {spec.get('name', THEME_NAME)}")
    print(f"written:  {args.out}  ({os.path.getsize(args.out) / 1024 / 1024:.1f} MB)")


if __name__ == "__main__":
    main()
