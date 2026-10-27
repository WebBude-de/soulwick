"""Draws every picture of Flint, the companion, from the website figure (D-217; pure Python).

Usage (from the project root):  python tools/generate_flint.py [--preview <folder>]

The template is the website's Flint (soulwick-platform/apps/web/src/components/wick/wick-figure.tsx
and wick.css): dark outline #1c1a2b, cream wax with white highlight streaks on the left and a shade
on the right, small narrow eyes high up, pink cheeks, a tiny mouth, two feet, the wick and a flame
in three layers (rim #ff8a3c, middle #ffb54a, core #fff3c4) that flickers. Two rasters keep it the
same figure everywhere:
  FULL  the website raster itself (16x24), drawn twice as large for the explanation portraits
        (art/ui/flint_guide/flint_portrait_<mood>_<n>f.png, 48x48, facing left to the bubble);
  GAME  the same figure at companion size (D-205: about as large as a pet, body 13 px, 21 px with
        wick and flame) for art/companions/flint/flint_<anim>_<n>f.png (32x32 frames, pivot (16, 30)
        like the website frame, facing left) plus a flame mask per animation (white = flame, for the
        flame colour cosmetic) and flint.json (frame size, pivot, fps, per-frame anchors flame/head).
Moods are small changes of eyes, mouth, flame, squash and hop; no light is painted in (D-174): the
warm glow and the rising sparks come from code (FlintShine). Old strips of the folders that this
run did not write are removed, so the folders hold exactly one set. FlintPlaceholder (code fallback)
copies GAME_BODY and the flames a, b, c; test_flint_art checks that both draw the same idle frame.
"""
import json
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COMPANION_DIR = ROOT / "art" / "companions" / "flint"
PORTRAIT_DIR = ROOT / "art" / "ui" / "flint_guide"

# Website colours (wick-figure.tsx COLORS) plus the ember and a tear.
PALETTE = {
    "k": (0x1C, 0x1A, 0x2B, 255),  # outline, eyes, mouth
    "t": (0x3B, 0x36, 0x50, 255),  # the wick thread
    "o": (0xFF, 0x8A, 0x3C, 255),  # flame rim
    "y": (0xFF, 0xB5, 0x4A, 255),  # flame
    "w": (0xFF, 0xF3, 0xC4, 255),  # flame core
    "c": (0xEF, 0xE6, 0xCF, 255),  # wax body
    "h": (0xFF, 0xFF, 0xFF, 255),  # highlight
    "s": (0xB9, 0xB3, 0xC9, 255),  # body shade
    "p": (0xF0, 0x64, 0x8C, 255),  # cheeks
    "e": (0xE0, 0x4E, 0x2A, 255),  # ember (glowing wick, D-198)
    "b": (0x8F, 0xC8, 0xFF, 255),  # tear
}
FLAME_CHARS = "oyw"
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


class Figure:
    """One raster of Flint: flame variants, body (wick row first) and where the face sits."""

    def __init__(self, flames, body, eyes, eye_row, cheeks, mouth, squash_rows, left_col, arm_row):
        self.flames = flames
        self.body = body
        self.eyes = eyes
        self.eye_row = eye_row
        self.cheeks = cheeks
        self.mouth = mouth
        self.squash_rows = squash_rows
        self.left_col = left_col
        self.arm_row = arm_row


# --- FULL: the website raster (wick-figure.tsx FLAME + BODY), body columns 3..12 ---

FULL_FLAMES = {
    # The website flame.
    "a": [
        "........o.......",
        ".......ooo......",
        ".......oyo......",
        "......oyyyo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        ".....oywwwyo....",
        "......oyyyo.....",
    ],
    # Flicker (wick.css wick-flicker): taller and thinner, the tip to the left ...
    "b": [
        ".......o........",
        ".......oo.......",
        ".......oyo......",
        "......oyyo......",
        "......oywyo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        "......oyyyo.....",
    ],
    # ... and shorter and wider, the tip to the right.
    "c": [
        "................",
        ".........o......",
        "........ooo.....",
        ".......oyyo.....",
        "......oyywyo....",
        ".....oywwwyo....",
        ".....oywwwyo....",
        "......oyyyo.....",
    ],
    # Big and bright (proud, light pulse).
    "big": [
        "........o.......",
        ".......ooo......",
        "......ooyoo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        "....oywwwwwyo...",
        "....oywwwwwyo...",
        ".....oyyyyyo....",
    ],
    "big2": [
        ".......oo.......",
        ".......ooo......",
        "......oyyoo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        "....oywwwwwyo...",
        "....oywwwwwyo...",
        ".....oyyyyyo....",
    ],
    # Small and trembling (worried).
    "small": [
        "........o.......",
        ".......oyo......",
        "......oywyo.....",
        "......oywyo.....",
        ".......oyo......",
    ],
    "small2": [
        ".......o........",
        ".......oyo......",
        "......oywyo.....",
        "......oywyo.....",
        ".......oyo......",
    ],
}

