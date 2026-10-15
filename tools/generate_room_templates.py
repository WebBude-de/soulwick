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
    exit: 2                       which N of the north front row (left to right) is the exit; the
                                  others are branch places (default 1, the first)
    special: shop, weapon         rest rooms: the special types the plan is made for
    scene: combat/combat_hall.tscn  fixed output path (legacy names other files load)
    auto_deco: no                 no decoration groups added by the generator
    rock: blob                    blob = cave rock (RockTerrain, M1), wall = masonry (WallAutotile);
                                  default blob for combat plans, wall for every other role
    cave: yes                     a cave mouth instead of an arch at the doors (M2 builds it);
                                  default yes for rock: blob
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
  zones       ;  slab (way, middle)   ,  cobble (old paths)   :  dirt (edges, bays)
              %  rubble (under collapses)   - floor with a zone look (Makeover 2, M1)
  height      ^  plateau   L  ladder   &  stairs cut into a cliff - prepared for M3: built as rock
              until then, the tiles are kept as metadata (plateau_tiles, ladder_tiles, stair_tiles)
  sources     G  grave    s  sarcophagus    p  puddle    i  floor rift    v  lava vent
              (floor sources follow the biome of the template: G in the crypt, p in the grotto,
              i in the shadow realm, v in the ember forge; s stays a sarcophagus in the crypt)
  objectives  1 escort figure  f soul flame  A relic altar  R relic  * soul  e escape hole
              X collapse field  C light crystal  B brazier  t torch stand  u torch stand (off)
              M stone guardian  9 the crowned one  0 boss  h merchant  H counter (2 tiles)
              Q fountain  U upgrade altar  Y pact altar  V wager altar  J campfire  O exit portal
              l log  z bedroll  j* weapon rack    2 slime  3 skeleton  4 archer  5 shadow  6 golem (guards)
  decoration  c chest  r rubble  b barrel  a* crate  F* explosive barrel  k bones  o coffin
              P fallen pillar (2 tiles)  K offering site  d drip  + spike trap
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
  - the floor tile in front of a cracked wall ('q') stays free (no prop, no spawn marker, no group):
    the secret niche needs it; an explosive barrel ('F') right beside it opens the wall without a
    bomber, staff or hammer (its blast reaches the front from the row below it, one column aside);
  - at most one decoration group per 20 floor tiles; groups at walls and corners;
  - spawn markers: count per size (D-086, S >= 5, M >= 8, L >= 12, at most 14), on free reachable
    floor, away from every entrance.

Cave plans (rock: blob, M1, Makeover 2/3) besides:
  - no rectangle: at least CAVE_MIN_CONCAVE concave corners in the outline (two bays or ledges);
  - a rock block, plateau or abyss inside the floor, not joined to the outline;
  - no straight outline edge longer than CAVE_MAX_EDGE tiles (doors break an edge);
  - floor (without water and abyss) at most CAVE_FLOOR_SHARE of the plan grid;
  - single-player cave plans between 17x11 and 23x13 cells (L plans for groups are larger).
What the generator adds (fixed per template from its id, no dungeon RNG):
  - floor zones as frayed patches of 4-12 tiles (dirt in bays, slab on the way, cobble on an old
    path, rubble under fallen things) where the plan draws few itself (cave plans);
  - scatter overlays (crack, pebbles, tuft, bones, puddle, dust): 30-50 % of the floor at walls
    and in corners, 5-8 % in the open, never under objects, randomly mirrored (every plan);
  - moving points (drips, faint fog) until a room has two or three (torches, braziers, drips and
    water count);
  - decoration until one object or group per CAVE_OBJECT_TILES floor tiles (cave plans), within the
    group limit above.
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
# RoomSequence.RoomKind / RoomSize / RoomTemplate.Shape.PLAN / RoomTiles.DoorSide. Plans are normal or
# arena rooms; RoomKind.CHASM (2) is no room kind of a plan since D-120 (abysses are plan cells).
KINDS = {"normal": 0, "arena": 1}
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
# A plan with enemy sources has at least this many for normal enemies (sarcophagi serve elites; a
# plan with sarcophagi only falls back to its spawn points): a push comes out of several sources and
# never all of them, and one of them may lie too close to the player (R2, SpawnSourceRules).
MIN_PLAN_SOURCES = 3
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
# Two special rooms behind two north doors only fit side by side from 8 columns apart (R5,
# DungeonManager._ways_fit), so plans put their own branch places near the side walls.
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
DECO_CELLS = set("crbaFkoPKd+DZm")
TWO_TILE = {"P", "H"}
# Decoration that blocks walking (and the tile under it).
SOLID_DECO = set("crbaFoPDZ")
# Floor zones (M1) -> RockTerrain.Zone; height markers (prepared for M3, built as rock).
ZONE_CELLS = {";": 0, ",": 1, ":": 2, "%": 3}
ZONE_SLAB, ZONE_COBBLE, ZONE_DIRT, ZONE_RUBBLE = 0, 1, 2, 3
HEIGHT_CELLS = {"^": "plateau", "L": "ladder", "&": "stairs"}
# RoomTiles.RockStyle.
ROCK_STYLES = {"wall": 0, "blob": 1}

# --- Cave rules (M1, Makeover 2/3; TESTWERTE where they are numbers of the design) ---
# Concave corners of the outline a cave needs (a rectangle has none; a bay or ledge brings two).
CAVE_MIN_CONCAVE = 4
# Longest straight outline edge (tiles).
CAVE_MAX_EDGE = 8
# Floor share of the plan grid (water and abyss are no floor).
CAVE_FLOOR_SHARE = 0.6
# Grid size of single-player cave plans (cells, ring included): 17x11 up to 23x13 (§9, camera 1.25x).
CAVE_MIN_GRID = (17, 11)
CAVE_MAX_GRID = (23, 13)
# Size class of a cave plan from its floor (walkable, no water): up to this many tiles S, else M.
CAVE_S_FLOOR = 90
# One object or decoration group per this many floor tiles (§9).
CAVE_OBJECT_TILES = 12
# Zones: patches of 4-12 tiles; the generator adds patches while the plan's own zones cover less
# than this share of the floor.
ZONE_PATCH = (4, 12)
ZONE_SHARE = 0.18
# Overlays (Makeover 2, playtest 14.10.2026: only as a border): chance at walls and in corners / in
# the open floor (none); weights per biome over RockTerrain.Overlay (crack, pebbles, tuft, bones,
# puddle, dust).
OVERLAY_WALL_CHANCE = 0.32
OVERLAY_OPEN_CHANCE = 0.0
OVERLAY_WEIGHTS = {
    "crypt": (3, 3, 1, 1, 0, 3),
    "slime_grotto": (1, 3, 4, 0, 2, 1),
    "shadow_realm": (3, 3, 1, 1, 0, 3),
    "ember_forge": (3, 3, 0, 1, 0, 3),
}
OVERLAY_FLIP = 8
# Moving points per room (drips, fog, torches, braziers, water): at least / at most added.
MOVING_MIN = 2
MOVING_MAX = 3

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
        self.exit_index = int(h.get("exit", "1"))
        self.scene = h.get("scene", "")
        self.special = [SPECIAL_TYPES[s.strip()] for s in h.get("special", "").split(",") if s.strip()]
        self.auto_deco = h.get("auto_deco", "yes" if self.role in ("combat", "boss", "miniboss") else "no").lower() in ("yes", "true", "1")
        self.size_class = h.get("class", "")
        self.rock = h.get("rock", "blob" if self.role == "combat" else "wall").lower()
        self.cave = h.get("cave", "yes" if self.rock == "blob" else "no").lower() in ("yes", "true", "1")
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
        if self.rock not in ROCK_STYLES:
            raise PlanError(f"{name}: rock must be blob or wall")

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


