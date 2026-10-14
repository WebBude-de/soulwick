"""Generates world/village/village.tscn (tile layout, buildings, houses, NPCs, villagers, decoration).

Usage (from the project root):  python tools/generate_village.py
One tile = 64 world px. Buildings use the village_v2 art (art/environment/buildings/village_v2.json):
they are drawn at the same scale as the player (2x), their pivot is the bottom centre of the door,
so the node origin sits on the door and y-sorting against the player is correct. Each building has
a solid footprint over the walls and most of the roof and an Interactable at its door that opens
the building's dialog (D-078). Enterable buildings get a wooden sign above the door (art/ui/sign_*.png,
24x16, pivot top centre, SPRITES_V3 section 4) so their purpose is visible from outside (D-087).
The player's home (MM1) opens the wardrobe ("Umkleiden").

B3 (Dorf beleben): compact map (30x19) with two streets, a market square with the fountain and the
dungeon entrance at the end of the main road; neighbour houses (house_1..3, no door), barrels,
crates, garden fences, chimney smoke, villagers walking routes on the paths, pollen/fireflies.
Props whose art is still missing (bench, cart, hay bales, signpost, pond, chickens, cat;
docs/SPRITES_V4.md) are placed as VillageProp/Villager and appear once the file exists.
Small decoration (flowers, stones, grass, bushes) is scattered at runtime by VillageDecor.
"""
from pathlib import Path

T = 64
SCALE = 2
OUT = Path(__file__).resolve().parent.parent / "world" / "village" / "village.tscn"
ART_UI = Path(__file__).resolve().parent.parent / "art" / "ui"
MAP_SIZE = (30, 19)
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

# Layout in tiles. Upper street y 7-8, lower street y 15-16, main road x 14-15 from the dungeon
# entrance (y 5) to the spawn (y 17), market square x 12-17 / y 9-11 around the fountain.
PATHS = [(2, 7, 26, 2), (2, 15, 26, 2), (14, 5, 2, 13), (12, 9, 6, 3)]  # x, y, w, h
ENTRANCE = (15, 5)
SPAWN = (15, 17.4)

