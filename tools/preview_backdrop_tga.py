"""Writes GroupChevron/backdrop.tga: a white rounded square (64x64, 32-bit TGA, alpha).

It is tinted grey at runtime and sits behind the chevron previews of the options page.

Usage, from the repo root: python3 tools/preview_backdrop_tga.py GroupChevron/backdrop.tga
"""
import struct, sys

W = H = 64
RADIUS = 12.0
SS = 4  # supersampling per axis

def inside(px, py):
    cx = min(max(px, RADIUS), W - RADIUS)
    cy = min(max(py, RADIUS), H - RADIUS)
    return (px - cx) ** 2 + (py - cy) ** 2 <= RADIUS ** 2

rows = []
for y in range(H):
    row = bytearray()
    for x in range(W):
        hit = sum(inside(x + (i + 0.5) / SS, y + (j + 0.5) / SS) for i in range(SS) for j in range(SS))
        row += bytes((255, 255, 255, round(255 * hit / (SS * SS))))  # BGRA
    rows.append(bytes(row))

header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
with open(sys.argv[1], "wb") as f:
    f.write(header)
    for row in reversed(rows):
        f.write(row)
