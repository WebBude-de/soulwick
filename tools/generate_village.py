"""Generates world/village/village.tscn (tile layout, buildings, houses, NPCs, villagers, decoration).

Usage (from the project root):  python tools/generate_village.py
One tile = 64 world px. Buildings use the village_v2 art (art/environment/buildings/village_v2.json):
they are drawn at the same scale as the player (2x), their pivot is the bottom centre of the door,
so the node origin sits on the door and y-sorting against the player is correct. Each building has
a solid footprint over the walls and most of the roof and an Interactable at its door that opens
the building's dialog (D-078). Enterable buildings get a wooden sign above the door (art/ui/sign_*.png,
24x16, pivot top centre, SPRITES_V3 section 4) so their purpose is visible from outside (D-087).
The player's home (MM1, KE8) leads into the home interior ("Eintreten").

B3 (Dorf beleben): neighbour houses (house_1..3, no door), barrels, crates, garden fences, chimney
smoke, villagers walking routes on the paths, pollen/fireflies. Props whose art may be missing are
placed as VillageProp/Villager and appear once the file exists (or with a drawn placeholder).
Small decoration (flowers, stones, grass, bushes) is scattered at runtime by VillageDecor.

R7 (Dorf und Dungeon-Eingang, docs/design/responses/06_dorf.md): no symmetric cross any
more. A cobbled village square with the fountain in the middle, the houses around it slightly offset,
lanes leaving it to the west, the south (spawn) and the east; the way to the dungeon climbs from the
square's north-east corner to stairs in a ridge (rock face, solid) at the top edge. On the terrace
above: the ruin of the entrance (dungeon_entrance_v2, VillageEntrance with torches and ravens), a
path of stone slabs and the soul flame bowl in front, forest around it. Fences, beds and hay bales
stand in groups (chicken yard, vegetable garden); chickens and the cat keep to their territory.
Slots for rescued villagers and chickens (RescueRecord, D-135): Village keeps as many as were rescued.

Reports 17.10.2026 (hitboxes like the hay bales: the visible width minus a little, the lower part of
the art): flower beds are solid (#5a560cd1), crates, barrels and the market stall have a box instead
of a small circle (#0a088654, #90544fa9), the flat rubble lies under characters, weapons and shadows
(#d83bda23), animals dodge the player without the villagers' sound (#ec4f0b9f).

Reports 23.10.2026 (#0ef74410, #7539cc72 "Hier kann man die Map verlassen"): the fence tiles alone
left a gap in every corner (vertical and horizontal bar do not meet), so the village gets a closed
ring of walls (Bounds) from outside the map up to the inner side of the fence line.

WK12 (D-196, Dorftiere zum Anfassen): every animal has a kind (animal = chicken, cat, dog) and reacts
when spoken to (world/village/village_animal.gd). The dog lies in wait for its art: without
art/characters/npcs/dog_idle_<n>f.png it frees itself like the other optional animals.
"""
from pathlib import Path

T = 64
SCALE = 2
OUT = Path(__file__).resolve().parent.parent / "world" / "village" / "village.tscn"
ART_UI = Path(__file__).resolve().parent.parent / "art" / "ui"
MAP_SIZE = (32, 20)
BUILDING_DIR = "res://art/environment/buildings"
PROP_DIR = "res://art/environment/props"

# Sprite facts (art px) from village_v2.json / buildings.json: size, pivot (door or bottom centre),
# chimney top (None = no chimney).
SPRITES = {
    "forge": {"size": (96, 96), "pivot": (48, 93), "chimney": (78, 1)},
    "trading_post": {"size": (96, 80), "pivot": (30, 77), "chimney": None},
    "chronicle_hall": {"size": (80, 96), "pivot": (52, 93), "chimney": None},
    "guild_hall": {"size": (112, 96), "pivot": (56, 93), "chimney": None},
    "home": {"size": (80, 80), "pivot": (40, 77), "chimney": (62, 2)},
    "house_1": {"size": (64, 64), "pivot": (32, 62), "chimney": None},
    "house_2": {"size": (80, 64), "pivot": (40, 62), "chimney": (65, 1)},
    "house_3": {"size": (96, 80), "pivot": (48, 78), "chimney": (81, 1)},
}
# Walls take roughly the lower half of each sprite; the footprint also covers this share of the
# roof, so the player cannot walk "into" the house but can still pass close behind it.
WALL_SHARE = 0.5
ROOF_SOLID = 0.55