def vec3i_list(cells):
    return "Array[Vector3i]([" + ", ".join(f"Vector3i({x}, {y}, {z})" for x, y, z in cells) + "])"


def rect_list(rects):
    return "Array[Rect2i]([" + ", ".join(f"Rect2i({x}, {y}, {w}, {h})" for x, y, w, h in rects) + "])"


def color(c):
    return f"Color({fmt(float(c[0]))}, {fmt(float(c[1]))}, {fmt(float(c[2]))}, 1)"


def centre(tile):
    return ((tile[0] + 0.5) * T, (tile[1] + 0.5) * T)


def base(tile):
    """Base line of a standing prop on a tile (same spot as IngredientScatter._base_of)."""
    return ((tile[0] + 0.5) * T, (tile[1] + 1) * T - 8)


# --- What things look like (M1: nothing overlaps, everything on floor) ---

# Visible extent of every decoration item and prop scene around its origin in world px (left, top,
# right, bottom): the alpha bounds of the delivered art at its draw scale, measured 14.10.2026 from
# the files DecoProp / the scenes use (flip mirrors x); test_room_terrain measures the real nodes.
# Update when art changes. Things keep OVERLAP_MARGIN px apart (rounding of the art).
VISIBLE = {
    "coffin": (-18, -66, 24, 2),
    "pillar_fallen": (-62, -34, 64, 4),
    "candles": (-28, -38, 28, 4),
    "drip": (-6, -62, 6, 2),
    "puddle": (-24, -14, 24, 18),
    "wall_niche": (-22, -92, 22, -8),
    "wall_niche_soft": (-32, -94, 32, 2),
    "group_1": (-54, -60, 52, 2),
    "group_2": (-58, -72, 60, 2),
    "group_3": (-60, -52, 60, 0),
    "group_large_1": (-92, -60, 92, 2),
    "group_large_2": (-92, -72, 92, 2),
    "chains": (-18, -62, 22, 2),
    "bones_1": (-24, -10, 28, 12),
    "bones_2": (-26, -20, 26, 14),
    "bone_pile": (-28, -30, 30, 4),
    "cobweb": (0, 0, 58, 58),
    "rubble_1": (-19, -13, 21, 6),
    "rubble_2": (-18, -14, 20, 5),
    "gravestone": (-24, -38, 24, 2),
    "mushrooms": (-26, -40, 30, -2),
    "crystal_cluster": (-22, -50, 28, -2),
    "anvil": (-30, -40, 30, -6),
    "brazier": (-20, -52, 20, 2),
    "bedroll": (-32, -18, 32, 6),
    "log": (-32, -22, 30, 2),
    "pack": (-16, -26, 16, 0),
    "torch_stand_unlit": (-12, -64, 12, 2),
    "mist": (-70, -36, 72, -4),
    "light_crystal": (-22, -52, 22, 2),
    "torch_stand": (-12, -78, 12, 2),
    "scene:crate": (-26, -48, 26, 0),
    "scene:barrel": (-22, -52, 22, 2),
    "scene:explosive": (-22, -52, 22, 2),
    "scene:chest": (-24, -38, 24, 2),
    "scene:rubble": (-32, -28, 30, 2),
    "scene:spike_trap": (-28, -28, 28, 28),
    "scene:lava_crack": (-30, -24, 32, 28),
    "scene:toxic_puddle": (-36, -15, 36, 33),
    "scene:torch": (26, 14, 38, 58),
}
# Draw layer per item (DecoProp.Layer): floor decals lie fully on floor, standing things stand on it
# with their foot, wall things hang in a front.
ITEM_LAYER = {
    "candles": "floor", "drip": "floor", "puddle": "floor", "bones_1": "floor", "bones_2": "floor",
    "bone_pile": "floor", "rubble_1": "floor", "rubble_2": "floor", "mushrooms": "floor", "bedroll": "floor",
    "log": "floor", "pack": "floor", "mist": "floor", "stairs": "floor", "wall_niche": "wall", "wall_niche_soft": "wall", "chains": "wall",
    "cobweb": "wall", "scene:torch": "wall", "scene:spike_trap": "floor", "scene:lava_crack": "floor",
    "scene:toxic_puddle": "floor",
}
SOLID_SCENES = {"crate", "barrel", "explosive", "chest", "rubble"}
OVERLAP_MARGIN = 2
# Wall things whose art ends below their pivot (chains) hang this many px higher, so they end on the
# front and not in the floor under it (look).
WALL_ITEM_LIFT = 4
# Objectives that are markers only (enemies, souls, collapse fields, the escort's start): no thing of
# their own in the template, not spaced.
MARKER_OBJECTIVES = {"merchant", "guard", "soul", "collapse_field", "escort_start", "crowned", "stone_guardian", "boss", "log", "bedroll", "relic"}
# Fixed objects keep this Chebyshev distance (2 = one free tile between them).
OBJECT_SPACING = 2
# Caves: at most one composed decoration group per this many floor tiles (playtest: fewer, larger).
CAVE_GROUP_TILES = 28
# Overlays at decoration groups (their border).
OVERLAY_GROUP_CHANCE = 0.55

# Decoration groups drawn as one picture per biome (SPRITES_V9 §3, deco_group_<biome>_1..3 64x48 and
# deco_group_large_<biome>_1..2 96x64, pivot bottom middle): small ones stand on two floor tiles,
# large ones on three, side by side; the footprint blocks walking. Share of large ones (TESTWERT).
GROUP_ART_DIR = ROOT / "art" / "environment" / "deco"
GROUP_LARGE_CHANCE = 0.4


def has_group_art(biome):
    return all((GROUP_ART_DIR / f"deco_group_{biome}_{n}.png").exists() for n in (1, 2, 3))