FULL_BODY = [
    "........t.......",
    ".....kkkkkk.....",
    "....khccccsk....",
    "...khcccccssk...",
    "...kccccccssk...",
    "...kccccccssk...",
    "...kccccccssk...",
    "...kpcccccpsk...",
    "...kccckccssk...",
    "...kcccccccsk...",
    "...khccccccsk...",
    "...kcccccccsk...",
    "...khcccccssk...",
    "....kssssssk....",
    ".....kkkkkk.....",
    ".....kk..kk.....",
]

FULL = Figure(
    flames=FULL_FLAMES,
    body=FULL_BODY,
    eyes=(6, 9),
    eye_row=4,
    cheeks=((4, 7), (10, 7)),
    mouth=(7, 8),
    squash_rows=(9, 11),
    left_col=3,
    arm_row=9,
)

# --- GAME: the same figure at companion size (D-205), body columns 4..11 ---
# Flames a, b, c and GAME_BODY are copied in companions/flint/flint_placeholder.gd: change both.

GAME_FLAMES = {
    # The website flame without its second row, so it keeps its weight on the smaller body.
    "a": [
        "........o.......",
        ".......ooo......",
        "......oyyyo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        ".....oywwwyo....",
        "......oyyyo.....",
    ],
    "b": [
        ".......o........",
        ".......oo.......",
        ".......oyo......",
        "......oyyyo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        "......oyyyo.....",
    ],
    "c": [
        "................",
        ".........o......",
        "........ooo.....",
        "......ooyyyo....",
        ".....oyywwyo....",
        ".....oywwwyo....",
        "......oyyyo.....",
    ],
    # Trailing behind while he flies to the left (move).
    "trail": [
        "................",
        "...........o....",
        "..........oo....",
        "........ooyo....",
        ".......oyywo....",
        "......oywwyo....",
        "......oyyyo.....",
    ],
    "trail2": [
        "................",
        "................",
        "...........oo...",
        ".........ooyo...",
        ".......ooyywo...",
        "......oywwyo....",
        "......oyyyo.....",
    ],
    # Leaning forward (to the left: curious).
    "lean": [
        ".....o..........",
        ".....oo.........",
        "......ooo.......",
        "......oyyyo.....",
        ".....oywwyo.....",
        ".....oywwwyo....",
        "......oyyyo.....",
    ],
    "big": [
        "........o.......",
        ".......ooo......",
        ".......oyo......",
        "......oyyyo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        "....oywwwwwyo...",
        "....oywwwwwyo...",
        ".....oyyyyyo....",
    ],
    "big2": [
        ".......o........",
        ".......oo.......",
        "......ooyo......",
        "......oyyyo.....",
        "......oywyo.....",
        ".....oywwwyo....",
        "....oywwwwwyo...",
        "....oywwwwwyo...",
        ".....oyyyyyo....",
    ],
    "small": [
        "........o.......",
        ".......oyo......",
        "......oywyo.....",
        "......oywyo.....",
        ".......oyo......",
    ],
    "small2": [
        ".......o........",
        ".......oyo......",
        "......oywyo.....",
        "......oywyo.....",
        ".......oyo......",
    ],
    "tiny": [
        "........o.......",
        ".......oyo......",
        ".......oyo......",
    ],
    "ember": [
        "........o.......",
    ],
}

GAME_BODY = [
    "........t.......",
    ".....kkkkkk.....",
    "....khccccsk....",
    "....khccccsk....",
    "....kcccccsk....",
    "....kcccccsk....",
    "....kccccssk....",
    "....kpccccpk....",
    "....kcckcssk....",
    "....khcccssk....",
    "....kccccssk....",
    "....kssssssk....",
    ".....kkkkkk.....",
    ".....kk..kk.....",
]