# Door signs (art px): doors are 30 px high (village_v2.json); the sign hangs this far above the pivot.
DOOR_HEIGHT = 30
SIGN_SIZE = (24, 16)
SIGN_GAP = 1

# Ground (tiles, x, y, w, h). Ridge with the rock face in row 6, the terrace (rows 1-5) above it.
# Paths: the square (with a dirt rim around the cobbles), the climb to the stairs, the west lane,
# the south path to the spawn, the lane in the south-west and the east lane.
PATHS = [
    (13, 9, 8, 5), (12, 10, 10, 3),  # square with cut corners, dirt rim
    (21, 8, 3, 2), (22, 7, 2, 1),  # climb from the square's north-east corner to the stairs
    (2, 10, 10, 2),            # west lane
    (15, 14, 2, 5),            # south path to the spawn
    (3, 17, 12, 2),            # south-west lane
    (17, 15, 14, 2),           # east lane
]
PLAZA = [(14, 10, 6, 3), (13, 11, 8, 1)]  # cobbles inside the square, rounded
CLIFFS = [(1, 6, 21, 1), (24, 6, 7, 1)]
STAIRS = [(22, 6, 2, 1)]
SLABS = [(22, 4, 2, 2)]
ENTRANCE = (23, 4)
SPAWN = (16.0, 17.8)
# Border ring (world px): the fence bars of the tileset (village_tileset.tres, 2x) end this far inside
# the map edge: vertical bar x 22..42, top bar y 24..44, bottom bar 40..20 above the edge. The walls
# reach WALL_OUTSIDE beyond the map, so nothing slips around a corner.
WALL_INNER_SIDE = 42
WALL_INNER_TOP = 44
WALL_INNER_BOTTOM = 40
WALL_OUTSIDE = 128

