"""Builds every dungeon room template from hand-made floor plans (R1, D-120).

Usage (from the project root):
    python tools/generate_room_templates.py            build and check every plan, write what changed,
                                                       remove templates no plan produces any more
    python tools/generate_room_templates.py --check    build and check only, write nothing
    python tools/generate_room_templates.py --list     print every plan and the templates it makes

Plans live in dungeon/rooms/plans/<group>/<id>.txt (docs/design/claude_design_antwort/02_grundrisse.md).
A plan file has a header ("key: value" lines, "#" comments), a line "---" and the ASCII grid:

    name: Grabhalle               shown nowhere, for people
    role: combat                  combat | boss | miniboss | rest | campfire | fixture
    kind: normal                  normal | arena            (combat only, from the mode by default)
    mode: clear                   clear | arena | escort | flame | relic | souls | rifts | hunt |
                                  beacon | collapse | boss | rest | campfire (RoomTemplate.mode)
    biomes: crypt, shadow_realm   or "all"; one template per biome (floor sources follow the biome)
    size: 23x13                   grid size (checked)
    class: S                      S | M | L (default from the floor area)
    weight: 1.0                   share among the candidates of a draw (TESTWERT)
    min_room: 1                   first room number
    mirror: yes                   also build the plan mirrored west <-> east
    special: shop, weapon         rest rooms: the special types the plan is made for
    scene: combat/combat_hall.tscn  fixed output path (legacy names other files load)
    auto_deco: no                 no decoration groups added by the generator
    ---
    #######################
    #######################
    ##T###n####N####n###T##
    ##...................##
    ...

Grid (one cell = one tile of 64 world px, 32 px art at scale 2): the outer two columns, the top
three rows and the bottom two rows are the wall ring (RoomTiles: north wall = two crowns plus one
brick front, the side walls and the south wall are crowns). The floor rectangle inside it becomes
RoomTiles.room_size. Legend (02_grundrisse.md, plus a few cells of our own, marked *):

  walls       #  wall (crown; the brick front comes by itself where floor lies south)
              x  outside / rock
  fronts      T  wall torch    n  wall niche    q  cracked secret wall    g  gate (arena source)
              !  rift in the wall    - these sit IN a brick front, flush with the wall
  doors       S  entrance (south wall)    N  north door (first = exit, more = branch places)
              W  west door (column 0 or 1)    E  east door (last or second last column)
  floor       .  floor    ~  abyss    =  bridge over the abyss    w  shallow water / mud
              m* moss (floor)
  sources     G  grave    s  sarcophagus    p  puddle    i  floor rift    v  lava vent
              (floor sources follow the biome of the template: G in the crypt, p in the grotto,
              i in the shadow realm, v in the ember forge; s stays a sarcophagus in the crypt)
  objectives  1 escort figure  f soul flame  A relic altar  R relic  * soul  e escape hole
              X collapse field  C light crystal  B brazier  t torch stand  u torch stand (off)
              M stone guardian  9 the crowned one  0 boss  h merchant  H counter (2 tiles)
              Q fountain  U upgrade altar  Y pact altar  V wager altar  J campfire  O exit portal
              l log  z bedroll  j* weapon rack    2 slime  3 skeleton  4 archer  5 shadow  6 golem (guards)
  decoration  c chest  r rubble  b barrel  a* crate  F* explosive barrel  k bones  o coffin
              P fallen pillar (2 tiles)  K offering site  d drip  + spike trap  & stairs
              D* camp (crate, barrel, bedroll at a wall)  Z* guard post (torch stand, rubble, bones)
  player      @  start of the player (marker only)

What a template gets (contract for R2 and R4, docs in the R1 report):
  - Tiles: room size, doors (door_slots), wall_rects, pit_rects, bridge_rects, water_rects,
    moss_tiles, secret_cracks ('q'), front_fixtures (fronts holding T n g ! q and chains).
  - Sources/SourceN (Marker2D, the Sources node only exists when the plan has sources; same for
    Objectives): metadata source_kind (grave, sarcophagus, puddle, rift, vent, gate,
    rift_wall), tile (Vector2i), floor_tile (where an enemy stands when it is out), wall_side
    (RoomTiles.DoorSide of the wall a gate or wall rift sits in; -1 for floor sources).
  - Objectives/<Kind>N (Marker2D): metadata objective_kind, tile, enemy (guards), built (true if
    this generator already placed the prop: light crystal, brazier, torch stand).
  - PlayerStart (Marker2D), ContentAnchor, PortalAnchor, SpawnPoints (5-14 markers, the floor
    sources come first), Props (torches, niches, chests, breakables, traps, DecoProp groups).
  - Ingredients: the IngredientScatter stays (one dungeon RNG draw per room), but scatters nothing
    any more (allowed = []): no random props (R1).

Rules checked for every template (the generator stops on the first broken plan):
  - grid size, ring, legend; every fixture in a brick front (wall above, floor below);
  - wall mass: a wall with floor south of it has a crown above it (WallAutotile.is_valid_mass);
  - entrance, exits and side doors: two tiles of floor straight in, no abyss in their lane, no
    prop, source or objective in their lane, no front fixture right beside a north door; template
    torches keep 4 columns from the exit door (the door brings its own, D1);
  - every floor tile reachable on foot from the entrance with every solid prop and every source
    treated as blocked (sources never close a way), every door reachable;
  - no decoration on a tile that is the only way (articulation point of the floor);
  - spike traps only with a reason: next to a chest or in a side passage;
  - at most one decoration group per 20 floor tiles; groups at walls and corners;
  - spawn markers: count per size (D-086, S >= 5, M >= 8, L >= 12, at most 14), on free reachable
    floor, away from every entrance.
"""
import math
import random
import sys
import zlib
from collections import deque
from pathlib import Path

T = 64
ROOT = Path(__file__).resolve().parent.parent
ROOMS = ROOT / "dungeon" / "rooms"
PLANS = ROOMS / "plans"
TEMPLATES = ROOMS / "templates"
COMBAT_CATALOG = ROOMS / "combat" / "combat_catalog.tres"
PLAN_CATALOG = ROOMS / "plan_catalog.tres"
TEMPLATE_SCRIPT = "res://dungeon/rooms/templates/room_template.gd"
SCATTER_SCRIPT = "res://dungeon/rooms/ingredients/ingredient_scatter.gd"
DECO_SCRIPT = "res://dungeon/environment/deco/deco_prop.gd"
SCENES = {
    "torch": "res://dungeon/environment/decorations/torch.tscn",
    "crate": "res://dungeon/environment/decorations/crate.tscn",
    "barrel": "res://dungeon/environment/decorations/barrel.tscn",
    "explosive": "res://dungeon/rooms/ingredients/explosive_barrel.tscn",
    "chest": "res://dungeon/rooms/ingredients/treasure_chest.tscn",
    "rubble": "res://dungeon/rooms/ingredients/rubble.tscn",
    "spike_trap": "res://dungeon/environment/traps/spike_trap.tscn",
    "lava_crack": "res://dungeon/environment/traps/lava_crack.tscn",
    "toxic_puddle": "res://dungeon/environment/traps/toxic_puddle.tscn",
}
BIOMES = ["crypt", "slime_grotto", "shadow_realm", "ember_forge"]
# Per biome (copied from dungeon/rooms/ingredients/sets/*.tres): floor source cell, trap scene and
# tint, light island style and colour, rubble tint.
BIOME_STYLE = {
    "crypt": dict(source="G", trap="spike_trap", trap_tint=None, light="torch_stand", light_color=(1, 0.85, 0.6), rubble_tint=None),
    "slime_grotto": dict(source="p", trap="toxic_puddle", trap_tint=None, light="light_crystal", light_color=(0.6, 1, 0.65), rubble_tint=(0.72, 0.92, 0.78)),
    "shadow_realm": dict(source="i", trap="spike_trap", trap_tint=(0.75, 0.55, 1), light="light_crystal", light_color=(0.85, 0.7, 1), rubble_tint=(0.85, 0.75, 1)),
    "ember_forge": dict(source="v", trap="lava_crack", trap_tint=None, light="torch_stand", light_color=(1, 0.7, 0.45), rubble_tint=(0.8, 0.68, 0.6)),
}
# RoomSequence.RoomKind / RoomSize / RoomTemplate.Shape.PLAN / RoomTiles.DoorSide.
KINDS = {"normal": 0, "arena": 1, "chasm": 2}
SIZES = {"S": 0, "M": 1, "L": 2}
SHAPE_PLAN = 11
NORTH, EAST, SOUTH, WEST = 0, 1, 2, 3
INWARD = {NORTH: (0, 1), EAST: (-1, 0), SOUTH: (0, -1), WEST: (1, 0)}
# RoomSequence.SpecialType.
SPECIAL_TYPES = {"shop": 0, "weapon": 1, "fountain": 2, "altar": 3, "trial": 4}
ROLES = ("combat", "boss", "miniboss", "rest", "campfire", "fixture")
MODES = ("clear", "arena", "escort", "flame", "relic", "souls", "rifts", "hunt", "beacon", "collapse",
         "boss", "miniboss", "rest", "campfire")

