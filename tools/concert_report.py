#!/usr/bin/env python3
"""concert_report.py — read-only MainStage .concert reporter.

Point it at a .concert bundle and it prints (and optionally writes) a report:
setlist order, every patch and sub-patch, every channel strip, every
instrument/plugin referenced, and — critically — which sounds are Logic-only
(no REAPER equivalent) versus loadable in REAPER, with suggested substitutes
from instruments the owner actually has.

Never writes into the .concert. Read-only by construction.

Usage:
    python3 concert_report.py "/path/to/Show.concert" [--json out.json] [--md out.md]
"""

import argparse
import json
import os
import plistlib
import re
import sys
import zlib

# ---------------------------------------------------------------- knowledge

# Logic/MainStage built-in instruments: these do NOT exist as loadable AUs
# outside Logic. A faithful port is impossible; substitution is the answer.
LOGIC_ONLY = {
    "Alchemy": "Omnisphere (closest sound-design depth) or ANA 2",
    "Sampler": "UVI Workstation / Kontakt (re-sample or find equivalent)",
    "Quick Sampler": "UVI Workstation / ReaSamplOmatic5000",
    "EXS24": "UVI Workstation / Kontakt",
    "Retro Synth": "Arturia V Collection (matching model)",
    "ES2": "Arturia V Collection / ANA 2",
    "ES1": "Arturia V Collection / ANA 2",
    "Sculpture": "no direct equivalent — resample or Omnisphere",
    "Vintage Electric Piano": "Keyscape / Lounge Lizard / Arturia Stage-73 V",
    "Vintage B3": "Arturia B-3 V / IK Hammond B-3X",
    "Vintage Clav": "Arturia Clavinet V / Keyscape",
    "Vintage Mellotron": "Arturia Mellotron V / UVI Mello",
    "Studio Horns": "Kontakt Session Horns / UVI brass",
    "Studio Strings": "Kontakt Session Strings / Spitfire",
    "Drum Kit Designer": "MT Power Drum Kit / Kontakt kits",
    "Drummer": "pre-rendered audio loops",
    "Ultrabeat": "pre-rendered audio loops / MT Power Drum Kit",
    "Splendid Grand": "Pianoteq 8/9 or Keyscape grand",
    "Steinway Grand Piano": "Pianoteq 8/9 or Keyscape grand",
    "Yamaha Grand Piano": "Pianoteq 8/9",
    "Space Designer": "ReaVerb (import the same IRs) / Valhalla",
    "ChromaVerb": "ReaVerb / Valhalla",
    "Pedalboard": "REAPER FX chain equivalents",
    "Amp Designer": "Neural Amp Modeler / ReaJS amp sims",
}

# Third-party plugins that load in REAPER directly (as seen in Jason's rigs).
THIRD_PARTY = [
    "Kontakt", "Pianoteq", "Keyscape", "Omnisphere", "Trilian", "UVI",
    "Arturia", "Analog Lab", "ANA 2", "Lounge Lizard", "Massive", "Serum",
    "Zebra", "Diva", "Repro", "Sylenth", "Nexus", "Dexed", "Surge",
    "Blue3", "VB3", "B-3X", "Korg", "Roland Cloud", "JV-1080", "Zenology",
]

# Strings worth surfacing from a .cst blob even if not in the tables above.
CST_NOISE = re.compile(
    r"^(OCuA|bplist|NSKeyedArchiver|NS[A-Z]\w+|CF\$\w+|\$\w+|root|data|"
    r"com\.apple\.\w[\w.]*|[0-9A-F-]{8,}|Master|Output( \d+(-\d+)?)?|"
    r"AudioUnit|Channel|Version\w*|Track\w*|Custom\w*|MIDI\w*|hermode|"
    r"transforms?|filter|in|out|channels?|nodes?|patch|engineNode)$"
)


def is_probable_name(s):
    if len(s) < 3 or len(s) > 60:
        return False
    if CST_NOISE.match(s):
        return False
    if not re.search(r"[A-Za-z]{3}", s):
        return False
    # mostly printable words, allow #/+/digits
    return bool(re.fullmatch(r"[\w #&'’.+\-()/]+", s))


BASE64ISH = re.compile(r"^[A-Za-z0-9+/=]{20,}$")