# node name, sprite, tile position of the door pivot, caption, prompt, building id, door sign
BUILDINGS = [
    ("Forge", "forge", (8.6, 10), "Schmiede", "Schmiede betreten", "forge", "sign_forge"),
    ("Chronicle", "chronicle_hall", (14.6, 9), "Chronik", "Chronik betreten", "chronicle", "sign_chronicle"),
    ("Home", "home", (11.2, 17), "Zuhause", "Eintreten", "home", "sign_home"),
    ("TradingPost", "trading_post", (23.6, 15), "Handelsposten", "Handelsposten betreten", "trader", "sign_trading"),
    ("Guild", "guild_hall", (28.4, 15), "Gilde", "Gilde betreten", "guild", "sign_guild"),
]
# Neighbour houses without a door: name, sprite, tile position (bottom centre), mirrored
HOUSES = [
    ("HouseW", "house_2", (4.4, 10), False),
    ("HouseN", "house_1", (18.2, 9), True),
    ("HouseNE", "house_3", (27.4, 10.4), False),
    ("HouseSW", "house_1", (4.6, 17), False),
    ("HouseS", "house_3", (7.9, 17), True),
]
# npc name, frames, tile position (feet), face left
NPCS = [
    ("Smith", "smith", (10.55, 9.95), True),
    ("Chronicler", "chronicler", (16.1, 8.95), True),
    ("Trader", "trader", (26.15, 14.95), True),
    ("GuildMaster", "guild_master", (30.45, 14.95), True),
]
# decoration: name, folder, texture, size, pivot, tile position, solid (0 = none, a number = circle
# radius around (0, -8), a pair (w, h) = box in world px standing on the base line), frames
LAMP = (BUILDING_DIR, "lamp_post_4f", (16, 48), (8, 47))
BARREL = (PROP_DIR, "barrel", (32, 32), (16, 31))
CRATE = (PROP_DIR, "crate", (32, 32), (16, 31))
# TESTWERTE (17.10.2026): boxes from the opaque art (2x): barrel 44 px wide -> 40 x 20, crate 52 x 48
# -> 48 x 22, market stall counter 116 px wide (the awning above it is wider) -> 116 x 30.
BARREL_SOLID = (40, 20)
CRATE_SOLID = (48, 22)
STALL_SOLID = (116, 30)
DECOR = [
    ("Fountain", PROP_DIR, "fountain_4f", (32, 40), (16, 38), (16.5, 12.1), 20, 4),
    ("Well", BUILDING_DIR, "well_4f", (32, 40), (16, 38), (6.5, 9.6), 22, 4),
    ("MarketStall", BUILDING_DIR, "market_stall", (64, 48), (32, 44), (20.3, 12.9), STALL_SOLID, 1),
    # Lamps as light islands (VillageDaylight.LAMP_RADIUS = 3 tiles), not along one axis.
    ("Lamp1", *LAMP, (12.35, 13.75), 8, 4),
    ("Lamp2", *LAMP, (12.45, 9.75), 8, 4),
    ("Lamp3", *LAMP, (20.6, 7.75), 8, 4),
    ("Lamp4", *LAMP, (6.0, 12.4), 8, 4),
    ("Lamp5", *LAMP, (17.5, 18.6), 8, 4),
    ("Lamp6", *LAMP, (22.0, 17.6), 8, 4),
    ("Barrel1", *BARREL, (6.0, 16.9), BARREL_SOLID, 1),
    ("Barrel2", *BARREL, (25.5, 10.3), BARREL_SOLID, 1),
    ("Barrel3", *BARREL, (22.3, 14.9), BARREL_SOLID, 1),
    ("Barrel4", *BARREL, (10.7, 8.6), BARREL_SOLID, 1),
    ("Crate1", *CRATE, (29.5, 10.4), CRATE_SOLID, 1),
    ("Crate2", *CRATE, (2.6, 16.9), CRATE_SOLID, 1),
    ("Crate3", *CRATE, (24.9, 14.95), CRATE_SOLID, 1),
    ("Crate4", *CRATE, (21.6, 13.85), CRATE_SOLID, 1),
]
# Props (art/environment/village/<art>.png; placeholder or hidden until then): name, art, tile
# position (bottom centre), solid size in world px (None = walk through), mirrored, extra lines.
BOWL_LIGHT = 'frames = 6\nfps = 8.0\nlight_radius = 170.0\nlight_color = Color(0.72, 0.45, 1, 1)\nlight_height = 40.0\n'
# TESTWERT: flower beds (32 x 14 art, 64 x 28 world) like the hay bales: full width - 4, lower part.
BED_SOLID = (60, 16)
# Flat props without a body (rubble) lie under characters, their weapons and shadows: one below
# DropShadow.Z (-2), above the ground (-10), like VillageDecor.FLAT_Z.
FLAT = "z_index = -3\n"
PROPS = [
    # Chicken yard in the west: fence above and below (gate in the lower row), hay inside.
    ("YardFence1", "garden_fence", (2.5, 12.6), (60, 12), False, ""),
    ("YardFence2", "garden_fence", (3.5, 12.6), (60, 12), False, ""),
    ("YardFence3", "garden_fence", (4.5, 12.6), (60, 12), False, ""),
    ("YardFence4", "garden_fence", (5.5, 12.6), (60, 12), False, ""),
    ("YardFence5", "garden_fence", (2.5, 14.45), (60, 12), False, ""),
    ("YardFence6", "garden_fence", (3.5, 14.45), (60, 12), False, ""),
    ("YardFence7", "garden_fence", (5.5, 14.45), (60, 12), False, ""),
    ("HayBale1", "hay_bale", (3.1, 13.75), (44, 18), False, ""),
    ("HayBale2", "hay_bale", (5.5, 13.5), (44, 18), True, ""),
    # Vegetable garden next to the house in the south-west: fence and beds.
    ("GardenFence1", "garden_fence", (7.5, 12.6), (60, 12), False, ""),
    ("GardenFence2", "garden_fence", (8.5, 12.6), (60, 12), False, ""),
    ("Bed1", "flower_bed", (7.4, 13.3), BED_SOLID, False, ""),
    ("Bed2", "flower_bed", (8.6, 13.3), BED_SOLID, True, ""),
    ("Bed3", "flower_bed", (8.0, 14.0), BED_SOLID, False, ""),
    # Bench looking onto the square, signpost at the spawn, cart and hay in the east.
    ("Bench", "bench", (11.5, 8.95), (56, 14), False, ""),
    ("Signpost", "signpost", (17.4, 17.3), (12, 10), False, ""),
    ("Cart", "cart", (29.7, 17.8), (80, 24), False, ""),
    ("HayBale3", "hay_bale", (27.6, 17.9), (44, 18), False, ""),
    ("Pond", "pond", (24.3, 11.9), (110, 44), False, ""),
    ("PondBench", "bench", (24.4, 10.75), (56, 14), False, ""),
    # Small field in the south-east next to the cart.
    ("FieldFence1", "garden_fence", (24.5, 17.6), (60, 12), False, ""),
    ("FieldFence2", "garden_fence", (25.5, 17.6), (60, 12), False, ""),
    ("Bed4", "flower_bed", (24.4, 18.5), BED_SOLID, False, ""),
    ("Bed5", "flower_bed", (25.6, 18.5), BED_SOLID, True, ""),
    # In front of the dungeon ruin: soul flame bowl and rubble.
    ("FlameBowl", "entrance_flame_bowl", (21.25, 5.3), (28, 12), False, BOWL_LIGHT),
    ("Rubble1", "stones", (20.3, 5.55), None, False, FLAT),
    ("Rubble2", "stones", (24.9, 5.1), None, True, FLAT),
]
# Villagers walk the paths (feet positions in tiles); placeholder = an NPC sprite with a tint.
# name, art, fallback frames, tint, loop, speed, route
VILLAGERS = [
    ("Villager1", "villager_1", "guild_master", "Color(1, 0.9, 0.8, 1)", False, 30,
     [(2.6, 10.6), (7.0, 10.5), (11.6, 11.2), (13.6, 10.2)]),
    ("Villager2", "villager_2", "smith", "Color(0.82, 0.9, 1, 1)", False, 26,
     [(17.4, 16.4), (21.0, 16.3), (25.0, 16.4), (29.8, 16.3)]),
    ("Villager3", "villager_3", "chronicler", "Color(1, 0.86, 0.95, 1)", True, 22,
     [(14.0, 10.0), (18.8, 10.0), (18.6, 13.4), (14.2, 13.6)]),
]
# Rescued villagers (RescueRecord, D-135): one slot each in rescue order; Village frees the slots
# that are not rescued yet. loop, speed, route (on the paths)
RESCUED = [
    (False, 20, [(15.5, 15.0), (15.6, 18.2)]),
    (False, 24, [(3.4, 17.6), (9.0, 17.9), (13.8, 17.6)]),
    (False, 18, [(22.4, 7.4), (21.8, 8.4), (21.3, 9.5), (19.6, 9.6)]),
    (False, 26, [(17.6, 15.6), (27.0, 15.8)]),
    (False, 22, [(3.0, 11.4), (10.6, 11.6)]),
    (True, 16, [(15.0, 11.0), (17.8, 11.0), (17.8, 13.2), (15.2, 13.4)]),
]
# Animals keep to their territory (06_dorf.md): only with art (or the chicken placeholder).
# name, art (= animal kind of VillageAnimal), loop, speed, route
ANIMALS = [
    ("Chicken1", "chicken", True, 18, [(2.8, 13.0), (4.2, 12.9), (5.8, 13.3), (4.0, 14.0)]),
    ("Chicken2", "chicken", True, 16, [(5.6, 14.0), (3.4, 14.1), (2.9, 13.2)]),
    ("Cat", "cat", False, 22, [(9.6, 18.3), (13.2, 18.4)]),
    # WK12: the dog trots along the south fence by the field (shows once its art exists).
    ("Dog", "dog", False, 26, [(26.6, 18.7), (29.2, 18.7)]),
]
# Rescued chickens: two more in the yard, two in the garden and at the pond. loop, speed, route
RESCUED_CHICKENS = [
    (False, 16, [(3.6, 13.4), (5.2, 13.8)]),
    (False, 14, [(4.8, 12.95), (2.9, 13.8)]),
    (False, 15, [(7.2, 13.7), (9.0, 13.6)]),
    (False, 15, [(22.6, 10.4), (23.6, 10.5)]),
]
TREES = [
    # forest on the terrace above the ridge, darker towards the back; free around the ruin
    (1.5, 1.5), (3.6, 1.2), (5.4, 1.7), (7.7, 1.3), (9.4, 1.6), (11.6, 1.2), (13.5, 1.7), (15.7, 1.3),
    (17.4, 1.6), (19.5, 1.3), (21.0, 1.1), (25.3, 1.2), (27.0, 1.6), (28.8, 1.2), (30.4, 1.7),
    (2.3, 3.2), (4.5, 2.9), (6.8, 3.4), (8.5, 2.8), (10.7, 3.3), (12.4, 2.9), (14.8, 3.4), (16.5, 2.8),
    (18.7, 3.3), (27.8, 3.0), (29.8, 3.4),
    (1.5, 5.2), (4.0, 5.5), (7.6, 5.0), (11.2, 5.4), (14.4, 5.1), (17.6, 5.5), (26.4, 5.3), (29.2, 5.5),
    # a few trees at the village's edge
    (1.2, 12.4), (1.1, 15.0), (30.6, 12.4), (1.0, 18.6),
]
# Terrace trees further back are darker (deep forest behind the ridge): rows above these tile ys.
TREE_SHADES = [(2.0, "Color(0.66, 0.74, 0.7, 1)"), (4.0, "Color(0.8, 0.86, 0.82, 1)")]
# Bushes along the foot of the ridge soften its line; a few more at the edges.
BUSHES = [(2, 18), (30, 18), (20, 18), (24, 5), (1, 7), (6, 7), (11, 7), (16, 7), (24, 7), (30, 7)]
STUMPS = [(19, 5)]