# Composed decoration groups (the fallback from delivered parts where a biome has no group art):
# a solid piece on the anchor tile (optional), loose pieces packed around it without overlap, wall
# pieces in the front above (chains). Weights per biome (TESTWERTE).
COMPOSITES = {
    "shrine": [dict(deco="coffin", name="Coffin", solid=True), dict(deco="candles", name="Candles"), dict(deco="bones_1", name="Bones")],
    "ossuary": [dict(deco="bone_pile", name="Bones"), dict(deco="bones_2", name="Bones"), dict(deco="bones_1", name="Bones")],
    "collapse": [dict(deco="rubble_1", name="RubbleBit"), dict(deco="rubble_2", name="RubbleBit"), dict(deco="rubble_1", name="RubbleBit"), dict(deco="bones_2", name="Bones")],
    "mushroom_bed": [dict(deco="crystal_cluster", name="Crystals", solid=True), dict(deco="mushrooms", name="Mushrooms"), dict(deco="mushrooms", name="Mushrooms"), dict(deco="rubble_2", name="RubbleBit")],
    "crystals": [dict(deco="crystal_cluster", name="Crystals", solid=True), dict(deco="rubble_2", name="RubbleBit"), dict(deco="rubble_1", name="RubbleBit")],
    "forge": [dict(deco="anvil", name="Anvil", solid=True), dict(deco="rubble_1", name="RubbleBit"), dict(deco="rubble_2", name="RubbleBit"), dict(deco="chains", name="Chains", wall=True)],
    "camp": [],
}
COMPOSITES_BY_BIOME = {
    "crypt": [("shrine", 3), ("ossuary", 2), ("collapse", 2), ("camp", 1)],
    "slime_grotto": [("mushroom_bed", 3), ("crystals", 2), ("collapse", 1)],
    "shadow_realm": [("crystals", 3), ("ossuary", 2), ("collapse", 2)],
    "ember_forge": [("forge", 3), ("collapse", 3), ("camp", 2)],
}


def item_rect(item, pos, flip=False):
    """World rect (x0, y0, x1, y1) of an item drawn at pos (None: nothing known)."""
    extent = VISIBLE.get(item)
    if extent is None:
        return None
    left, top, right, bottom = extent
    if flip and not item.startswith("scene:"):
        left, right = -right, -left
    return (pos[0] + left, pos[1] + top, pos[0] + right, pos[1] + bottom)


def prop_rect(prop):
    item = prop.get("deco") or "scene:" + str(prop.get("scene"))
    return item_rect(item, prop["pos"], prop.get("flip", False))


