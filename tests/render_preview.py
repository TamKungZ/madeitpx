import sys
from pathlib import Path

from render_patterns import OUTPUT_DIR, write_png
from test_patterns import PATTERN_DIR, PatternTests, load_library, read_png


GRID = 48
SCALE = 4
SHOWCASE = [
    ("12_scene_sprite", "SCENE SPRITE"),
    ("13_plasma_photo_like", "PLASMA PHOTO"),
    ("06_alpha_soft_circle", "ALPHA CIRCLE"),
]
COLUMNS = [
    ("BOLD", 2, 16),
    ("BALANCED", 0, 32),
    ("DETAIL", 1, 64),
]
SAMPLE_MODE = 0

S = GRID * SCALE
MARGIN, GAP = 32, 16


SHOW_TITLE = False
SHOW_PALETTE = False
BG = (255, 255, 255)
BORDER = (222, 224, 228)
HEADER = (84, 90, 100)


_GLYPHS = {
    " ": ".....|.....|.....|.....|.....|.....|.....",
    "A": ".###.|#...#|#...#|#####|#...#|#...#|#...#",
    "B": "####.|#...#|#...#|####.|#...#|#...#|####.",
    "C": ".###.|#...#|#....|#....|#....|#...#|.###.",
    "D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
    "E": "#####|#....|#....|####.|#....|#....|#####",
    "F": "#####|#....|#....|####.|#....|#....|#....",
    "G": ".###.|#...#|#....|#.###|#...#|#...#|.###.",
    "H": "#...#|#...#|#...#|#####|#...#|#...#|#...#",
    "I": "#####|..#..|..#..|..#..|..#..|..#..|#####",
    "J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
    "K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
    "L": "#....|#....|#....|#....|#....|#....|#####",
    "M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
    "N": "#...#|##..#|#.#.#|#..##|#...#|#...#|#...#",
    "O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
    "P": "####.|#...#|#...#|####.|#....|#....|#....",
    "Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
    "R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
    "S": ".####|#....|#....|.###.|....#|....#|####.",
    "T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
    "U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
    "V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
    "W": "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#",
    "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
    "Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
    "Z": "#####|....#|...#.|..#..|.#...|#....|#####",
    "0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
    "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
    "2": ".###.|#...#|....#|...#.|..#..|.#...|#####",
    "3": "####.|....#|....#|.###.|....#|....#|####.",
    "4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
    "5": "#####|#....|####.|....#|....#|#...#|.###.",
    "6": "..##.|.#...|#....|####.|#...#|#...#|.###.",
    "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
    "8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
    "9": ".###.|#...#|#...#|.####|....#|...#.|.##..",
    "-": ".....|.....|.....|#####|.....|.....|.....",
    "/": "....#|...#.|...#.|..#..|.#...|.#...|#....",
    ".": ".....|.....|.....|.....|.....|.....|..#..",
    ":": ".....|..#..|.....|.....|.....|..#..|.....",
    ">": "#....|.#...|..#..|...#.|..#..|.#...|#....",
}
FONT = {k: v.split("|") for k, v in _GLYPHS.items()}


class Canvas:
    def __init__(self, width, height, color):
        self.width, self.height = width, height
        px = bytes(color) + b"\xff"
        self.rows = [bytearray(px * width) for _ in range(height)]

    def rect(self, x, y, w, h, color):
        seg = (bytes(color) + b"\xff") * w
        for yy in range(y, y + h):
            self.rows[yy][x * 4 : (x + w) * 4] = seg

    def blit(self, x, y, w, h, pixels, scale=1):
        for sy in range(h):
            line = b"".join(
                pixels[(sy * w + sx) * 4 : (sy * w + sx) * 4 + 4] * scale
                for sx in range(w)
            )
            for r in range(scale):
                self.rows[y + sy * scale + r][x * 4 : (x + w * scale) * 4] = line

    def text(self, x, y, s, scale, color):
        for ch in s.upper():
            for gy, row in enumerate(FONT.get(ch, FONT[" "])):
                for gx, cell in enumerate(row):
                    if cell == "#":
                        self.rect(x + gx * scale, y + gy * scale, scale, scale, color)
            x += 6 * scale

    def tobytes(self):
        return b"".join(self.rows)


def text_width(s, scale):
    return max(0, len(s) * 6 - 1) * scale


