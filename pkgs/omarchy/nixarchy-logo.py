#!/usr/bin/env python3
"""Build the NIXARCHY greeter wordmark from Omarchy's own logo.svg.

Omarchy's logo is a pixel font on a strict 15-unit grid: every coordinate in
logo.svg is a multiple of 15, and default/sddm/omarchy/logo.png is that file
rendered 800px wide and tinted green. "NIXARCHY" shares ARCHY with it, so five
of the eight glyphs are upstream's own paths, translated. Only N, I and X have
to be drawn, and they are drawn on the same grid with the same one-cell
beveled corners the O and H have.

Deriving them rather than hand-drawing a lookalike is what keeps the wordmark
matching after an Omarchy bump: the five reused glyphs come from whatever
logo.svg currently says.
"""

import re
import sys

CELL = 15
ROWS = 16  # 240 units tall, y=15..255, matching every glyph in logo.svg

# Where each letter sits in upstream's viewBox, measured from the rendered
# per-path bounding boxes rather than guessed from the path data.
UPSTREAM = {"A": 405, "R": 570, "C": 750, "H": 885, "Y": 1080}


def bitmap(rows):
    return [[c != "." for c in r] for r in rows]


def bevel(grid):
    """Cut one cell from each outer corner, the way O and H are cut."""
    h = len(grid)
    for r, c in ((0, 0), (0, -1), (h - 1, 0), (h - 1, -1)):
        row = grid[r]
        if c == 0:
            for i, on in enumerate(row):
                if on:
                    row[i] = False
                    break
        else:
            for i in range(len(row) - 1, -1, -1):
                if row[i]:
                    row[i] = False
                    break
    return grid


def stems_and_diagonal(width, left, right, diag_from, diag_to, thickness=3):
    """Two vertical stems plus a staircase between them -- an N."""
    grid = [[False] * width for _ in range(ROWS)]
    for r in range(ROWS):
        for c in range(left, left + thickness):
            grid[r][c] = True
        for c in range(right, right + thickness):
            grid[r][c] = True
        start = diag_from + round(r * (diag_to - diag_from) / (ROWS - 1))
        for c in range(start, min(start + thickness, width)):
            grid[r][c] = True
    return grid


def crossing(width, thickness=3):
    """Two staircases crossing -- an X."""
    grid = [[False] * width for _ in range(ROWS)]
    span = width - thickness
    for r in range(ROWS):
        a = round(r * span / (ROWS - 1))
        b = span - a
        for c in range(a, a + thickness):
            grid[r][c] = True
        for c in range(b, b + thickness):
            grid[r][c] = True
    return grid


def bar(width=3):
    return [[True] * width for _ in range(ROWS)]


def to_rects(grid, x0, y0=CELL):
    """Emit one rect per horizontal run, so the path count stays small."""
    out = []
    for r, row in enumerate(grid):
        c = 0
        while c < len(row):
            if not row[c]:
                c += 1
                continue
            start = c
            while c < len(row) and row[c]:
                c += 1
            out.append(
                '<rect x="{}" y="{}" width="{}" height="{}"/>'.format(
                    x0 + start * CELL, y0 + r * CELL, (c - start) * CELL, CELL
                )
            )
    return out


def path_x_extent(path):
    """Left and right edge of one glyph, by walking its path data.

    The font is strictly rectilinear -- only m, h, v, l and z appear -- so a
    full walk is a dozen lines and exact, where guessing from the opening
    coordinate is neither.
    """
    m = re.search(r'd="([^"]+)"', path)
    if not m:
        return (0.0, 0.0)
    d = m.group(1)
    tokens = re.findall(r"([mlhvzMLHVZ])|(-?\d*\.?\d+)", d)
    x = y = 0.0
    xs = []
    cmd = None
    nums = []

    def flush():
        nonlocal x, y
        if cmd is None:
            return
        c = cmd.lower()
        rel = cmd.islower()
        if c == "h":
            for n in nums:
                x = x + n if rel else n
                xs.append(x)
        elif c == "v":
            for n in nums:
                y = y + n if rel else n
        elif c in ("m", "l"):
            for i in range(0, len(nums) - 1, 2):
                x = x + nums[i] if rel else nums[i]
                y = y + nums[i + 1] if rel else nums[i + 1]
                xs.append(x)

    for op, num in tokens:
        if op:
            flush()
            cmd, nums = op, []
        elif num:
            nums.append(float(num))
    flush()
    return (min(xs), max(xs)) if xs else (0.0, 0.0)


def main(src, dest):
    svg = open(src).read()
    paths = re.findall(r"<path[^>]*/>", svg)

    # Match each path to its letter by where the glyph actually sits, not by
    # the coordinate its path happens to open on: R's data starts at its right
    # edge, and matching on that made C and H both claim the same path -- so
    # the wordmark rendered with a hole where the H should be.
    by_letter = {}
    for p in paths:
        x0, x1 = path_x_extent(p)
        for letter, x in UPSTREAM.items():
            if abs(x0 - x) <= CELL:
                by_letter[letter] = p
    missing = sorted(set(UPSTREAM) - set(by_letter))
    if missing:
        sys.exit(f"logo.svg no longer contains glyphs for: {' '.join(missing)}")

    n = bevel(stems_and_diagonal(12, 0, 9, 3, 6))
    i = bevel(bar(3))
    x = bevel(crossing(10))

    parts = []
    parts += to_rects(n, 0)
    parts += to_rects(i, 195)
    parts += to_rects(x, 255)

    # ARCHY keeps upstream's own spacing; the group just shifts right to make
    # room for NIX.
    dx = 15
    body = "".join(by_letter[c] for c in "ARCHY")
    parts.append(f'<g transform="translate({dx},0)">{body}</g>')

    width = 1230
    open(dest, "w").write(
        '<svg xmlns="http://www.w3.org/2000/svg" fill="none" '
        f'viewBox="0 0 {width} 285" width="{width}" height="285">'
        '<g fill="#000">' + "".join(parts) + "</g></svg>"
    )
    print(f"wrote {dest}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
