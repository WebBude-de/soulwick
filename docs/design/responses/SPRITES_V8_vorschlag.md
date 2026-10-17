# SPRITES_V8 – Vorschlag

| Datei | Größe | Status |
| --- | --- | --- |
| art/environment/tiles/wall_autotile_<biom>.png | 128×160, 4×5 | GELIEFERT (V6) |
| art/environment/tiles/wall_inner_corner_<biom>.png | 128×32 | GELIEFERT (V6) |
| art/environment/doors/door_side_<biom>_open_4f.png | 128×32 | GELIEFERT (V7) |
| art/characters/player/player_tint_mask_fall_4f.png | 128×32 | GELIEFERT (V7) |
| art/environment/tiles/abyss_cliff_<biom>.png | 128×32 | GELIEFERT (V7) |
| art/environment/spawn/spawn_grave_6f.png, spawn_sarcophagus_4f.png (32×40), spawn_puddle_6f.png, spawn_rift_6f.png, spawn_vent_6f.png | 32×32 je Frame | GELIEFERT (V8-Kern) |
| art/environment/doors/door_mode_symbols.png (10×16×16), door_glow.png (48×32) |  | GELIEFERT |
| art/characters/npcs/lost_villager_idle_4f/walk_6f/scared_4f.png | 32×32 | GELIEFERT |
| art/environment/objectives/escort_path_4f, relic_banner/lantern/skull (16×24), relic_altar, soul_wisp_4f, soul_wisp_fade_4f (16×16) |  | GELIEFERT |
| art/environment/deco/pillar_fallen (64×32), candles_cluster (32×24), drip_4f (16×32), shallow_water_4f, wall_niche (32×48), stairs_down |  | GELIEFERT |
| art/environment/doors/door_frame_boss_<biom>.png | 64×56 | offen: Bosstor je Biom eingefärbt + Ketten-Animation door_boss_chains_4f |
| art/environment/corridors/corridor_<biom>_{straight,stairs,niche}.png | 96×64 je Variante | offen: Gang-Vorlagen mit Charakter |
| art/environment/village/dungeon_entrance_v2.png (96×80), entrance_flame_bowl_6f (32×32), ravens_4f (32×16) |  | offen: Dungeon-Eingang inszeniert |
| art/ui/taskbar_frame.png (9-slice 48×24), banner_stripe.png (8×32), countdown_digits.png (3×24×32) |  | offen: Aufgabenleiste, Banner, Countdown |
| art/characters/npcs/lost_chicken_lantern_idle_4f/walk_4f.png | 16×16 | offen: Huhn-Variante des Geleits |
| art/environment/objectives/relic_pedestal_<biom>.png | 32×32 | offen: Reliquien-Podest je Biom (heute weapon_pedestal) |
| art/environment/spawn/spawn_<biom>_idle_4f.png | 32×32 | offen: Ruhezustand der Quellen leicht animiert (Glimmen) |
| art/environment/deco/deco_group_<biom>_{1..3}.png | 64×48 | offen: fertige Deko-Gruppen je Biom als ein Sprite |
| art/environment/trials/collapse_marker_4f.png | 32×32 | offen: Einbruch-Warnmarke (Risse + rotes Glühen), falls crumbling_floor Frames 1-3 nicht reichen |
| art/ui/objective_icons.png (10×16×16) |  | offen: Aufgabenleisten-Icons = door_mode_symbols farbig |

Alle gelieferten Dateien liegen in `art/` (Ordner spawn, doors, objectives, deco, npcs, tiles) mit JSON (fps, Pivot, Notizen).
