"""Writes the CurseForge project icon: the GroupChevron double chevron (pink #FF4FD8, second
stroke faded) on a dark square, 400x400 RGB PNG. Same V geometry as icon.tga
(tools/groupchevron_icon_tga.py), scaled up. Standard library only.

Usage, from the repo root: python3 tools/curseforge_icon_png.py assets/curseforge-icon.png
"""
import math, struct, sys, zlib

SIZE = 400
SCALE = 5.0                    # icon.tga is 64x64; 64 * 5 = 320, leaving a 40 px margin
MARGIN = (SIZE - 64 * SCALE) / 2
PINK = (0xFF, 0x4F, 0xD8)
BG = (0x1B, 0x16, 0x2E)
# Geometry of icon.tga, in its 64x64 pixels.
Y_SHIFT, GAP = 5.25, 15.0
PTS = [(6.0, 7.0 + Y_SHIFT), (32.0, 25.5 + Y_SHIFT), (58.0, 7.0 + Y_SHIFT)]
STROKES = [(0.0, 1.0), (GAP, 0.45)]  # (y offset, alpha factor)
HALF = 4.6
SS = 3

def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def coverage(x, y, off):
    hit = 0
    for i in range(SS):
        for j in range(SS):
            # Output pixel -> icon.tga pixel space.
            px = (x + (i + 0.5) / SS - MARGIN) / SCALE
            py = (y + (j + 0.5) / SS - MARGIN) / SCALE - off
            d = min(seg_dist(px, py, *PTS[0], *PTS[1]), seg_dist(px, py, *PTS[1], *PTS[2]))
            if d <= HALF:
                hit += 1
    return hit / (SS * SS)

raw = bytearray()
for y in range(SIZE):
    raw.append(0)  # filter: none
    for x in range(SIZE):
        a = max(coverage(x, y, off) * k for off, k in STROKES)
        raw += bytes(round(BG[c] + (PINK[c] - BG[c]) * a) for c in range(3))

def chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
       + chunk(b"IEND", b""))
with open(sys.argv[1], "wb") as f:
    f.write(png)