GAME = Figure(
    flames=GAME_FLAMES,
    body=GAME_BODY,
    eyes=(6, 9),
    eye_row=4,
    cheeks=((5, 7), (10, 7)),
    mouth=(7, 8),
    squash_rows=(9, 10),
    left_col=4,
    arm_row=8,
)

# Arms on the left side (he faces left): rows relative to arm_row, column 0 = left_col - 3; "."
# leaves the pixel, the last column replaces the body outline so the arm joins the wax.
ARMS = {
    "point": [
        (-1, ".kk."),
        (0, "kccc"),
        (1, ".kk."),
    ],
    "raise": [
        (-3, "kk.."),
        (-2, "kck."),
        (-1, ".kck"),
        (0, "..kc"),
        (1, "...k"),
    ],
}


class Pose:
    """One frame: flame variant, eyes, mouth, arm, squash (+ = top lower), lift (hop), shift."""

    def __init__(self, flame="a", eyes="open", mouth="dot", arm=None, squash=0, lift=0, shift=0, extras=None, ember=False):
        self.flame = flame
        self.eyes = eyes
        self.mouth = mouth
        self.arm = arm
        self.squash = squash
        self.lift = lift
        self.shift = shift
        # [(x, y, char)] relative to the body raster (row 0 = wick row) before squash and lift.
        self.extras = extras or []
        self.ember = ember


def P(**kwargs):
    return Pose(**kwargs)


# --- Faces ---

def _eye_pixels(figure, style):
    left, right = figure.eyes
    r = figure.eye_row
    if style == "open":
        return [(left, r), (left, r + 1), (right, r), (right, r + 1)]
    if style == "blink":
        return [(left, r + 1), (right, r + 1)]
    if style == "closed":
        return [(left - 1, r + 1), (left, r + 1), (right, r + 1), (right + 1, r + 1)]
    if style == "happy":
        return [(left - 1, r + 1), (left, r), (right, r), (right + 1, r + 1)]
    if style == "worried":
        return [(left, r), (left, r + 1), (right, r), (right, r + 1), (left - 1, r - 1), (left, r - 2), (right, r - 2), (right + 1, r - 1)]
    if style == "look":
        return [(left - 1, r), (left - 1, r + 1), (right - 1, r), (right - 1, r + 1)]
    if style == "up":
        return [(left, r - 1), (left, r), (right, r - 1), (right, r)]
    if style == "squeeze":
        return [(left - 1, r), (left, r + 1), (right + 1, r), (right, r + 1)]
    raise ValueError("unknown eyes " + style)


def _mouth_pixels(figure, style):
    x, y = figure.mouth
    if style == "dot":
        return [(x, y, "k")]
    if style == "none":
        return []
    if style == "open":
        return [(x, y, "k"), (x + 1, y, "k"), (x, y + 1, "p"), (x + 1, y + 1, "k")]
    if style == "o":
        return [(x, y, "k"), (x, y + 1, "k")]
    if style == "smile":
        return [(x - 1, y, "k"), (x, y + 1, "k"), (x + 1, y + 1, "k"), (x + 2, y, "k")]
    if style == "grin":
        return [(x, y, "k"), (x + 1, y, "k"), (x, y + 1, "p"), (x + 1, y + 1, "p")]
    if style == "frown":
        return [(x - 1, y + 1, "k"), (x, y, "k"), (x + 1, y + 1, "k")]
    raise ValueError("unknown mouth " + style)


def _wax_at(figure, x, y):
    """The wax under a face pixel of the website raster (mouth and cheeks sit in plain wax)."""
    char = figure.body[y][x]
    return "c" if char in "kp" else char