def extract_strings(blob, min_len=4):
    """ASCII + UTF-16LE string extraction from a binary blob (deduped, denoised)."""
    found = set()
    for m in re.finditer(rb"[\x20-\x7e]{%d,}" % min_len, blob):
        found.add(m.group().decode("ascii", "replace"))
    for m in re.finditer(rb"(?:[\x20-\x7e]\x00){%d,}" % min_len, blob):
        found.add(m.group().decode("utf-16-le", "replace"))
    # drop base64/parameter-blob noise before any per-string work
    return [s for s in found
            if len(s) <= 60 and not BASE64ISH.match(s)
            and re.search(r"[A-Za-z]{3}", s)]


def classify(names):
    """Split surfaced names into logic_only / third_party / other."""
    logic, third, other = {}, set(), set()
    for n in names:
        matched = False
        for key, sub in LOGIC_ONLY.items():
            if key.lower() in n.lower():
                logic[key] = sub
                matched = True
        for key in THIRD_PARTY:
            if key.lower() in n.lower():
                third.add(key if len(key) > len(n) else n)
                matched = True
        if not matched and is_probable_name(n):
            other.add(n)
    return logic, sorted(third), sorted(other)


# ---------------------------------------------------------------- parsing

def load_plist(path):
    try:
        with open(path, "rb") as f:
            return plistlib.load(f)
    except Exception:
        return None


def load_plistz(path):
    """zlib-compressed NSKeyedArchiver plist (base.plistZ)."""
    try:
        raw = open(path, "rb").read()
        return plistlib.loads(zlib.decompress(raw))
    except Exception:
        return None


def cst_summary(path):
    """Best-effort read of a Logic channel-strip file (proprietary OCuA)."""
    try:
        blob = open(path, "rb").read()
    except Exception:
        return {"error": "unreadable"}
    names = extract_strings(blob)
    logic, third, other = classify(names)
    # keep 'other' tight: drop pure setting words, keep title-cased phrases
    other = [o for o in other if re.search(r"[A-Z]", o) and " " in o or
             any(c.isupper() for c in o[1:])][:12]
    return {"logic_only": logic, "third_party": third, "other_strings": other,
            "size": len(blob)}


def midi_transforms(ch):
    """Decode the per-channel MIDI transform list (key range / transpose live here)."""
    out = []
    mt = ch.get("MIDITransform") or {}
    for t in mt.get("transforms", []):
        entry = {k: v for k, v in t.items() if not isinstance(v, (bytes, dict))}
        if entry:
            out.append(entry)
    return out


def parse_patch_dir(path):
    """A .patch folder: data.plist + child .patch folders + .cst strips."""
    name = os.path.basename(path)
    name = re.sub(r"\.patch$", "", name)
    name = re.sub(r"^\d+__#\$!@%!#__", "", name)  # MainStage duplicate-name mangling
    name = re.sub(r"^\s*\d+\s+", "", name).strip() or name
    data = load_plist(os.path.join(path, "data.plist")) or {}

    node = {"name": name, "channels": [], "sub_patches": [], "settings": {}}

    p = data.get("patch") or {}
    eng = p.get("engineNode") or {}
    for k in ("globalTranspose", "hasTempo", "tempo", "hasProgramChange",
              "programChangeNumber", "defersPatchChange"):
        if k in eng and eng[k] not in (False, 0, None):
            node["settings"][k] = eng[k]

    for ch in data.get("channels", []):
        entry = {
            "name": ch.get("Channel_name", "?"),
            "file": ch.get("Filename"),
            "muted": bool(ch.get("Channel_isMuted")),
            "transforms": midi_transforms(ch),
        }
        cst = ch.get("Filename")
        if cst:
            cst_path = os.path.join(path, cst)
            if os.path.exists(cst_path):
                entry["strip"] = cst_summary(cst_path)
        node["channels"].append(entry)

    # ordered children if data.plist declares them; fall back to dir listing
    ordered = [n for n in (data.get("nodes") or []) if isinstance(n, str)]
    seen = set()
    children = []
    for child in ordered:
        cp = os.path.join(path, child)
        if os.path.isdir(cp) and child.endswith(".patch"):
            children.append(cp)
            seen.add(child)
    for child in sorted(os.listdir(path)):
        if child.endswith(".patch") and child not in seen and \
                os.path.isdir(os.path.join(path, child)):
            children.append(os.path.join(path, child))
    for cp in children:
        node["sub_patches"].append(parse_patch_dir(cp))

    return node