def prop_tile(prop):
    """Floor tile a prop stands on (its origin, nudged up from the base line)."""
    return (int(prop["pos"][0] // T), int((prop["pos"][1] - 1) // T))


def tile_rect(tile, inset=4):
    return (tile[0] * T + inset, tile[1] * T + inset, (tile[0] + 1) * T - inset, (tile[1] + 1) * T - inset)


def overlaps(a, b, margin=None):
    """Do two rects come closer than margin px (OVERLAP_MARGIN; 0 = touching is fine)?"""
    m = OVERLAP_MARGIN if margin is None else margin
    return a[0] < b[2] + m and b[0] < a[2] + m and a[1] < b[3] + m and b[1] < a[3] + m


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
        # Floor zones of the plan (tile -> zone) and the height markers kept for M3.
        self.zones = {}
        self.height = {"plateau": set(), "ladder": set(), "stairs": set()}
        self.overlays = []
        self.cave = plan.rock == "blob"
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
        # Floor in front of every cracked wall ('q'): where players stand to blow it open (kept free).
        self.secret_approaches = []
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
        # The first N of the plan (or the one the header names, "exit: 2") is the exit, the others
        # are branch places; a mirrored grid reads them the other way round, so the exit stays the
        # same door.
        if self.mirrored:
            self.north.reverse()
        if not 1 <= self.plan.exit_index <= len(self.north):
            self.fail(f"exit: {self.plan.exit_index}, but the north front row has {len(self.north)} N")
        self.north.insert(0, self.north.pop(self.plan.exit_index - 1))

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
        elif c in ZONE_CELLS:
            self.zones[tile] = ZONE_CELLS[c]
        elif c in HEIGHT_CELLS:
            # Prepared for M3: rock until plateaus, ladders and stairs are walkable.
            self.walls.add(tile)
            self.height[HEIGHT_CELLS[c]].add(tile)
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
        if self.cave:
            self._check_cave()
            self._add_zones()
        self._add_moving_points()
        self._add_overlays()
        if self.plan.role != "fixture":
            self._check_gaps()
            self._check_objects()
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
            if c == "q":
                self.secret_approaches.append(below)
            if c in WALL_SOURCES:
                self.sources.append(dict(kind=WALL_SOURCES[c], tile=tile, floor_tile=below, wall_side=NORTH))
                self._occupy([below], "source")
            elif c == "T":
                self.props.append(dict(scene="torch", name="Torch", pos=(x * T, y * T), group=None))
            elif c == "n" and self.plan.rock == "blob" and GROUP_ART_DIR.joinpath("../tiles/wall_niche_soft.png").exists():
                self.props.append(dict(deco="wall_niche_soft", name="Niche", pos=(x * T + T / 2, (y + 1) * T - WALL_ITEM_LIFT), group=None))
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
        # Sources and objectives first, then solid decoration, so loose bits pack themselves around them.
        order = sorted(self.items, key=lambda item: 0 if item[0] in FLOOR_SOURCES or item[0] in OBJECTIVES or item[0] in GUARDS else (1 if item[0] in SOLID_DECO else 2))
        for c, tile in order:
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
        self._occupy(tiles, "decoration")
        if c in SOLID_DECO and c not in "DZ":
            self.blocked.update(tiles)
        if c == "c":
            self._add_prop(dict(scene="chest", name="Chest", pos=base(tile), group=group))
        elif c == "r":
            self._add_prop(dict(scene="rubble", name="Rubble", pos=base(tile), tint=style["rubble_tint"], group=group))
        elif c == "b":
            self._add_prop(dict(scene="barrel", name="Barrel", pos=base(tile), group=group))
        elif c == "a":
            self._add_prop(dict(scene="crate", name="Crate", pos=base(tile), group=group))
        elif c == "F":
            self._add_prop(dict(scene="explosive", name="Explosive", pos=base(tile), group=group, min_room=EXPLOSIVES_FROM_ROOM))
        elif c == "k":
            self._compose(group, [tile] + [n for n in neighbours4(tile) if n not in self.occupied], [dict(deco=rng.choice(["bones_1", "bones_2", "bone_pile"]), name="Bones")])
        elif c == "o":
            self._add_prop(dict(deco="coffin", name="Coffin", pos=base(tile), flip=rng.random() < 0.5, blocked=tiles, group=group))
        elif c == "P":
            # Fallen pillar plus rubble at its broken end (02_grundrisse.md), the bits beside it.
            flip = rng.random() < 0.5
            self._add_prop(dict(deco="pillar_fallen", name="Pillar", pos=((tile[0] + 1) * T, (tile[1] + 1) * T - 8), flip=flip, blocked=tiles, group=group))
            end = tiles[0] if flip else tiles[1]
            around = [t for t in self._ring_of(tiles) if abs(t[1] - end[1]) <= 1 and abs(t[0] - end[0]) <= 1]
            self._compose(group, around, [dict(deco="rubble_1", name="RubbleBit"), dict(deco="rubble_2", name="RubbleBit")], required=False)
        elif c == "K":
            # Offering site: candles with bones beside them (no gravestone: it reads as a grave source).
            spill = [n for n in neighbours4(tile) if n not in self.occupied]
            self._compose(group, [tile] + spill, [dict(deco="candles", name="Candles"), dict(deco="bones_1", name="Bones")])
        elif c == "d":
            self._drip(tile, group)
        elif c == "+":
            near_chest = any(chebyshev(tile, chest) <= TRAP_CHEST_DISTANCE for chest in chests)
            self._add_prop(dict(scene=style["trap"], name="Trap", pos=centre(tile), tint=style["trap_tint"], group=group, trap=True, chest=near_chest))
        elif c == "D":
            self._camp(tile, group)
        elif c == "Z":
            self._guard_post(tile, group, style)
        elif c == "m":
            self.moss.add(tile)

    def _drip(self, tile, group):
        """A drip from the ceiling into its puddle (one picture: the drop falls into the puddle)."""
        cx, cy = centre(tile)
        self._add_prop(dict(deco="puddle", name="Puddle", pos=(cx, cy + 6), tint=WATER_TINTS[self.biome], group=group))
        self._add_prop(dict(deco="drip", name="Drip", pos=(cx + self.rng.randint(-4, 4), cy + 4), group=group))
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
        self._add_prop(dict(scene="crate", name="Crate", pos=base(tile), group=group))
        self._add_prop(dict(scene="barrel", name="Barrel", pos=base(second), group=group))
        self._compose(group, [second, (second[0] + step, second[1])], [dict(deco="bedroll", name="Bedroll", flip=step < 0)], required=False)

    def _guard_post(self, tile, group, style):
        self.blocked.add(tile)
        self._add_prop(dict(deco="torch_stand", name="TorchStand", pos=base(tile), tint=style["light_color"], blocked=[tile], group=group))
        self._compose(group, self._ring_of([tile]), [dict(deco="rubble_2", name="RubbleBit"), dict(deco="bones_2", name="Bones")], required=False)

    # --- decoration layout (M1: nothing overlaps, everything on floor) ---

    def _add_prop(self, prop):
        self.props.append(prop)
        return prop

    def _ring_of(self, tiles):
        """Floor tiles around tiles (8 neighbours), without them."""
        floor = self.walk_floor() - self.pits
        ring = set()
        for x, y in tiles:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    t = (x + dx, y + dy)
                    if t in floor and t not in tiles:
                        ring.add(t)
        return sorted(ring)

    def _taken_rects(self, skip_group=None):
        rects = []
        for prop in self.props:
            if skip_group is not None and prop.get("group") == skip_group:
                continue
            rect = prop_rect(prop)
            if rect:
                rects.append(rect)
        for s in self.sources:
            rects.append(tile_rect(s["tile"]))
        for o in self.objectives:
            if o["kind"] in MARKER_OBJECTIVES:
                continue
            rects.append(tile_rect(o["tile"]))
        return rects

    def _rect_on_ground(self, item, rect):
        """Floor decals lie fully on plain floor; standing things stand with their foot on it."""
        ground = self.walk_floor() - self.pits - self.bridges
        layer = ITEM_LAYER.get(item, "standing")
        if layer == "wall":
            return self._rect_on_front(rect)
        x0, y0, x1, y1 = rect
        if layer == "floor":
            rows = range(int(y0 // T), int((y1 - 1) // T) + 1)
        else:
            rows = [int((y1 - 1) // T)]
        for ty in rows:
            for tx in range(int(x0 // T), int((x1 - 1) // T) + 1):
                if (tx, ty) not in ground:
                    return False
        return True

    def _rect_on_front(self, rect):
        """Wall things hang fully on rock (M1, playtest 15.10.2026: a torch stem below a front):
        every tile they cover is solid, and the lowest row they reach is a brick front (plain floor
        right below it), so nothing hangs out under the front into the floor."""
        floor = self.floor_tiles()
        x0, y0, x1, y1 = rect
        bottom = int((y1 - 1) // T)
        columns = range(int(x0 // T), int((x1 - 1) // T) + 1)
        for ty in range(int(y0 // T), bottom + 1):
            for tx in columns:
                if (tx, ty) in floor:
                    return False
        return all((tx, bottom + 1) in floor for tx in columns)

    def _compose(self, group, tiles, pieces, required=True):
        """Places pieces (dict with deco and name, optional flip) without overlap inside tiles, as
        close as possible to the first tile's middle; fails (required) or drops pieces that find no
        place."""
        placed = [prop_rect(p) for p in self.props if p.get("group") == group and prop_rect(p)]
        taken = self._taken_rects(skip_group=group) + placed
        # The floor in front of a cracked wall stays free (SecretRules: nothing stands where the
        # players blow it open).
        tiles = [t for t in tiles if t in self.walk_floor() - self.pits - self.bridges and t not in self.secret_approaches]
        if not tiles:
            if required:
                self.fail(f"no floor for {group}")
            return []
        target = centre(tiles[0])
        result = []
        for piece in pieces:
            item = piece["deco"]
            flip = piece.get("flip", self.rng.random() < 0.5)
            best = None
            for tx, ty in tiles:
                for ox in range(4, T - 3, 6):
                    for oy in range(10, T + 1, 6):
                        pos = (tx * T + ox, ty * T + oy)
                        rect = item_rect(item, pos, flip)
                        if rect is None or not self._rect_on_ground(item, rect):
                            continue
                        if any(overlaps(rect, other) for other in taken):
                            continue
                        score = (pos[0] - target[0]) ** 2 + (pos[1] - target[1]) ** 2
                        if best is None or score < best[0]:
                            best = (score, pos, rect)
            if best is None:
                if required:
                    self.fail(f"{item} of {group} finds no free place on {tiles}")
                continue
            prop = dict(piece, pos=best[1], flip=flip, group=group)
            self._add_prop(prop)
            taken.append(best[2])
            result.append(prop)
            target = best[1]
        return result

    # --- doors ---

    def _door_ok(self, side, place, strict=True):
        walk = self.walk_floor()
        for tile in self.core(side, place):
            if tile not in walk or tile in self.bridges:
                return f"no plain floor at {tile} in front of the door"
        # No rock right beside the tile inside a door (M2 H5): the one corridor tile must not look
        # like a longer corridor.
        ix, iy = INWARD[side]
        x0, y0 = self.inside_tile(side, place)
        for a in (-1, 1):
            beside = (x0 + abs(iy) * a, y0 + abs(ix) * a)
            if beside not in walk:
                return f"rock at {beside} right beside the door"
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
        """Fewer, larger composed groups (M1, playtest 14.10.2026) at deliberate anchors: corners,
        bays and rock blocks, never in a door lane, on the only way or close to another fixed object."""
        floor = self.walk_floor() - self.water
        count = len(floor)
        wanted = count // AUTO_GROUP_TILES
        existing = self._group_count()
        if self.cave:
            # One object or group per CAVE_OBJECT_TILES floor tiles, groups at most one per CAVE_GROUP_TILES.
            objects = len(self.sources) + sum(1 for o in self.objectives if o["kind"] not in MARKER_OBJECTIVES)
            wanted = max(wanted, min(count // CAVE_GROUP_TILES, -(-count // CAVE_OBJECT_TILES) - objects))
        if existing >= wanted:
            return
        lanes = set()
        for side, place in self.door_slots():
            lanes.update(self.lane(side, place, 3))
        self.auto_lanes = lanes
        cut = articulation_points(self.walk_floor())
        anchors = []
        for tile in sorted(floor):
            if tile in self.occupied or tile in lanes or tile in cut or tile == self.player_start:
                continue
            solid = self._rock_around(tile)
            orth = sum(self.solid(n) for n in neighbours4(tile))
            if orth < 1 or solid < 3:
                continue
            # Corners and bays first.
            anchors.append((-min(orth, 2), -solid, self.rng.random(), tile))
        anchors.sort()
        pool = [(kind, weight) for kind, weight in COMPOSITES_BY_BIOME[self.biome] if self.plan.role == "combat" or kind != "camp"]
        used = []
        for _, _, _, tile in anchors:
            if existing >= wanted:
                break
            fresh = [(kind, weight) for kind, weight in pool if kind not in used] or pool
            if has_group_art(self.biome):
                item = self._try_group_art(tile, lanes, cut, used)
                if item:
                    existing += 1
                    used.append(item)
                continue
            kind = self._weighted(fresh)
            if self._try_composite(kind, tile, lanes, cut):
                existing += 1
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
            if self.solid((x + dx, y + dy)):
                sides += name
        return sides

    def _fixed_tiles(self):
        """Tiles of fixed objects: sources, objectives (not the markers), solid props, chests."""
        tiles = {s["tile"] for s in self.sources}
        tiles |= {o["tile"] for o in self.objectives if o["kind"] not in MARKER_OBJECTIVES}
        tiles |= set(self.blocked)
        for prop in self.props:
            if prop.get("scene") in ("chest", "explosive"):
                tiles.add(prop_tile(prop))
        return tiles

    def _try_group_art(self, tile, lanes, cut, used):
        """One delivered decoration group on two (small) or three (large) floor tiles in a row that
        hold the anchor tile; the row with the most rock behind it wins. Returns its item or None."""
        floor = self.walk_floor() - self.water - self.pits - self.bridges
        fixed = self._fixed_tiles()
        keep = [s["floor_tile"] for s in self.sources] + [o["tile"] for o in self.objectives] + self.secret_approaches + [self.player_start]
        if any(chebyshev(tile, c) < GROUP_SPACING for c in self._group_centres()):
            return None
        taken = self._taken_rects()
        sizes = [3, 2] if self.rng.random() < GROUP_LARGE_CHANCE else [2]
        for length in sizes:
            rows = [[(tile[0] + start + i, tile[1]) for i in range(length)] for start in range(-length + 1, 1)]
            rows.sort(key=lambda row: (-sum(self._rock_around(t) for t in row), row))
            for row in rows:
                if any(t not in floor or t in lanes or t in cut or t in self.occupied for t in row):
                    continue
                if any(chebyshev(t, f) < OBJECT_SPACING for t in row for f in fixed):
                    continue
                if any(k and chebyshev(t, k) <= 1 for t in row for k in keep):
                    continue
                if not self._keeps_ways(row):
                    continue
                names = [f"group_large_{n}" for n in (1, 2)] if length == 3 else [f"group_{n}" for n in (1, 2, 3)]
                fresh = [n for n in names if n not in used] or names
                item = fresh[self.rng.randrange(len(fresh))]
                flip = self.rng.random() < 0.5
                pos = ((row[0][0] + length / 2) * T, (tile[1] + 1) * T - 8)
                rect = item_rect(item, pos, flip)
                if any(overlaps(rect, other) for other in taken):
                    continue
                if not self._rect_on_ground(item, rect):
                    continue
                self._add_prop(dict(deco=item, name="Group", pos=pos, blocked=list(row), flip=flip, group=f"auto{tile}"))
                self.blocked.update(row)
                self._occupy(row, "decoration")
                return item
        return None

    def _try_composite(self, kind, tile, lanes, cut):
        """One composed group at an anchor tile and the floor tile beside it along the wall."""
        walls = self._wall_sides(tile)
        floor = self.walk_floor() - self.water - self.pits - self.bridges
        # The second tile follows the wall (the neighbour with the most rock around it).
        options = [n for n in neighbours4(tile) if n in floor and n not in self.occupied and n not in lanes and n not in cut]
        options.sort(key=lambda n: (-self._rock_around(n), n))
        footprint = [tile] + options[:1]
        fixed = self._fixed_tiles()
        keep = [s["floor_tile"] for s in self.sources] + [o["tile"] for o in self.objectives] + self.secret_approaches + [self.player_start]
        for t in footprint:
            if t in lanes or t in cut or t in self.occupied:
                return False
            if any(chebyshev(t, f) < OBJECT_SPACING for f in fixed):
                return False
            if any(chebyshev(t, k) <= 1 for k in keep if k):
                return False
        if any(chebyshev(tile, c) < GROUP_SPACING for c in self._group_centres()):
            return False
        recipe = COMPOSITES[kind]
        solid = [piece for piece in recipe if piece.get("solid")]
        if solid and not self._keeps_ways([tile]):
            return False
        taken = self._taken_rects()
        flips = [self.rng.random() < 0.5 for _ in solid]
        for piece, flip in zip(solid, flips):
            if any(overlaps(item_rect(piece["deco"], base(tile), flip), other) for other in taken):
                return False
        if kind == "camp" and len(footprint) < 2:
            return False
        group = f"auto{tile}"
        before = len(self.props)
        flip = "E" in walls
        if kind == "camp":
            if not self._keeps_ways(footprint) or any(overlaps(item_rect(f"scene:{s}", base(t)), other) for s, t in zip(("crate", "barrel"), footprint) for other in taken):
                return False
            self._occupy(footprint, "decoration")
            self.blocked.update(footprint)
            self._add_prop(dict(scene="crate", name="Crate", pos=base(footprint[0]), group=group))
            self._add_prop(dict(scene="barrel", name="Barrel", pos=base(footprint[1]), group=group))
            ring = [t for t in self._ring_of(footprint) if t not in lanes and t not in fixed]
            self._compose(group, ring, [dict(deco="bedroll", name="Bedroll", flip=flip)], required=False)
            return True
        for piece, piece_flip in zip(solid, flips):
            self._add_prop(dict(deco=piece["deco"], name=piece["name"], pos=base(tile), blocked=[tile], flip=piece_flip, group=group))
        if solid:
            self.blocked.add(tile)
        loose = [dict(deco=p["deco"], name=p["name"]) for p in recipe if not p.get("solid") and not p.get("wall")]
        area = footprint if not solid else [t for t in footprint if t != tile] + [t for t in self._ring_of([tile]) if t not in lanes and t not in fixed and t not in self.occupied]
        placed = self._compose(group, area, loose, required=False)
        if len(placed) < max(1, len(loose) - 1):
            # Too little room for a group worth the name: take it back.
            del self.props[before:]
            if solid:
                self.blocked.discard(tile)
            return False
        for piece in recipe:
            above = (tile[0], tile[1] - 1)
            if piece.get("wall") and "N" in walls and above in self.walls and self._front_free(above):
                self._add_prop(dict(deco=piece["deco"], name=piece["name"], pos=(above[0] * T + T / 2, (above[1] + 1) * T - WALL_ITEM_LIFT), flip=self.rng.random() < 0.5, group=group))
                self.fixtures[above] = "c"
        self._occupy([tile], "decoration")
        if kind in ("mushroom_bed", "drip_pool"):
            for t in [tile] + neighbours4(tile):
                if t in floor and t not in self.occupied:
                    self.moss.add(t)
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
                centres.setdefault(prop["group"], prop_tile(prop))
        return list(centres.values())

    def _group_count(self):
        """Decoration groups: props of one plan cell or automatic group, clusters of neighbouring
        cells counted once (a coffin pair is one group)."""
        tiles = {}
        for prop in self.props:
            group = prop.get("group")
            if not group or group == "light" or prop.get("scene") == "torch":
                continue
            tiles.setdefault(group, prop_tile(prop))
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
        normal_sources = [s for s in self.sources if s["kind"] != "sarcophagus"]
        if normal_sources and len(normal_sources) < MIN_PLAN_SOURCES:
            self.fail(f"{len(normal_sources)} enemy sources, at least {MIN_PLAN_SOURCES} (sarcophagi not counted)")
        for o in self.objectives:
            if o["tile"] not in walk:
                self.fail(f"{o['kind']} at {o['tile']} not on floor")
        if self.player_start and self.player_start not in reached:
            self.fail(f"player start {self.player_start} not reachable")
        # No decoration in the only way.
        cut = articulation_points(walk)
        for prop in self.props:
            if prop.get("scene") == "torch" or prop.get("deco") in ("wall_niche", "wall_niche_soft", "chains", "cobweb") or prop.get("group") in (None, "light"):
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
        # A cracked wall needs free floor in front of it (SecretRules: no prop, no marker there).
        for tile in self.secret_approaches:
            if tile in self.blocked or (tile in self.occupied and tile not in self.soft):
                self.fail(f"cracked wall above {tile}: {self.occupied.get(tile, 'something solid')} on the floor in front of it")
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

    # --- caves (M1) ---

    def solid(self, tile):
        """Rock or wall at a room tile (everything outside the floor rectangle counts, door corridors
        excepted)."""
        if self.in_floor(tile):
            return tile in self.walls
        return tile not in self._corridor_set()

    def _corridor_set(self):
        if not hasattr(self, "_corridors"):
            self._corridors = set(self._all_corridors())
        return self._corridors

    def outline_rock(self):
        """Rock tiles inside the floor rectangle joined to the ring (the outline), as opposed to
        free-standing blocks."""
        w, h = self.size
        rock = set(self.walls)
        seen = {t for t in rock if t[0] in (0, w - 1) or t[1] in (0, h - 1)}
        queue = deque(seen)
        while queue:
            tile = queue.popleft()
            for n in neighbours4(tile):
                if n in rock and n not in seen:
                    seen.add(n)
                    queue.append(n)
        return seen

    def _check_cave(self):
        """Makeover 2/3 rules of a cave plan (M1)."""
        plan = self.plan
        gw, gh = len(self.grid[0]), len(self.grid)
        if plan.role != "combat":
            return
        if plan.size_class != "L" and not (CAVE_MIN_GRID[0] <= gw <= CAVE_MAX_GRID[0] and CAVE_MIN_GRID[1] <= gh <= CAVE_MAX_GRID[1]):
            self.fail(f"cave plan {gw}x{gh}: single-player caves are {CAVE_MIN_GRID[0]}x{CAVE_MIN_GRID[1]} to {CAVE_MAX_GRID[0]}x{CAVE_MAX_GRID[1]} cells")
        outline = self.outline_rock()
        blocks = set(self.walls) - outline
        if not blocks and not self.height["plateau"] and len(self.pits - self.bridges) < 4:
            self.fail("cave without a rock block, plateau or abyss inside")
        concave = self._concave_corners(outline)
        if concave < CAVE_MIN_CONCAVE:
            self.fail(f"cave outline with {concave} concave corners (a rectangle; at least {CAVE_MIN_CONCAVE}: two bays or ledges)")
        longest, where = self._longest_edge(outline)
        if longest > CAVE_MAX_EDGE:
            self.fail(f"straight outline edge of {longest} tiles ending at {where} (at most {CAVE_MAX_EDGE})")
        floor = len(self.walk_floor() - self.water)
        if floor > CAVE_FLOOR_SHARE * gw * gh:
            self.fail(f"floor {floor} of {gw * gh} cells (at most {int(CAVE_FLOOR_SHARE * 100)} %)")
        self.concave = concave
        self.longest_edge = longest

    def _concave_corners(self, outline):
        """Inner corners of the floor against the outline rock (and the ring): grid points where
        exactly one of the four cells around it is outline rock and the other three are floor."""
        w, h = self.size
        floor = self.floor_tiles()
        count = 0
        for y in range(0, h + 1):
            for x in range(0, w + 1):
                cells = [(x - 1, y - 1), (x, y - 1), (x - 1, y), (x, y)]
                rock = [c for c in cells if c not in floor and (c in outline or not self.in_floor(c))]
                if len(rock) == 1 and all(c in floor for c in cells if c not in rock):
                    count += 1
        return count

    def _longest_edge(self, outline):
        """Longest straight run of floor along outline rock (or the ring), doors breaking runs."""
        w, h = self.size
        floor = self.floor_tiles()
        doors = {self.door_tile(side, place) for side, place in self.door_slots()}

        def rock(tile):
            if tile in doors:
                return False
            return (tile in outline) or not self.in_floor(tile)

        longest, where = 0, None
        for dx, dy, horizontal in ((0, -1, True), (0, 1, True), (-1, 0, False), (1, 0, False)):
            for line in range(h if horizontal else w):
                run = 0
                for step in range(w if horizontal else h):
                    tile = (step, line) if horizontal else (line, step)
                    if tile in floor and rock((tile[0] + dx, tile[1] + dy)):
                        run += 1
                        if run > longest:
                            longest, where = run, tile
                    else:
                        run = 0
        return longest, where

    def _free_ground(self):
        """Floor tiles that hold nothing: no prop, source, objective, water, abyss or bridge."""
        taken = set(self.occupied) | set(self.blocked)
        for prop in self.props:
            taken.add((int(prop["pos"][0] // T), int((prop["pos"][1] - 1) // T)))
            taken.update(tuple(t) for t in prop.get("blocked", []))
        return self.walk_floor() - self.water - self.bridges - taken

    def _rock_around(self, tile):
        return sum(self.solid((tile[0] + dx, tile[1] + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)

    def _add_zones(self):
        """Frayed patches of zone floor where the plan draws few itself (Makeover 2): dirt in bays and
        corners, slab on the way through the room, cobble on an old path near the entrance, rubble
        under fallen pillars, rubble props and collapse fields."""
        ground = self.walk_floor() - self.water - self.bridges
        for tile in list(self.zones):
            if tile not in ground:
                del self.zones[tile]
        wanted = int(len(ground) * ZONE_SHARE)
        if len(self.zones) >= wanted:
            return
        rng = random.Random(zlib.crc32(("zones" + self.id).encode()))
        start = self.inside_tile(SOUTH, self.entrance)
        path = bfs_path(ground - self.blocked, start, self.inside_tile(NORTH, self.north[0])) or [start]
        seeds = []
        fallen = [o["tile"] for o in self.objectives if o["kind"] == "collapse_field"]
        fallen += [(int(p["pos"][0] // T), int((p["pos"][1] - 1) // T)) for p in self.props if p.get("deco") == "pillar_fallen" or p.get("scene") == "rubble"]
        for tile in fallen[:2]:
            seeds.append((ZONE_RUBBLE, tile))
        seeds.append((ZONE_SLAB, path[len(path) // 2]))
        seeds.append((ZONE_COBBLE, path[min(len(path) - 1, 2)]))
        bays = sorted((t for t in ground if self._rock_around(t) >= 4), key=lambda t: (rng.random(), t))
        for tile in bays[:3]:
            seeds.append((ZONE_DIRT, tile))
        along = {ZONE_SLAB: set(path), ZONE_COBBLE: set(path[:len(path) // 2 + 1])}
        for zone, seed in seeds:
            if len(self.zones) >= wanted:
                break
            if seed not in ground or seed in self.zones:
                continue
            size = rng.randint(*ZONE_PATCH)
            patch = [seed]
            frontier = [seed]
            while frontier and len(patch) < size:
                tile = frontier.pop(rng.randrange(len(frontier)))
                options = [n for n in neighbours4(tile) if n in ground and n not in self.zones and n not in patch]
                # Way zones follow the way, the others grow round with frayed edges.
                if zone in along:
                    options.sort(key=lambda n: (n not in along[zone], rng.random()))
                    options = options[:2]
                for n in options:
                    if len(patch) < size and rng.random() < 0.8:
                        patch.append(n)
                        frontier.append(n)
            if len(patch) >= ZONE_PATCH[0]:
                for tile in patch:
                    self.zones[tile] = zone

    def _add_overlays(self):
        """Scatter overlays only as a border (M1, playtest 14.10.2026): at walls and in corners and
        around decoration groups, never in the open floor, never under or on objects (their visible
        rects), never on the player start; mirrored at random. Moss tiles of a cave get a tuft."""
        rng = random.Random(zlib.crc32(("overlay" + self.id).encode()))
        weights = OVERLAY_WEIGHTS[self.biome]
        taken = self._taken_rects()
        groups = {prop_tile(p) for p in self.props if p.get("group") not in (None, "light")}
        near_group = {t for g in groups for t in self._ring_of([g])}
        ground = self.walk_floor() - self.pits - self.bridges - self.water - set(self.occupied) - set(self.blocked)
        ground -= {self.player_start}
        # Door lanes stay clean (playtest: no overlays or puddles in gate fields).
        for side, place in self.door_slots():
            ground -= set(self.lane(side, place, DOOR_LANE_ROWS))
        near_water = {n for t in self.water for n in neighbours4(t)}
        cells = []
        for tile in sorted(ground):
            rect = tile_rect(tile)
            if any(overlaps(rect, other, 0) for other in taken):
                continue
            if self.cave and tile in self.moss:
                cells.append((tile, 2, rng.random() < 0.5))
                continue
            if tile in near_group:
                chance = OVERLAY_GROUP_CHANCE
            elif self._rock_around(tile) > 0:
                chance = OVERLAY_WALL_CHANCE
            else:
                chance = OVERLAY_OPEN_CHANCE
            if rng.random() >= chance:
                continue
            pool = list(weights)
            if tile in near_water:
                pool[4] += 3
            roll = rng.random() * sum(pool)
            item = 0
            for i, weight in enumerate(pool):
                roll -= weight
                if roll < 0:
                    item = i
                    break
            cells.append((tile, item, rng.random() < 0.5))
        self.overlays = cells

    def _add_moving_points(self):
        """Two or three things that move in every room (Makeover 2 "Bewegung im Bild"): torches,
        braziers, burning stands, drips and water count; faint fog wisps fill up, in bays and
        corners, never on the only way, never on another object."""
        moving = sum(1 for c in self.fixtures.values() if c == "T")
        moving += sum(1 for p in self.props if p.get("deco") in ("drip", "brazier", "mist"))
        moving += sum(1 for o in self.objectives if o["kind"] in ("brazier", "torch_stand"))
        moving += 1 if self.water else 0
        if moving >= MOVING_MIN or self.plan.role in ("boss", "miniboss"):
            return
        rng = random.Random(zlib.crc32(("moving" + self.id).encode()))
        cut = articulation_points(self.walk_floor())
        lanes = set()
        for side, place in self.door_slots():
            lanes.update(self.lane(side, place, 3))
        options = [t for t in sorted(self.walk_floor() - self.pits - self.bridges - self.water - set(self.occupied) - set(self.blocked))
                   if t not in cut and t not in lanes and t != self.player_start and self._rock_around(t) >= 3 and t not in self.spawns]
        # Fog wisps sit in bays and at the rock, never next to open floor: room modes look for free
        # spots there (a tile with free floor all around, VariantSpots.is_open), and a wisp would
        # take that away.
        free = self.walk_floor() - self.pits - self.bridges - self.water - set(self.occupied) - set(self.blocked)
        around = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
        def open_floor(t):
            return t in free and all((t[0] + dx, t[1] + dy) in free for dx, dy in around)
        options = [t for t in options if not open_floor(t) and not any(open_floor((t[0] + dx, t[1] + dy)) for dx, dy in around)]
        rng.shuffle(options)
        options.sort(key=lambda t: -self._rock_around(t))
        placed = []
        for tile in options:
            if moving >= MOVING_MAX or (moving >= MOVING_MIN and rng.random() < 0.5):
                break
            if any(chebyshev(tile, other) < 4 for other in placed):
                continue
            if self._compose(f"mist{tile}", [tile], [dict(deco="mist", name="Mist")], required=False):
                placed.append(tile)
                moving += 1

    # --- object rules (M1, playtest 14.10.2026) ---

    def _objects(self):
        """Every thing on the floor as one object: decoration groups (all props of one group), single
        props, sources and objectives (markers of enemies, souls and fields excluded)."""
        objects = {}
        for i, prop in enumerate(self.props):
            key = prop.get("group") or f"prop{i}"
            if key == "light":
                key = f"light{prop_tile(prop)}"
            entry = objects.setdefault(key, dict(name=key, rects=[], tiles=set(), fixed=False))
            rect = prop_rect(prop)
            if rect:
                entry["rects"].append((rect, prop.get("deco") or prop.get("scene")))
            # Only the solid tiles count for the spacing; loose bits of a group may lie close by.
            if prop.get("blocked") or prop.get("scene") in SOLID_SCENES:
                entry["fixed"] = True
                entry["tiles"].update(tuple(t) for t in prop.get("blocked", [prop_tile(prop)]))
        built = {prop_tile(p) for p in self.props if p.get("group") == "light"}
        for s in self.sources:
            objects[f"source{s['tile']}"] = dict(name=f"{s['kind']} {s['tile']}", rects=[(tile_rect(s["tile"]), "source")], tiles={s["tile"]}, fixed=True)
        for o in self.objectives:
            if o["kind"] in MARKER_OBJECTIVES or o["tile"] in built:
                continue
            objects[f"objective{o['tile']}"] = dict(name=f"{o['kind']} {o['tile']}", rects=[(tile_rect(o["tile"]), o["kind"])], tiles={o["tile"]}, fixed=True)
        return list(objects.values())

    def _check_objects(self):
        """No overlap between any two things, fixed objects one free tile apart, everything that lies
        on the floor fully on floor (no abyss, no rock), markers on walkable floor."""
        objects = self._objects()
        ground = self.walk_floor() - self.pits - self.bridges
        for i, a in enumerate(objects):
            pieces = a["rects"]
            for j in range(len(pieces)):
                for k in range(j + 1, len(pieces)):
                    if {pieces[j][1], pieces[k][1]} != {"drip", "puddle"} and overlaps(pieces[j][0], pieces[k][0]):
                        self.fail(f"{pieces[j][1]} and {pieces[k][1]} of {a['name']} overlap")
            for b in objects[i + 1:]:
                for ra, ia in a["rects"]:
                    for rb, ib in b["rects"]:
                        if overlaps(ra, rb):
                            self.fail(f"{ia} ({a['name']}) overlaps {ib} ({b['name']})")
                if a["fixed"] and b["fixed"] and a["tiles"] and b["tiles"]:
                    gap = min(chebyshev(p, q) for p in a["tiles"] for q in b["tiles"])
                    if gap < OBJECT_SPACING:
                        self.fail(f"{a['name']} and {b['name']} need one free tile between them")
        for prop in self.props:
            item = prop.get("deco") or "scene:" + str(prop.get("scene"))
            rect = prop_rect(prop)
            if rect and not self._rect_on_ground(item, rect):
                if ITEM_LAYER.get(item) == "wall":
                    self.fail(f"{item} at {prop_tile(prop)} does not hang fully on a wall front (it would reach into the floor)")
                else:
                    self.fail(f"{item} at {prop_tile(prop)} reaches off the floor (abyss, rock or bridge)")
        for marker in [s["floor_tile"] for s in self.sources] + [o["tile"] for o in self.objectives] + list(self.spawns):
            if marker not in ground:
                self.fail(f"marker at {marker} not on walkable floor")

    def _check_gaps(self):
        """Between two solid or unwalkable things (rock, wall, abyss, the room's edge) lies either
        nothing or at least two tiles of floor: no one-tile slots that look like a way; no front
        right above an abyss (M1, playtest 14.10.2026). Bridges are ways on purpose."""
        floor = self.floor_tiles()
        corridors = self._corridor_set()

        def blocked(tile):
            if tile in corridors:
                return False
            return tile not in floor or (tile in self.pits and tile not in self.bridges)

        for tile in sorted(self.walk_floor() - self.bridges):
            x, y = tile
            if blocked((x - 1, y)) and blocked((x + 1, y)):
                self.fail(f"one-tile slot at {tile} (solid west and east)")
            if blocked((x, y - 1)) and blocked((x, y + 1)):
                self.fail(f"one-tile slot at {tile} (solid north and south)")
        for x, y in sorted(self.pits):
            above = (x, y - 1)
            if above not in floor and above not in corridors:
                self.fail(f"wall front right above the abyss at {(x, y)}")

    # --- markers ---

    def size_class(self):
        if self.plan.size_class:
            return self.plan.size_class
        if self.cave:
            return "S" if len(self.walk_floor() - self.water) <= CAVE_S_FLOOR else "M"
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
                    and tile not in self.secret_approaches
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
    if room.cave:
        text += f"rock_style = {ROCK_STYLES['blob']}\n"
    if plan.cave:
        text += "cave_mouth = true\n"
    if room.zones:
        text += f"zone_cells = {vec3i_list(sorted((x, y, z) for (x, y), z in room.zones.items()))}\n"
    if room.overlays:
        text += f"overlay_cells = {vec3i_list([(t[0], t[1], item + (OVERLAY_FLIP if flip else 0)) for t, item, flip in room.overlays])}\n"
    for key, name in (("plateau", "plateau_tiles"), ("ladder", "ladder_tiles"), ("stairs", "stair_tiles")):
        if room.height[key]:
            text += f"{name} = {vec2i_list(sorted(room.height[key]))}\n"
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
            parent = "Props"
            if p["deco"] == "mist":
                # Fog wisps are mood, no object: their own node, so nothing that looks for free
                # spots among the props (room modes, VariantSpots) counts them.
                if "Ambience" not in counts:
                    counts["Ambience"] = 1
                    text += '\n[node name="Ambience" type="Node2D" parent="."]\n'
                parent = "Ambience"
            text += f'\n[node name="{node}" type="Node2D" parent="{parent}"]\nposition = {vec2(*p["pos"])}\nscript = ExtResource("{deco_id}")\n'
            text += f'item = &"{p["deco"]}"\n'
            if p.get("flip"):
                text += "flip = true\n"
            if p.get("tint"):
                text += f"tint = {color(p['tint'])}\n"
            if p.get("blocked"):
                text += f"blocked_tiles = {vec2i_list(p['blocked'])}\n"
            if "still" in p:
                text += f"still_frame = {p['still']}\n"
            if p["deco"] == "puddle" or p["deco"].startswith("group_") or p["deco"] == "wall_niche_soft":
                # Biome art: water palette (WaterArt), group pictures, soft rock colours (M1, V9).
                text += f'biome = &"{room.biome}"\n'
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
    if room.cave:
        text += f"rock_style = {ROCK_STYLES['blob']}\n"
    if plan.cave:
        text += "cave = true\n"
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
