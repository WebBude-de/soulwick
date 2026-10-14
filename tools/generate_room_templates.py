"""Generates dungeon room templates (.tscn) from tile coordinates.

Usage (from the project root):
    python tools/generate_room_templates.py                 all templates
    python tools/generate_room_templates.py --combat-only   combat templates, their RoomTemplate
                                                            resources and the catalog; the other
                                                            templates are only compared (report)
One tile = 64 world px (32 px art at scale 2). The templates stay normal Godot scenes that can be
edited in the editor afterwards; re-running this script overwrites them. Files whose content does
not change are not touched.

Combat templates (KONZEPT_RAEUME §3, D-086, D-100) are built from a room kind (normal, arena,
chasm), a shape (rectangle, L, cross, ring, two chambers, pillar hall, catacomb; for chasm rooms
bridge hall, islands, walkway, ring around a hole) and a size class (S/M/L). Inner walls go to RoomTiles.wall_rects, pillars to pillar_tiles. Every wall looks like the
outer wall (WallAutotile, SPRITES_V6): crown on top, one row of brick front under it; the front is
part of the solid mass, so wall_rects hold crown and front and a pillar blocks its tile and the
tile below. Every column of wall above floor is at least two tiles tall. Every combat template gets an IngredientScatter node ("Ingredients") that scatters the
biome's ingredients at runtime, with the ingredients its shape allows. Next to each scene the
generator writes a RoomTemplate resource (dungeon/rooms/templates/<id>.tres) and lists all of them in
dungeon/rooms/combat/combat_catalog.tres (RoomCatalog).

Every combat template is checked before it is written: spawn marker count per size, every floor
tile, the exit and all spawn markers reachable from the entrance (walking, plus dashing over gaps
of at most one pit tile), no marker on blocked tiles, props or right next to the entrance, no
template torch right beside the exit door (the doors bring their own, D1), and for the catacomb at
most two dead ends, at most two branchings between entrance and exit and the chest in the deepest
dead end. Chasm templates (A4) come from tile maps (CHASM_MAPS) and are checked further: every
floor and bridge tile reachable on foot (enemies cannot dash; a dash over a one-tile gap is only a
shortcut), at least one such shortcut, no pit in the door lanes, markers and props on solid floor
only (never on a bridge). Catacomb templates appear from room 2, chasm templates from room 6
(RoomTemplate.min_room).

The campfire template (D-103, ROADMAP_AUSBAU A6) sits between two biomes after every boss room.
It has no enemies; the fire stands on ContentAnchor, the exit portal on PortalAnchor. Its floor
blend and content are built at runtime (RoomController, CampfireContent).
"""
import math
import random
import sys
import zlib
from collections import deque
from pathlib import Path

T = 64
ROOMS = Path(__file__).resolve().parent.parent / "dungeon" / "rooms"
DECO = {
    "torch": "res://dungeon/environment/decorations/torch.tscn",
    "crate": "res://dungeon/environment/decorations/crate.tscn",
    "barrel": "res://dungeon/environment/decorations/barrel.tscn",
    "bones_1": "res://dungeon/environment/decorations/bones_1.tscn",
    "bones_2": "res://dungeon/environment/decorations/bones_2.tscn",
    "trap": "res://dungeon/environment/traps/spike_trap.tscn",
    "chest": "res://dungeon/rooms/ingredients/treasure_chest.tscn",
    "bone_pile": "res://dungeon/rooms/ingredients/decor/bone_pile.tscn",
    "cobweb": "res://dungeon/rooms/ingredients/decor/cobweb.tscn",
}
# RoomSequence.RoomKind / RoomSequence.RoomSize / RoomTemplate.Shape (same order as the GDScript enums).
KINDS = {"normal": 0, "arena": 1, "chasm": 2}
SIZES = {"S": 0, "M": 1, "L": 2}
SHAPES = {"rectangle": 0, "l_shape": 1, "cross": 2, "ring": 3, "two_chambers": 4, "pillar_hall": 5, "catacomb": 6,
          "bridge_hall": 7, "islands": 8, "walkway": 9, "ring_hole": 10}
# RoomTemplate.DoorSide.
SIDE_NORTH, SIDE_SOUTH = 0, 2
# IngredientSet.Kind.
COVER, TRAPS, WALLS, CHOKEPOINTS, LIGHT, EXPLOSIVES, PITS = range(7)
ALL_INGREDIENTS = [COVER, TRAPS, WALLS, CHOKEPOINTS, LIGHT, EXPLOSIVES, PITS]
# First room of a template (RoomTemplate.min_room): no catacomb in room 1 (UX2 finding), chasm rooms
# from RoomSequence.CHASM_FROM_ROOM.
MIN_ROOM = {"catacomb": 2}
CHASM_FROM_ROOM = 6
# Rows in front of each door that stay free of pits (door lanes, 3 wide): nobody falls on entry.
PIT_FREE_DOOR_ROWS = 2
# Spawn markers per combat template (D-086): S >= 5, M >= 8, L >= 12, never more than 14.
MIN_SPAWNS = {"S": 5, "M": 8, "L": 12}
MAX_SPAWNS = 14
# Markers of every non-combat template: the champion escort still draws from exactly five (D-009).
BASE_SPAWNS = 5
# Widest pit gap a dash crosses (RoomTiles.MAX_DASH_GAP, D-086).
MAX_DASH_GAP = 1
# Chebyshev distance in tiles a spawn marker keeps from the tile inside the entrance.
ENTRANCE_CLEARANCE = 2
# Props standing on the floor (spawn markers must not share their tile).
SOLID_PROPS = {"crate", "barrel", "chest"}
CATALOG = ROOMS / "combat" / "combat_catalog.tres"
TEMPLATES = ROOMS / "templates"
SCATTER_SCRIPT = "res://dungeon/rooms/ingredients/ingredient_scatter.gd"
TEMPLATE_SCRIPT = "res://dungeon/rooms/templates/room_template.gd"
# Campfire (A6): free tiles the fire, its seat and the bedroll take around ContentAnchor, as
# offsets in tiles from the anchor tile. Spawn markers and the way through must avoid them.
CAMPFIRE_SIZE = (13, 11)
CAMPFIRE_DOOR_X = 6
CAMPFIRE_ANCHOR = (6.5, 5.6)
CAMPFIRE_PORTAL = (10.5, 2.6)
CAMPFIRE_BLOCKED = [(-1, 0), (0, 0), (1, 0), (-2, 0)]

