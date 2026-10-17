# SPRITES_V9 – Lieferung (15.10.2026)

Alle Teile aus dem Briefing V9 (Makeover-Welle A) sind geliefert. Weiche Palette je Biom per Palettentausch (SOFTS in tools/spritegen/v9lib.js). Zu jedem Teil liegt ein JSON mit fps und Pivot neben der Datei.

| Abschnitt | Datei | Hinweis |
| --- | --- | --- |
| §1 | `art/environment/tiles/rock_blob_<biom>_soft_inner.png + .json` | Innenecken-Masken (r87, r93, r213 …, 20 Stück) + fill_left/right/both (Slots 51–53) + front_step_left/right. Als zweites Atlas-Sheet laden oder in das Haupt-Sheet kopieren (Maskennamen identisch). |
| §2 | `art/environment/doors/cave_mouth_<biom>_soft.png` | nur Bogenrand (6 px Band), Öffnung/Umfeld transparent, Krone läuft durch |
| §2 | `art/environment/doors/door_frame_<biom>_soft.png` | 64×56, runde Öffnung, kein Netz, Krone läuft durch |
| §2 | `art/environment/doors/tunnel_shade_{cave,arch}.png` | Innenschatten 18 px, biomneutral |
| §2 | `art/environment/doors/side_mouth_<biom>_soft.png` | 20×32, Ostwand, Pivot (0,0); Lichtkante bei x 7–10, Schlitz 7–12, Übergang 12–20, weich oben/unten |
| §2 | `art/environment/doors/door_side_<biom>_bars_4f.png` | Fallgitter quer 10 px, Frame 1 zu, Frame 4 weg |
| §3 | `art/environment/deco/water_glint_4f.png, fog_floor_4f.png` | Glitzer-Overlay (Modulate = Wasserfarbe), Bodennebel 64×32 |
| §3 | `art/environment/deco/deco_group_<biom>_{1..3}.png, deco_group_large_<biom>_{1,2}.png` | 64×48 / 96×64, Pivot unten Mitte |
| §3 | `art/environment/tiles/wall_cracked_<biom>_soft.png, wall_niche_soft.png` | 32×48 Felsfronten |
| §3 | `art/environment/tiles/abyss_tiles_{slime_grotto,shadow_realm,ember_forge}_soft.png` | Abgrund-Sets soft |
| §3 | `art/environment/rooms/wall_breach_cave_<biom>_6f.png` | Durchbruch in Felsfront |
| §4 | `art/environment/deco/platform_edge_<biom>.png` | 96×16 Oberkanten |
| §4 | `art/environment/side/bg_<biom>_parallax.png, spikes_side_3f.png` | Hintergrund 480×270, Stacheln 32×16 |
| §4 | `art/environment/props/golden_coin_4f.png` | goldene Münze |
| §4 | `art/environment/doors/door_mode_symbols_11.png`, `art/environment/rooms/door_branch_symbols_4.png`, `art/ui/symbol_ladder.png` | Leiter-Symbol als 11. bzw. 4. Spalte (neue Dateien, die alten bleiben unverändert; beim Einbau umbenennen) |
| §4 | `art/characters/player/player_climb_4f.png, player_tint_mask_climb_4f.png, player_tint_mask_land_2f.png` | Klettern + Masken |
| §5 | `art/characters/npcs/lost_villager_{idle_4f,walk_6f,scared_4f}.png` | ohne eingemalten Schein; Laterne 2 px weiter innen, Anker lantern (20,20) |

Hinweise:
- Innenecken: Das Randband läuft als Bogen (Innenradius 4 px) um den freien oberen Eckpunkt; unten liegende Diagonalen (r23, r29 …) sind ebenfalls enthalten.
- side_mouth ist so gezeichnet, dass die Lichtkante der Felskacheln (x 7–10) an den Enden weiterläuft; oben und unten 6 px weiches Auslaufen.
- Offen bleibt: 16-px-Felsrand (P1b) und die Seitenansicht-Vorlagen je Biom.
