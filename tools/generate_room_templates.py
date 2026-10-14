"""Generates dungeon room templates (.tscn) from tile coordinates.

Usage (from the project root):  python tools/generate_room_templates.py
One tile = 64 world px (32 px art at scale 2). The templates stay normal Godot scenes that can be
edited in the editor afterwards; re-running this script overwrites them.

Combat templates carry a room kind and a size class (D-086), stored on the RoomController root and
listed in dungeon/rooms/combat/combat_catalog.tres (RoomCatalog). Every template is checked before
it is written: spawn marker count per size, exit and all spawn markers reachable from the entrance
(walking, plus dashing over gaps of at most one pit tile), no marker on blocked tiles, traps,
props or right next to the entrance.

The campfire template (D-103, ROADMAP_AUSBAU A6) sits between two biomes after every boss room.
It has no enemies; the fire stands on ContentAnchor, the exit portal on PortalAnchor. Its floor
blend and content are built at runtime (RoomController, CampfireContent).
"""
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
}
# RoomSequence.RoomKind / RoomSequence.RoomSize (same order as the GDScript enums).
KINDS = {"arena": 0, "structured": 1, "abyss": 2}
SIZES = {"S": 0, "M": 1, "L": 2}
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
SOLID_PROPS = {"crate", "barrel"}
CATALOG = ROOMS / "combat" / "combat_catalog.tres"
# Campfire (A6): free tiles the fire, its seat and the bedroll take around ContentAnchor, as
# offsets in tiles from the anchor tile. Spawn markers and the way through must avoid them.
CAMPFIRE_SIZE = (13, 11)
CAMPFIRE_DOOR_X = 6
CAMPFIRE_ANCHOR = (6.5, 5.6)
CAMPFIRE_PORTAL = (10.5, 2.6)
CAMPFIRE_BLOCKED = [(-1, 0), (0, 0), (1, 0), (-2, 0)]


def centre(tx, ty):
    return f"Vector2({(tx + 0.5) * T:g}, {(ty + 0.5) * T:g})"


def write(path, text):
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


def check_layout(name, size, entrance, exit_x, spawns, props, blocked=(), pits=()):
    """Asserts a playable layout. A3 passes inner wall tiles in blocked, A4 abyss tiles in pits."""
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
    """props: (kind, tile_x, tile_y); torches hang on the north wall front (row -1).
    room_kind/size_class: only for combat templates (keys of KINDS / SIZES)."""
    if room_kind is not None:
        assert room_kind in KINDS and size_class in SIZES, f"{root}: unknown room kind or size class"
        assert MIN_SPAWNS[size_class] <= len(spawns) <= MAX_SPAWNS, \
            f"{root}: size {size_class} needs {MIN_SPAWNS[size_class]}-{MAX_SPAWNS} spawn markers (D-086), has {len(spawns)}"
    else:
        assert len(spawns) == BASE_SPAWNS, f"{root}: non-combat templates keep exactly {BASE_SPAWNS} spawn markers"
    check_layout(root, size, entrance, exit_x, spawns, props, blocked=pillars)
    used = sorted({p[0] for p in props})
    ids = {kind: f"{i + 2}_{kind}" for i, kind in enumerate(used)}
    text = '[gd_scene format=3]\n\n[ext_resource type="PackedScene" path="res://dungeon/rooms/room_base.tscn" id="1_base"]\n'
    for kind in used:
        text += f'[ext_resource type="PackedScene" path="{DECO[kind]}" id="{ids[kind]}"]\n'
    text += f'\n[node name="{root}" instance=ExtResource("1_base")]\n'
    if room_kind is not None:
        text += f"room_kind = {KINDS[room_kind]}\nroom_size_class = {SIZES[size_class]}\n"
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
        if kind == "torch":
            pos = f"Vector2({x * T:g}, {-T:g})"
        elif kind == "trap":
            pos = centre(x, y)
        else:
            pos = f"Vector2({(x + 0.5) * T:g}, {(y + 1) * T - 8:g})"
        text += f'\n[node name="{kind.capitalize()}{i}" parent="Props" instance=ExtResource("{ids[kind]}")]\nposition = {pos}\n'
    write(ROOMS / rel_path, text)
    return f"res://dungeon/rooms/{rel_path}" if room_kind is not None else None


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


def catalog(paths):
    """combat_catalog.tres: every combat template, read by RoomCatalog.create()."""
    text = '[gd_resource type="Resource" script_class="RoomCatalog" format=3]\n\n'
    text += '[ext_resource type="Script" path="res://dungeon/rooms/room_catalog.gd" id="1_catalog"]\n'
    for i, path in enumerate(paths):
        text += f'[ext_resource type="PackedScene" path="{path}" id="{i + 2}_template"]\n'
    entries = ", ".join(f'ExtResource("{i + 2}_template")' for i in range(len(paths)))
    text += f'\n[resource]\nscript = ExtResource("1_catalog")\ntemplates = Array[PackedScene]([{entries}])\n'
    write(CATALOG, text)


def main():
    base()
    # Combat templates (D-086): kind and size class; M needs at least eight spawn markers.
    combat = [
        variant("combat/combat_hall.tscn", "CombatHall", (15, 9), 7, 7, [], 11,
                [(3, 2), (11, 2), (7, 3), (2, 5), (12, 5)], (7.5, 3.5), (11.5, 3),
                [("torch", 3, 0), ("torch", 11, 0), ("bones_1", 1, 7), ("crate", 13, 0), ("barrel", 1, 0),
                 ("trap", 5, 5), ("trap", 9, 5)],
                room_kind="arena", size_class="S"),
        variant("combat/combat_pillars.tscn", "CombatPillars", (17, 10), 8, 8, [(4, 3), (12, 3), (4, 6), (12, 6)], 23,
                [(2, 1), (8, 1), (14, 1), (6, 5), (10, 5)], (8.5, 4), (13.5, 3),
                [("torch", 2, 0), ("torch", 6, 0), ("torch", 10, 0), ("torch", 14, 0),
                 ("bones_2", 8, 7), ("barrel", 15, 8), ("crate", 1, 8),
                 ("trap", 8, 4), ("trap", 4, 8), ("trap", 12, 8), ("crate", 15, 1)],
                room_kind="structured", size_class="S"),
        variant("combat/combat_wide.tscn", "CombatWide", (19, 8), 4, 14, [(9, 3), (9, 4)], 37,
                [(2, 1), (7, 2), (12, 1), (16, 3), (13, 5), (5, 2), (10, 6), (17, 1)], (9.5, 3.5), (15.5, 3),
                [("torch", 1, 0), ("torch", 7, 0), ("torch", 17, 0), ("bones_1", 16, 6), ("crate", 0, 6), ("barrel", 18, 0),
                 ("trap", 6, 5), ("trap", 12, 3), ("trap", 15, 6), ("barrel", 0, 0)],
                room_kind="arena", size_class="M"),
    ]
    catalog(combat)
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
    print("room templates written to", ROOMS)


if __name__ == "__main__":
    main()