def body_grid(figure, pose):
    """The body raster with the pose's face and arm: {(x, y): char}, y = body row."""
    grid = {}
    for y, row in enumerate(figure.body):
        for x, char in enumerate(row):
            if char != ".":
                grid[(x, y)] = char
    # Clear the website face (mouth and cheeks) and paint the pose's.
    mx, my = figure.mouth
    grid[(mx, my)] = _wax_at(figure, mx, my)
    for cx, cy in figure.cheeks:
        grid[(cx, cy)] = _wax_at(figure, cx, cy)
    if pose.eyes != "none":
        for x, y in _eye_pixels(figure, pose.eyes):
            grid[(x, y)] = "k"
    for cx, cy in figure.cheeks:
        grid[(cx, cy)] = "p"
    for x, y, char in _mouth_pixels(figure, pose.mouth):
        grid[(x, y)] = char
    if pose.arm:
        base_x = figure.left_col - 3
        for dy, pattern in ARMS[pose.arm]:
            for i, char in enumerate(pattern):
                if char != ".":
                    grid[(base_x + i, figure.arm_row + dy)] = char
    if pose.ember:
        grid[(8, 0)] = "e"
    for x, y, char in pose.extras:
        grid[(x, y)] = char
    return grid


def squashed(figure, grid, squash):
    """Removes (squash > 0) or doubles (squash < 0) plain rows below the face; the feet stay."""
    rows = list(range(len(figure.body)))
    picks = list(figure.squash_rows)
    for i in range(abs(squash)):
        row = picks[i % len(picks)]
        if squash > 0:
            rows.remove(row)
        else:
            rows.insert(rows.index(row), row)
    # Re-number from the bottom so the feet keep their row.
    out = {}
    bottom = len(figure.body) - 1
    for new_index, old_row in enumerate(reversed(rows)):
        for (x, y), char in grid.items():
            if y == old_row:
                out[(x, bottom - new_index)] = char
    # Pixels outside the body rows (extras above the head) move with the top.
    top_shift = len(figure.body) - len(rows)
    for (x, y), char in grid.items():
        if y < 0:
            out[(x, y + top_shift)] = char
    return out


def figure_pixels(figure, pose):
    """{(x, y): char} of the whole figure; y = 0 is the wick row, the flame has negative rows."""
    grid = squashed(figure, body_grid(figure, pose), pose.squash)
    wick_row = min(y for (x, y), c in grid.items() if c in "te" and x == 8)
    flame = figure.flames[pose.flame]
    for i, row in enumerate(reversed(flame)):
        for x, char in enumerate(row):
            if char != ".":
                grid[(x, wick_row - 1 - i)] = char
    return grid


# --- Frames ---

def blank(width, height):
    return [[CLEAR] * width for _ in range(height)]


def paint(figure, pose, frame_size, feet, scale=1):
    """A frame image: the figure with its feet row at feet (frame px), hop and shake applied."""
    width, height = frame_size
    image = blank(width, height)
    flame_mask = blank(width, height)
    pixels = figure_pixels(figure, pose)
    bottom = max(y for (x, y) in pixels)
    for (x, y), char in pixels.items():
        fx = feet[0] + (x - 8 + pose.shift) * scale
        fy = feet[1] + (y - bottom - pose.lift) * scale
        for dy in range(scale):
            for dx in range(scale):
                px, py = fx + dx, fy + dy
                if 0 <= px < width and 0 <= py < height:
                    image[py][px] = PALETTE[char]
                    if char in FLAME_CHARS:
                        flame_mask[py][px] = WHITE
    return image, flame_mask, pixels, bottom


def anchors(figure, pose, feet, scale=1):
    """Flame anchor (centre of the flame pixels) and head anchor (top of the wax outline) in frame
    px, like paint() places the figure."""
    pixels = figure_pixels(figure, pose)
    bottom = max(y for (x, y) in pixels)

    def to_frame(x, y):
        return feet[0] + (x - 8 + pose.shift) * scale, feet[1] + (y - bottom - pose.lift) * scale

    flame = [to_frame(x, y) for (x, y), c in pixels.items() if c in FLAME_CHARS]
    half = scale * 0.5
    flame_x = sum(x + half for x, _ in flame) / len(flame)
    flame_y = sum(y + half for _, y in flame) / len(flame)
    top = min(y for (x, y), c in pixels.items() if c == "k")
    head = to_frame(8, top)
    return [round(flame_x * 2) / 2, round(flame_y * 2) / 2], [head[0], head[1]]


# --- Animations (companion, GAME raster) ---

