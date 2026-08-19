#!/usr/bin/env python3
"""
Nathaniel Tools toolbar icons for REAPER.

Draws every icon as SVG (three states side by side: normal / hover / on) and
renders the PNG strips REAPER wants: 90x30 (100%), 135x45 (150/), 180x60 (200/).
Run:  python3 tools/toolbar/make_icons.py <out_dir>
Needs rsvg-convert (brew install librsvg).
"""
import os, subprocess, sys, html

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Application Support/REAPER/Data/toolbar_icons")

BG      = "#1A1D27"; BG_H = "#262B38"; BORDER = "#2A2F3B"; BORDER_H = "#3A4050"
INK     = "#E9EBF1"; INK_ON = "#0F1117"
ACC = { "speed": "#4F8EF7", "teal": "#2FB7A6", "green": "#3FA95E", "amber": "#E0912E",
        "violet": "#8A5CF0", "grid": "#E8B23A", "red": "#E0455A" }

def tile(state, accent, body_fn):
    """One 24x24 tile at the given state. body_fn(ink) -> svg fragment."""
    if state == 0: bg, bd, ink = BG, BORDER, INK
    elif state == 1: bg, bd, ink = BG_H, BORDER_H, "#FFFFFF"
    else: bg, bd, ink = accent, accent, INK_ON
    return (f'<rect x="1" y="1" width="22" height="22" rx="5.5" fill="{bg}" stroke="{bd}" stroke-width="1"/>'
            + body_fn(ink))

def strip(accent, body_fn):
    parts = []
    for st in range(3):
        parts.append(f'<g transform="translate({st*24},0)">{tile(st, accent, body_fn)}</g>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 24" width="72" height="24">'
            + "".join(parts) + "</svg>")

# ---------------------------------------------------------------- glyphs (24x24)
def S(ink, w=1.8): return f'fill="none" stroke="{ink}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"'
def text(ink, s, size=8.2, y=15.2, x=12, weight=700, spacing=0):
    return (f'<text x="{x}" y="{y}" text-anchor="middle" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" '
            f'font-weight="{weight}" font-size="{size}" letter-spacing="{spacing}" fill="{ink}">{html.escape(s)}</text>')