# node name, sprite, tile position of the door pivot, caption, prompt, building id, door sign
BUILDINGS = [
    ("Forge", "forge", (7.6, 7), "Schmiede", "Schmiede betreten", "forge", "sign_forge"),
    ("Chronicle", "chronicle_hall", (19.6, 7), "Chronik", "Chronik betreten", "chronicle", "sign_chronicle"),
    ("Home", "home", (11.6, 15), "Zuhause", "Umkleiden", "home", "sign_home"),
    ("TradingPost", "trading_post", (18, 15), "Handelsposten", "Handelsposten betreten", "trader", "sign_trading"),
    ("Guild", "guild_hall", (23.8, 15), "Gilde", "Gilde betreten", "guild", "sign_guild"),
]
# Neighbour houses without a door: name, sprite, tile position (bottom centre), mirrored
HOUSES = [
    ("HouseNW", "house_2", (3.6, 7), False),
    ("HouseN", "house_1", (11.6, 7), False),
    ("HouseNE", "house_3", (24.4, 7), False),
    ("HouseSW", "house_1", (3.6, 15), True),
    ("HouseS", "house_2", (7.5, 15), True),
]
# npc name, frames, tile position (feet), face left
NPCS = [
    ("Smith", "smith", (9.75, 6.95), True),
    ("Chronicler", "chronicler", (21.0, 6.95), True),
    ("Trader", "trader", (20.6, 14.95), True),
    ("GuildMaster", "guild_master", (26.0, 14.95), True),
]
# decoration: name, folder, texture, size, pivot, tile position, solid radius (0 = none), frames
LAMP = (BUILDING_DIR, "lamp_post_4f", (16, 48), (8, 47))
BARREL = (PROP_DIR, "barrel", (32, 32), (16, 31))
CRATE = (PROP_DIR, "crate", (32, 32), (16, 31))
DECOR = [
    ("Fountain", PROP_DIR, "fountain_4f", (32, 40), (16, 38), (15, 10.6), 20, 4),
    ("Well", BUILDING_DIR, "well_4f", (32, 40), (16, 38), (9.2, 11.3), 22, 4),
    ("MarketStall", BUILDING_DIR, "market_stall", (64, 48), (32, 44), (21, 11.4), 40, 1),
    ("Lamp1", *LAMP, (13.4, 6.95), 8, 4),
    ("Lamp2", *LAMP, (16.6, 6.95), 8, 4),
    ("Lamp3", *LAMP, (13.4, 14.95), 8, 4),
    ("Lamp4", *LAMP, (16.6, 14.95), 8, 4),
    ("Lamp5", *LAMP, (11.6, 11.95), 8, 4),
    ("Lamp6", *LAMP, (18.4, 11.95), 8, 4),
    ("Barrel1", *BARREL, (5.55, 6.9), 11, 1),
    ("Barrel2", *BARREL, (22.55, 11.45), 11, 1),
    ("Barrel3", *BARREL, (9.85, 14.85), 11, 1),
    ("Barrel4", *BARREL, (26.4, 6.9), 11, 1),
    ("Crate1", *CRATE, (21.3, 14.7), 12, 1),
    ("Crate2", *CRATE, (23.3, 11.5), 12, 1),
    ("Crate3", *CRATE, (5.4, 14.85), 12, 1),
]
# Props from docs/SPRITES_V4.md (art/environment/village/<art>.png; placeholder or hidden until then):
# name, art, tile position (bottom centre), solid size in world px (None = walk through), mirrored
PROPS = [
    ("FenceW1", "garden_fence", (3.5, 9.75), (60, 12), False),
    ("FenceW2", "garden_fence", (4.5, 9.75), (60, 12), False),
    ("FenceW3", "garden_fence", (6.5, 9.75), (60, 12), False),
    ("FenceW4", "garden_fence", (3.5, 12.2), (60, 12), False),
    ("FenceW5", "garden_fence", (4.5, 12.2), (60, 12), False),
    ("FenceW6", "garden_fence", (5.5, 12.2), (60, 12), False),
    ("FenceW7", "garden_fence", (6.5, 12.2), (60, 12), False),
    ("Bench", "bench", (11.0, 9.8), (56, 14), False),
    ("Signpost", "signpost", (13.4, 17.55), (12, 10), False),
    ("Cart", "cart", (27.5, 14.85), (80, 24), False),
    ("HayBale1", "hay_bale", (4.3, 11.3), (44, 18), False),
    ("HayBale2", "hay_bale", (5.4, 11.6), (44, 18), True),
    ("Pond", "pond", (25.4, 11.5), (110, 44), False),
]
# Villagers walk the paths (feet positions in tiles); placeholder = an NPC sprite with a tint.
# name, art, fallback frames, tint, loop, speed, route
VILLAGERS = [
    ("Villager1", "villager_1", "guild_master", "Color(1, 0.9, 0.8, 1)", False, 30,
     [(3.0, 8.2), (9.4, 8.35), (13.0, 8.2), (17.2, 8.35), (26.8, 8.2)]),
    ("Villager2", "villager_2", "smith", "Color(0.82, 0.9, 1, 1)", False, 26,
     [(3.2, 16.3), (9.0, 16.2), (15.6, 16.4), (21.0, 16.25), (26.8, 16.3)]),
    ("Villager3", "villager_3", "chronicler", "Color(1, 0.86, 0.95, 1)", True, 22,
     [(12.2, 9.5), (12.6, 11.5), (17.4, 11.6), (17.8, 9.5)]),
]
# Animals: only with art (SPRITES_V4). name, art, loop, speed, route
ANIMALS = [
    ("Chicken1", "chicken", True, 18, [(3.6, 10.6), (4.8, 10.25), (6.2, 10.9), (5.0, 11.8)]),
    ("Chicken2", "chicken", True, 16, [(6.0, 11.7), (4.0, 11.9), (3.4, 10.5)]),
    ("Cat", "cat", False, 22, [(9.0, 17.45), (12.4, 17.6)]),
]
TREES = [
    # forest behind the upper row
    (1.3, 3.4), (4.3, 3.4), (9.6, 3.4), (12.2, 3.6), (17.6, 3.6), (21.4, 3.4), (26.0, 3.4), (28.4, 3.4),
    (2.8, 2.2), (7.6, 2.2), (10.8, 2.2), (19.6, 2.2), (23.6, 2.2), (27.2, 2.2),
    # left and right edge
    (1.0, 6.6), (1.1, 12.2), (2.4, 11.9), (1.1, 14.6), (1.0, 17.9),
    (28.6, 6.6), (28.5, 10.6), (28.6, 14.6), (28.9, 17.9),
]
BUSHES = [(3, 17), (26, 17), (20, 17)]
STUMPS = [(8, 17)]


