"""Draws the pixel-art mouse cursors as PNGs (pure Python).

Usage (from the project root):  python tools/generate_cursors.py
Output: art/ui/cursor_crosshair.png (gameplay), art/ui/cursor_pointer.png (menus).
Designs are 16 px pixel art, written at 2x so they stay crisp. Replace them with own art anytime.
"""
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "art" / "ui"
SCALE = 2

# . transparent, o outline (dark), w white, a accent (gold), r red
PALETTE = {
    ".": (0, 0, 0, 0),
    "o": (20, 14, 28, 255),
    "w": (245, 240, 230, 255),
    "a": (255, 210, 90, 255),
    "r": (235, 60, 60, 255),
}

CROSSHAIR = [
    "......ooo......",
    "......owo......",
    "......owo......",
    "......owo......",
    "......ooo......",
    "...............",
    "ooooo..r..ooooo",
    "owwwo.rrr.owwwo",
    "ooooo..r..ooooo",
    "...............",
    "......ooo......",
    "......owo......",
    "......owo......",
    "......owo......",
    "......ooo......",
]

POINTER = [
    "oo..........",
    "owo.........",
    "owwo........",
    "owwwo.......",
    "owwwwo......",
    "owwwwwo.....",
    "owwwwwwo....",
    "owwwwwwwo...",
    "owwwwwwwwo..",
    "owwwwwoooo..",
    "owwowwo.....",
    "owo.owwo....",
    "oo..owwo....",
    ".....owwo...",
    ".....owwo...",
    "......oo....",
]


def write_png(path, rows):
    height = len(rows) * SCALE
    width = len(rows[0]) * SCALE
    raw = bytearray()
    for row in rows:
        line = bytearray()
        for ch in row:
            line.extend(bytes(PALETTE[ch]) * SCALE)
        for _ in range(SCALE):
            raw.append(0)
            raw.extend(line)

    def chunk(kind, data):
        payload = kind + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)
    print("written", path.name, f"{width}x{height}")


if __name__ == "__main__":
    write_png(OUT / "cursor_crosshair.png", CROSSHAIR)
    write_png(OUT / "cursor_pointer.png", POINTER)