G = {}
# --- speed layer
G["solo_focus"]      = ("speed", lambda i: f'<circle cx="12" cy="12" r="7.2" {S(i,1.6)}/>' + text(i, "S", 9.5, 15.6))
G["record_arm"]      = ("red",   lambda i: f'<circle cx="12" cy="12" r="7.5" {S(i,1.6)}/><circle cx="12" cy="12" r="3.6" fill="{i}"/>')
G["fx_float"]        = ("speed", lambda i: f'<rect x="4.5" y="5.5" width="15" height="13" rx="2" {S(i,1.6)}/><line x1="4.5" y1="9" x2="19.5" y2="9" {S(i,1.4)}/>' + text(i, "FX", 6.2, 16.4, 12))
G["fx_all"]          = ("speed", lambda i: f'<rect x="3.5" y="7.5" width="12" height="10" rx="2" {S(i,1.5)}/><rect x="8.5" y="4.5" width="12" height="10" rx="2" {S(i,1.5)}/><line x1="8.5" y1="7.5" x2="20.5" y2="7.5" {S(i,1.3)}/>')
G["region_prev"]     = ("speed", lambda i: f'<path d="M9 6H5.5V18H9" {S(i)}/><path d="M18 12H11M14 8.5L10.5 12L14 15.5" {S(i)}/>')
G["region_next"]     = ("speed", lambda i: f'<path d="M15 6H18.5V18H15" {S(i)}/><path d="M6 12H13M10 8.5L13.5 12L10 15.5" {S(i)}/>')
G["marker_bar"]      = ("speed", lambda i: f'<line x1="8" y1="4.5" x2="8" y2="19.5" {S(i,1.7)}/><path d="M8 5.5H17L14.5 9L17 12.5H8Z" fill="{i}"/>')
G["tempo_bar"]       = ("speed", lambda i: f'<path d="M9 19.5L11 5.5H13L15 19.5Z" {S(i,1.5)}/><line x1="7" y1="19.5" x2="17" y2="19.5" {S(i,1.7)}/><line x1="12" y1="15" x2="16.5" y2="7.5" {S(i,1.5)}/>')
G["midi_render"]     = ("speed", lambda i: f'<rect x="4" y="5" width="16" height="9" rx="1.5" {S(i,1.5)}/><line x1="8" y1="5" x2="8" y2="11" {S(i,1.4)}/><line x1="12" y1="5" x2="12" y2="11" {S(i,1.4)}/><line x1="16" y1="5" x2="16" y2="11" {S(i,1.4)}/><path d="M12 15V20.5M9.5 18.5L12 21L14.5 18.5" {S(i,1.6)}/>')
G["flush_paste"]     = ("speed", lambda i: f'<rect x="6" y="5.5" width="12" height="14.5" rx="2" {S(i,1.5)}/><rect x="9.5" y="3.8" width="5" height="3" rx="1" fill="{i}"/><path d="M12 9.5V16.5M9.5 14L12 16.5L14.5 14" {S(i,1.6)}/>')
G["duplicate_track"] = ("speed", lambda i: f'<rect x="4" y="5" width="16" height="4.5" rx="1.5" {S(i,1.5)}/><rect x="4" y="12" width="9" height="4.5" rx="1.5" {S(i,1.5)}/><path d="M17 11.5V18M13.8 14.8H20.2" {S(i,1.7)}/>')
G["unsolo_unselect"] = ("speed", lambda i: f'<path d="M18 12A6 6 0 1 1 15.5 7.2" {S(i)}/><path d="M15.5 4V7.5H19" {S(i)}/>')
G["toggle_chorale"]  = ("violet",lambda i: f'<path d="M5 15V9M9 18V6M13 16V8M17 14V10M21 13V11" {S(i,2.2)}/>')
# --- apps
G["app_palette"]     = ("teal",  lambda i: f'<circle cx="9" cy="9.5" r="4.2" {S(i,1.5)}/><circle cx="15" cy="9.5" r="4.2" {S(i,1.5)}/><circle cx="12" cy="14.5" r="4.2" {S(i,1.5)}/>')
G["app_folders"]     = ("green", lambda i: f'<path d="M4 7.5A1.5 1.5 0 0 1 5.5 6H9.5L11.5 8H18.5A1.5 1.5 0 0 1 20 9.5V17A1.5 1.5 0 0 1 18.5 18.5H5.5A1.5 1.5 0 0 1 4 17Z" {S(i,1.5)}/>')
G["app_transfer"]    = ("green", lambda i: f'<rect x="3.5" y="5" width="7" height="14" rx="1.5" {S(i,1.4)}/><rect x="13.5" y="5" width="7" height="14" rx="1.5" {S(i,1.4)}/><path d="M9 9.5H15M13 7.5L15 9.5L13 11.5M15 14.5H9M11 12.5L9 14.5L11 16.5" {S(i,1.4)}/>')
G["app_stems"]       = ("amber", lambda i: f'<path d="M4 7H13M4 12H13M4 17H13" {S(i,2)}/><path d="M16 12H20.5M18.5 9.5L21 12L18.5 14.5" {S(i,1.7)}/>')
G["app_midi_export"] = ("amber", lambda i: f'<rect x="4" y="6" width="13" height="12" rx="1.5" {S(i,1.5)}/><line x1="8" y1="6" x2="8" y2="13" {S(i,1.3)}/><line x1="12" y1="6" x2="12" y2="13" {S(i,1.3)}/><path d="M19.5 8V16M17 13.5L19.5 16L22 13.5" {S(i,1.5)}/>')
G["app_dock"]        = ("teal",  lambda i: f'<rect x="4" y="4.5" width="16" height="15" rx="2" {S(i,1.5)}/><line x1="4" y1="13.5" x2="20" y2="13.5" {S(i,1.4)}/><line x1="9.5" y1="13.5" x2="9.5" y2="19.5" {S(i,1.4)}/><line x1="14.5" y1="13.5" x2="14.5" y2="19.5" {S(i,1.4)}/>')
G["app_stagerig"]    = ("violet",lambda i: f'<path d="M5 18L12 5L19 18Z" {S(i,1.6)}/><circle cx="12" cy="14" r="1.6" fill="{i}"/>')
# --- grid tiles (text)
for key, label, size in [("grid_bar","BAR",7.2), ("grid_1_2","1/2",8.2), ("grid_1_4","1/4",8.2), ("grid_1_4t","1/4T",7), ("grid_1_8","1/8",8.2),
                         ("grid_1_8t","1/8T",7), ("grid_1_16","1/16",7.4), ("grid_1_24","1/24",7.4), ("grid_rel","REL",7.2), ("grid_swing","SWG",7.2)]:
    G[key] = ("grid", (lambda L, sz: (lambda i: text(i, L, sz, 15.4)))(label, size))
G["grid_click"]      = ("grid",  lambda i: f'<path d="M9 19.5L11 5.5H13L15 19.5Z" {S(i,1.4)}/><line x1="7" y1="19.5" x2="17" y2="19.5" {S(i,1.6)}/><circle cx="12" cy="11" r="1.4" fill="{i}"/>')
G["grid_random_col"] = ("grid",  lambda i: f'<circle cx="8" cy="9" r="2.4" fill="{i}"/><circle cx="15.5" cy="8" r="2.4" fill="{i}" opacity=".75"/><circle cx="10" cy="15.5" r="2.4" fill="{i}" opacity=".55"/><circle cx="16.5" cy="15" r="2.4" fill="{i}" opacity=".9"/>')

def render(name, accent, body):
    svg = strip(ACC[accent], body)
    os.makedirs(OUT, exist_ok=True)
    for sub, px in [("", 30), ("150", 45), ("200", 60)]:
        d = os.path.join(OUT, sub) if sub else OUT
        os.makedirs(d, exist_ok=True)
        svgp = f"/tmp/nt_{name}.svg"
        with open(svgp, "w") as f: f.write(svg)
        png = os.path.join(d, f"nt_{name}.png")
        subprocess.run(["rsvg-convert", "-w", str(px*3), "-h", str(px), "-o", png, svgp], check=True)

if __name__ == "__main__":
    for name, (acc, body) in G.items():
        render(name, acc, body)
    print(f"{len(G)} icons x 3 sizes -> {OUT}")
