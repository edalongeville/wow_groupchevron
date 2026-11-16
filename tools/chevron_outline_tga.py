"""Writes GroupChevron/chevron_outline.tga: the same "V" as chevron.tga, thicker, for its outline.

80x40, 32-bit TGA, white with alpha (tinted black at runtime). The "V" has the geometry of
tools/chevron_tga.py shifted by (8, 4) so that both textures are concentric, and a half stroke
OUTLINE texture pixels wider: the outline texture is drawn 1.25 times the size of chevron.tga
(80/64), centred on it.

Usage, from the repo root: python3 tools/chevron_outline_tga.py GroupChevron/chevron_outline.tga
"""
import math, struct, sys

W, H = 80, 40
PTS = [(14.0, 11.0), (40.0, 29.5), (66.0, 11.0)]  # chevron_tga.py's points + (8, 4)
HALF = 4.6 + 2.4  # chevron_tga.py's half stroke + the outline width, in texture pixels
SS = 4            # supersampling per axis

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

header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
with open(sys.argv[1], "wb") as f:
    f.write(header)
    for row in reversed(rows):
        f.write(row)