# --- Combat template layout (KONZEPT_RAEUME §3.2, TESTWERTE) ---
# Floor size per size class (D-086: S ~ 15x9, M ~ 19x11, L ~ 25x15).
SIZE_TILES = {"S": (15, 9), "M": (19, 11), "L": (25, 15)}
# Spawn markers per size; arenas get more (waves come from all sides, A5).
SPAWN_COUNT = {"S": 6, "M": 9, "L": 13}
ARENA_SPAWN_COUNT = {"M": 10, "L": 14}
# Wall torches on the north wall per size (catacomb: one, it lives from the darkness).
TORCH_COUNT = {"S": 2, "M": 2, "L": 3}
# Template torches keep this many tiles from the exit door, which has torches of its own (D1).
DOOR_TORCH_CLEARANCE = 4
# Spawn markers keep this Chebyshev distance from the tile inside the exit.
EXIT_CLEARANCE = 1
# Catacomb rules (KONZEPT_RAEUME §3.2).
MAX_DEAD_ENDS = 2
MAX_JUNCTIONS_TO_EXIT = 2
# Bones lying around (decoration only); the catacomb gets bone piles and cobwebs in its corners.
BONES_COUNT = {"S": 2, "M": 2, "L": 3}
COBWEB_COUNT = {"M": 3, "L": 4}
# Template scenes referenced by dungeon.tscn keep their file names.
LEGACY_NAMES = {
    ("normal", "rectangle", "S"): ("combat_hall", "CombatHall"),
    ("normal", "pillar_hall", "S"): ("combat_pillars", "CombatPillars"),
    ("arena", "rectangle", "M"): ("combat_wide", "CombatWide"),
}

MODE = "all"
_skipped = []


def centre(tx, ty):
    return f"Vector2({(tx + 0.5) * T:g}, {(ty + 0.5) * T:g})"


def write(path, text, combat=False):
    """Writes text if it differs. In --combat-only mode other templates are only compared."""
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return
    if MODE == "combat" and not combat:
        _skipped.append(path)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def walkable_tiles(size, entrance, exit_x, blocked, pits):
    """Same rule as RoomTiles.get_walkable_tiles(): floor plus door corridors, minus blocked/pits."""
    w, h = size
    tiles = {(x, y) for x in range(w) for y in range(h)}
    tiles |= {(exit_x, y) for y in (-1, -2, -3)}
    tiles |= {(entrance, y) for y in (h, h + 1)}
    return tiles - set(blocked) - set(pits)


def flood_fill(walkable, pits, start, max_gap):
    """Same rule as RoomTiles.flood_fill(): 4-neighbours, straight dash over <= max_gap pit tiles."""
    if start not in walkable:
        return set()
    reached = {start}
    open_tiles = [start]
    while open_tiles:
        x, y = open_tiles.pop()
        for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
            nx, ny = x + dx, y + dy
            gap = 0
            while (nx, ny) in pits and gap < max_gap:
                nx, ny = nx + dx, ny + dy
                gap += 1
            if (nx, ny) in walkable and (nx, ny) not in reached:
                reached.add((nx, ny))
                open_tiles.append((nx, ny))
    return reached


def pillar_mass(pillars, size):
    """A pillar is a small wall: its crown tile and the brick front below (RoomTiles.get_wall_mass)."""
    w, h = size
    return {t for x, y in pillars for t in ((x, y), (x, y + 1)) if 0 <= t[0] < w and 0 <= t[1] < h}


def check_wall_mass(name, size, mass):
    """WallAutotile.is_valid_mass: no wall between two floors; a wall with floor below has a solid
    tile above (its crown), so it is at least two tiles tall. Outside the floor is solid."""
    w, h = size
    for x, y in mass:
        if y + 1 < h and (x, y + 1) not in mass:
            assert y - 1 < 0 or (x, y - 1) in mass, f"{name}: wall {(x, y)} has no crown above its front"


def check_layout(name, size, entrance, exit_x, spawns, props, blocked=(), pits=()):
    """Asserts a playable layout. Inner walls and pillars come in blocked, A4 abyss tiles in pits."""
    w, h = size
    walkable = walkable_tiles(size, entrance, exit_x, blocked, pits)
    start = (entrance, h - 1)
    reached = flood_fill(walkable, set(pits), start, MAX_DASH_GAP)
    assert start in walkable, f"{name}: the tile inside the entrance is blocked"
    assert (exit_x, 0) in reached and (exit_x, -3) in reached, f"{name}: exit not reachable from the entrance"
    traps = {(x, y) for kind, x, y in props if kind == "trap"}
    solid = {(x, y) for kind, x, y in props if kind in SOLID_PROPS}
    assert len(set(spawns)) == len(spawns), f"{name}: two spawn markers share a tile"
    for spawn in spawns:
        assert 0 <= spawn[0] < w and 0 <= spawn[1] < h, f"{name}: spawn {spawn} outside the floor"
        assert spawn in reached, f"{name}: spawn {spawn} not on reachable floor"
        assert spawn not in traps and spawn not in solid, f"{name}: spawn {spawn} on a trap or prop"
        assert max(abs(spawn[0] - start[0]), abs(spawn[1] - start[1])) > ENTRANCE_CLEARANCE, \
            f"{name}: spawn {spawn} right at the entrance"


