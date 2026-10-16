"""Placeholder app icons for the web build (PWA): art/ui/logo_square.png scaled by whole pixels.

Usage (from the project root):  python deploy/web/make_icons.py
Output: deploy/web/icons/icon_144.png, icon_180.png, icon_512.png (referenced by the "Web" export
preset). Nearest neighbour only (pixel art), centred on the page background; replace the files with
real icons of the same size and name (briefing in docs/WEB_BUILD.md).
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art" / "ui" / "logo_square.png"
OUT_DIR = Path(__file__).resolve().parent / "icons"
BACKGROUND = (0x15, 0x13, 0x1F, 255)
# size -> whole-number scale of the 64 px logo (leaves a margin for round and squircle masks)
SIZES = {144: 2, 180: 2, 512: 7}


def main():
    logo = Image.open(SOURCE).convert("RGBA")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for size, scale in SIZES.items():
        scaled = logo.resize((logo.width * scale, logo.height * scale), Image.NEAREST)
        canvas = Image.new("RGBA", (size, size), BACKGROUND)
        offset = ((size - scaled.width) // 2, (size - scaled.height) // 2)
        canvas.alpha_composite(scaled, offset)
        canvas.convert("RGB").save(OUT_DIR / f"icon_{size}.png", optimize=True)
        print(f"icon_{size}.png  logo x{scale}")


if __name__ == "__main__":
    main()
