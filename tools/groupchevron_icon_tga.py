"""Writes GroupChevron/icon.tga: the AddOns-list icon (64x64, 32-bit TGA, alpha).

Two stacked "V"s in GroupChevron's pink #FF4FD8 (the second stroke faded) on a transparent
background. Same V geometry and stroke width as chevron.tga (tools/chevron_tga.py).
Unlike chevron.tga (white, tinted at runtime with SetVertexColor), this icon is PRE-COLOURED:
the AddOns list cannot tint it. Referenced by `## IconTexture` in GroupChevron.toc.

Usage, from the repo root: python3 tools/groupchevron_icon_tga.py GroupChevron/icon.tga
"""
import math, struct, sys

W, H = 64, 64
BGR = (0xD8, 0x4F, 0xFF)  # #FF4FD8 as B, G, R
# First V, as in chevron_tga.py (left top, bottom point, right top; y down), moved down so the
# pair is vertically centred; the second V is the first one moved down by GAP.
Y_SHIFT = 5.25
GAP = 15.0
PTS = [(6.0, 7.0 + Y_SHIFT), (32.0, 25.5 + Y_SHIFT), (58.0, 7.0 + Y_SHIFT)]
STROKES = [(0.0, 1.0), (GAP, 0.45)]  # (y offset, alpha factor)
HALF = 4.6  # half stroke width, in texture pixels
SS = 4      # supersampling per axis

def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def coverage(x, y, off):
    hit = 0
    for i in range(SS):
        for j in range(SS):
            px, py = x + (i + 0.5) / SS, y + (j + 0.5) / SS - off
            d = min(seg_dist(px, py, *PTS[0], *PTS[1]), seg_dist(px, py, *PTS[1], *PTS[2]))
            if d <= HALF:
                hit += 1
    return hit / (SS * SS)

rows = []
for y in range(H):
    row = bytearray()
    for x in range(W):
        a = max(coverage(x, y, off) * k for off, k in STROKES)
        row += bytes(BGR) + bytes((round(a * 255),))  # BGRA
    rows.append(bytes(row))

# Uncompressed true-colour TGA, 32 bpp, 8 alpha bits, bottom-left origin (rows bottom-up).
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
with open(sys.argv[1], "wb") as f:
    f.write(header)
    for row in reversed(rows):
        f.write(row)