def vec(x, y):
    return f"Vector2({x:g}, {y:g})"


def tiles(pos):
    return vec(pos[0] * T, pos[1] * T)


def rects(items):
    return ", ".join(f"Rect2i({x}, {y}, {w}, {h})" for x, y, w, h in items)


def caption(parent, text, top, size=18):
    return f'''[node name="Caption" type="Label" parent="{parent}"]
offset_left = -120.0
offset_top = {top:g}
offset_right = 120.0
offset_bottom = {top + 26:g}
theme_override_colors/font_color = Color(1, 0.82, 0.35, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 5
theme_override_font_sizes/font_size = {size}
text = "{text}"
horizontal_alignment = 1
'''


def main():
    ext = [
        '[ext_resource type="Script" path="res://world/village/village.gd" id="1_village"]',
        '[ext_resource type="Script" path="res://world/village/village_tiles.gd" id="2_tiles"]',
        '[ext_resource type="TileSet" path="res://world/village/village_tileset.tres" id="3_tileset"]',
        '[ext_resource type="Script" path="res://components/interaction/interactable.gd" id="4_interactable"]',
        '[ext_resource type="Script" path="res://world/village/village_entrance.gd" id="5_entrance"]',
        '[ext_resource type="Texture2D" path="res://art/environment/buildings/tree.png" id="6_tree"]',
        '[ext_resource type="Script" path="res://components/visual/animated_prop.gd" id="7_prop"]',
    ]
    ids = {}

    def add_ext(kind, path):
        if path not in ids:
            ids[path] = f"{len(ext) + 1}_res"
            ext.append(f'[ext_resource type="{kind}" path="{path}" id="{ids[path]}"]')
        return ids[path]

    subs = []
    nodes = []

    def rect_shape(sid, w, h):
        subs.append(f'[sub_resource type="RectangleShape2D" id="{sid}"]\nsize = {vec(w, h)}\n')

    def bounds():
        """Closed ring of walls around the map (#0ef74410): left, right, top, bottom, overlapping."""
        width, height = MAP_SIZE[0] * T, MAP_SIZE[1] * T
        out = WALL_OUTSIDE
        walls = [
            ("Left", -out, -out, WALL_INNER_SIDE + out, height + 2 * out),
            ("Right", width - WALL_INNER_SIDE, -out, WALL_INNER_SIDE + out, height + 2 * out),
            ("Top", -out, -out, width + 2 * out, WALL_INNER_TOP + out),
            ("Bottom", -out, height - WALL_INNER_BOTTOM, width + 2 * out, WALL_INNER_BOTTOM + out),
        ]
        text = '''[node name="Bounds" type="StaticBody2D" parent="."]
collision_mask = 0
'''
        for name, x, y, w, h in walls:
            rect_shape(f"Rect_bounds_{name.lower()}", w, h)
            text += f'''
[node name="{name}" type="CollisionShape2D" parent="Bounds"]
position = {vec(x + w / 2, y + h / 2)}
shape = SubResource("Rect_bounds_{name.lower()}")
'''
        return text

    def circle_shape(sid, r):
        subs.append(f'[sub_resource type="CircleShape2D" id="{sid}"]\nradius = {r:g}\n')

    def smoke(parent, info, flip):
        """Chimney smoke at the chimney top (art px relative to the pivot, mirrored with the sprite)."""
        if not info["chimney"]:
            return ""
        script = add_ext("Script", "res://world/village/chimney_smoke.gd")
        (cx, cy), (px, py) = info["chimney"], info["pivot"]
        dx = (cx - px) * SCALE * (-1 if flip else 1)
        return f'''
[node name="Smoke" type="CPUParticles2D" parent="{parent}"]
position = {vec(dx, (cy - py) * SCALE - 2)}
script = ExtResource("{script}")
'''

    def solid_body(name, tex, pos, flip=False, meta=""):
        """StaticBody with the building sprite and a footprint over walls and most of the roof."""
        info = SPRITES[tex]
        (w, h), (px, py) = info["size"], info["pivot"]
        texture_id = add_ext("Texture2D", f"{BUILDING_DIR}/{tex}.png")
        off = (w / 2 - px, h / 2 - py)
        wall_h = h * WALL_SHARE
        solid_h = (wall_h + (h - wall_h) * ROOF_SOLID) * SCALE
        solid_w = (w - 6) * SCALE
        sid = f"Rect_{name}"
        rect_shape(sid, solid_w, solid_h)
        centre_x = (w / 2 - px) * SCALE * (-1 if flip else 1)
        flip_line = "flip_h = true\n" if flip else ""
        return f'''[node name="{name}" type="StaticBody2D" parent="Buildings"]
position = {tiles(pos)}
collision_mask = 0
{meta}
[node name="Sprite" type="Sprite2D" parent="Buildings/{name}"]
scale = Vector2({SCALE}, {SCALE})
texture = ExtResource("{texture_id}")
offset = {vec(*off)}
{flip_line}
[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/{name}"]
position = {vec(centre_x, -solid_h / 2 - 4)}
shape = SubResource("{sid}")
''' + smoke(f"Buildings/{name}", info, flip)

    bushes = ", ".join(f"Vector2i({x}, {y})" for x, y in BUSHES)
    stumps = ", ".join(f"Vector2i({x}, {y})" for x, y in STUMPS)
    decor_script = add_ext("Script", "res://world/village/village_decor.gd")
    ambience_script = add_ext("Script", "res://world/village/village_ambience.gd")
    evening_script = add_ext("Script", "res://world/village/village_evening.gd")
    nodes.append(f'''[node name="Village" type="Node2D"]
y_sort_enabled = true
script = ExtResource("1_village")

[node name="Ground" type="TileMapLayer" parent="."]
z_index = -10
scale = Vector2(2, 2)
tile_set = ExtResource("3_tileset")
script = ExtResource("2_tiles")
map_size = Vector2i({MAP_SIZE[0]}, {MAP_SIZE[1]})
path_rects = Array[Rect2i]([{rects(PATHS)}])
bush_tiles = Array[Vector2i]([{bushes}])
stump_tiles = Array[Vector2i]([{stumps}])
plaza_rects = Array[Rect2i]([{rects(PLAZA)}])
cliff_rects = Array[Rect2i]([{rects(CLIFFS)}])
stair_rects = Array[Rect2i]([{rects(STAIRS)}])
slab_rects = Array[Rect2i]([{rects(SLABS)}])

[node name="Buildings" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Decor" type="Node2D" parent="."]
y_sort_enabled = true
script = ExtResource("{decor_script}")

[node name="Villagers" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Ambience" type="CPUParticles2D" parent="."]
script = ExtResource("{ambience_script}")

[node name="Evening" type="Node" parent="."]
script = ExtResource("{evening_script}")
''')
    nodes.append(bounds())

    # Dungeon entrance: the ruin on the terrace (VillageEntrance builds sprite, torches and ravens).
    rect_shape("Rect_entrance", 176, 56)
    circle_shape("Circle_entrance", 56)
    nodes.append(f'''[node name="DungeonEntrance" type="StaticBody2D" parent="Buildings"]
position = {tiles(ENTRANCE)}
collision_mask = 0
script = ExtResource("5_entrance")

[node name="Sprite" type="Sprite2D" parent="Buildings/DungeonEntrance"]
scale = Vector2(2, 2)
offset = Vector2(0, -40)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/DungeonEntrance"]
position = Vector2(0, -28)
shape = SubResource("Rect_entrance")

[node name="Interactable" type="Area2D" parent="Buildings/DungeonEntrance"]
position = Vector2(0, 10)
script = ExtResource("4_interactable")
prompt = "Dungeon betreten"

[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/DungeonEntrance/Interactable"]
shape = SubResource("Circle_entrance")

''' + caption("Buildings/DungeonEntrance", "Dungeon", -196, 20))

    circle_shape("Circle_door", 32)
    for name, tex, pos, title, prompt, building_id, sign in BUILDINGS:
        py = SPRITES[tex]["pivot"][1]
        text = solid_body(name, tex, pos, meta=f'metadata/building_id = "{building_id}"\n')
        # A sign whose art is still missing (sign_home, SPRITES_V3/V4) is left out here; Village adds
        # the file at runtime once it exists, else a placeholder board.
        if sign and (ART_UI / f"{sign}.png").exists():
            sign_id = add_ext("Texture2D", f"res://art/ui/{sign}.png")
            sign_top = -(DOOR_HEIGHT + SIGN_GAP + SIGN_SIZE[1]) * SCALE
            text += f'''
[node name="Sign" type="Sprite2D" parent="Buildings/{name}"]
position = {vec(0, sign_top)}
scale = Vector2({SCALE}, {SCALE})
texture = ExtResource("{sign_id}")
centered = false
offset = {vec(-SIGN_SIZE[0] / 2, 0)}
'''
        text += f'''
[node name="Door" type="Area2D" parent="Buildings/{name}"]
position = Vector2(0, 22)
script = ExtResource("4_interactable")
prompt = "{prompt}"

[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/{name}/Door"]
shape = SubResource("Circle_door")
'''
        nodes.append(text + "\n" + caption(f"Buildings/{name}", title, -py * SCALE - 30))

    for name, tex, pos, flip in HOUSES:
        nodes.append(solid_body(name, tex, pos, flip, meta='metadata/neighbour_house = true\n'))

    circle_shape("Circle_npc", 12)
    for name, frames, pos, face_left in NPCS:
        frames_id = add_ext("SpriteFrames", f"res://art/characters/npcs/{frames}_frames.tres")
        nodes.append(f'''[node name="{name}" type="StaticBody2D" parent="Buildings"]
position = {tiles(pos)}
collision_mask = 0

[node name="Sprite" type="AnimatedSprite2D" parent="Buildings/{name}"]
scale = Vector2(2, 2)
sprite_frames = ExtResource("{frames_id}")
animation = &"idle"
autoplay = "idle"
offset = Vector2(0, -14)
flip_h = {"true" if face_left else "false"}

[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/{name}"]
position = Vector2(0, -6)
shape = SubResource("Circle_npc")
''')

    fountain_sound = add_ext("Script", "res://world/village/fountain_sound.gd")
    for name, folder, tex, (w, h), (px, py), pos, solid, frames in DECOR:
        texture_id = add_ext("Texture2D", f"{folder}/{tex}.png")
        if frames > 1:
            sprite = f'''[node name="Sprite" type="AnimatedSprite2D" parent="Buildings/{name}"]
scale = Vector2(2, 2)
script = ExtResource("7_prop")
strip = ExtResource("{texture_id}")
frame_size = Vector2i({w}, {h})
fps = 5.0
pivot = {vec(px, py)}
'''
        else:
            sprite = f'''[node name="Sprite" type="Sprite2D" parent="Buildings/{name}"]
scale = Vector2(2, 2)
texture = ExtResource("{texture_id}")
offset = {vec(w / 2 - px, h / 2 - py)}
'''
        body = f'''[node name="{name}" type="StaticBody2D" parent="Buildings"]
position = {tiles(pos)}
collision_mask = 0

''' + sprite
        if isinstance(solid, tuple):
            sid = f"Rect_{name}"
            rect_shape(sid, *solid)
            body += f'''
[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/{name}"]
position = {vec(0, -solid[1] / 2)}
shape = SubResource("{sid}")
'''
        elif solid:
            sid = f"Circle_{name}"
            circle_shape(sid, solid)
            body += f'''
[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/{name}"]
position = Vector2(0, -8)
shape = SubResource("{sid}")
'''
        if name == "Fountain":
            light_script = add_ext("Script", "res://components/visual/light_source.gd")
            body += f'''
[node name="Sound" type="AudioStreamPlayer2D" parent="Buildings/{name}"]
position = Vector2(0, -24)
script = ExtResource("{fountain_sound}")

[node name="WaterLight" type="Node2D" parent="Buildings/{name}"]
position = Vector2(0, -30)
script = ExtResource("{light_script}")
radius = 130.0
intensity = 0.6
flicker = 0.03
ground_offset = Vector2(0, 30)
color = Color(0.42, 0.82, 1, 1)
'''
        nodes.append(body)

    prop_script = add_ext("Script", "res://world/village/village_prop.gd")
    for name, art, pos, solid, flip, extra in PROPS:
        solid_line = f"solid_size = {vec(*solid)}\n" if solid else ""
        flip_line = "flip = true\n" if flip else ""
        nodes.append(f'''[node name="{name}" type="StaticBody2D" parent="Buildings"]
position = {tiles(pos)}
collision_mask = 0
script = ExtResource("{prop_script}")
art_name = "{art}"
{solid_line}{flip_line}{extra}''')

    circle_shape("Circle_trunk", 14)
    for i, pos in enumerate(TREES):
        shade = next((color for limit, color in TREE_SHADES if pos[1] < limit), None)
        shade_line = f"modulate = {shade}\n" if shade else ""
        nodes.append(f'''[node name="Tree{i}" type="StaticBody2D" parent="Buildings"]
position = {tiles(pos)}
collision_mask = 0
{shade_line}
[node name="Sprite" type="Sprite2D" parent="Buildings/Tree{i}"]
scale = Vector2(2, 2)
texture = ExtResource("6_tree")
offset = Vector2(0, -30)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/Tree{i}"]
position = Vector2(0, -8)
shape = SubResource("Circle_trunk")
''')

    villager_script = add_ext("Script", "res://world/village/villager.gd")

    def route(points):
        return "PackedVector2Array(" + ", ".join(f"{x * T:g}, {y * T:g}" for x, y in points) + ")"

    for name, art, fallback, tint, loop, speed, points in VILLAGERS:
        frames_id = add_ext("SpriteFrames", f"res://art/characters/npcs/{fallback}_frames.tres")
        nodes.append(f'''[node name="{name}" type="Node2D" parent="Villagers"]
position = {tiles(points[0])}
script = ExtResource("{villager_script}")
route = {route(points)}
loop = {"true" if loop else "false"}
speed = {speed:g}
art_name = "{art}"
fallback_frames = ExtResource("{frames_id}")
tint = {tint}
''')
    for i, (loop, speed, points) in enumerate(RESCUED):
        nodes.append(f'''[node name="Rescued{i + 1}" type="Node2D" parent="Villagers"]
position = {tiles(points[0])}
script = ExtResource("{villager_script}")
route = {route(points)}
loop = {"true" if loop else "false"}
speed = {speed:g}
pause_max = 6.0
art_name = "lost_villager"
optional = true
metadata/rescued_slot = {i}
''')
    for name, art, loop, speed, points in ANIMALS:
        nodes.append(f'''[node name="{name}" type="Node2D" parent="Villagers"]
position = {tiles(points[0])}
script = ExtResource("{villager_script}")
route = {route(points)}
loop = {"true" if loop else "false"}
speed = {speed:g}
pause_max = 5.0
art_name = "{art}"
optional = true
dodge_sound = &""
animal = &"{art}"
''')
    for i, (loop, speed, points) in enumerate(RESCUED_CHICKENS):
        nodes.append(f'''[node name="RescuedChicken{i + 1}" type="Node2D" parent="Villagers"]
position = {tiles(points[0])}
script = ExtResource("{villager_script}")
route = {route(points)}
loop = {"true" if loop else "false"}
speed = {speed:g}
pause_max = 5.0
art_name = "chicken"
optional = true
dodge_sound = &""
animal = &"chicken"
metadata/rescued_chicken_slot = {i}
''')

    nodes.append(f'''[node name="PlayerSpawn" type="Marker2D" parent="."]
position = {tiles(SPAWN)}
''')

    text = "[gd_scene format=3]\n\n" + "\n".join(ext) + "\n\n" + "\n".join(subs) + "\n" + "\n".join(nodes)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print("written", OUT)


if __name__ == "__main__":
    main()
