"""Writes GroupChevron/chevron.tga: one anti-aliased white "V" (64x32, 32-bit TGA, alpha).

Usage, from the repo root: python3 tools/chevron_tga.py GroupChevron/chevron.tga
"""
import math, struct, sys

W, H = 64, 32
PTS = [(6.0, 7.0), (32.0, 25.5), (58.0, 7.0)]  # left top, bottom point, right top (y down)
HALF = 4.6  # half stroke width, in texture pixels
SS = 4      # supersampling per axis

def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def coverage(x, y):
    hit = 0
    for i in range(SS):
        for j in range(SS):
            px, py = x + (i + 0.5) / SS, y + (j + 0.5) / SS
            d = min(seg_dist(px, py, *PTS[0], *PTS[1]), seg_dist(px, py, *PTS[1], *PTS[2]))
            if d <= HALF:
                hit += 1
    return hit / (SS * SS)

rows = []
for y in range(H):
    row = bytearray()
    for x in range(W):
        a = round(coverage(x, y) * 255)
        row += bytes((255, 255, 255, a))  # BGRA, white
    rows.append(bytes(row))

# Uncompressed true-colour TGA, 32 bpp, 8 alpha bits, bottom-left origin (rows bottom-up).
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
with open(sys.argv[1], "wb") as f:
    f.write(header)
    for row in reversed(rows):
        f.write(row)