def centered(canvas, cx, y, s, scale, color):
    canvas.text(cx - text_width(s, scale) // 2, y, s, scale, color)


def box_resize(rgb, sw, sh, tw, th):
    """Area-average downscale of RGBA (alpha ignored), returns opaque RGBA."""
    out = bytearray(tw * th * 4)
    xr = [(x * sw // tw, max(x * sw // tw + 1, -(-(x + 1) * sw // tw))) for x in range(tw)]
    yr = [(y * sh // th, max(y * sh // th + 1, -(-(y + 1) * sh // th))) for y in range(th)]
    for ty, (y0, y1) in enumerate(yr):
        for tx, (x0, x1) in enumerate(xr):
            r = g = b = 0
            n = (y1 - y0) * (x1 - x0)
            for sy in range(y0, y1):
                base = sy * sw * 4
                for sx in range(x0, x1):
                    i = base + sx * 4
                    r += rgb[i]
                    g += rgb[i + 1]
                    b += rgb[i + 2]
            o = (ty * tw + tx) * 4
            out[o], out[o + 1], out[o + 2], out[o + 3] = r // n, g // n, b // n, 255
    return bytes(out)


def display_source(width, height, pixels):
    """Source thumbnail; transparent areas are shown over a checkerboard."""
    if any(a < 255 for a in pixels[3::4]):
        pixels = bytearray(pixels)
        cell = max(1, width // 16)
        for y in range(height):
            for x in range(width):
                i = (y * width + x) * 4
                a = pixels[i + 3]
                if a == 255:
                    continue
                bg = 205 if (x // cell + y // cell) % 2 else 150
                for c in range(3):
                    pixels[i + c] = (pixels[i + c] * a + bg * (255 - a) + 127) // 255
                pixels[i + 3] = 255
    return box_resize(pixels, width, height, S, S)


def palette_of(pixels):
    counts = {}
    for i in range(0, len(pixels), 4):
        key = bytes(pixels[i : i + 3])
        counts[key] = counts.get(key, 0) + 1
    return [tuple(k) for k, _ in sorted(counts.items(), key=lambda kv: -kv[1])]


def main():
    out_path = Path(sys.argv[1]) if len(sys.argv) > 1 else OUTPUT_DIR / "preview.png"
    renderer = PatternTests()
    renderer.library = load_library()

    cols = 1 + len(COLUMNS)
    pal_h = 22 if SHOW_PALETTE else 0
    cell_h = S + pal_h
    title_h = 60 if SHOW_TITLE else 0
    head_h = 14
    width = 2 * MARGIN + cols * S + (cols - 1) * GAP
    top = MARGIN + title_h + head_h + 14
    height = top + len(SHOWCASE) * cell_h + (len(SHOWCASE) - 1) * GAP + MARGIN

    cv = Canvas(width, height, BG)
    if SHOW_TITLE:
        cv.text(MARGIN, MARGIN, "MADEITPX", 5, (30, 33, 40))

    def col_x(c):
        return MARGIN + c * (S + GAP)

    head_y = MARGIN + title_h
    headers = ["SOURCE"] + [f"{n} {limit}" for n, _, limit in COLUMNS]
    for c, label in enumerate(headers):
        centered(cv, col_x(c) + S // 2, head_y, label, 2, HEADER)

    for r, (stem, _caption) in enumerate(SHOWCASE):
        path = PATTERN_DIR / f"{stem}.png"
        sw, sh, pixels = read_png(path)
        image = (sw, sh, pixels, path.name)
        y = top + r * (cell_h + GAP)
        cells = [display_source(sw, sh, pixels)]
        for _, preset, _ in COLUMNS:
            cells.append(
                renderer.convert(image, GRID, GRID, preset=preset, sample_mode=SAMPLE_MODE)
            )
        for c, data in enumerate(cells):
            x = col_x(c)
            cv.rect(x - 1, y - 1, S + 2, S + 2, BORDER)
            if c == 0:
                cv.blit(x, y, S, S, data)
            else:
                cv.blit(x, y, GRID, GRID, data, SCALE)
                if SHOW_PALETTE:
                    palette = palette_of(data)
                    for i, color in enumerate(palette):
                        x0, x1 = i * S // len(palette), (i + 1) * S // len(palette)
                        cv.rect(x + x0, y + S + 8, x1 - x0, 6, color)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(out_path, width, height, cv.tobytes())
    print(f"Wrote {out_path} ({width}x{height})")
    print("Markdown: ![madeitpx preview](test_sources/output/preview.png)")


if __name__ == "__main__":
    main()