# --- Rules (TESTWERTE where they are numbers of the design) ---
# Spawn markers per combat template (D-086): S >= 5, M >= 8, L >= 12, never more than 14.
MIN_SPAWNS = {"S": 5, "M": 8, "L": 12}
MAX_SPAWNS = 14
SPAWN_COUNT = {"S": 6, "M": 9, "L": 13}
ARENA_SPAWN_COUNT = {"S": 8, "M": 10, "L": 14}
# Boss, miniboss, rest and campfire rooms keep exactly five markers (champion escort, D-009).
BASE_SPAWNS = 5
# Floor area (tiles of the floor rectangle) up to which a plan is S / M (D-086: S ~ 15x9, M ~ 19x11).
SIZE_LIMITS = (("S", 180), ("M", 300))
# Chebyshev distance spawn markers keep from the tile inside any entrance / from the exits.
ENTRANCE_CLEARANCE = 2
EXIT_CLEARANCE = 1
# Tiles of floor straight in from a door; rows of its three-tile lane that stay free.
DOOR_DEPTH = 2
DOOR_LANE_ROWS = 2
# Second and third north place of a branch room (D-105): this many columns from other north places.
BRANCH_DOOR_SPACING = 5
# Template torches keep this many columns from the exit door (the door brings its own, D1).
DOOR_TORCH_CLEARANCE = 4
# Front fixtures keep this many columns from a north door (its arch is 1.5 tiles wide).
DOOR_FIXTURE_CLEARANCE = 1
# A cracked wall in the north wall keeps this many columns from a north door: the niche behind it
# (three wide, SecretRules) and its rock must not touch the door corridor.
SECRET_DOOR_DISTANCE = 3
# Decoration groups: at most one per this many floor tiles (02_grundrisse.md); the generator adds
# groups until one per AUTO_GROUP_TILES floor tiles (TESTWERT), only where the rules allow it.
GROUP_TILES = 20
AUTO_GROUP_TILES = 30
GROUP_SPACING = 4
# A spike trap needs a reason: a chest within this Chebyshev distance or a side passage.
TRAP_CHEST_DISTANCE = 2
# Explosive barrels only from this room on (IngredientSet.explosives_from_room); props carry it as
# metadata/min_room and RoomController removes them in earlier rooms.
EXPLOSIVES_FROM_ROOM = 3

WALL_CELLS = set("#x")
FRONT_FIXTURES = set("Tnqg!")
FLOOR_SOURCES = {"G": "grave", "s": "sarcophagus", "p": "puddle", "i": "rift", "v": "vent"}
WALL_SOURCES = {"g": "gate", "!": "rift_wall"}
OBJECTIVES = {
    "1": "escort_start", "f": "soul_flame", "A": "relic_altar", "R": "relic", "*": "soul",
    "e": "escape_hole", "X": "collapse_field", "C": "light_crystal", "B": "brazier", "t": "torch_stand",
    "u": "torch_stand_unlit", "M": "stone_guardian", "9": "crowned", "0": "boss", "h": "merchant",
    "H": "counter", "Q": "fountain", "U": "upgrade_altar", "Y": "pact_altar", "V": "wager_altar",
    "J": "campfire", "O": "exit_portal", "l": "log", "z": "bedroll", "j": "weapon_rack",
}
GUARDS = {"2": "slime", "3": "skeleton", "4": "archer", "5": "shadow", "6": "golem"}
# Objectives this generator builds right away (scenery that lights the room); the marker says so.
BUILT_OBJECTIVES = {"C", "B", "t"}
# Objectives that block their tile (built props, heavy furniture of rest rooms).
SOLID_OBJECTIVES = {"C", "B", "t", "u", "A", "H", "Q", "U", "Y", "V", "J"}
DECO_CELLS = set("crbaFkoPKd+&DZm")
TWO_TILE = {"P", "H"}
# Decoration that blocks walking (and the tile under it).
SOLID_DECO = set("crbaFoPDZ")

MODE = "write"
_written = []
_unchanged = 0
_problems = []


class PlanError(Exception):
    pass


# --- Plan files ---

class Plan:
    def __init__(self, path):
        self.path = path
        self.id = path.stem
        self.group = path.parent.name
        self.header = {}
        self.grid = []
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        if "---" not in [line.strip() for line in lines]:
            raise PlanError(f"{path.name}: no '---' line between header and grid")
        in_grid = False
        for line in lines:
            if not in_grid:
                if line.strip() == "---":
                    in_grid = True
                    continue
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                if ":" not in stripped:
                    raise PlanError(f"{path.name}: header line without ':' ({stripped})")
                key, value = stripped.split(":", 1)
                self.header[key.strip().lower()] = value.strip()
            else:
                row = line.rstrip()
                if row:
                    self.grid.append(row)
        h = self.header
        self.id = h.get("id", self.id)
        self.name = h.get("name", self.id)
        self.role = h.get("role", "combat")
        self.mode = h.get("mode", "arena" if h.get("kind") == "arena" else ("clear" if self.role in ("combat", "fixture") else self.role))
        self.kind = h.get("kind", "arena" if self.mode == "arena" else "normal")
        biomes = h.get("biomes", "all")
        self.biomes = list(BIOMES) if biomes == "all" else [b.strip() for b in biomes.split(",") if b.strip()]
        self.weight = float(h.get("weight", "1"))
        self.min_room = int(h.get("min_room", "1"))
        self.mirror = h.get("mirror", "no").lower() in ("yes", "true", "1")
        self.scene = h.get("scene", "")
        self.special = [SPECIAL_TYPES[s.strip()] for s in h.get("special", "").split(",") if s.strip()]
        self.auto_deco = h.get("auto_deco", "yes" if self.role in ("combat", "boss", "miniboss") else "no").lower() in ("yes", "true", "1")
        self.size_class = h.get("class", "")
        self._check_header()

    def _check_header(self):
        name = self.path.name
        if self.role not in ROLES:
            raise PlanError(f"{name}: unknown role {self.role}")
        if self.mode not in MODES:
            raise PlanError(f"{name}: unknown mode {self.mode}")
        if self.kind not in ("normal", "arena"):
            raise PlanError(f"{name}: kind must be normal or arena")
        for biome in self.biomes:
            if biome not in BIOMES:
                raise PlanError(f"{name}: unknown biome {biome}")
        if not self.grid:
            raise PlanError(f"{name}: empty grid")
        widths = {len(row) for row in self.grid}
        if len(widths) != 1:
            raise PlanError(f"{name}: rows of different length {sorted(widths)}")
        if "size" in self.header:
            expected = self.header["size"].lower().replace(" ", "")
            actual = f"{len(self.grid[0])}x{len(self.grid)}"
            if expected != actual:
                raise PlanError(f"{name}: header size {expected}, grid is {actual}")
        if self.size_class and self.size_class not in SIZES:
            raise PlanError(f"{name}: class must be S, M or L")

    def variants(self):
        """(out_id, biome, mirrored) of every template the plan makes."""
        result = []
        for biome in self.biomes:
            for mirrored in ([False, True] if self.mirror else [False]):
                out_id = self.id + ("_mirror" if mirrored else "")
                if len(self.biomes) > 1:
                    out_id += "_" + biome
                result.append((out_id, biome, mirrored))
        return result


def mirrored_grid(grid):
    """The grid mirrored west <-> east: W and E swap, two-tile items keep their left anchor."""
    swap = {"W": "E", "E": "W"}
    rows = []
    for row in grid:
        cells = [swap.get(c, c) for c in reversed(row)]
        for x in range(len(cells)):
            if cells[x] in TWO_TILE:
                if x == 0 or cells[x - 1] != ".":
                    raise PlanError(f"mirrored two-tile item {cells[x]} needs floor to its west")
                cells[x - 1], cells[x] = cells[x], "."
        rows.append("".join(cells))
    return rows


def biome_grid(grid, biome):
    """Floor sources of the biome: G / p / i / v become the biome's own; a sarcophagus stays one in
    the crypt only."""
    own = BIOME_STYLE[biome]["source"]
    rows = []
    for row in grid:
        cells = []
        for c in row:
            if c in "Gpiv" or (c == "s" and biome != "crypt"):
                c = own
            cells.append(c)
        rows.append("".join(cells))
    return rows


# --- Geometry helpers ---

