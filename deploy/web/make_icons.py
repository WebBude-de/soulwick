"""App icons for the web build (PWA), made from art/ui/logo_square.png.

Usage (from the project root):  python deploy/web/make_icons.py
Output: deploy/web/icons/icon_144.png, icon_180.png, icon_512.png (referenced by the "Web" export
preset). The candle and crystal of the logo without its gold frame, on the page background with a
stepped violet glow behind the crystal and a faint warm glow at the candle, all on the logo's own
pixel grid (whole-number nearest-neighbour scaling, no smooth gradients). The motif keeps inside the
middle ~70 % so round and squircle masks (Android) never cut it. Replace the files with drawn icons
of the same size and name if wanted (briefing in docs/WEB_BUILD.md §8).
Since 16.10.2026 drawn icons from Claude Design are in place: the script then only writes with
--force, so a run never replaces them by accident.
"""
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art" / "ui" / "logo_square.png"
OUT_DIR = Path(__file__).resolve().parent / "icons"
BACKGROUND = (0x15, 0x13, 0x1F)
# Logo background colours (dropped) and the frame (gold pixels in the outer band, dropped).
LOGO_BACKGROUND = {(30, 27, 44), (28, 26, 43)}
FRAME_BAND = 3
# Share of the icon the motif's height may fill.
MOTIF_SHARE = 0.70
# Hard limit after rounding the scale (small icons are not masked, they may fill more).
MOTIF_MAX_SHARE = 0.82
# Glow rings around the crystal: (radius in logo pixels, colour, opacity), outermost first.
VIOLET = (0x6B, 0x3A, 0xB5)
WARM = (0xF2, 0xCF, 0x4A)
VIOLET_RINGS = [(30, 0.10), (24, 0.16), (19, 0.23), (14, 0.30)]
WARM_RINGS = [(17, 0.05)]


def motif(logo: Image.Image) -> Image.Image:
    """The logo without background and frame, cropped to what is left."""
    out = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    w, h = logo.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = logo.getpixel((x, y))
            if a == 0 or (r, g, b) in LOGO_BACKGROUND:
                continue
            in_band = x < FRAME_BAND or y < FRAME_BAND or x >= w - FRAME_BAND or y >= h - FRAME_BAND
            if in_band and r > 150 and b < 100:
                continue
            out.putpixel((x, y), (r, g, b, a))
    return out.crop(out.getbbox())


def crystal_centre(m: Image.Image) -> tuple[float, float]:
    """Centre of the violet pixels (the crystal) in motif coordinates."""
    xs, ys = [], []
    for y in range(m.height):
        for x in range(m.width):
            r, g, b, a = m.getpixel((x, y))
            if a == 255 and b > 150 and b > r:
                xs.append(x)
                ys.append(y)
    return sum(xs) / len(xs), sum(ys) / len(ys)


def blend(base: tuple, colour: tuple, amount: float) -> tuple:
    return tuple(round(c0 + (c1 - c0) * amount) for c0, c1 in zip(base, colour))


def render(m: Image.Image, size: int) -> Image.Image:
    scale = max(1, round(size * MOTIF_SHARE / m.height))
    while scale > 1 and m.height * scale > size * MOTIF_MAX_SHARE:
        scale -= 1
    grid = math.ceil(size / scale)
    left = (grid - m.width) // 2
    top = (grid - m.height) // 2
    cx, cy = crystal_centre(m)
    cx, cy = cx + left, cy + top
    candle_y = top + m.height * 0.72
    canvas = Image.new("RGBA", (grid, grid), BACKGROUND + (255,))
    for y in range(grid):
        for x in range(grid):
            colour = BACKGROUND
            d_warm = math.hypot(x + 0.5 - cx, (y + 0.5 - candle_y) * 1.3)
            for radius, amount in WARM_RINGS:
                if d_warm <= radius:
                    colour = blend(BACKGROUND, WARM, amount)
            d = math.hypot(x + 0.5 - cx, (y + 0.5 - cy) * 0.9)
            for radius, amount in VIOLET_RINGS:
                if d <= radius:
                    colour = blend(colour, VIOLET, amount)
            canvas.putpixel((x, y), colour + (255,))
    canvas.alpha_composite(m, (left, top))
    big = canvas.resize((grid * scale, grid * scale), Image.NEAREST)
    offset = (big.width - size) // 2
    return big.crop((offset, offset, offset + size, offset + size)).convert("RGB"), scale


def main():
    if not "--force" in sys.argv and any((OUT_DIR / f"icon_{size}.png").exists() for size in (144, 180, 512)):
        print("icons exist (drawn ones are kept); use --force to replace them with generated ones")
        return
    logo = Image.open(SOURCE).convert("RGBA")
    m = motif(logo)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for size in (144, 180, 512):
        icon, scale = render(m, size)
        icon.save(OUT_DIR / f"icon_{size}.png", optimize=True)
        print(f"icon_{size}.png  motif {m.width}x{m.height} x{scale}")


if __name__ == "__main__":
    main()