def base():
    markers = [(3, 2), (11, 2), (7, 3), (2, 5), (12, 5)]
    spawn_nodes = "".join(
        f'\n[node name="Spawn{i + 1}" type="Marker2D" parent="SpawnPoints"]\nposition = {centre(x, y)}\n'
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


def variant(rel_path, root, size, entrance, exit_x, pillars, seed, spawns, content, portal, props,
            room_kind=None, size_class=None):
    """Special, boss and campfire templates (combat templates: combat_template()).
    props: (kind, tile_x, tile_y); torches hang on the north wall front (row -1)."""
    assert room_kind is None, f"{root}: combat templates are written by combat_template()"
    assert len(spawns) == BASE_SPAWNS, f"{root}: non-combat templates keep exactly {BASE_SPAWNS} spawn markers"
    check_layout(root, size, entrance, exit_x, spawns, props, blocked=pillar_mass(pillars, size))
    used = sorted({p[0] for p in props})
    ids = {kind: f"{i + 2}_{kind}" for i, kind in enumerate(used)}
    text = '[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="res://dungeon/rooms/room_base.tscn" id="1_base"]\n'
    for kind in used:
        text += f'[ext_resource type="PackedScene" path="{DECO[kind]}" id="{ids[kind]}"]\n'
    text += f'\n[node name="{root}" instance=ExtResource("1_base")]\n'
    text += '\n[node name="Tiles" parent="."]\n'
    text += f"room_size = Vector2i({size[0]}, {size[1]})\nentrance_x = {entrance}\nexit_x = {exit_x}\nfloor_seed = {seed}\n"
    if pillars:
        text += "pillar_tiles = Array[Vector2i]([" + ", ".join(f"Vector2i({x}, {y})" for x, y in pillars) + "])\n"
    for i, (x, y) in enumerate(spawns):
        # Spawn1..5 exist in room_base; further markers are new nodes.
        node_type = ' type="Marker2D"' if i >= BASE_SPAWNS else ""
        text += f'\n[node name="Spawn{i + 1}"{node_type} parent="SpawnPoints"]\nposition = {centre(x, y)}\n'
    text += f'\n[node name="ContentAnchor" parent="."]\nposition = Vector2({content[0] * T:g}, {content[1] * T:g})\n'
    text += f'\n[node name="PortalAnchor" parent="."]\nposition = Vector2({portal[0] * T:g}, {portal[1] * T:g})\n'
    for i, (kind, x, y) in enumerate(props):
        text += f'\n[node name="{kind.capitalize()}{i}" parent="Props" instance=ExtResource("{ids[kind]}")]\nposition = {prop_position(kind, x, y)}\n'
    write(ROOMS / rel_path, text)


def prop_position(kind, x, y):
    if kind == "cobweb":
        return f"Vector2({x * T:g}, {y * T:g})"
    if kind == "torch":
        return f"Vector2({x * T:g}, {-T:g})"
    if kind == "trap":
        return centre(x, y)
    return f"Vector2({(x + 0.5) * T:g}, {(y + 1) * T - 8:g})"


def campfire():
    """Campfire between two biomes: no enemies, the fire in the middle, the portal top right.
    The fire, the seat and the bedroll are runtime props; the layout check treats their tiles
    as blocked, so the way from the entrance to the exit always leads around them."""
    w, h = CAMPFIRE_SIZE
    anchor = (int(CAMPFIRE_ANCHOR[0]), int(CAMPFIRE_ANCHOR[1]))
    blocked = [(anchor[0] + dx, anchor[1] + dy) for dx, dy in CAMPFIRE_BLOCKED]
    spawns = [(1, 1), (w - 2, 1), (1, h - 5), (w - 2, h - 5), (anchor[0], 2)]
    check_layout("CampfireRoom", CAMPFIRE_SIZE, CAMPFIRE_DOOR_X, CAMPFIRE_DOOR_X, spawns, [], blocked=blocked)
    portal_tile = (int(CAMPFIRE_PORTAL[0]), int(CAMPFIRE_PORTAL[1]))
    assert portal_tile not in blocked, "CampfireRoom: portal on the fire"
    variant("campfire/campfire_room.tscn", "CampfireRoom", CAMPFIRE_SIZE, CAMPFIRE_DOOR_X, CAMPFIRE_DOOR_X, [], 83,
            spawns, CAMPFIRE_ANCHOR, CAMPFIRE_PORTAL,
            [("torch", 3, 0), ("torch", 9, 0), ("crate", 0, 0), ("crate", w - 1, h - 1)])


# --- Shapes (KONZEPT_RAEUME §3.2). Each returns size, doors, inner wall tiles and pillars. ---

def rect_tiles(x, y, w, h):
    return {(x + i, y + j) for i in range(w) for j in range(h)}


def shape_rectangle(kind, size_class):
    w, h = SIZE_TILES[size_class]
    return dict(size=(w, h), entrance=w // 2, exit_x=w // 2, walls=set(), pillars=[])


def shape_l(kind, size_class):
    """A corner of the rectangle is solid: enemies wait around the corner. The M room is mirrored."""
    w, h = SIZE_TILES[size_class]
    cut_w, cut_h = round(w * 0.45), h // 2
    if size_class == "M":
        walls = rect_tiles(0, 0, cut_w, cut_h)
        exit_x, entrance = cut_w + (w - cut_w) // 2, 3
    else:
        walls = rect_tiles(w - cut_w, 0, cut_w, cut_h)
        exit_x, entrance = (w - cut_w) // 2, w - 4
    return dict(size=(w, h), entrance=entrance, exit_x=exit_x, walls=walls, pillars=[])


# Arm width (vertical arm) and arm height (horizontal arm) of the cross per kind and size.
CROSS_ARMS = {("normal", "S"): (5, 3), ("normal", "M"): (7, 5), ("normal", "L"): (9, 7),
              ("arena", "M"): (9, 5), ("arena", "L"): (11, 7)}


def shape_cross(kind, size_class):
    """Four arms, the four corners solid: enemies from every side, the middle is dangerous."""
    w, h = SIZE_TILES[size_class]
    arm_w, arm_h = CROSS_ARMS[(kind, size_class)]
    x0, y0 = (w - arm_w) // 2, (h - arm_h) // 2
    x1, y1 = x0 + arm_w, y0 + arm_h
    walls = (rect_tiles(0, 0, x0, y0) | rect_tiles(x1, 0, w - x1, y0)
             | rect_tiles(0, y1, x0, h - y1) | rect_tiles(x1, y1, w - x1, h - y1))
    return dict(size=(w, h), entrance=w // 2, exit_x=w // 2, walls=walls, pillars=[])


RING_BLOCK = {"S": (7, 3), "M": (9, 5), "L": (11, 7)}


def shape_ring(kind, size_class):
    """A massive block in the middle: the way leads around it, archers lose sight."""
    w, h = SIZE_TILES[size_class]
    bw, bh = RING_BLOCK[size_class]
    walls = rect_tiles((w - bw) // 2, (h - bh) // 2, bw, bh)
    return dict(size=(w, h), entrance=w // 2, exit_x=w // 2, walls=walls, pillars=[])


# Divider row and height, the narrow passage (x, width) and the doors on the far sides from it.
CHAMBERS = {"S": dict(row=4, rows=2, gap=(10, 2), entrance=4, exit_x=7),
            "M": dict(row=5, rows=2, gap=(3, 2), entrance=13, exit_x=9),
            "L": dict(row=7, rows=2, gap=(18, 2), entrance=6, exit_x=12)}


def shape_two_chambers(kind, size_class):
    """A wall across the room with one narrow passage: hold the choke or break through."""
    w, h = SIZE_TILES[size_class]
    c = CHAMBERS[size_class]
    walls = rect_tiles(0, c["row"], w, c["rows"]) - rect_tiles(c["gap"][0], c["row"], c["gap"][1], c["rows"])
    return dict(size=(w, h), entrance=c["entrance"], exit_x=c["exit_x"], walls=walls, pillars=[])


PILLAR_GRID = {("normal", "S"): ([2, 5, 9, 12], [2, 6]),
               ("normal", "M"): ([3, 6, 12, 15], [2, 5, 8]),
               ("normal", "L"): ([3, 6, 9, 15, 18, 21], [3, 7, 11])}
PILLAR_LIST = {("arena", "M"): [(4, 3), (14, 3), (4, 7), (14, 7), (9, 5)],
               ("arena", "L"): [(5, 4), (19, 4), (5, 10), (19, 10), (9, 7), (15, 7)]}


def shape_pillar_hall(kind, size_class):
    """Rows of pillars: cover and bow duels; the arena hall is sparser."""
    w, h = SIZE_TILES[size_class]
    if (kind, size_class) in PILLAR_LIST:
        pillars = PILLAR_LIST[(kind, size_class)]
    else:
        xs, ys = PILLAR_GRID[(kind, size_class)]
        pillars = [(x, y) for y in ys for x in xs]
    return dict(size=(w, h), entrance=w // 2, exit_x=w // 2, walls=set(), pillars=pillars)


# Corridors (one tile wide) as polylines; everything else is wall. Two dead ends, two branchings
# on the way to the exit, loops elsewhere (KONZEPT_RAEUME §3.2).
CATACOMB = {
    "M": dict(entrance=9, exit_x=5, paths=[
        [(9, 10), (9, 8), (2, 8), (2, 2), (5, 2), (5, 0)],
        [(2, 5), (6, 5)],
        [(9, 8), (16, 8), (16, 2), (10, 2)],
        [(16, 5), (12, 5), (12, 8)],
    ]),
    "L": dict(entrance=12, exit_x=20, paths=[
        [(12, 14), (12, 11), (20, 11), (20, 0)],
        [(12, 11), (3, 11), (3, 3), (15, 3), (15, 7), (20, 7)],
        [(3, 7), (10, 7)],
        [(9, 3), (9, 0)],
        [(15, 4), (18, 4), (18, 7)],
    ]),
}


def shape_catacomb(kind, size_class):
    """Narrow corridors, only the light circle to see by; dead ends hide enemies and the chest."""
    w, h = SIZE_TILES[size_class]
    c = CATACOMB[size_class]
    floor = set()
    for path in c["paths"]:
        for (ax, ay), (bx, by) in zip(path, path[1:]):
            assert ax == bx or ay == by, f"catacomb {size_class}: corridors run straight"
            for x in range(min(ax, bx), max(ax, bx) + 1):
                for y in range(min(ay, by), max(ay, by) + 1):
                    floor.add((x, y))
    walls = rect_tiles(0, 0, w, h) - floor
    return dict(size=(w, h), entrance=c["entrance"], exit_x=c["exit_x"], walls=walls, pillars=[])


# Chasm templates (A4, KONZEPT_RAEUME §3.1): "." floor, "~" abyss, "=" bridge over the abyss,
# "#" inner wall. Broad abysses need bridges; one-tile gaps are dash shortcuts (D-086).
CHASM_MAPS = {
    # Bridge hall: an abyss band across the room, bridges at the sides, a tongue in the middle
    # leaves a one-tile gap to dash over.
    ("bridge_hall", "S"): dict(entrance=7, exit_x=7, rows=[
        "...............",
        "...............",
        "...............",
        "~~=~~~...~~~=~~",
        "~~=~~~...~~~=~~",
        "~~=~~~~~~~~~=~~",
        "...............",
        "...............",
        "...............",
    ]),
    ("bridge_hall", "M"): dict(entrance=9, exit_x=9, rows=[
        "...................",
        "...................",
        "...................",
        "...................",
        "~~~=~~~~...~~~~=~~~",
        "~~~=~~~~...~..~=~~~",
        "~~~=~~~~~~~~..~=~~~",
        "...................",
        "...................",
        "...................",
        "...................",
    ]),
    ("bridge_hall", "L"): dict(entrance=12, exit_x=12, rows=[
        ".........................",
        ".........................",
        ".........................",
        "~~~~=~~~~~~...~~~~~~=~~~~",
        "~~~~=~~~~~~...~~~~~~=~~~~",
        "~~~~=~~~~~~~~~~~~~~~=~~~~",
        ".........................",
        ".........................",
        ".........................",
        "~~~~~~~~~~~~=~~~~~~...~~~",
        "~~~...~~~~~~=~~~~~~...~~~",
        "~~~...~~~~~~=~~~~~~~~~~~~",
        ".........................",
        ".........................",
        ".........................",
    ]),
    # Islands: platforms in the abyss, joined by bridges; the thin rims are dash shortcuts.
    ("islands", "S"): dict(entrance=7, exit_x=7, rows=[
        "...............",
        "...............",
        "~~~=~~~~~~~=~~~",
        "~.....~~~.....~",
        "~.....===.....~",
        "~.....~~~.....~",
        "~~~~=~~~~~~~~~~",
        "...............",
        "...............",
    ]),
    ("islands", "M"): dict(entrance=9, exit_x=9, rows=[
        "...................",
        "...................",
        "~~=~~~~~~~~~~~~~=~~",
        "~.....~~...~~.....~",
        "~.....==...~~.....~",
        "~.....~~...==.....~",
        "~.....~~...~~.....~",
        "~~~~~~~~~=~~~~~~~~~",
        "...................",
        "...................",
        "...................",
    ]),
    ("islands", "L"): dict(entrance=12, exit_x=12, rows=[
        ".........................",
        ".........................",
        "~~~=~~~~~~~~~~~~~~~~~=~~~",
        "~......~~.......~~......~",
        "~......==.......~~......~",
        "~......~~.......==......~",
        "~......~~.......~~......~",
        "~~~~~~~~~~~~=~~~~~~~~~~~~",
        "~......~~.......~~......~",
        "~......==.......~~......~",
        "~......~~.......==......~",
        "~......~~.......~~......~",
        "~~~~~~~~~~~~=~~~~~~~~~~~~",
        ".........................",
        ".........................",
    ]),
    # Walkway: a narrow winding pier over the abyss with a platform on a bridge.
    ("walkway", "S"): dict(entrance=7, exit_x=7, rows=[
        "...............",
        "...............",
        "~~..~~~~~~~~~~~",
        "~~..~~~~~~....~",
        "~~......~~....~",
        "~~......==....~",
        "~~~~~~..~~~~~~~",
        "...............",
        "...............",
    ]),
    ("walkway", "M"): dict(entrance=9, exit_x=9, rows=[
        "...................",
        "...................",
        "~~~~~~~~~~~~..~~~~~",
        "~~~...........~~~~~",
        "~~~...........~~~~~",
        "~~~..~~~~~~~~~~...~",
        "~~~........====...~",
        "~~~........~~~~...~",
        "~~~~~~~~~..~~~~~~~~",
        "...................",
        "...................",
    ]),
    ("walkway", "L"): dict(entrance=12, exit_x=12, rows=[
        ".........................",
        ".........................",
        "~~~~~~~~~......~~~~..~~~~",
        "~~~~~~~~~......~~~~..~~~~",
        "~~~~~~~~~~~~~~~~~~~..~~~~",
        "~~~~.................~~~~",
        "~~~~.................~~~~",
        "~~~~..~~~~~~~~~~~~~~~~~~~",
        "~~~~..~~~~~~~~~~~~~~~~~~~",
        "~~~~..........~~.......~~",
        "~~~~..........==.......~~",
        "~~~~~~~~~~~~..~~.......~~",
        "~~~~~~~~~~~~..~~~~~~~~~~~",
        ".........................",
        ".........................",
    ]),
    # Ring around a hole: the way leads around the abyss; a bridge leads to the middle, from where
    # a dash crosses to the far side.
    ("ring_hole", "S"): dict(entrance=7, exit_x=7, rows=[
        "...............",
        "...............",
        "...............",
        "....~~~~~~~....",
        "....==...~~....",
        "....~~~~~~~....",
        "...............",
        "...............",
        "...............",
    ]),
    ("ring_hole", "M"): dict(entrance=9, exit_x=9, rows=[
        "...................",
        "...................",
        "...................",
        "....~~~~~~~~~~~....",
        "....~~~.....~~~....",
        "....~~~.....===....",
        "....~~~.....~~~....",
        "....~~~~~~~~~~~....",
        "...................",
        "...................",
        "...................",
    ]),
    ("ring_hole", "L"): dict(entrance=12, exit_x=12, rows=[
        ".........................",
        ".........................",
        ".........................",
        "....~~~~~~~~~~~~~~~~~....",
        "....~~~...........~~~....",
        "....~~~...........===....",
        "....~~~....~~~....~~~....",
        "....===....~~~....~~~....",
        "....~~~....~~~....~~~....",
        "....~~~...........~~~....",
        "....~~~...........~~~....",
        "....~~~~~~~~~~~~~~~~~....",
        ".........................",
        ".........................",
        ".........................",
    ]),
}


def shape_chasm(shape):
    """Chasm shapes from CHASM_MAPS: pits, bridges and inner walls of the map."""
    def build(kind, size_class):
        w, h = SIZE_TILES[size_class]
        c = CHASM_MAPS[(shape, size_class)]
        rows = c["rows"]
        assert len(rows) == h and all(len(r) == w for r in rows), f"chasm {shape} {size_class}: map is not {w}x{h}"
        pits, bridges, walls = set(), set(), set()
        for y, row in enumerate(rows):
            for x, cell in enumerate(row):
                assert cell in ".~=#", f"chasm {shape} {size_class}: unknown cell {cell!r}"
                if cell == "~":
                    pits.add((x, y))
                elif cell == "=":
                    bridges.add((x, y))
                elif cell == "#":
                    walls.add((x, y))
        return dict(size=(w, h), entrance=c["entrance"], exit_x=c["exit_x"], walls=walls, pillars=[],
                    pits=pits, bridges=bridges)
    return build


CHASM_SHAPES = ("bridge_hall", "islands", "walkway", "ring_hole")


def dash_shortcuts(walkable_floor, pits):
    """Pairs of floor tiles with exactly one pit tile between them in a straight line."""
    shortcuts = []
    for x, y in walkable_floor:
        for dx, dy in ((1, 0), (0, 1)):
            gap, far = (x + dx, y + dy), (x + 2 * dx, y + 2 * dy)
            if gap in pits and far in walkable_floor:
                shortcuts.append(((x, y), far))
    return shortcuts


SHAPE_BUILDERS = {"rectangle": shape_rectangle, "l_shape": shape_l, "cross": shape_cross, "ring": shape_ring,
                  "two_chambers": shape_two_chambers, "pillar_hall": shape_pillar_hall, "catacomb": shape_catacomb,
                  **{shape: shape_chasm(shape) for shape in CHASM_SHAPES}}

# Every combat template: (kind, shape, size). Arena shapes: rectangle M/L, cross, pillar hall (A3/A5).
COMBAT_TEMPLATES = (
    [("normal", shape, size) for shape in ("rectangle", "l_shape", "cross", "ring", "two_chambers", "pillar_hall")
     for size in ("S", "M", "L")]
    + [("normal", "catacomb", size) for size in ("M", "L")]
    + [("arena", shape, size) for shape in ("rectangle", "cross", "pillar_hall") for size in ("M", "L")]
    + [("chasm", shape, size) for shape in CHASM_SHAPES for size in ("S", "M", "L")]
)


def allowed_ingredients(kind, shape):
    """Ingredients the IngredientScatter may use: arenas stay open (little cover, no extra walls),
    the catacomb has walls enough, the pillar hall its pillars, a chasm room its abyss (no extra
    walls or holes there). Small holes (A4) everywhere else; the set keeps them out of rooms 1-5."""
    if shape == "catacomb":
        return [TRAPS, LIGHT, EXPLOSIVES]
    if kind == "chasm":
        return [COVER, TRAPS, LIGHT, EXPLOSIVES]
    if kind == "arena" or shape == "pillar_hall":
        return [COVER, TRAPS, LIGHT, EXPLOSIVES, PITS]
    return list(ALL_INGREDIENTS)


# --- Analysis helpers ---

def neighbours(tile, walkable):
    x, y = tile
    return [n for n in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)) if n in walkable]


def bfs(walkable, start):
    """Distances and parents of a 4-neighbour breadth-first search (fixed neighbour order)."""
    dist, parent = {start: 0}, {start: None}
    queue = deque([start])
    while queue:
        tile = queue.popleft()
        for n in neighbours(tile, walkable):
            if n not in dist:
                dist[n] = dist[tile] + 1
                parent[n] = tile
                queue.append(n)
    return dist, parent


def path_to(parent, goal):
    path = []
    while goal is not None:
        path.append(goal)
        goal = parent[goal]
    return path[::-1]


def catacomb_rules(name, size, walkable, start, exit_tile):
    """Dead ends (floor tiles with one neighbour) sorted deepest first; asserts the catacomb rules."""
    w, h = size
    floor = [t for t in walkable if 0 <= t[0] < w and 0 <= t[1] < h]
    dead_ends = [t for t in floor if len(neighbours(t, walkable)) == 1]
    assert len(dead_ends) <= MAX_DEAD_ENDS, f"{name}: {len(dead_ends)} dead ends (max {MAX_DEAD_ENDS})"
    dist, parent = bfs(walkable, start)
    junctions = [t for t in path_to(parent, exit_tile) if t in floor and len(neighbours(t, walkable)) >= 3]
    assert len(junctions) <= MAX_JUNCTIONS_TO_EXIT, f"{name}: {len(junctions)} branchings to the exit"
    return sorted(dead_ends, key=lambda t: (-dist[t], t[1], t[0]))


def dead_end_corridor(tip, walkable):
    """Tiles from a dead-end tip back to the first branching (excluded)."""
    corridor, previous, tile = [tip], None, tip
    while True:
        options = [n for n in neighbours(tile, walkable) if n != previous]
        if len(options) != 1:
            break
        previous, tile = tile, options[0]
        if len(neighbours(tile, walkable)) >= 3:
            break
        corridor.append(tile)
    return corridor


def chebyshev(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def pick_spawns(floor, start, exit_tile, count, seeds, excluded):
    """Farthest-point sampling over reachable floor: markers spread over the room, away from the
    entrance; seeds (ambush spots) come first. Deterministic."""
    picked = list(seeds)
    candidates = [t for t in floor if t not in excluded and t not in picked
                  and chebyshev(t, start) > ENTRANCE_CLEARANCE and chebyshev(t, exit_tile) > EXIT_CLEARANCE]
    while len(picked) < count and candidates:
        anchors = picked + [start]
        best = max(candidates, key=lambda t: (min((t[0] - a[0]) ** 2 + (t[1] - a[1]) ** 2 for a in anchors), -t[1], -t[0]))
        picked.append(best)
        candidates.remove(best)
    return picked


def pick_torches(size, exit_x, walkable, count):
    """Wall torches over floor columns, evenly spread, never right beside the exit door (D1)."""
    w, _ = size
    columns = [x for x in range(1, w - 1) if (x, 0) in walkable and abs(x - exit_x) >= DOOR_TORCH_CLEARANCE]
    torches = []
    for i in range(count):
        target = w * (i + 1) / (count + 1)
        options = [x for x in columns if all(abs(x - t) >= 3 for t in torches)]
        if not options:
            break
        torches.append(min(options, key=lambda x: (abs(x - target), x)))
    return sorted(torches)


def pick_bones(floor, walkable, count, seed, excluded):
    """Bones in corners and along walls (decoration, walkable)."""
    rng = random.Random(seed)
    options = [t for t in floor if t not in excluded]
    rng.shuffle(options)
    options.sort(key=lambda t: -sum((t[0] + dx, t[1] + dy) not in walkable for dx in (-1, 0, 1) for dy in (-1, 0, 1)))
    bones = []
    for tile in options:
        if len(bones) >= count:
            break
        if all(chebyshev(tile, b) >= 3 for b, _ in bones):
            bones.append((tile, "bones_1" if len(bones) % 2 == 0 else "bones_2"))
    return bones


def pick_cobwebs(floor, walkable, count, seed, excluded):
    """Cobwebs in upper corners of corridors (wall north and west, or north and east = mirrored)."""
    rng = random.Random(seed + 1)
    options = [t for t in floor if t not in excluded and (t[0], t[1] - 1) not in walkable
               and ((t[0] - 1, t[1]) not in walkable or (t[0] + 1, t[1]) not in walkable)]
    rng.shuffle(options)
    webs = []
    for tile in options:
        if len(webs) >= count:
            break
        if all(chebyshev(tile, w) >= 4 for w, _ in webs):
            webs.append((tile, (tile[0] - 1, tile[1]) in walkable))
    return webs


def nearest_floor(floor, target):
    return min(floor, key=lambda t: ((t[0] + 0.5 - target[0]) ** 2 + (t[1] + 0.5 - target[1]) ** 2, t[1], t[0]))


def to_rects(tiles):
    """Wall tiles as few Rect2i: horizontal runs, merged downwards when identical."""
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
    assert covered == set(tiles), "wall rects do not cover the wall tiles exactly"
    return sorted(rects, key=lambda r: (r[1], r[0]))


def vec_list(tiles):
    return "Array[Vector2i]([" + ", ".join(f"Vector2i({x}, {y})" for x, y in tiles) + "])"


# --- Combat templates ---

def combat_template(kind, shape, size_class):
    """Builds, checks and writes one combat template and its RoomTemplate. Returns the template id."""
    stem, root = LEGACY_NAMES.get((kind, shape, size_class), (None, None))
    if stem is None:
        stem = f"{kind}_{shape}_{size_class.lower()}"
        root = "".join(part.capitalize() for part in stem.split("_"))
    name = f"{stem} ({kind}, {shape}, {size_class})"
    layout = SHAPE_BUILDERS[shape](kind, size_class)
    size, entrance, exit_x = layout["size"], layout["entrance"], layout["exit_x"]
    w, h = size
    walls, pillars = set(layout["walls"]), list(layout["pillars"])
    pits, bridges = set(layout.get("pits", ())), set(layout.get("bridges", ()))
    blocked = walls | pillar_mass(pillars, size)
    check_wall_mass(name, size, blocked)
    walkable = walkable_tiles(size, entrance, exit_x, blocked, pits)
    start, exit_tile = (entrance, h - 1), (exit_x, 0)
    reached = flood_fill(walkable, pits, start, MAX_DASH_GAP)
    # Floor that can hold markers and props: no bridge (and never a pit).
    all_floor = sorted((t for t in walkable if 0 <= t[0] < w and 0 <= t[1] < h), key=lambda t: (t[1], t[0]))
    floor = [t for t in all_floor if t not in bridges]
    unreached = [t for t in all_floor if t not in reached]
    assert not unreached, f"{name}: floor tiles cut off from the entrance: {unreached[:5]}"
    for tile in ((entrance, h - 1), (entrance, h - 2), (exit_x, 0), (exit_x, 1)):
        assert tile in walkable, f"{name}: door lane {tile} blocked"
    if pits:
        on_foot = flood_fill(walkable, set(), start, 0)
        stranded = [t for t in all_floor if t not in on_foot]
        assert not stranded, f"{name}: floor only reachable with a dash (enemies cannot follow): {stranded[:5]}"
        assert (exit_x, -3) in on_foot, f"{name}: exit not reachable on foot"
        assert dash_shortcuts(set(floor), pits), f"{name}: no one-tile gap to dash over"
        lanes = {(entrance + dx, h - 1 - dy) for dx in (-1, 0, 1) for dy in range(PIT_FREE_DOOR_ROWS)}
        lanes |= {(exit_x + dx, dy) for dx in (-1, 0, 1) for dy in range(PIT_FREE_DOOR_ROWS)}
        assert not (lanes & (pits | bridges)), f"{name}: abyss in a door lane: {sorted(lanes & (pits | bridges))[:4]}"

    chest, ambush, reserved = None, [], []
    if shape == "catacomb":
        dead_ends = catacomb_rules(name, size, walkable, start, exit_tile)
        for i, tip in enumerate(dead_ends):
            corridor = dead_end_corridor(tip, walkable)
            if i == 0:
                # The deepest dead end holds the chest; its guards wait a little further back.
                chest = tip
                ambush += corridor[2:4]
            else:
                ambush += corridor[0:3:2]
        reserved = [chest] + [n for n in neighbours(chest, walkable)]
    count = (ARENA_SPAWN_COUNT if kind == "arena" else SPAWN_COUNT)[size_class]
    spawns = pick_spawns(floor, start, exit_tile, count, ambush, set(reserved))
    assert MIN_SPAWNS[size_class] <= len(spawns) <= MAX_SPAWNS, \
        f"{name}: size {size_class} needs {MIN_SPAWNS[size_class]}-{MAX_SPAWNS} spawn markers (D-086), has {len(spawns)}"

    props = []
    torch_count = 1 if shape == "catacomb" else TORCH_COUNT[size_class]
    for x in pick_torches(size, exit_x, walkable, torch_count):
        assert abs(x - exit_x) >= DOOR_TORCH_CLEARANCE, f"{name}: torch beside the exit door"
        props.append(("torch", x, 0))
    seed = zlib.crc32(stem.encode()) % 997 + 1
    bones_count = BONES_COUNT[size_class] + (2 if shape == "catacomb" else 0)
    lanes = {(entrance + dx, h - 1 - dy) for dx in (-1, 0, 1) for dy in range(3)}
    lanes |= {(exit_x + dx, dy) for dx in (-1, 0, 1) for dy in range(3)}
    for tile, bone in pick_bones(floor, walkable - bridges, bones_count, seed, set(spawns) | set(reserved) | lanes):
        props.append(("bone_pile" if shape == "catacomb" and bone == "bones_1" else bone, tile[0], tile[1]))
    flipped = set()
    if shape == "catacomb":
        for tile, flip in pick_cobwebs(floor, walkable, COBWEB_COUNT[size_class], seed, set(reserved) | lanes):
            props.append(("cobweb", tile[0], tile[1]))
            if flip:
                flipped.add(tile)
    if chest is not None:
        props.append(("chest", chest[0], chest[1]))
    check_layout(name, size, entrance, exit_x, spawns, props, blocked=blocked, pits=pits)
    for kind_, x, y in props:
        assert (x, y) not in pits and (x, y) not in bridges, f"{name}: {kind_} over the abyss at {(x, y)}"

    content = nearest_floor(floor, (w / 2, h / 2))
    portal = nearest_floor(floor, (w * 0.75, 2.5))
    rel_path = f"combat/{stem}.tscn"
    pit_rects = to_rects(pits | bridges) if pits else []
    bridge_rects = to_rects(bridges) if bridges else []
    _write_combat_scene(rel_path, root, kind, size_class, size, entrance, exit_x, seed, pillars, to_rects(walls) if walls else [],
                        spawns, set(ambush), content, portal, props, allowed_ingredients(kind, shape), reserved, flipped,
                        pit_rects, bridge_rects)
    min_room = CHASM_FROM_ROOM if kind == "chasm" else MIN_ROOM.get(shape, 1)
    _write_template_resource(stem, rel_path, kind, shape, size_class, size, spawns, ambush, chest, min_room)
    return stem


def _write_combat_scene(rel_path, root, kind, size_class, size, entrance, exit_x, seed, pillars, wall_rects, spawns,
                        ambush, content, portal, props, allowed, reserved, flipped=(), pit_rects=(), bridge_rects=()):
    used = sorted({p[0] for p in props})
    ids = {k: f"{i + 2}_{k}" for i, k in enumerate(used)}
    scatter_id = f"{len(used) + 2}_scatter"
    text = '[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="res://dungeon/rooms/room_base.tscn" id="1_base"]\n'
    for k in used:
        text += f'[ext_resource type="PackedScene" path="{DECO[k]}" id="{ids[k]}"]\n'
    text += f'[ext_resource type="Script" path="{SCATTER_SCRIPT}" id="{scatter_id}"]\n'
    text += f'\n[node name="{root}" instance=ExtResource("1_base")]\n'
    text += f"room_kind = {KINDS[kind]}\nroom_size_class = {SIZES[size_class]}\n"
    text += '\n[node name="Tiles" parent="."]\n'
    text += f"room_size = Vector2i({size[0]}, {size[1]})\nentrance_x = {entrance}\nexit_x = {exit_x}\nfloor_seed = {seed}\n"
    if pillars:
        text += f"pillar_tiles = {vec_list(pillars)}\n"
    if wall_rects:
        text += "wall_rects = Array[Rect2i]([" + ", ".join(f"Rect2i({x}, {y}, {w}, {h})" for x, y, w, h in wall_rects) + "])\n"
    if pit_rects:
        text += "pit_rects = Array[Rect2i]([" + ", ".join(f"Rect2i({x}, {y}, {w}, {h})" for x, y, w, h in pit_rects) + "])\n"
    if bridge_rects:
        text += "bridge_rects = Array[Rect2i]([" + ", ".join(f"Rect2i({x}, {y}, {w}, {h})" for x, y, w, h in bridge_rects) + "])\n"
    for i, (x, y) in enumerate(spawns):
        # Spawn1..5 exist in room_base; further markers are new nodes. Ambush markers sit in dead ends.
        node_type = ' type="Marker2D"' if i >= BASE_SPAWNS else ""
        text += f'\n[node name="Spawn{i + 1}"{node_type} parent="SpawnPoints"]\nposition = {centre(x, y)}\n'
        if (x, y) in ambush:
            text += "metadata/ambush = true\n"
    text += f'\n[node name="ContentAnchor" parent="."]\nposition = {centre(*content)}\n'
    text += f'\n[node name="PortalAnchor" parent="."]\nposition = {centre(*portal)}\n'
    for i, (k, x, y) in enumerate(props):
        text += f'\n[node name="{k.capitalize()}{i}" parent="Props" instance=ExtResource("{ids[k]}")]\nposition = {prop_position(k, x, y)}\n'
        if k == "cobweb" and (x, y) in flipped:
            text += "flip_h = true\n"
    text += f'\n[node name="Ingredients" type="Node2D" parent="."]\ny_sort_enabled = true\nscript = ExtResource("{scatter_id}")\n'
    text += "allowed = Array[int]([" + ", ".join(str(a) for a in allowed) + "])\n"
    if reserved:
        text += f"reserved_tiles = {vec_list(reserved)}\n"
    write(ROOMS / rel_path, text, combat=True)


def _write_template_resource(stem, rel_path, kind, shape, size_class, size, spawns, ambush, chest, min_room=1):
    text = '[gd_resource type="Resource" script_class="RoomTemplate" format=3]\n\n'
    text += f'[ext_resource type="Script" path="{TEMPLATE_SCRIPT}" id="1_template"]\n'
    text += f'[ext_resource type="PackedScene" path="res://dungeon/rooms/{rel_path}" id="2_scene"]\n\n'
    text += '[resource]\nscript = ExtResource("1_template")\n'
    text += f'id = &"{stem}"\nscene = ExtResource("2_scene")\n'
    text += f"room_kind = {KINDS[kind]}\nshape = {SHAPES[shape]}\nsize_class = {SIZES[size_class]}\n"
    text += f"room_size = Vector2i({size[0]}, {size[1]})\n"
    text += f"entrance_side = {SIDE_SOUTH}\nexit_sides = Array[int]([{SIDE_NORTH}])\n"
    text += f"spawn_tiles = {vec_list(spawns)}\n"
    if ambush:
        text += f"ambush_tiles = {vec_list(ambush)}\n"
    if chest is not None:
        text += f"chest_tile = Vector2i({chest[0]}, {chest[1]})\n"
    if min_room != 1:
        text += f"min_room = {min_room}\n"
    write(TEMPLATES / f"{stem}.tres", text, combat=True)


def catalog(stems):
    """combat_catalog.tres: the RoomTemplate of every combat template, read by RoomCatalog.create()."""
    text = '[gd_resource type="Resource" script_class="RoomCatalog" format=3]\n\n'
    text += '[ext_resource type="Script" path="res://dungeon/rooms/room_catalog.gd" id="1_catalog"]\n'
    text += f'[ext_resource type="Script" path="{TEMPLATE_SCRIPT}" id="2_template"]\n'
    for i, stem in enumerate(stems):
        text += f'[ext_resource type="Resource" path="res://dungeon/rooms/templates/{stem}.tres" id="{i + 3}_{stem}"]\n'
    entries = ", ".join(f'ExtResource("{i + 3}_{stem}")' for i, stem in enumerate(stems))
    text += f'\n[resource]\nscript = ExtResource("1_catalog")\nentries = Array[ExtResource("2_template")]([{entries}])\n'
    write(CATALOG, text, combat=True)


def main():
    global MODE
    if "--combat-only" in sys.argv[1:]:
        MODE = "combat"
    base()
    catalog([combat_template(kind, shape, size) for kind, shape, size in COMBAT_TEMPLATES])
    variant("special/special_room.tscn", "SpecialRoom", (13, 9), 6, 6, [], 51,
            [(2, 2), (10, 2), (6, 2), (2, 6), (10, 6)], (6.5, 4.2), (10.5, 2.5),
            [("torch", 2, 0), ("torch", 10, 0), ("barrel", 0, 0), ("crate", 12, 7)])
    variant("boss/miniboss_room.tscn", "MinibossRoom", (15, 11), 7, 7, [(3, 3), (11, 3)], 61,
            [(3, 2), (11, 2), (7, 3), (2, 7), (12, 7)], (7.5, 3.5), (12.5, 3),
            [("torch", 3, 0), ("torch", 5, 0), ("torch", 9, 0), ("torch", 11, 0), ("bones_1", 2, 9), ("bones_2", 12, 9),
             ("trap", 5, 7), ("trap", 9, 7), ("crate", 0, 0), ("barrel", 14, 0)])
    campfire()
    variant("boss/boss_room.tscn", "BossRoom", (19, 13), 9, 9, [(3, 3), (15, 3), (3, 9), (15, 9)], 71,
            [(3, 2), (15, 2), (9, 3), (2, 10), (16, 10)], (9.5, 4), (16.5, 2.5),
            [("torch", 2, 0), ("torch", 6, 0), ("torch", 12, 0), ("torch", 16, 0),
             ("bones_1", 1, 11), ("bones_2", 17, 11), ("bones_1", 9, 11)])
    print(f"{len(COMBAT_TEMPLATES)} combat templates and the other room templates written to", ROOMS)
    for path in _skipped:
        print("  not written (--combat-only), differs from the generator:", path.relative_to(ROOMS))


if __name__ == "__main__":
    main()
