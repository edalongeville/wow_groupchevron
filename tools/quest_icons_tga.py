"""Writes the quest hostiles' icons (32x64, 32-bit TGA, white with alpha, tinted in game):

  GroupChevron/quest_kill.tga         a diagonal sword above a small chevron ("kill this mob")
  GroupChevron/quest_loot.tga         a sack above a small chevron ("loot a quest item from it")
  GroupChevron/quest_loot_detail.tga  the sack's tie, drawn in black over quest_loot.tga
  GroupChevron/quest_generic.tga      an open book above a small chevron ("tied to a quest", kind unknown)
  GroupChevron/quest_generic_detail.tga  the book's spine, drawn in black over quest_generic.tga

The black outline is not in the textures: like the chevron's, it is drawn in game from black copies
of the icon moved in eight directions (hostileoutlinesize). Shapes are on the 24x24 grid of the
design canvas; the icon is scaled to 62 % above a thin chevron. No dependency.

Usage, from the repo root: python3 tools/quest_icons_tga.py GroupChevron
"""
import math, os, struct, sys

W, H = 32, 64
SS = 4  # supersampling per axis
# The part of the design's grid the icons use (x 5.15..18.15, y 0.8..26.8, a 2-pixel margin included),
# mapped onto the 32 x 64 pixels: about 2.46 pixels per unit both ways.
VB_X, VB_Y = 5.15, 0.8
SCALE = H / 26.0
PAD_X = 0.0
ICON = 0.62  # the icon's scale above the chevron


def icon_xy(x, y):
    return 12 - 12 * ICON + ICON * x, ICON * y


def to_px(x, y):
    return PAD_X + (x - VB_X) * SCALE, (y - VB_Y) * SCALE


def bezier(p0, p1, p2, p3, n=16):
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        out.append((u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                    u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]))
    return out


def path(cmds):
    """cmds: ("M", x, y), ("L", x, y), ("C", x1, y1, x2, y2, x, y); returns the polygon points."""
    pts = []
    for c in cmds:
        if c[0] in "ML":
            pts.append((c[1], c[2]))
        else:
            pts += bezier(pts[-1], (c[1], c[2]), (c[3], c[4]), (c[5], c[6]))
    return pts


def inside(px, py, poly):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def seg_dist(px, py, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((px - a[0]) * dx + (py - a[1]) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (a[0] + t * dx), py - (a[1] + t * dy))


class Shape:
    """Filled polygons, circles and stroked polylines, all in pixels."""

    def __init__(self):
        self.polys, self.circles, self.strokes = [], [], []

    def poly(self, pts, icon=True):
        self.polys.append([to_px(*(icon_xy(*p) if icon else p)) for p in pts])

    def circle(self, cx, cy, r, icon=True):
        x, y = to_px(*(icon_xy(cx, cy) if icon else (cx, cy)))
        self.circles.append((x, y, r * (ICON if icon else 1) * SCALE))

    def stroke(self, pts, width, icon=True):
        px = [to_px(*(icon_xy(*p) if icon else p)) for p in pts]
        self.strokes.append((px, width * (ICON if icon else 1) * SCALE / 2))

    def hit(self, x, y):
        for p in self.polys:
            if inside(x, y, p):
                return True
        for cx, cy, r in self.circles:
            if math.hypot(x - cx, y - cy) <= r:
                return True
        for pts, half in self.strokes:
            for a, b in zip(pts, pts[1:]):
                if seg_dist(x, y, a, b) <= half:
                    return True
        return False


def chevron(s):
    s.stroke([(7.5, 19.7), (12, 24.2), (16.5, 19.7)], 1.6, icon=False)


def kill():
    s = Shape()
    s.poly([(20.5, 3.5), (19.5, 7), (10, 16.5), (7.5, 14), (17, 4.5)])
    s.stroke([(5, 12), (12, 19)], 2.2)
    s.stroke([(8.5, 15.5), (4.5, 19.5)], 2.2)
    s.circle(3.6, 20.4, 1.3)
    chevron(s)
    return s


def loot():
    s = Shape()
    s.poly(path([("M", 8, 8), ("C", 4, 11, 3.5, 16, 5, 19), ("C", 6.5, 21.6, 17.5, 21.6, 19, 19),
                 ("C", 20.5, 16, 20, 11, 16, 8)]))
    s.poly([(9, 8), (8, 3.8), (10.5, 5.4), (12, 3.4), (13.5, 5.4), (16, 3.8), (15, 8)])
    chevron(s)
    return s


def loot_detail():
    s = Shape()
    s.stroke([(8.4, 8.2), (15.6, 8.2)], 1.4)
    return s


BOOK = 0.8  # the book is drawn at 80 % around the centre of its 24 x 24 box, so it is not wider than the sack


def book_xy(x, y):
    return 12 + (x - 12) * BOOK, 12 + (y - 12) * BOOK


def generic():
    s = Shape()
    cmds = [("M", 12, 6), ("C", 9, 4, 5, 4, 2.5, 5), ("L", 2.5, 19), ("C", 5, 18, 9, 18, 12, 20),
            ("C", 15, 18, 19, 18, 21.5, 19), ("L", 21.5, 5), ("C", 19, 4, 15, 4, 12, 6)]
    scaled = []
    for c in cmds:
        pts = [book_xy(c[i], c[i + 1]) for i in range(1, len(c), 2)]
        scaled.append((c[0],) + tuple(v for p in pts for v in p))
    s.poly(path(scaled))
    chevron(s)
    return s


def generic_detail():
    s = Shape()
    s.stroke([book_xy(12, 6.5), book_xy(12, 19.5)], 1.2 * BOOK)
    return s


def write(path_out, shape):
    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(W):
            n = 0
            for i in range(SS):
                for j in range(SS):
                    if shape.hit(x + (i + 0.5) / SS, y + (j + 0.5) / SS):
                        n += 1
            row += bytes((255, 255, 255, round(n * 255 / (SS * SS))))  # BGRA, white
        rows.append(bytes(row))
    # Uncompressed true-colour TGA, 32 bpp, 8 alpha bits, bottom-left origin (rows bottom-up).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 8)
    with open(path_out, "wb") as f:
        f.write(header)
        for row in reversed(rows):
            f.write(row)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "GroupChevron"
    write(os.path.join(out, "quest_kill.tga"), kill())
    write(os.path.join(out, "quest_loot.tga"), loot())
    write(os.path.join(out, "quest_loot_detail.tga"), loot_detail())
    write(os.path.join(out, "quest_generic.tga"), generic())
    write(os.path.join(out, "quest_generic_detail.tga"), generic_detail())
