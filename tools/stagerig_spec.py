#!/usr/bin/env python3
"""stagerig_spec.py — turn a MainStage concert into a StageRig build spec.

Reads a `.concert` bundle (via concert_report's parser), picks the patches you
name, applies the editable substitution map, and writes `rig.json`.

Nothing here touches REAPER. The JSON it emits is consumed by
`NPH/NPH_StageRig Build.lua`, which builds the project inside REAPER using the
real API — so plugins are resolved by name against what is actually installed
rather than hand-forged into an .RPP.

Every substitution is recorded explicitly, including the ones that could not be
made. A track with no instrument is still created, named and routed, and marked
`needs_sound` so it shows up in the report and on the stage view.

Usage:
    python3 stagerig_spec.py "/path/to/Show.concert" \\
        --patches "Aasma" "Humma Humma" "BRAHMA Gm" "Upright" "Maari Kannu" \\
        --out stagerig/rig.json
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import concert_report as cr  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SUBS = os.path.join(HERE, "..", "stagerig", "substitutions.json")

# Patch accent colours (REAPER native ints are computed Lua-side from these).
PALETTE = [
    [0x8a, 0x5c, 0xf0],  # violet
    [0x3e, 0xc9, 0xc0],  # teal
    [0x54, 0xd0, 0x7a],  # green
    [0xe8, 0xb2, 0x3a],  # amber
    [0xe0, 0x45, 0x5a],  # red
    [0x5b, 0x9d, 0xf5],  # blue
]


def flatten(node, trail=None, out=None):
    """Every patch in the tree, with the path that leads to it."""
    out = [] if out is None else out
    trail = trail or []
    here = trail + [node["name"]]
    if node["channels"]:
        out.append({"name": node["name"], "path": here, "node": node})
    for sp in node["sub_patches"]:
        flatten(sp, here, out)
    return out


def pick(patches, wanted):
    """Match requested patch names against the flattened tree, in order."""
    chosen, missing = [], []
    for w in wanted:
        wl = w.lower()
        exact = [p for p in patches if p["name"].lower() == wl]
        loose = [p for p in patches if wl in p["name"].lower()]
        hit = (exact or loose)
        if hit:
            # deepest match wins: a song patch beats a folder of the same name
            hit = sorted(hit, key=lambda p: -len(p["path"]))[0]
            if hit not in chosen:
                chosen.append(hit)
        else:
            missing.append(w)
    return chosen, missing


def resolve_fx(strip_name, instruments, subs):
    """Decide the instrument for one channel strip.

    Strip name wins over the detected Logic instrument, because the name is what
    actually says what the sound is ('Shenai' is more informative than
    'Sampler'). Returns (fx_name_or_None, reason, source_instrument).
    """
    by_name = subs.get("by_strip_name", {})
    sl = (strip_name or "").lower()
    for key, entry in by_name.items():
        if key.startswith("_"):
            continue
        if key in sl:
            return entry.get("fx"), entry.get("note", ""), f"strip name '{key}'"

    for inst in instruments:
        entry = subs.get("map", {}).get(inst)
        if entry:
            return entry.get("fx"), entry.get("note", ""), inst

    return None, "no rule matched - pick an instrument for this track yourself", \
        (instruments[0] if instruments else "unknown")


def build(concert_path, wanted, subs_path):
    with open(subs_path) as f:
        subs = json.load(f)

    concert = cr.parse_concert(os.path.abspath(concert_path))
    root = {"name": "", "channels": concert["concert_channels"],
            "sub_patches": concert["setlist"], "settings": {}}
    all_patches = flatten(root)
    chosen, missing = pick(all_patches, wanted)

    rig = {
        "concert": concert["concert"],
        "concert_path": concert["path"],
        "generated_from": "stagerig_spec.py",
        "patches": [],
        "not_found": missing,
        "summary": {"exact": 0, "substituted": 0, "needs_sound": 0},
    }

    for i, p in enumerate(chosen):
        node = p["node"]
        col = PALETTE[i % len(PALETTE)]
        patch = {
            "name": node["name"],
            "path": " / ".join(p["path"]).strip(" /"),
            "colour": col,
            "tempo": node["settings"].get("tempo"),
            "tracks": [],
        }
        for ch in node["channels"]:
            strip = ch.get("strip") or {}
            insts = list((strip.get("logic_only") or {}).keys()) + \
                (strip.get("third_party") or [])
            fx, note, src = resolve_fx(ch["name"], insts, subs)

            exact = fx is not None and any(
                fx.split()[0].lower() in inst.lower() for inst in insts)
            if fx is None:
                kind = "needs_sound"
                rig["summary"]["needs_sound"] += 1
            elif exact:
                kind = "exact"
                rig["summary"]["exact"] += 1
            else:
                kind = "substituted"
                rig["summary"]["substituted"] += 1

            patch["tracks"].append({
                "name": ch["name"],
                "muted_in_concert": ch["muted"],
                "was": insts or ["(none detected)"],
                "fx": fx,
                "kind": kind,
                "why": note,
                "matched_on": src,
            })
        rig["patches"].append(patch)

    return rig


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def to_lua(rig):
    """Emit the rig as a Lua table literal the builder can dofile()."""
    L = ["-- Generated by tools/stagerig_spec.py - do not edit by hand.",
         "-- Edit stagerig/substitutions.json and regenerate instead.",
         "return {",
         f"  concert = {lua_str(rig['concert'])},",
         "  patches = {"]
    for p in rig["patches"]:
        c = p["colour"]
        L.append("    {")
        L.append(f"      name = {lua_str(p['name'])},")
        L.append(f"      path = {lua_str(p['path'])},")
        L.append(f"      colour = {{ {c[0]}, {c[1]}, {c[2]} }},")
        L.append(f"      tempo = {p['tempo'] if p.get('tempo') else 'nil'},")
        L.append("      tracks = {")
        for t in p["tracks"]:
            fx = lua_str(t["fx"]) if t["fx"] else "nil"
            L.append("        { name = %s, fx = %s, kind = %s, was = %s },"
                     % (lua_str(t["name"]), fx, lua_str(t["kind"]),
                        lua_str(" + ".join(t["was"]))))
        L.append("      },")
        L.append("    },")
    L.append("  },")
    L.append("}")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("concert")
    ap.add_argument("--patches", nargs="+", required=True)
    ap.add_argument("--subs", default=DEFAULT_SUBS)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    rig = build(args.concert, args.patches, args.subs)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(rig, f, indent=2)

    # Also emit the same spec as a Lua table. The REAPER-side builder then needs
    # no JSON parser at all - one less thing to be subtly wrong on stage.
    lua_out = os.path.splitext(args.out)[0] + ".lua"
    with open(lua_out, "w") as f:
        f.write(to_lua(rig))
    print(f"written: {lua_out}")

    print(f"concert: {rig['concert']}")
    if rig["not_found"]:
        print(f"!! patches not found: {', '.join(rig['not_found'])}")
    for p in rig["patches"]:
        print(f"\n== {p['name']}   ({p['path']})"
              + (f"   {p['tempo']:.0f} bpm" if p.get("tempo") else ""))
        for t in p["tracks"]:
            flag = {"exact": "  ", "substituted": "~ ", "needs_sound": "! "}[t["kind"]]
            print(f"  {flag}{t['name']:<22} {' + '.join(t['was']):<28} -> "
                  f"{t['fx'] or 'EMPTY - add your own'}")
    s = rig["summary"]
    print(f"\nexact {s['exact']} · substituted {s['substituted']} · "
          f"needs a sound {s['needs_sound']}")
    print(f"written: {args.out}")


if __name__ == "__main__":
    main()