def _snooze(x, y):
    """A small z (3x4) floating up from his head while he sleeps; x, y = its top left."""
    return [(x + dx, y + dy, "s") for dx, dy in [(0, 0), (1, 0), (2, 0), (2, 1), (1, 2), (0, 3), (1, 3), (2, 3)]]


def idle_poses():
    """Website idle: the flame flickers (3 steps, 4 fps), the body breathes (0.7 s), a blink."""
    flames = ["a", "a", "b", "b", "c", "c"]
    poses = []
    for i in range(36):
        squash = 1 if (i // 6) % 2 == 1 else 0
        eyes = "blink" if i == 33 else "open"
        poses.append(P(flame=flames[i % 6], squash=squash, eyes=eyes))
    return poses


COMPANION = [
    # name, fps, loop, poses
    ("idle", 8, True, idle_poses()),
    ("move", 10, True, [P(flame=f, lift=l) for f, l in zip(["trail", "trail2", "trail", "trail2", "trail", "trail2"], [0, 0, 1, 1, 0, 0])]),
    ("cast", 12, False, [
        P(arm="raise", flame="a", eyes="up"),
        P(arm="raise", flame="lean", eyes="up", mouth="o"),
        P(arm="raise", flame="big", eyes="happy", mouth="o", squash=-1),
        P(arm="raise", flame="big2", eyes="happy", mouth="o", squash=-1),
        P(arm="raise", flame="big", eyes="happy", mouth="dot"),
        P(flame="a"),
    ]),
    ("talk", 6, True, [P(flame=f, mouth=m) for f, m in zip(["a", "b", "a", "c"], ["dot", "open", "dot", "o"])]),
    ("joy", 12, False, [
        P(flame="a", eyes="happy", mouth="smile", squash=1),
        P(flame="b", eyes="happy", mouth="smile", squash=-1, lift=1),
        P(flame="b", eyes="happy", mouth="grin", lift=3),
        P(flame="a", eyes="happy", mouth="grin", lift=4),
        P(flame="c", eyes="happy", mouth="grin", lift=3),
        P(flame="a", eyes="happy", mouth="smile", lift=1),
        P(flame="c", eyes="happy", mouth="smile", squash=1),
        P(flame="a", eyes="happy", mouth="smile"),
    ]),
    ("curious", 5, True, [P(flame=f, eyes="look", mouth="o") for f in ["lean", "a", "lean", "b"]]),
    ("pulse", 12, False, [
        P(flame="a", eyes="blink", squash=1),
        P(flame="small", eyes="closed", squash=1),
        P(flame="a", eyes="closed", mouth="o"),
        P(flame="big", eyes="happy", mouth="o", squash=-1),
        P(flame="big2", eyes="happy", mouth="o", squash=-1),
        P(flame="big", eyes="happy", mouth="smile"),
        P(flame="b", eyes="open"),
        P(flame="a", eyes="open"),
    ]),
    ("point", 6, True, [P(arm="point", flame=f, mouth=m) for f, m in zip(["a", "b", "a", "c"], ["dot", "open", "dot", "dot"])]),
    ("scared", 10, True, [P(flame=f, eyes="open", mouth="o", squash=1, shift=x) for f, x in zip(["small", "small2", "small", "small2"], [0, 1, 0, -1])]),
    ("sad", 4, True, [
        P(flame="small", eyes="blink", mouth="frown"),
        P(flame="small", eyes="blink", mouth="frown", extras=[(9, 6, "b")]),
        P(flame="small2", eyes="blink", mouth="frown", extras=[(9, 7, "b")]),
        P(flame="small", eyes="blink", mouth="frown", extras=[(9, 9, "b")]),
    ]),
    ("blink", 2, True, [P(flame="a"), P(flame="a", eyes="blink")]),
    ("dim", 4, True, [P(flame=f, eyes="blink", ember=e) for f, e in zip(["tiny", "ember", "tiny", "small"], [False, True, False, False])]),
    ("hurt", 10, False, [
        P(flame="c", eyes="squeeze", mouth="frown", squash=1, shift=1),
        P(flame="small", eyes="squeeze", mouth="frown", squash=1, shift=-1),
        P(flame="a", eyes="open", mouth="o"),
    ]),
    ("sleep", 2, True, [
        P(flame="tiny", eyes="closed", mouth="none"),
        P(flame="ember", eyes="closed", mouth="none", squash=1, ember=True, extras=_snooze(12, -3)),
        P(flame="tiny", eyes="closed", mouth="none", squash=1, extras=_snooze(13, -5)),
        P(flame="tiny", eyes="closed", mouth="none", extras=_snooze(13, -7)),
    ]),
]

COMPANION_FRAME = (32, 32)
COMPANION_PIVOT = (16, 30)

# --- Portraits (FULL raster at x2, 48x48, facing left) ---

PORTRAIT_FRAME = (48, 48)
PORTRAIT_SCALE = 2
# Feet row of the raster lands on the last row; x 16 of the frame is the raster's column 8.
PORTRAIT_FEET = (24, 46)

PORTRAITS = [
    # mood, fps, poses
    ("neutral", 6, [P(flame=f, squash=s, eyes=e) for f, s, e in zip(
        ["a", "b", "c", "a", "b", "c", "a", "b", "c", "a", "b", "c"],
        [0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 1],
        ["open"] * 10 + ["blink", "open"])]),
    ("talk", 8, [P(flame=f, mouth=m) for f, m in zip(["a", "b", "c", "a", "b", "c"], ["dot", "open", "o", "dot", "open", "dot"])]),
    ("happy", 6, [P(flame=f, eyes="happy", mouth=m, squash=s) for f, m, s in zip(["a", "b", "c", "b"], ["smile", "grin", "smile", "grin"], [0, 1, 0, 1])]),
    ("worried", 8, [P(flame=f, eyes="worried", mouth="o", shift=s) for f, s in zip(["small", "small2", "small", "small2"], [0, 1, 0, -1])]),
    ("point", 6, [P(arm="point", flame=f, mouth=m) for f, m in zip(["a", "b", "c", "b"], ["dot", "open", "dot", "o"])]),
    ("proud", 6, [P(flame=f, eyes="happy", mouth="smile") for f in ["big", "big2", "big", "big2"]]),
]


# --- Files ---

def write_png(path, image):
    height = len(image)
    width = len(image[0])
    raw = bytearray()
    for row in image:
        raw.append(0)
        for pixel in row:
            raw.extend(bytes(pixel))

    def chunk(kind, data):
        payload = kind + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def strip(frames):
    height = len(frames[0])
    return [sum((frame[y] for frame in frames), []) for y in range(height)]


def scaled(image, factor):
    out = []
    for row in image:
        line = []
        for pixel in row:
            line.extend([pixel] * factor)
        for _ in range(factor):
            out.append(list(line))
    return out


def companion_strips():
    """name -> (fps, loop, frames, masks, flame anchors, head anchors)."""
    result = {}
    for name, fps, loop, poses in COMPANION:
        frames, masks, flames, heads = [], [], [], []
        for pose in poses:
            image, mask, _, _ = paint(GAME, pose, COMPANION_FRAME, COMPANION_PIVOT)
            frames.append(image)
            masks.append(mask)
            flame, head = anchors(GAME, pose, COMPANION_PIVOT)
            flames.append(flame)
            heads.append(head)
        result[name] = (fps, loop, frames, masks, flames, heads)
    return result


def portrait_strips():
    result = {}
    for mood, fps, poses in PORTRAITS:
        frames = []
        for pose in poses:
            # The portrait's x2 raster: feet on the bottom rows, the flame tip on row 0.
            image, _, _, _ = paint(FULL, pose, PORTRAIT_FRAME, (PORTRAIT_FEET[0], PORTRAIT_FEET[1]), PORTRAIT_SCALE)
            frames.append(image)
        result[mood] = (fps, frames)
    return result


def _remove_stale(folder, prefix, keep):
    """Removes strips of an earlier run (other frame counts) and import files without their PNG."""
    for path in folder.glob(prefix + "*.png"):
        if path.name not in keep:
            path.unlink()
            print("removed", path.relative_to(ROOT))
    for imported in folder.glob(prefix + "*.png.import"):
        if not imported.with_suffix("").exists():
            imported.unlink()


def write_companion():
    COMPANION_DIR.mkdir(parents=True, exist_ok=True)
    strips = companion_strips()
    written = set()
    entries = []
    masks = []
    for name, (fps, loop, frames, mask_frames, flames, heads) in strips.items():
        count = len(frames)
        file_name = "flint_%s_%df.png" % (name, count)
        write_png(COMPANION_DIR / file_name, strip(frames))
        written.add(file_name)
        entries.append({"name": name, "file": file_name, "frames": count, "fps": fps, "loop": loop,
                        "anchors": {"flame": flames, "head": heads}})
        mask_name = "flint_flame_mask_%s_%df.png" % (name, count)
        write_png(COMPANION_DIR / mask_name, strip(mask_frames))
        written.add(mask_name)
        masks.append({"name": "flame_mask_" + name, "file": mask_name, "frames": count, "fps": fps, "loop": loop})
    settings = {
        "name": "flint",
        "generated_by": "tools/generate_flint.py (D-217)",
        "frame_size": list(COMPANION_FRAME),
        "pivot": list(COMPANION_PIVOT),
        "facing": "left",
        "anchors": {"eyes": [16, 22], "speech": [11, 12]},
        "notes": [
            "Vorlage ist die Website-Figur (D-217); alle Bilder kommen aus tools/generate_flint.py, nicht von Hand ändern.",
            "Spielgröße (D-205): Körper 13 px, mit Flamme 20 px; Frame 32×32 wie auf der Website, Füße auf Zeile 30, Blick nach links.",
            "Anker flame (Mitte der Flammenpixel) und head (Oberkante der Kontur) je Frame; flame_mask_*: weiß = Flamme.",
            "Kein Licht in den Pixeln (D-174): Schein und Funken macht der Code (FlintShine).",
        ],
        "animations": entries + masks,
    }
    (COMPANION_DIR / "flint.json").write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    _remove_stale(COMPANION_DIR, "flint_", written)
    stale_frames = COMPANION_DIR / "flint_frames.tres"
    if stale_frames.exists():
        # The old hand-made SpriteFrames of V13c pointed at the replaced strips; FlintArt reads the JSON.
        stale_frames.unlink()
        print("removed", stale_frames.relative_to(ROOT))
    print("written", len(written), "companion strips and flint.json")
    return strips


def write_portraits():
    PORTRAIT_DIR.mkdir(parents=True, exist_ok=True)
    strips = portrait_strips()
    written = set()
    items = []
    for mood, (fps, frames) in strips.items():
        count = len(frames)
        file_name = "flint_portrait_%s_%df.png" % (mood, count)
        write_png(PORTRAIT_DIR / file_name, strip(frames))
        written.add(file_name)
        items.append({"name": "flint_portrait_" + mood, "file": file_name, "frame_size": list(PORTRAIT_FRAME),
                      "frames": count, "fps": fps, "loop": True, "pivot": [24, 24]})
    flame, _head = anchors(FULL, PORTRAITS[0][2][0], PORTRAIT_FEET, PORTRAIT_SCALE)
    data = {
        "generated_by": "tools/generate_flint.py (D-217)",
        "anchors": {"flame": flame},
        "notes": ["Website-Figur zweifach (32×48) im 48×48-Rahmen, Blick nach links zur Sprechblase; Schein und Funken macht FlintPortrait am Anker flame (Mitte der Flamme im neutralen Frame)."],
        "items": items,
    }
    (PORTRAIT_DIR / "flint_guide_portraits.json").write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    _remove_stale(PORTRAIT_DIR, "flint_portrait_", written)
    print("written", len(written), "portrait strips and flint_guide_portraits.json")
    return strips


def write_preview(folder, companion, portraits):
    """Enlarged contact sheets on a dark background to look at (not used by the game)."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    background = (0x5A, 0x54, 0x70, 255)

    def on_background(image):
        return [[pixel if pixel[3] else background for pixel in row] for row in image]

    for name, (_fps, _loop, frames, _m, _f, _h) in companion.items():
        write_png(folder / ("companion_%s.png" % name), scaled(on_background(strip(frames)), 6))
    for mood, (_fps, frames) in portraits.items():
        write_png(folder / ("portrait_%s.png" % mood), scaled(on_background(strip(frames)), 4))
    print("preview in", folder)


def main(argv):
    companion = write_companion()
    portraits = write_portraits()
    if "--preview" in argv:
        write_preview(argv[argv.index("--preview") + 1], companion, portraits)


if __name__ == "__main__":
    main(sys.argv[1:])