def vec(x, y):
    return f"Vector2({x:g}, {y:g})"


def tiles(pos):
    return vec(pos[0] * T, pos[1] * T)


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
        '[ext_resource type="Texture2D" path="res://art/environment/props/dungeon_entrance.png" id="5_entrance"]',
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

    paths = ", ".join(f"Rect2i({x}, {y}, {w}, {h})" for x, y, w, h in PATHS)
    bushes = ", ".join(f"Vector2i({x}, {y})" for x, y in BUSHES)
    stumps = ", ".join(f"Vector2i({x}, {y})" for x, y in STUMPS)
    decor_script = add_ext("Script", "res://world/village/village_decor.gd")
    ambience_script = add_ext("Script", "res://world/village/village_ambience.gd")
    nodes.append(f'''[node name="Village" type="Node2D"]
y_sort_enabled = true
script = ExtResource("1_village")

[node name="Ground" type="TileMapLayer" parent="."]
z_index = -10
scale = Vector2(2, 2)
tile_set = ExtResource("3_tileset")
script = ExtResource("2_tiles")
map_size = Vector2i({MAP_SIZE[0]}, {MAP_SIZE[1]})
path_rects = Array[Rect2i]([{paths}])
bush_tiles = Array[Vector2i]([{bushes}])
stump_tiles = Array[Vector2i]([{stumps}])

[node name="Buildings" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Decor" type="Node2D" parent="."]
y_sort_enabled = true
script = ExtResource("{decor_script}")

[node name="Villagers" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Ambience" type="CPUParticles2D" parent="."]
script = ExtResource("{ambience_script}")
''')

    # Dungeon entrance at the top end of the main road.
    rect_shape("Rect_entrance", 104, 40)
    circle_shape("Circle_entrance", 56)
    nodes.append(f'''[node name="DungeonEntrance" type="StaticBody2D" parent="Buildings"]
position = {tiles(ENTRANCE)}
collision_mask = 0

[node name="Sprite" type="Sprite2D" parent="Buildings/DungeonEntrance"]
scale = Vector2(2, 2)
texture = ExtResource("5_entrance")
offset = Vector2(0, -30)

[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/DungeonEntrance"]
position = Vector2(0, -24)
shape = SubResource("Rect_entrance")

[node name="Interactable" type="Area2D" parent="Buildings/DungeonEntrance"]
position = Vector2(0, 10)
script = ExtResource("4_interactable")
prompt = "Dungeon betreten"

[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/DungeonEntrance/Interactable"]
shape = SubResource("Circle_entrance")

''' + caption("Buildings/DungeonEntrance", "Dungeon", -170, 20))

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

    for name, folder, tex, (w, h), (px, py), pos, radius, frames in DECOR:
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
        if radius:
            sid = f"Circle_{name}"
            circle_shape(sid, radius)
            body += f'''
[node name="CollisionShape2D" type="CollisionShape2D" parent="Buildings/{name}"]
position = Vector2(0, -8)
shape = SubResource("{sid}")
'''
        nodes.append(body)

    prop_script = add_ext("Script", "res://world/village/village_prop.gd")
    for name, art, pos, solid, flip in PROPS:
        solid_line = f"solid_size = {vec(*solid)}\n" if solid else ""
        flip_line = "flip = true\n" if flip else ""
        nodes.append(f'''[node name="{name}" type="StaticBody2D" parent="Buildings"]
position = {tiles(pos)}
collision_mask = 0
script = ExtResource("{prop_script}")
art_name = "{art}"
{solid_line}{flip_line}''')

    circle_shape("Circle_trunk", 14)
    for i, pos in enumerate(TREES):
        nodes.append(f'''[node name="Tree{i}" type="StaticBody2D" parent="Buildings"]
position = {tiles(pos)}
collision_mask = 0

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
''')

    nodes.append(f'''[node name="PlayerSpawn" type="Marker2D" parent="."]
position = {tiles(SPAWN)}
''')

    text = "[gd_scene format=3]\n\n" + "\n".join(ext) + "\n\n" + "\n".join(subs) + "\n" + "\n".join(nodes)
    OUT.write_text(text, encoding="utf-8", newline="\n")
    print("written", OUT)


if __name__ == "__main__":
    main()