def parse_concert(path):
    concert = {
        "concert": os.path.basename(path),
        "path": path,
        "setlist": [],
        "concert_channels": [],
    }
    root = os.path.join(path, "Concert.patch")
    if not os.path.isdir(root):
        raise SystemExit(f"not a concert bundle (no Concert.patch): {path}")

    tree = parse_patch_dir(root)
    concert["concert_channels"] = tree["channels"]
    concert["setlist"] = tree["sub_patches"]

    base = load_plistz(os.path.join(path, "base.plistZ"))
    if base and "$objects" in base:
        # keep the raw archived strings around: patch order lives in here too
        strs = [o for o in base["$objects"] if isinstance(o, str)
                and o.endswith(".patch")]
        if strs:
            concert["base_plist_patch_refs"] = strs
    return concert


# ---------------------------------------------------------------- reporting

def collect_instruments(node, acc):
    for ch in node["channels"]:
        strip = ch.get("strip") or {}
        for k, sub in (strip.get("logic_only") or {}).items():
            acc["logic_only"].setdefault(k, {"substitute": sub, "patches": set()})
            acc["logic_only"][k]["patches"].add(node["name"])
        for t in strip.get("third_party") or []:
            acc["third_party"].setdefault(t, set()).add(node["name"])
    for sp in node["sub_patches"]:
        collect_instruments(sp, acc)


def md_patch(node, depth=0):
    pad = "  " * depth
    lines = [f"{pad}- **{node['name']}**"]
    if node["settings"]:
        lines.append(f"{pad}  - settings: `{node['settings']}`")
    for ch in node["channels"]:
        strip = ch.get("strip") or {}
        insts = list((strip.get("logic_only") or {}).keys()) + \
            (strip.get("third_party") or [])
        inst_s = ", ".join(insts) if insts else "—"
        mute = " (muted)" if ch["muted"] else ""
        lines.append(f"{pad}  - strip `{ch['name']}`{mute}: {inst_s}")
    for sp in node["sub_patches"]:
        lines.extend(md_patch(sp, depth + 1))
    return lines


def to_markdown(concert):
    acc = {"logic_only": {}, "third_party": {}}
    fake_root = {"name": "", "channels": concert["concert_channels"],
                 "sub_patches": concert["setlist"], "settings": {}}
    collect_instruments(fake_root, acc)

    L = [f"# Concert report — {concert['concert']}", ""]
    L.append(f"Patches at top level: {len(concert['setlist'])}")
    L.append("")
    L.append("## Setlist / patch tree")
    for p in concert["setlist"]:
        L.extend(md_patch(p))
    L.append("")
    L.append("## Instruments that CANNOT load in REAPER (Logic-only)")
    if acc["logic_only"]:
        L.append("| Logic instrument | Used in | Suggested substitute |")
        L.append("|---|---|---|")
        for k, v in sorted(acc["logic_only"].items()):
            L.append(f"| {k} | {', '.join(sorted(v['patches']))} | {v['substitute']} |")
    else:
        L.append("None detected.")
    L.append("")
    L.append("## Third-party plugins (load in REAPER as-is)")
    if acc["third_party"]:
        for k, v in sorted(acc["third_party"].items()):
            L.append(f"- **{k}** — {', '.join(sorted(v))}")
    else:
        L.append("None detected.")
    L.append("")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("concert")
    ap.add_argument("--json")
    ap.add_argument("--md")
    args = ap.parse_args()

    concert = parse_concert(os.path.abspath(args.concert))
    md = to_markdown(concert)
    print(md)

    def clean(o):
        if isinstance(o, dict):
            return {k: clean(v) for k, v in o.items()}
        if isinstance(o, (list, set, tuple)):
            return [clean(v) for v in o]
        if isinstance(o, bytes):
            return f"<{len(o)} bytes>"
        return o

    if args.json:
        with open(args.json, "w") as f:
            json.dump(clean(concert), f, indent=2)
        print(f"[json written: {args.json}]", file=sys.stderr)
    if args.md:
        with open(args.md, "w") as f:
            f.write(md)
        print(f"[md written: {args.md}]", file=sys.stderr)


if __name__ == "__main__":
    main()