def chebyshev(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def neighbours4(tile):
    x, y = tile
    return [(x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)]


def flood(walkable, start):
    if start not in walkable:
        return set()
    seen = {start}
    queue = deque([start])
    while queue:
        tile = queue.popleft()
        for n in neighbours4(tile):
            if n in walkable and n not in seen:
                seen.add(n)
                queue.append(n)
    return seen


def bfs_path(walkable, start, goal):
    parent = {start: None}
    queue = deque([start])
    while queue:
        tile = queue.popleft()
        if tile == goal:
            break
        for n in neighbours4(tile):
            if n in walkable and n not in parent:
                parent[n] = tile
                queue.append(n)
    if goal not in parent:
        return []
    path, tile = [], goal
    while tile is not None:
        path.append(tile)
        tile = parent[tile]
    return path[::-1]


def articulation_points(nodes):
    """Tiles whose removal splits the 4-neighbour graph over nodes (iterative Tarjan)."""
    nodes = set(nodes)
    index, low, result = {}, {}, set()
    counter = 0
    for root in sorted(nodes):
        if root in index:
            continue
        index[root] = low[root] = counter
        counter += 1
        children = 0
        stack = [(root, None, iter([n for n in neighbours4(root) if n in nodes]))]
        while stack:
            node, parent, it = stack[-1]
            advanced = False
            for n in it:
                if n == parent:
                    continue
                if n in index:
                    low[node] = min(low[node], index[n])
                else:
                    index[n] = low[n] = counter
                    counter += 1
                    if node == root:
                        children += 1
                    stack.append((n, node, iter([m for m in neighbours4(n) if m in nodes])))
                    advanced = True
                    break
            if not advanced:
                stack.pop()
                if parent is not None:
                    low[parent] = min(low[parent], low[node])
                    if parent != root and low[node] >= index[parent]:
                        result.add(parent)
        if children > 1:
            result.add(root)
    return result


def to_rects(tiles):
    """Tiles as few Rect2i: horizontal runs, merged downwards when identical."""
    if not tiles:
        return []
    runs = []
    for y in sorted({t[1] for t in tiles}):
        xs = sorted(t[0] for t in tiles if t[1] == y)
        start = prev = xs[0]
        for x in xs[1:]:
            if x != prev + 1:
                runs.append((start, y, prev - start + 1))
                start = x
            prev = x
        runs.append((start, y, prev - start + 1))
    rects, open_rects = [], {}
    for x, y, w in runs:
        key = (x, w)
        current = open_rects.get(key)
        if current is not None and current[1] + current[3] == y:
            current[3] += 1
            continue
        if current is not None:
            rects.append(tuple(current))
        open_rects[key] = [x, y, w, 1]
    rects.extend(tuple(r) for r in open_rects.values())
    covered = {(x + i, y + j) for x, y, w, h in rects for i in range(w) for j in range(h)}
    assert covered == set(tiles), "rects do not cover the tiles exactly"
    return sorted(rects, key=lambda r: (r[1], r[0]))


def fmt(value):
    return f"{value:g}" if isinstance(value, float) else str(value)


def vec2(x, y):
    return f"Vector2({fmt(float(x))}, {fmt(float(y))})"


def vec2i_list(tiles):
    return "Array[Vector2i]([" + ", ".join(f"Vector2i({x}, {y})" for x, y in tiles) + "])"


def rect_list(rects):
    return "Array[Rect2i]([" + ", ".join(f"Rect2i({x}, {y}, {w}, {h})" for x, y, w, h in rects) + "])"


def color(c):
    return f"Color({fmt(float(c[0]))}, {fmt(float(c[1]))}, {fmt(float(c[2]))}, 1)"


def centre(tile):
    return ((tile[0] + 0.5) * T, (tile[1] + 0.5) * T)


def base(tile):
    """Base line of a standing prop on a tile (same spot as IngredientScatter._base_of)."""
    return ((tile[0] + 0.5) * T, (tile[1] + 1) * T - 8)


# --- One template from a plan ---

class Room:
    """Everything a template needs, built and checked from a plan for one biome."""

    def __init__(self, plan, out_id, biome, mirrored):
        self.plan = plan
        self.id = out_id
        self.biome = biome
        self.mirrored = mirrored
        self.name = f"{plan.path.relative_to(PLANS).as_posix()} -> {out_id}"
        grid = mirrored_grid(plan.grid) if mirrored else list(plan.grid)
        self.grid = biome_grid(grid, biome)
        self.rng = random.Random(zlib.crc32(out_id.encode()))
        self.seed = zlib.crc32(out_id.encode()) % 997 + 1
        gw, gh = len(self.grid[0]), len(self.grid)
        if gw < 9 or gh < 9:
            self.fail(f"grid {gw}x{gh} too small")
        self.size = (gw - 4, gh - 5)
        self.walls, self.pits, self.bridges, self.water, self.moss = set(), set(), set(), set(), set()
        self.fixtures = {}
        self.items = []
        self.entrance = None
        self.north, self.west, self.east = [], [], []
        self.player_start = None
        self.props = []
        self.sources = []
        self.objectives = []
        self.occupied = {}
        # Occupied tiles that hold nothing solid (objective markers): allowed in door lanes.
        self.soft = set()
        self.blocked = set()
        self.groups = []
        self.spawns = []
        self.notes = []
        self._read_grid()

    def fail(self, message):
        raise PlanError(f"{self.name}: {message}")

    def cell(self, x, y):
        """Grid cell of a room tile (room tile (0, 0) = grid (2, 3))."""
        return self.grid[y + 3][x + 2]

    def in_floor(self, tile):
        return 0 <= tile[0] < self.size[0] and 0 <= tile[1] < self.size[1]

    # --- reading ---

    def _read_grid(self):
        w, h = self.size
        gw, gh = len(self.grid[0]), len(self.grid)
        for gy in range(gh):
            for gx in range(gw):
                c = self.grid[gy][gx]
                x, y = gx - 2, gy - 3
                if 0 <= x < w and 0 <= y < h:
                    self._read_floor_cell(c, (x, y))
                    continue
                if gy == 2 and 2 <= gx < gw - 2:
                    if c == "N":
                        self.north.append(x)
                    elif c in FRONT_FIXTURES:
                        self.fixtures[(x, -1)] = c
                    elif c not in WALL_CELLS:
                        self.fail(f"north front row: '{c}' at column {gx}")
                elif gy == gh - 2 and 2 <= gx < gw - 2:
                    if c == "S":
                        if self.entrance is not None:
                            self.fail("two entrances (S)")
                        self.entrance = x
                    elif c not in WALL_CELLS:
                        self.fail(f"south wall: '{c}' at column {gx}")
                elif gy in (0, 1, gh - 1) or gx in (0, 1, gw - 2, gw - 1):
                    if 3 <= gy < gh - 2 and c in "WE.":
                        continue
                    if c not in WALL_CELLS:
                        self.fail(f"wall ring: '{c}' at {(gx, gy)}")
        # Side doors: W in column 0 or 1, E in the last or second last column, floor between.
        for gy in range(3, gh - 2):
            row = self.grid[gy]
            y = gy - 3
            # The two ring cells of a side door are its corridor: the door letter and floor.
            for letter, cells, places in (("W", row[0:2], self.west), ("E", row[gw - 2:], self.east)):
                if letter in cells:
                    if any(c not in letter + "." for c in cells):
                        self.fail(f"{letter} door in row {gy}: ring must be door and floor (is '{cells}')")
                    places.append(y)
                elif "." in cells:
                    self.fail(f"row {gy}: floor in the side wall without a door")
        if self.entrance is None:
            self.fail("no entrance (S in the south wall)")
        if not self.north:
            self.fail("no north door (N in the north front row)")

    def _read_floor_cell(self, c, tile):
        if c in WALL_CELLS:
            self.walls.add(tile)
        elif c in FRONT_FIXTURES:
            self.walls.add(tile)
            self.fixtures[tile] = c
        elif c == "~":
            self.pits.add(tile)
        elif c == "=":
            self.pits.add(tile)
            self.bridges.add(tile)
        elif c == "w":
            self.water.add(tile)
        elif c == "m":
            self.moss.add(tile)
        elif c == ".":
            pass
        elif c == "@":
            self.player_start = tile
        elif c in FLOOR_SOURCES or c in OBJECTIVES or c in GUARDS or c in DECO_CELLS:
            self.items.append((c, tile))
        elif c in "SNWE":
            self.fail(f"door '{c}' inside the floor at {tile}")
        else:
            self.fail(f"unknown cell '{c}' at {tile}")

    # --- derived sets ---

    def floor_tiles(self):
        w, h = self.size
        return {(x, y) for x in range(w) for y in range(h)} - self.walls

    def walk_floor(self):
        return self.floor_tiles() - (self.pits - self.bridges)

    def door_slots(self):
        slots = [(SOUTH, self.entrance)] + [(NORTH, x) for x in self.north]
        slots += [(WEST, y) for y in self.west] + [(EAST, y) for y in self.east]
        return slots

    def inside_tile(self, side, place):
        w, h = self.size
        return {NORTH: (place, 0), EAST: (w - 1, place), SOUTH: (place, h - 1), WEST: (0, place)}[side]

    def door_tile(self, side, place):
        w, h = self.size
        return {NORTH: (place, -1), EAST: (w, place), SOUTH: (place, h), WEST: (-1, place)}[side]

    def corridor(self, side, place):
        length = 3 if side == NORTH else 2
        out = {NORTH: (0, -1), EAST: (1, 0), SOUTH: (0, 1), WEST: (-1, 0)}[side]
        x, y = self.door_tile(side, place)
        return [(x + out[0] * i, y + out[1] * i) for i in range(length)]

    def lane(self, side, place, rows):
        ix, iy = INWARD[side]
        ax, ay = abs(iy), abs(ix)
        x0, y0 = self.inside_tile(side, place)
        return [(x0 + ix * d + ax * a, y0 + iy * d + ay * a) for d in range(rows) for a in (-1, 0, 1)]

    def core(self, side, place):
        ix, iy = INWARD[side]
        x0, y0 = self.inside_tile(side, place)
        return [(x0 + ix * d, y0 + iy * d) for d in range(DOOR_DEPTH)]

    # --- building ---

    def build(self):
        self._check_walls()
        self._check_fixtures()
        self._place_items()
        self._check_doors()
        self._add_auto_doors()
        if self.plan.auto_deco:
            self._add_auto_groups()
        self._check_layout()
        self._place_spawns()
        self._place_anchors()
        return self

    def _check_walls(self):
        floor = self.floor_tiles()
        for x, y in self.walls:
            if (x, y + 1) in floor and y - 1 >= 0 and (x, y - 1) not in self.walls:
                self.fail(f"wall {(x, y)} has floor north and south: a wall above floor needs a crown above its front")
        for tile in self.bridges:
            pass

    def _check_fixtures(self):
        walk = self.walk_floor()
        for tile, c in self.fixtures.items():
            x, y = tile
            below = (x, y + 1)
            if below not in walk or below in self.pits:
                self.fail(f"'{c}' at {tile} is no brick front (no plain floor below it)")
            if y >= 0 and y - 1 >= 0 and (x, y - 1) not in self.walls:
                self.fail(f"'{c}' at {tile} has no crown above it")
            if c == "q" and not 2 <= x <= self.size[0] - 3:
                self.fail(f"cracked wall at {tile}: the niche behind it needs two columns to each side wall")
            if c == "q" and y == -1 and any(abs(x - n) < SECRET_DOOR_DISTANCE for n in self.north):
                self.fail(f"cracked wall at {tile}: the niche behind it would touch the north door corridor")
            if c in WALL_SOURCES:
                self.sources.append(dict(kind=WALL_SOURCES[c], tile=tile, floor_tile=below, wall_side=NORTH))
                self._occupy([below], "source")
            elif c == "T":
                self.props.append(dict(scene="torch", name="Torch", pos=(x * T, y * T), group=None))
            elif c == "n":
                self.props.append(dict(deco="wall_niche", name="Niche", pos=(x * T + T / 2, (y + 1) * T), group=None))
        for x in self.north:
            for tile, c in self.fixtures.items():
                if tile[1] == -1 and abs(tile[0] - x) <= DOOR_FIXTURE_CLEARANCE:
                    self.fail(f"'{c}' at {tile} right beside the north door at column {x}")
            for tile, c in self.fixtures.items():
                if c == "T" and tile[1] == -1 and x == self.north[0] and abs(tile[0] - x) < DOOR_TORCH_CLEARANCE:
                    self.fail(f"torch at {tile} within {DOOR_TORCH_CLEARANCE - 1} columns of the exit door (it brings its own, D1)")

    def _occupy(self, tiles, what):
        for tile in tiles:
            if tile in self.occupied:
                self.fail(f"{what} at {tile} on the {self.occupied[tile]}")
            self.occupied[tile] = what

    def _place_items(self):
        floor = self.walk_floor()
        style = BIOME_STYLE[self.biome]
        chests = [t for c, t in self.items if c == "c"]
        for c, tile in self.items:
            tiles = [tile, (tile[0] + 1, tile[1])] if c in TWO_TILE else [tile]
            for t in tiles:
                if t not in floor or t in self.bridges:
                    self.fail(f"'{c}' at {t} not on solid floor")
            if c in FLOOR_SOURCES:
                self.sources.append(dict(kind=FLOOR_SOURCES[c], tile=tile, floor_tile=tile, wall_side=-1))
                self._occupy(tiles, "source")
            elif c in OBJECTIVES or c in GUARDS:
                self._place_objective(c, tile, tiles, style)
            else:
                self._place_deco(c, tile, tiles, style, chests)

    def _place_objective(self, c, tile, tiles, style):
        kind = "guard" if c in GUARDS else OBJECTIVES[c]
        entry = dict(kind=kind, tile=tile, enemy=GUARDS.get(c, ""), built=c in BUILT_OBJECTIVES)
        self.objectives.append(entry)
        self._occupy(tiles, kind)
        if c in SOLID_OBJECTIVES:
            self.blocked.update(tiles)
        else:
            # Enemies, souls, fields: markers only, they may stand in a door lane.
            self.soft.update(tiles)
        if c == "C":
            self.props.append(dict(deco="light_crystal", name="Crystal", pos=base(tile), tint=style["light_color"], blocked=tiles, group="light"))
        elif c == "t":
            self.props.append(dict(deco="torch_stand", name="TorchStand", pos=base(tile), tint=style["light_color"], blocked=tiles, group="light"))
        elif c == "B":
            self.props.append(dict(deco="brazier", name="Brazier", pos=base(tile), blocked=tiles, group="light"))

    def _place_deco(self, c, tile, tiles, style, chests):
        rng = self.rng
        group = f"{c}{tile}"
        jx = lambda: rng.randint(-8, 8)
        jy = lambda: rng.randint(-5, 4)
        self._occupy(tiles, "decoration")
        if c in SOLID_DECO and c not in "DZ":
            self.blocked.update(tiles)
        x, y = tile
        if c == "c":
            self.props.append(dict(scene="chest", name="Chest", pos=base(tile), group=group))
        elif c == "r":
            self.props.append(dict(scene="rubble", name="Rubble", pos=base(tile), tint=style["rubble_tint"], group=group))
        elif c == "b":
            self.props.append(dict(scene="barrel", name="Barrel", pos=base(tile), group=group))
        elif c == "a":
            self.props.append(dict(scene="crate", name="Crate", pos=base(tile), group=group))
        elif c == "F":
            self.props.append(dict(scene="explosive", name="Explosive", pos=base(tile), group=group, min_room=EXPLOSIVES_FROM_ROOM))
        elif c == "k":
            item = rng.choice(["bones_1", "bones_2", "bone_pile"])
            self.props.append(dict(deco=item, name="Bones", pos=(centre(tile)[0] + jx(), centre(tile)[1] + jy()), flip=rng.random() < 0.5, group=group))
        elif c == "o":
            self.props.append(dict(deco="coffin", name="Coffin", pos=(base(tile)[0] + rng.randint(-3, 3), base(tile)[1]), flip=rng.random() < 0.5, blocked=tiles, group=group))
        elif c == "P":
            # Fallen pillar plus a fan of rubble at its broken end (02_grundrisse.md).
            flip = rng.random() < 0.5
            px, py = (x + 1) * T, (y + 1) * T - 8
            self.props.append(dict(deco="pillar_fallen", name="Pillar", pos=(px, py), flip=flip, blocked=tiles, group=group))
            end = -1 if flip else 1
            self.props.append(dict(deco="rubble_1", name="RubbleBit", pos=(px + end * rng.randint(70, 84), py - rng.randint(6, 16)), flip=rng.random() < 0.5, group=group))
            self.props.append(dict(deco="rubble_2", name="RubbleBit", pos=(px + end * rng.randint(48, 60), py + rng.randint(10, 18)), flip=rng.random() < 0.5, group=group))
        elif c == "K":
            # Offering site: candles, bones, a gravestone behind (none if a grave is right there).
            cx, cy = centre(tile)
            self.props.append(dict(deco="candles", name="Candles", pos=(cx + jx(), cy + 4), group=group))
            self.props.append(dict(deco="bones_1", name="Bones", pos=(cx - 34 + jx(), cy + 18), flip=rng.random() < 0.5, group=group))
            # No gravestone in rest rooms (it reads as an enemy source) or right beside a grave.
            if self.plan.role != "rest" and not any(s["kind"] == "grave" and chebyshev(s["tile"], tile) <= 1 for s in self.sources):
                self.props.append(dict(deco="gravestone", name="Gravestone", pos=(cx + 28, cy - 14), still=0, group=group))
        elif c == "d":
            self._drip(tile, group)
        elif c == "+":
            near_chest = any(chebyshev(tile, chest) <= TRAP_CHEST_DISTANCE for chest in chests)
            self.props.append(dict(scene=style["trap"], name="Trap", pos=centre(tile), tint=style["trap_tint"], group=group, trap=True, chest=near_chest))
        elif c == "&":
            self.props.append(dict(deco="stairs", name="Stairs", pos=centre(tile), group=group))
        elif c == "D":
            self._camp(tile, group)
        elif c == "Z":
            self._guard_post(tile, group, style)
        elif c == "m":
            self.moss.add(tile)

    def _drip(self, tile, group):
        cx, cy = centre(tile)
        self.props.append(dict(deco="puddle", name="Puddle", pos=(cx, cy + 6), tint=WATER_TINTS[self.biome], group=group))
        self.props.append(dict(deco="drip", name="Drip", pos=(cx + self.rng.randint(-6, 6), cy + 4), group=group))
        floor = self.walk_floor()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                t = (tile[0] + dx, tile[1] + dy)
                if t in floor and t not in self.water:
                    self.moss.add(t)

    def _camp(self, tile, group):
        """Camp at a wall: crate, barrel and bedroll side by side (02_grundrisse.md "Lagerplatz")."""
        floor = self.walk_floor()
        step = 1 if (tile[0] + 1, tile[1]) in floor and (tile[0] + 1, tile[1]) not in self.occupied else -1
        second = (tile[0] + step, tile[1])
        if second not in floor or second in self.occupied:
            self.fail(f"camp 'D' at {tile} needs a free floor tile beside it")
        self._occupy([second], "decoration")
        self.blocked.update([tile, second])
        self.props.append(dict(scene="crate", name="Crate", pos=base(tile), group=group))
        self.props.append(dict(scene="barrel", name="Barrel", pos=(base(second)[0] + self.rng.randint(-4, 4), base(second)[1] + 2), group=group))
        bx = base(second)[0] + step * 52
        self.props.append(dict(deco="bedroll", name="Bedroll", pos=(bx, base(second)[1] - 4), flip=step < 0, group=group))

    def _guard_post(self, tile, group, style):
        cx, cy = centre(tile)
        self.blocked.add(tile)
        self.props.append(dict(deco="torch_stand", name="TorchStand", pos=base(tile), tint=style["light_color"], blocked=[tile], group=group))
        self.props.append(dict(deco="rubble_2", name="RubbleBit", pos=(cx + 30, cy + 20), flip=self.rng.random() < 0.5, group=group))
        self.props.append(dict(deco="bones_2", name="Bones", pos=(cx - 28, cy + 22), flip=self.rng.random() < 0.5, group=group))

    # --- doors ---

    def _door_ok(self, side, place, strict=True):
        walk = self.walk_floor()
        for tile in self.core(side, place):
            if tile not in walk or tile in self.bridges:
                return f"no plain floor at {tile} in front of the door"
        for tile in self.lane(side, place, DOOR_LANE_ROWS):
            if tile in self.pits:
                return f"abyss at {tile} in the door lane"
            if strict and tile in self.occupied and tile not in self.soft:
                return f"{self.occupied[tile]} at {tile} in the door lane"
        return ""

    def _check_doors(self):
        for side, place in self.door_slots():
            problem = self._door_ok(side, place)
            if problem:
                self.fail(f"door {('N', 'E', 'S', 'W')[side]}{place}: {problem}")

    def _add_auto_doors(self):
        """West/east places where the plan has none (A10), nearest the middle of the wall, and up to
        two more north places for a branch room (D-105); never at a fixture or a prop."""
        w, h = self.size
        if self.plan.role not in ("combat",):
            return
        for side, places in ((WEST, self.west), (EAST, self.east)):
            if places:
                continue
            rows = [y for y in range(h) if not self._door_ok(side, y)]
            if rows:
                places.append(min(rows, key=lambda y: (abs(y - (h - 1) / 2), -y)))
        options = [x for x in range(1, w - 1) if not self._door_ok(NORTH, x)
                   and all(abs(x - f[0]) > DOOR_FIXTURE_CLEARANCE for f in self.fixtures if f[1] == -1)
                   and all(abs(x - f[0]) >= SECRET_DOOR_DISTANCE for f, c in self.fixtures.items() if c == "q" and f[1] == -1)]
        for target in (w / 4, 3 * w / 4):
            fitting = [x for x in options if all(abs(x - p) >= BRANCH_DOOR_SPACING for p in self.north)]
            if fitting:
                self.north.append(min(fitting, key=lambda x: (abs(x - target), x)))

    # --- decoration groups ---

    def _add_auto_groups(self):
        floor = self.walk_floor() - self.water
        count = len(floor)
        wanted = count // AUTO_GROUP_TILES
        existing = self._group_count()
        if existing >= wanted:
            return
        lanes = set()
        for side, place in self.door_slots():
            lanes.update(self.lane(side, place, 3))
        self.auto_lanes = lanes
        cut = articulation_points(self.walk_floor())
        keep_out = [s["floor_tile"] for s in self.sources] + [o["tile"] for o in self.objectives]
        if self.player_start:
            keep_out.append(self.player_start)
        anchors = []
        for tile in sorted(floor):
            if tile in self.occupied or tile in lanes or tile in cut or tile in self.moss:
                continue
            if any(chebyshev(tile, k) <= 1 for k in keep_out):
                continue
            walls = self._wall_sides(tile)
            if not walls:
                continue
            corner = ("N" in walls or "S" in walls) and ("W" in walls or "E" in walls)
            anchors.append((0 if corner else 1, self.rng.random(), tile, walls))
        anchors.sort()
        # Boss and miniboss halls get no camp; a kind repeats only when nothing else is left.
        pool = [(kind, weight) for kind, weight in AUTO_GROUPS[self.biome] if self.plan.role == "combat" or kind != "camp"]
        centres = [g for g in self._group_centres()]
        used = []
        for _, _, tile, walls in anchors:
            if existing >= wanted:
                break
            if any(chebyshev(tile, c) < GROUP_SPACING for c in centres):
                continue
            fresh = [(kind, weight) for kind, weight in pool if kind not in used] or pool
            kind = self._weighted(fresh)
            if self._try_group(kind, tile, walls):
                existing += 1
                centres.append(tile)
                used.append(kind)

    def _weighted(self, pool):
        total = sum(weight for _, weight in pool)
        roll = self.rng.random() * total
        for kind, weight in pool:
            roll -= weight
            if roll < 0:
                return kind
        return pool[-1][0]

    def _wall_sides(self, tile):
        x, y = tile
        sides = ""
        for name, (dx, dy) in (("N", (0, -1)), ("S", (0, 1)), ("W", (-1, 0)), ("E", (1, 0))):
            other = (x + dx, y + dy)
            if other in self.walls or not self.in_floor(other):
                sides += name
        return sides

    def _try_group(self, kind, tile, walls):
        """One automatic group at a wall tile; False if it would close a way."""
        floor = self.walk_floor()
        cx, cy = centre(tile)
        # Sprites are wider than half a tile: nudge the group away from the walls it leans on.
        cx += (10 if "W" in walls else 0) - (10 if "E" in walls else 0)
        cy += 6 if "N" in walls else 0
        rng = self.rng
        group = f"auto{tile}"
        props, solid = [], []
        flip = "E" in walls
        if kind == "bones":
            props.append(dict(deco="bone_pile", name="Bones", pos=(cx + rng.randint(-6, 6), cy + rng.randint(0, 8)), flip=rng.random() < 0.5))
            props.append(dict(deco="bones_2", name="Bones", pos=(cx + (-30 if flip else 30), cy + rng.randint(10, 20)), flip=rng.random() < 0.5))
            if "N" in walls and ("W" in walls or "E" in walls):
                props.append(dict(deco="cobweb", name="Cobweb", pos=(tile[0] * T + (T if flip else 0), tile[1] * T), flip=flip))
        elif kind == "coffin":
            if "N" not in walls:
                return False
            solid = [tile]
            props.append(dict(deco="coffin", name="Coffin", pos=(base(tile)[0] + rng.randint(-3, 3), base(tile)[1]), blocked=[tile], flip=rng.random() < 0.5))
            props.append(dict(deco="candles", name="Candles", pos=(cx + (34 if not flip else -34), cy + 20)))
        elif kind == "rubble":
            props.append(dict(deco="rubble_1", name="RubbleBit", pos=(cx + rng.randint(-10, 10), cy + rng.randint(-4, 8)), flip=rng.random() < 0.5))
            props.append(dict(deco="rubble_2", name="RubbleBit", pos=(cx + (-28 if flip else 28) + rng.randint(-6, 6), cy + rng.randint(14, 24)), flip=rng.random() < 0.5))
            props.append(dict(deco="bones_1" if self.biome in ("crypt", "shadow_realm") else "rubble_2", name="Bit", pos=(cx + (-22 if flip else 22), cy + rng.randint(-14, -4)), flip=rng.random() < 0.5))
        elif kind == "mushrooms":
            props.append(dict(deco="mushrooms", name="Mushrooms", pos=(cx + rng.randint(-8, 8), (tile[1] + 1) * T - 10), flip=rng.random() < 0.5))
            props.append(dict(deco="mushrooms", name="Mushrooms", pos=(cx + (-30 if flip else 30), (tile[1] + 1) * T + 6), flip=rng.random() < 0.5, scale_hint=0.7))
            for t in [tile] + neighbours4(tile):
                if t in floor and t not in self.occupied:
                    self.moss.add(t)
        elif kind == "crystals":
            solid = [tile]
            props.append(dict(deco="crystal_cluster", name="Crystals", pos=(base(tile)[0] + rng.randint(-6, 6), base(tile)[1]), blocked=[tile], flip=rng.random() < 0.5))
            props.append(dict(deco="rubble_2", name="RubbleBit", pos=(cx + (-30 if flip else 30), cy + rng.randint(12, 22)), flip=rng.random() < 0.5))
        elif kind == "forge":
            solid = [tile]
            props.append(dict(deco="anvil", name="Anvil", pos=(base(tile)[0] + rng.randint(-5, 5), base(tile)[1]), blocked=[tile], flip=rng.random() < 0.5))
            props.append(dict(deco="rubble_1", name="RubbleBit", pos=(cx + (-32 if flip else 32), cy + rng.randint(10, 20)), flip=rng.random() < 0.5))
            above = (tile[0], tile[1] - 1)
            if "N" in walls and above in self.walls and self._front_free(above):
                props.append(dict(deco="chains", name="Chains", pos=(above[0] * T + T / 2, (above[1] + 1) * T), flip=rng.random() < 0.5))
                self.fixtures[above] = "c"
        elif kind == "drip":
            self._drip(tile, group)
            self._occupy([tile], "decoration")
            return True
        elif kind == "camp":
            if "N" not in walls:
                return False
            second = (tile[0] + (-1 if flip else 1), tile[1])
            if second not in floor or second in self.occupied or second in self.auto_lanes:
                return False
            solid = [tile, second]
            if not self._keeps_ways(solid):
                return False
            self._occupy([tile, second], "decoration")
            self.blocked.update(solid)
            step = -1 if flip else 1
            self.props.append(dict(scene="crate", name="Crate", pos=base(tile), group=group))
            self.props.append(dict(scene="barrel", name="Barrel", pos=(base(second)[0] + rng.randint(-4, 4), base(second)[1] + 2), group=group))
            self.props.append(dict(deco="bedroll", name="Bedroll", pos=(base(second)[0] + step * 52, base(second)[1] - 4), flip=flip, group=group))
            return True
        else:
            return False
        if solid and not self._keeps_ways(solid):
            return False
        self._occupy([tile], "decoration")
        self.blocked.update(solid)
        for prop in props:
            prop["group"] = group
            self.props.append(prop)
        return True

    def _front_free(self, tile):
        x, y = tile
        if tile in self.fixtures:
            return False
        if y == -1 and any(abs(x - n) <= DOOR_FIXTURE_CLEARANCE + 1 for n in self.north):
            return False
        return all(abs(x - f[0]) > 1 or f[1] != y for f in self.fixtures)

    def _keeps_ways(self, extra):
        walk = self.walk_floor() - self.blocked - set(extra) - {s["floor_tile"] for s in self.sources if s["wall_side"] < 0}
        start = self.inside_tile(SOUTH, self.entrance)
        reached = flood(walk, start)
        return all(t in reached for t in walk)

    def _group_centres(self):
        centres = {}
        for prop in self.props:
            if prop.get("group") and prop["group"] not in ("light",):
                centres.setdefault(prop["group"], (int(prop["pos"][0] // T), int(prop["pos"][1] // T)))
        return list(centres.values())

    def _group_count(self):
        """Decoration groups: props of one plan cell or automatic group, clusters of neighbouring
        cells counted once (a coffin pair is one group)."""
        tiles = {}
        for prop in self.props:
            group = prop.get("group")
            if not group or group == "light" or prop.get("scene") == "torch":
                continue
            tiles.setdefault(group, (int(prop["pos"][0] // T), int(prop["pos"][1] // T)))
        groups = list(tiles.values())
        seen, clusters = set(), 0
        for tile in groups:
            if tile in seen:
                continue
            clusters += 1
            stack = [tile]
            while stack:
                t = stack.pop()
                if t in seen:
                    continue
                seen.add(t)
                stack.extend(o for o in groups if o not in seen and chebyshev(o, t) <= 1)
        return clusters

    # --- checks ---

    def _check_layout(self):
        walk = self.walk_floor()
        floor_count = len(walk - self.water)
        start = self.inside_tile(SOUTH, self.entrance)
        # Every floor tile reachable on foot, solid props and sources counted as blocked.
        sources = {s["floor_tile"] for s in self.sources if s["wall_side"] < 0}
        open_floor = walk - self.blocked - sources
        reached = flood(open_floor | set(self._all_corridors()), start)
        cut_off = sorted(t for t in open_floor if t not in reached)
        if cut_off:
            self.fail(f"floor cut off from the entrance (solid props and sources blocked): {cut_off[:6]}")
        for side, place in self.door_slots():
            if self.inside_tile(side, place) not in reached:
                self.fail(f"door {('N', 'E', 'S', 'W')[side]}{place} not reachable")
            for tile in self.lane(side, place, DOOR_LANE_ROWS):
                if tile in self.blocked or tile in sources:
                    self.fail(f"door {('N', 'E', 'S', 'W')[side]}{place}: something solid at {tile} in its lane")
        for s in self.sources:
            if s["wall_side"] >= 0 and s["floor_tile"] not in reached:
                self.fail(f"{s['kind']} at {s['tile']}: the floor in front of it is not reachable")
        for o in self.objectives:
            if o["tile"] not in walk:
                self.fail(f"{o['kind']} at {o['tile']} not on floor")
        if self.player_start and self.player_start not in reached:
            self.fail(f"player start {self.player_start} not reachable")
        # No decoration in the only way.
        cut = articulation_points(walk)
        for prop in self.props:
            if prop.get("scene") == "torch" or prop.get("deco") in ("wall_niche", "chains", "cobweb") or prop.get("group") in (None, "light"):
                continue
            tile = (int(prop["pos"][0] // T), int((prop["pos"][1] - 1) // T))
            for t in prop.get("blocked", [tile]):
                if t in cut:
                    self.fail(f"{prop.get('deco') or prop.get('scene')} at {t} stands in the only way")
        for s in self.sources:
            if s["wall_side"] < 0 and s["tile"] in cut:
                self.fail(f"{s['kind']} at {s['tile']} stands in the only way")
        # Spike traps only with a reason.
        exit_path = set(bfs_path(walk - self.blocked, start, self.inside_tile(NORTH, self.north[0])))
        for prop in self.props:
            if not prop.get("trap"):
                continue
            tile = (int(prop["pos"][0] // T), int(prop["pos"][1] // T))
            side_passage = tile not in exit_path and sum(n in walk for n in neighbours4(tile)) <= 2
            if not prop.get("chest") and not side_passage:
                self.fail(f"trap at {tile} without a reason (no chest within {TRAP_CHEST_DISTANCE}, not in a side passage)")
        groups = self._group_count()
        if groups > max(1, floor_count // GROUP_TILES):
            self.fail(f"{groups} decoration groups on {floor_count} floor tiles (max one per {GROUP_TILES})")
        self.floor_count = floor_count
        self.group_total = groups

    def _all_corridors(self):
        tiles = []
        for side, place in self.door_slots():
            tiles += self.corridor(side, place)
        return tiles

    # --- markers ---

    def size_class(self):
        if self.plan.size_class:
            return self.plan.size_class
        area = self.size[0] * self.size[1]
        for name, limit in SIZE_LIMITS:
            if area <= limit:
                return name
        return "L"

    def _place_spawns(self):
        walk = self.walk_floor()
        reached_floor = walk - self.blocked
        entrances = [self.inside_tile(s, p) for s, p in self.door_slots() if s != NORTH]
        exits = [self.inside_tile(s, p) for s, p in self.door_slots() if s != SOUTH]
        lanes = set()
        for side, place in self.door_slots():
            lanes.update(self.lane(side, place, DOOR_LANE_ROWS))

        def allowed(tile):
            return (tile in reached_floor and tile not in self.bridges and tile not in lanes
                    and all(chebyshev(tile, e) > ENTRANCE_CLEARANCE for e in entrances)
                    and all(chebyshev(tile, e) > EXIT_CLEARANCE for e in exits))

        if self.plan.role == "combat":
            count = (ARENA_SPAWN_COUNT if self.plan.kind == "arena" else SPAWN_COUNT)[self.size_class()]
        else:
            count = BASE_SPAWNS
        seeds = []
        for s in self.sources:
            tile = s["floor_tile"]
            if allowed(tile) and tile not in seeds and len(seeds) < count:
                seeds.append(tile)
        taken = set(seeds)
        candidates = sorted(t for t in reached_floor if allowed(t) and t not in self.occupied and t not in taken)
        anchors = seeds + entrances
        while len(seeds) < count and candidates:
            best = max(candidates, key=lambda t: (min((t[0] - a[0]) ** 2 + (t[1] - a[1]) ** 2 for a in anchors), -t[1], -t[0]))
            seeds.append(best)
            anchors.append(best)
            candidates.remove(best)
        if self.plan.role == "combat":
            size = self.size_class()
            if not MIN_SPAWNS[size] <= len(seeds) <= MAX_SPAWNS:
                self.fail(f"size {size} needs {MIN_SPAWNS[size]}-{MAX_SPAWNS} spawn markers (D-086), found room for {len(seeds)}")
        elif len(seeds) != BASE_SPAWNS:
            self.fail(f"needs exactly {BASE_SPAWNS} spawn markers, found room for {len(seeds)}")
        self.spawns = seeds

    def _place_anchors(self):
        w, h = self.size
        free = sorted(self.walk_floor() - self.blocked - set(self.occupied) - self.bridges)

        def nearest(target):
            return min(free, key=lambda t: ((t[0] + 0.5 - target[0]) ** 2 + (t[1] + 0.5 - target[1]) ** 2, t[1], t[0]))

        def first(kinds):
            for kind in kinds:
                for o in self.objectives:
                    if o["kind"] == kind:
                        return o["tile"]
            return None

        role = self.plan.role
        content = None
        if role == "boss":
            content = first(["boss"])
        elif role == "rest":
            content = first(["counter", "merchant", "weapon_rack", "fountain", "upgrade_altar", "pact_altar", "wager_altar"])
        elif role == "campfire":
            content = first(["campfire"])
        else:
            content = first(["soul_flame", "boss"])
        if content is None:
            content = nearest((w / 2, h / 2))
        portal = first(["exit_portal"]) or nearest((w * 0.75, 2.5))
        self.content = content
        self.portal = portal
        if self.player_start is None:
            self.player_start = (self.entrance, h - 2)


# Puddle colour per biome (same as ShallowWater.BIOME_TINTS, without alpha).
WATER_TINTS = {
    "crypt": (0.75, 0.82, 1.0),
    "slime_grotto": (0.72, 1.0, 0.72),
    "shadow_realm": (0.72, 0.6, 1.0),
    "ember_forge": (1.0, 0.62, 0.42),
}

AUTO_GROUPS = {
    "crypt": [("bones", 3), ("coffin", 2), ("rubble", 2), ("camp", 1), ("drip", 1)],
    "slime_grotto": [("mushrooms", 3), ("drip", 3), ("crystals", 2), ("rubble", 1)],
    "shadow_realm": [("crystals", 3), ("bones", 2), ("rubble", 2), ("drip", 1)],
    "ember_forge": [("forge", 3), ("rubble", 3), ("camp", 2), ("bones", 1)],
}


# --- Writing ---

def write(path, text):
    global _unchanged
    if path.exists() and path.read_text(encoding="utf-8") == text:
        _unchanged += 1
        return
    _written.append(path)
    if MODE != "write":
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def base_scene():
    """room_base.tscn: what every room has (the plan scenes inherit it)."""
    markers = [(3, 2), (11, 2), (7, 3), (2, 5), (12, 5)]
    spawn_nodes = "".join(
        f'\n[node name="Spawn{i + 1}" type="Marker2D" parent="SpawnPoints"]\nposition = {vec2(*centre((x, y)))}\n'
        for i, (x, y) in enumerate(markers))
    write(ROOMS / "room_base.tscn", f'''[gd_scene format=3]

[ext_resource type="Script" path="res://dungeon/rooms/room_controller.gd" id="1_room"]
[ext_resource type="Script" path="res://dungeon/rooms/room_tiles.gd" id="2_tiles"]
[ext_resource type="TileSet" path="res://dungeon/environment/dungeon_tileset.tres" id="3_tileset"]
[ext_resource type="Script" path="res://dungeon/spawning/enemy_spawner.gd" id="4_spawner"]
[ext_resource type="Script" path="res://enemies/enemy_data.gd" id="5_enemy_data"]
[ext_resource type="Resource" path="res://enemies/data/slime.tres" id="6_slime"]
[ext_resource type="Resource" path="res://enemies/data/skeleton.tres" id="7_skeleton"]
[ext_resource type="Resource" path="res://enemies/data/archer.tres" id="8_archer"]
[ext_resource type="Resource" path="res://enemies/data/boss_bone_king.tres" id="9_boss"]
[ext_resource type="Resource" path="res://enemies/data/boss_slime_queen.tres" id="10_boss2"]
[ext_resource type="Resource" path="res://enemies/data/boss_shadow_lord.tres" id="11_boss3"]
[ext_resource type="Resource" path="res://enemies/data/shadow.tres" id="12_shadow"]
[ext_resource type="Resource" path="res://enemies/data/bomber.tres" id="13_bomber"]
[ext_resource type="Resource" path="res://enemies/data/boss_ember_golem.tres" id="14_boss4"]
[ext_resource type="Script" path="res://dungeon/biome_data.gd" id="15_biome"]
[ext_resource type="Resource" path="res://dungeon/biomes/crypt.tres" id="16_crypt"]
[ext_resource type="Resource" path="res://dungeon/biomes/slime_grotto.tres" id="17_grotto"]
[ext_resource type="Resource" path="res://dungeon/biomes/shadow_realm.tres" id="18_shadow"]
[ext_resource type="Resource" path="res://dungeon/biomes/ember_forge.tres" id="19_ember"]

[node name="Room" type="Node2D"]
y_sort_enabled = true
script = ExtResource("1_room")

[node name="Tiles" type="TileMapLayer" parent="."]
z_index = -10
scale = Vector2(2, 2)
tile_set = ExtResource("3_tileset")
script = ExtResource("2_tiles")
room_size = Vector2i(15, 9)
entrance_x = 7
exit_x = 7

[node name="Props" type="Node2D" parent="."]
y_sort_enabled = true

[node name="SpawnPoints" type="Node2D" parent="."]
{spawn_nodes}
[node name="EnemyContainer" type="Node2D" parent="."]
y_sort_enabled = true

[node name="ContentAnchor" type="Marker2D" parent="."]
position = Vector2({7.5 * T:g}, {3.5 * T:g})

[node name="PortalAnchor" type="Marker2D" parent="."]
position = Vector2({11.5 * T:g}, {3 * T:g})

[node name="EnterTrigger" type="Area2D" parent="."]
monitorable = false

[node name="EnemySpawner" type="Node" parent="."]
script = ExtResource("4_spawner")
enemy_types = Array[ExtResource("5_enemy_data")]([ExtResource("6_slime"), ExtResource("7_skeleton"), ExtResource("8_archer")])
spawn_weights = Array[float]([0.5, 0.35, 0.15])
extra_types = Array[ExtResource("5_enemy_data")]([ExtResource("12_shadow"), ExtResource("13_bomber")])
bosses = Array[ExtResource("5_enemy_data")]([ExtResource("9_boss"), ExtResource("10_boss2"), ExtResource("11_boss3"), ExtResource("14_boss4")])
escort_minion = ExtResource("6_slime")
biomes = Array[ExtResource("15_biome")]([ExtResource("16_crypt"), ExtResource("17_grotto"), ExtResource("18_shadow"), ExtResource("19_ember")])
''')


def out_path(room):
    plan = room.plan
    if plan.scene and room.id == plan.variants()[0][0]:
        return plan.scene
    folder = {"combat": "combat", "fixture": "combat", "boss": "boss", "miniboss": "boss", "rest": "rest", "campfire": "campfire"}[plan.role]
    return f"{folder}/{room.id}.tscn"


def root_name(room_id):
    return "".join(part.capitalize() for part in room_id.split("_"))


def write_scene(room, rel_path):
    plan = room.plan
    scenes = sorted({p["scene"] for p in room.props if "scene" in p})
    ids = {s: f"{i + 2}_{s}" for i, s in enumerate(scenes)}
    deco_id = f"{len(scenes) + 2}_deco"
    scatter_id = f"{len(scenes) + 3}_scatter"
    uses_deco = any("deco" in p for p in room.props)
    text = '[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="res://dungeon/rooms/room_base.tscn" id="1_base"]\n'
    for s in scenes:
        text += f'[ext_resource type="PackedScene" path="{SCENES[s]}" id="{ids[s]}"]\n'
    if uses_deco:
        text += f'[ext_resource type="Script" path="{DECO_SCRIPT}" id="{deco_id}"]\n'
    if plan.role == "combat":
        text += f'[ext_resource type="Script" path="{SCATTER_SCRIPT}" id="{scatter_id}"]\n'
    text += f'\n[node name="{root_name(room.id)}" instance=ExtResource("1_base")]\n'
    if plan.role in ("combat", "fixture"):
        text += f"room_kind = {KINDS[plan.kind]}\nroom_size_class = {SIZES[room.size_class()]}\n"
    w, h = room.size
    text += '\n[node name="Tiles" parent="."]\n'
    text += f"room_size = Vector2i({w}, {h})\nentrance_x = {room.entrance}\nexit_x = {room.north[0]}\nfloor_seed = {room.seed}\n"
    walls = to_rects(room.walls)
    if walls:
        text += f"wall_rects = {rect_list(walls)}\n"
    if room.pits:
        text += f"pit_rects = {rect_list(to_rects(room.pits))}\n"
    if room.bridges:
        text += f"bridge_rects = {rect_list(to_rects(room.bridges))}\n"
    if room.water:
        text += f"water_rects = {rect_list(to_rects(room.water))}\n"
    if room.moss:
        text += f"moss_tiles = {vec2i_list(sorted(room.moss))}\n"
    slots = room.door_slots()
    text += f"door_slots = {vec2i_list(slots)}\n"
    cracks = sorted(t for t, c in room.fixtures.items() if c == "q")
    if cracks:
        text += f"secret_cracks = {vec2i_list(cracks)}\n"
    fixtures = sorted(t for t, c in room.fixtures.items() if c != "q")
    if fixtures:
        text += f"front_fixtures = {vec2i_list(fixtures)}\n"
    for i, tile in enumerate(room.spawns):
        node_type = ' type="Marker2D"' if i >= BASE_SPAWNS else ""
        text += f'\n[node name="Spawn{i + 1}"{node_type} parent="SpawnPoints"]\nposition = {vec2(*centre(tile))}\n'
    for i in range(len(room.spawns), BASE_SPAWNS):
        # room_base has five markers; a template never has fewer (checked), nothing to remove.
        pass
    text += f'\n[node name="ContentAnchor" parent="."]\nposition = {vec2(*centre(room.content))}\n'
    text += f'\n[node name="PortalAnchor" parent="."]\nposition = {vec2(*centre(room.portal))}\n'
    text += f'\n[node name="PlayerStart" type="Marker2D" parent="."]\nposition = {vec2(*centre(room.player_start))}\n'
    if room.sources:
        text += '\n[node name="Sources" type="Node2D" parent="."]\n'
    if room.objectives:
        text += '\n[node name="Objectives" type="Node2D" parent="."]\n'
    for i, s in enumerate(room.sources):
        pos = centre(s["tile"])
        text += f'\n[node name="Source{i + 1}" type="Marker2D" parent="Sources"]\nposition = {vec2(*pos)}\n'
        text += f'metadata/source_kind = &"{s["kind"]}"\nmetadata/tile = Vector2i({s["tile"][0]}, {s["tile"][1]})\n'
        text += f'metadata/floor_tile = Vector2i({s["floor_tile"][0]}, {s["floor_tile"][1]})\nmetadata/wall_side = {s["wall_side"]}\n'
    counts = {}
    for o in room.objectives:
        name = root_name(o["kind"])
        counts[name] = counts.get(name, 0) + 1
        text += f'\n[node name="{name}{counts[name]}" type="Marker2D" parent="Objectives"]\nposition = {vec2(*centre(o["tile"]))}\n'
        text += f'metadata/objective_kind = &"{o["kind"]}"\nmetadata/tile = Vector2i({o["tile"][0]}, {o["tile"][1]})\n'
        if o["enemy"]:
            text += f'metadata/enemy = &"{o["enemy"]}"\n'
        if o["built"]:
            text += "metadata/built = true\n"
    counts = {}
    for p in room.props:
        name = p["name"]
        counts[name] = counts.get(name, 0) + 1
        node = f"{name}{counts[name]}"
        if "scene" in p:
            text += f'\n[node name="{node}" parent="Props" instance=ExtResource("{ids[p["scene"]]}")]\nposition = {vec2(*p["pos"])}\n'
            if p.get("tint"):
                text += f"modulate = {color(p['tint'])}\n"
            if p.get("min_room"):
                text += f"metadata/min_room = {p['min_room']}\n"
        else:
            text += f'\n[node name="{node}" type="Node2D" parent="Props"]\nposition = {vec2(*p["pos"])}\nscript = ExtResource("{deco_id}")\n'
            text += f'item = &"{p["deco"]}"\n'
            if p.get("flip"):
                text += "flip = true\n"
            if p.get("tint"):
                text += f"tint = {color(p['tint'])}\n"
            if p.get("blocked"):
                text += f"blocked_tiles = {vec2i_list(p['blocked'])}\n"
            if "still" in p:
                text += f"still_frame = {p['still']}\n"
    if plan.role == "combat":
        # The scatter keeps its one dungeon RNG draw per room but places nothing (R1: no random props).
        text += f'\n[node name="Ingredients" type="Node2D" parent="."]\ny_sort_enabled = true\nscript = ExtResource("{scatter_id}")\n'
        text += "allowed = Array[int]([])\n"
    write(ROOMS / rel_path, text)


def write_template(room, rel_path):
    plan = room.plan
    slots = room.door_slots()
    text = '[gd_resource type="Resource" script_class="RoomTemplate" format=3]\n\n'
    text += f'[ext_resource type="Script" path="{TEMPLATE_SCRIPT}" id="1_template"]\n'
    text += f'[ext_resource type="PackedScene" path="res://dungeon/rooms/{rel_path}" id="2_scene"]\n\n'
    text += '[resource]\nscript = ExtResource("1_template")\n'
    text += f'id = &"{room.id}"\nscene = ExtResource("2_scene")\n'
    kind = KINDS[plan.kind] if plan.role in ("combat", "fixture") else 0
    text += f"room_kind = {kind}\nshape = {SHAPE_PLAN}\nsize_class = {SIZES[room.size_class()]}\n"
    text += f"room_size = Vector2i({room.size[0]}, {room.size[1]})\n"
    exit_sides = [side for side in (NORTH, EAST, WEST) if any(s == side for s, _ in slots)]
    entrance_sides = [side for side in (SOUTH, EAST, WEST) if any(s == side for s, _ in slots)]
    text += f"entrance_side = {SOUTH}\nexit_sides = Array[int]([{', '.join(str(x) for x in exit_sides)}])\n"
    text += f"entrance_sides = Array[int]([{', '.join(str(x) for x in entrance_sides)}])\n"
    text += f"door_slots = {vec2i_list(slots)}\n"
    text += f"spawn_tiles = {vec2i_list(room.spawns)}\n"
    chests = [t for c, t in room.items if c == "c"]
    if chests:
        text += f"chest_tile = Vector2i({chests[0][0]}, {chests[0][1]})\n"
    text += f'allowed_biomes = Array[StringName]([&"{room.biome}"])\n'
    if plan.min_room != 1:
        text += f"min_room = {plan.min_room}\n"
    text += f'plan_id = &"{plan.id}"\nmode = &"{plan.mode}"\nrole = &"{plan.role}"\nweight = {fmt(float(plan.weight))}\n'
    if plan.special:
        text += f"special_types = Array[int]([{', '.join(str(s) for s in plan.special)}])\n"
    if room.mirrored:
        text += "mirrored = true\n"
    write(TEMPLATES / f"{room.id}.tres", text)


def write_catalog(path, ids):
    text = '[gd_resource type="Resource" script_class="RoomCatalog" format=3]\n\n'
    text += '[ext_resource type="Script" path="res://dungeon/rooms/room_catalog.gd" id="1_catalog"]\n'
    text += f'[ext_resource type="Script" path="{TEMPLATE_SCRIPT}" id="2_template"]\n'
    for i, room_id in enumerate(ids):
        text += f'[ext_resource type="Resource" path="res://dungeon/rooms/templates/{room_id}.tres" id="{i + 3}_{room_id}"]\n'
    entries = ", ".join(f'ExtResource("{i + 3}_{room_id}")' for i, room_id in enumerate(ids))
    text += f'\n[resource]\nscript = ExtResource("1_catalog")\nentries = Array[ExtResource("2_template")]([{entries}])\n'
    write(path, text)


def remove_stale(produced):
    """Old generated scenes and templates no plan makes any more (A3/A4 shapes, chasm rooms)."""
    stale = []
    for folder, pattern in ((ROOMS / "combat", "*.tscn"), (TEMPLATES, "*.tres"), (ROOMS / "rest", "*.tscn"), (ROOMS / "boss", "*.tscn")):
        if not folder.exists():
            continue
        for path in folder.glob(pattern):
            if path.resolve() not in produced:
                stale.append(path)
    for path in stale:
        print("  removed (no plan makes it):", path.relative_to(ROOT).as_posix())
        if MODE == "write":
            path.unlink()
            for extra in (path.with_suffix(path.suffix + ".import"),):
                if extra.exists():
                    extra.unlink()
    return stale


def load_plans():
    plans = []
    for path in sorted(PLANS.rglob("*.txt")):
        plans.append(Plan(path))
    ids = {}
    for plan in plans:
        for out_id, _, _ in plan.variants():
            if out_id in ids:
                raise PlanError(f"template id {out_id} made by {ids[out_id]} and {plan.path.name}")
            ids[out_id] = plan.path.name
    return plans


def main():
    global MODE
    args = sys.argv[1:]
    if "--check" in args:
        MODE = "check"
    plans = load_plans()
    if "--list" in args:
        for plan in plans:
            print(f"{plan.path.relative_to(PLANS).as_posix():40} {plan.role:9} {plan.mode:9} {', '.join(v[0] for v in plan.variants())}")
        return
    base_scene()
    combat_ids, plan_ids, produced, problems = [], [], set(), []
    stats = {}
    for plan in plans:
        for out_id, biome, mirrored in plan.variants():
            try:
                room = Room(plan, out_id, biome, mirrored).build()
            except PlanError as error:
                problems.append(str(error))
                continue
            rel_path = out_path(room)
            write_scene(room, rel_path)
            produced.add((ROOMS / rel_path).resolve())
            if plan.role == "fixture":
                continue
            write_template(room, rel_path)
            produced.add((TEMPLATES / f"{room.id}.tres").resolve())
            (combat_ids if plan.role == "combat" else plan_ids).append(room.id)
            key = (plan.role, plan.mode, biome)
            stats[key] = stats.get(key, 0) + 1
    if problems:
        print(f"{len(problems)} broken plan(s):")
        for problem in problems:
            print("  -", problem)
        sys.exit(1)
    write_catalog(COMBAT_CATALOG, combat_ids)
    write_catalog(PLAN_CATALOG, plan_ids)
    produced.add(COMBAT_CATALOG.resolve())
    remove_stale(produced)
    print(f"{len(plans)} plans -> {len(combat_ids)} combat templates, {len(plan_ids)} other templates "
          f"({len(_written)} files {'written' if MODE == 'write' else 'would change'}, {_unchanged} unchanged)")
    for role in ROLES:
        rows = sorted((k, v) for k, v in stats.items() if k[0] == role)
        if rows:
            print(f"  {role}: " + ", ".join(f"{mode}/{biome} {count}" for (_, mode, biome), count in rows))


if __name__ == "__main__":
    main()
