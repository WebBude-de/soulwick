"""Builds the GitHub images of both repositories (README banner, social preview, screenshots).

    python tools/make_github_images.py                       # banner + social preview, both repos
    python tools/make_github_images.py --shots <folder>      # also README screenshots from a
                                                             # tools/screenshots.gd run

Sources: art/store/steam_library_hero.png (scene without logo), art/store/steam_library_logo.png,
art/fonts/PixelifySans-Variable.ttf and the biome cards of the website
(../soulwick-platform/apps/web/public/brand/biome_*.webp). Output goes to .github/assets/ of this
repo and of ../soulwick-platform (skipped when that folder is missing). The images are assets
(LICENSE-ASSETS.md), this script is code. Needs Pillow.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

GAME = Path(__file__).resolve().parent.parent
PLATFORM = GAME.parent / "soulwick-platform"

TAGLINE = "Grab your friends. Light the dark."
PLATFORM_SUBTITLE = "Platform  ·  Website  ·  API  ·  Co-op relay"
SITE = "playsoulwick.com"

SIZE = (1280, 640)  # GitHub social preview: 1280x640, PNG/JPG, under 1 MB
CREAM = (255, 241, 201)
GOLD = (243, 200, 92)
INK = (20, 14, 32)

# README screenshots: output name -> image of a tools/screenshots.gd run (1280x720).
SHOTS = {
    "screenshot-village.webp": "02_village.png",
    "screenshot-dungeon.webp": "05_combat.png",
}


def font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(str(GAME / "art/fonts/PixelifySans-Variable.ttf"), size)
    face.set_variation_by_name(weight)
    return face


def background(darken: float) -> Image.Image:
    """Village scene with the dungeon gate, 2x pixels, figures at the bottom, sky for the text."""
    hero = Image.open(GAME / "art/store/steam_library_hero.png").convert("RGBA")
    # The store art is drawn at 4x: halving with BOX keeps the pixel edges sharp.
    hero = hero.resize((hero.width // 2, hero.height // 2), Image.BOX)  # 1920x620
    # The moon is cut off at the top edge; mirrored it would become a blob. Cover it with sky.
    hero.paste(hero.crop((1240, 0, 1400, 60)), (1540, 0))
    crop_x, offset_y = 540, 60
    canvas = Image.new("RGBA", SIZE)
    canvas.paste(hero.crop((crop_x, 0, crop_x + SIZE[0], hero.height)), (0, offset_y))
    # More sky above the scene: the top rows mirrored, so the seam is invisible.
    sky = hero.crop((crop_x, 0, crop_x + SIZE[0], offset_y)).transpose(Image.FLIP_TOP_BOTTOM)
    canvas.paste(sky, (0, 0))
    # Darker sky behind the text, a little vignette at the sides.
    shade = Image.new("L", SIZE, 0)
    draw = ImageDraw.Draw(shade)
    for y in range(SIZE[1]):
        t = max(0.0, 1.0 - y / 380.0)
        draw.line([(0, y), (SIZE[0], y)], fill=int(255 * (darken * t + 0.12)))
    vignette = Image.new("L", SIZE, 0)
    ImageDraw.Draw(vignette).rectangle((0, 0, SIZE[0], SIZE[1]), outline=255, width=90)
    shade = Image.composite(Image.new("L", SIZE, 150), shade,
                            vignette.filter(ImageFilter.GaussianBlur(70)).point(lambda v: v // 2))
    canvas = Image.composite(Image.new("RGBA", SIZE, (*INK, 255)), canvas, shade)
    return canvas


def logo(scale: int) -> Image.Image:
    """The word mark at `scale` x its native pixel size (the store logo is drawn at 8x)."""
    mark = Image.open(GAME / "art/store/steam_library_logo.png").convert("RGBA")
    mark = mark.crop(mark.getbbox())
    return mark.resize((mark.width * scale // 8, mark.height * scale // 8), Image.NEAREST)


def glow(layer: Image.Image, radius: int, strength: int) -> Image.Image:
    """Dark halo behind text and logo so they stay readable on any part of the scene."""
    alpha = layer.split()[3].filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(radius))
    alpha = alpha.point(lambda v: min(255, v * strength // 100))
    halo = Image.new("RGBA", layer.size, (*INK, 255))
    halo.putalpha(alpha)
    return halo


def text_layer(text: str, size: int, weight: str, fill: tuple, y: int, stroke: int = 3) -> Image.Image:
    layer = Image.new("RGBA", SIZE)
    face = font(size, weight)
    draw = ImageDraw.Draw(layer)
    width = draw.textlength(text, font=face)
    draw.text(((SIZE[0] - width) / 2, y), text, font=face, fill=fill,
              stroke_width=stroke, stroke_fill=INK)
    return layer


def card(subtitle: str | None) -> Image.Image:
    canvas = background(darken=0.62 if subtitle else 0.5)
    mark = logo(4)  # 568x192
    layers = Image.new("RGBA", SIZE)
    layers.alpha_composite(mark, ((SIZE[0] - mark.width) // 2, 30 if subtitle else 38))
    tagline_y = 236 if subtitle else 250
    layers.alpha_composite(text_layer(TAGLINE, 44, "Bold", CREAM, tagline_y))
    if subtitle:
        layers.alpha_composite(text_layer(subtitle, 30, "SemiBold", GOLD, tagline_y + 62))
    site = Image.new("RGBA", SIZE)
    face = font(26, "SemiBold")
    width = ImageDraw.Draw(site).textlength(SITE, font=face)
    ImageDraw.Draw(site).text((SIZE[0] - 40 - width, SIZE[1] - 58), SITE, font=face,
                              fill=CREAM, stroke_width=3, stroke_fill=INK)
    layers.alpha_composite(site)
    canvas.alpha_composite(glow(layers, 18, 170))
    canvas.alpha_composite(layers)
    return canvas.convert("RGB")


def biome_grid(out: Path) -> None:
    brand = PLATFORM / "apps/web/public/brand"
    names = ["biome_crypt", "biome_slime_grotto", "biome_shadow_realm", "biome_ember_forge"]
    files = [brand / f"{name}.webp" for name in names]
    if not all(f.exists() for f in files):
        print("skip biomes.webp (website brand folder not found)")
        return
    grid = Image.new("RGB", (1280, 720), INK)
    for i, f in enumerate(files):
        tile = Image.open(f).convert("RGBA")
        base = Image.new("RGBA", tile.size, (*INK, 255))
        base.alpha_composite(tile)
        grid.paste(base.convert("RGB"), ((i % 2) * 640, (i // 2) * 360))
    save(grid, out / "biomes.webp")


def screenshots(folder: Path, out: Path) -> None:
    for name, source in SHOTS.items():
        if not (folder / source).exists():
            print(f"skip {name} ({source} not in {folder})")
            continue
        image = Image.open(folder / source).convert("RGB")
        save(image.resize((960, 540), Image.LANCZOS), out / name)


def save(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix == ".png":
        image.save(path, optimize=True)
    else:
        image.save(path, quality=88, method=6)
    print(f"{path}  {image.width}x{image.height}  {path.stat().st_size // 1024} KB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--shots", type=Path, help="folder with tools/screenshots.gd images")
    args = parser.parse_args()

    targets = [(GAME / ".github/assets", None)]
    if PLATFORM.exists():
        targets.append((PLATFORM / ".github/assets", PLATFORM_SUBTITLE))
    else:
        print(f"skip platform images ({PLATFORM} not found)")
    for out, subtitle in targets:
        image = card(subtitle)
        save(image, out / "social-preview.png")
        save(image, out / "banner.webp")
    # Godot skips folders starting with "."; .gdignore makes sure it never imports these images.
    (GAME / ".github/assets/.gdignore").touch()
    biome_grid(GAME / ".github/assets")
    if args.shots:
        screenshots(args.shots, GAME / ".github/assets")


if __name__ == "__main__":
    main()
