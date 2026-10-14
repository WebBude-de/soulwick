# ROADMAP Ausbau – Spielbar machen, Räume, dann Multiplayer

> **Stand:** 14.10.2026 · **Neu ausgerichtet** nach dem Playtest vom 14.10.2026 und dem bestätigten Raumkonzept [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md).
> **Reihenfolge (D-088, D-106):** Phase 1 spielbar machen → Phase 2 **alle Räume als Einzelspieler-Content** → Phase 3 Multiplayer und Plattform ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md)) → Phase 4 KI-Bosse ([ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md)).
> **Entscheidungen:** D-086 (Raumarten, Abgründe), D-087 (Dorf), D-088 (Leitplanken), D-095–D-099 (Umsetzung 14.10.), D-100–D-106 (Raumkonzept, Reihenfolge) in [DECISIONS.md](DECISIONS.md).
> **Abhaken** nur mit Nachweis (Tests grün, Datum). Jedes Paket ist für **einen Agenten** geschnitten.

## Überblick

| Phase | Pakete | Ziel |
| --- | --- | --- |
| **1 – Spielbar für mich** ✓ (14.10.2026) | MM1 Hauptmenü und Spielstände · UX1 Spielbar-Pass · B2 Dorf straffen · B3 Dorf beleben · BI2 Boss-Story · C3 Musik-Übergänge | Das Projektmitglied kann mit eigenen Spielständen bequem spielen und testen. |
| **2 – Räume** | A2 Wegfindung · A3 Formen und Zutaten · A5 Arena · A6 Lagerfeuer · A7 Kampf-Varianten I + Wagnis-Altar · A4 Abgrund · A8 Spezialräume · A9 Licht-Varianten · A10 Wegführung | Der ganze Raum-Content aus KONZEPT_RAEUME im Einzelspieler. |
| **3 – Multiplayer und Plattform** | MP0–MP10 ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md)), Plattform-Repo parallel | Koop, Gilden, Ranglisten, Steam. |
| **4 – KI-Bosse** | KI0–KI4 ([ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md)) | Traumweber. KI1/KI2 brauchen keinen Server und können vorgezogen werden. |

**Parallel möglich** (verschiedene Dateien): In Phase 1 laufen MM1, BI2 und C3 gleichzeitig; UX1 und B2 danach. In Phase 2 können **A2 ‖ A3** und später **A6 ‖ A7** parallel laufen; A4, A8, A9, A10 nacheinander, weil sie Generator, `room_tiles.gd` oder `dungeon_manager.gd` teilen. Das Plattform-Repo (`soulwick-platform`, MP7/MP7b) darf jederzeit parallel laufen, weil es kein Spielcode ist.

**Grafiken:** [SPRITES_V3.md](SPRITES_V3.md) (geliefert, Nachträge §7). Neue Grafiken für Phase 2 schreibt der jeweilige Agent als Briefing in `docs/SPRITES_V4.md`.

## Regeln für jeden Agenten

1. Vorher lesen: [AGENTS.md](../AGENTS.md), die genannten D-Einträge, [ARCHITECTURE.md](ARCHITECTURE.md), für Räume [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md).
2. Zahlen als `@export`/Konstanten mit Kommentar `TESTWERT`, Gewichte als `.tres` (Balancing ohne Code).
3. Prüfen: `validate_project.gd`, GUT, `smoke_test.gd -- 47`; bei Kampf zusätzlich `combat_sim.gd` und `boss_sim.gd`.
4. Erledigte Punkte hier abhaken (mit Datum); Prüfstand in [ROADMAP.md](ROADMAP.md) aktualisieren.
5. **Koop-Check** (unten) im Bericht abhaken.

## Koop-Check für jedes Paket (D-088)

Phase 2 kommt **vor** dem Multiplayer. Damit der Umbau (MP1) klein bleibt, beantwortet jeder Bericht diese fünf Fragen mit „ja“:

- [ ] Kein neues `get_first_node_in_group(&"player")`; Spieler kommen als Parameter oder als Liste aller Spieler.
- [ ] Entscheidungen (fällt jemand, ist die Flamme aus, ist ein Punkt im Licht) an **einer** Stelle als Funktion; Effekte getrennt über Signale.
- [ ] Zufall nur über den Dungeon-RNG (`DungeonContext`); `randf()` nur für Optik.
- [ ] Keine neuen globalen Pausen, kein `Engine.time_scale` außer HitStop; Sperren je Spieler (`Player.set_input_locked`).
- [ ] Zustand je Spieler (letzte sichere Stelle, Fluch, getragene Laterne) liegt am Spieler, nicht in Autoloads.

---

## Phase 1 – Spielbar für mich

### MM1 – Hauptmenü, Spielstände, Charakterauswahl ✓ *(14.10.2026)*

- [x] Neues Hauptmenü mit `art/ui/logo.png` und Parallaxe-Hintergrund (`art/ui/menu/`), Weiterspielen, Spielstände, Optionen, Beenden; Platzhalter „Online / Gilde – bald“. *(14.10.2026; Hover-Ton und Klick-Auswahl nach Playtest)*
- [x] Spielstand-Slots (anlegen mit Name, laden, löschen); alter Stand wird einmalig Slot 1; Einstellungen global. *(14.10.2026; D-059 ergänzt; Löschen: Karte anklicken, dann „Löschen“, Bestätigung)*
- [x] Charakterauswahl vorbereitet (`CharacterData`, heute ein Held „Lichtträger“). *(14.10.2026)*
- [x] **Farbauswahl beim Anlegen** des Spielstands (wie im Kleiderschrank), Nachtrag aus dem Playtest. *(14.10.2026, UX1; GUT test_main_menu 12/12)*
- [x] **Umkleiden im Dorf** beim Gebäude „Zuhause“ (Kleidungsfarbe über die Tint-Maske), nicht im Hauptmenü; Farbe am Spieler über das SpriteFx-Material (Treffer-Blitz bleibt). *(14.10.2026; GUT 351/351, smoke_test 20 Räume)*

### UX1 – Spielbar-Pass ✓ *(14.10.2026)*

**Ziel:** Alles, was beim Spielen stört oder fehlt, ohne neue Inhalte. Dateien: `ui/**`, `scenes/**`, Optionen in `autoload/save_manager.gd` (nach MM1).

- [x] Optionen: Vollbild/Fenster, Lautstärken (Musik, Effekte, ggf. Atmosphäre), Bildschirmwackeln an/aus, Steuerung anzeigen. *(14.10.2026: gemeinsame `OptionsView` in Hauptmenü und Pausemenü, global in `settings.cfg [options]`, F11 Vollbild; „Atmosphäre“-Regler bleibt Idee laut D-097; GUT test_ux_options 9/9)*
- [x] Erster Run: kurze Steuerungs-Hinweise im ersten Raum (einmal je Spielstand, `SaveManager.has_seen`). *(14.10.2026: `ControlsHint`, 2 × 4 Tasten, Zeile wird grün bei Benutzung, keine Pause, `hint_controls`; GUT test_ux_controls_hint 4/4)*
- [x] Tod und Run-Ende: Statistik des Runs (Räume, Kills, Gold, Upgrades, Zeit), zurück ins Dorf oder direkt neuer Run. *(14.10.2026: `RunRecap` + Run-Ende-Dialog mit Todesursache und „Neuer Rekord!“, Enter = Dorf, N = Neuer Run; GUT test_ux_run_end 5/5, smoke_test 20 Räume)*
- [x] Rückmeldungen des Projektmitglieds aus dem Playtest (laufende Liste unten) abarbeiten. *(14.10.2026, Liste bleibt offen für neue Punkte)*
- [x] Y-Sortierung auch im Dungeon prüfen (Kisten, Fässer, Säulen, Fackeln vs. Spieler, `SortLift`). *(14.10.2026 geprüft: Kisten und Fässer verdecken den Spieler seitlich, wenn seine Füße schon vor ihrer Unterkante stehen – Behebung `SortLift.lift_props($Props)` im Raum ist Haken für den Integrator; Säulen (flache Tiles), Fackeln (Wand), Altar, Händler, Brunnen, Waffensockel sind in Ordnung)*

**Playtest-Liste (14.10.2026):** ~~Schwert sticht durch Laterne/Haus~~ · ~~Spieler hinter dem Haus~~ · ~~Upgrade mit Zifferntaste sofort wählen~~ · ~~Raum-Beschriftung „Arena · M“~~ · ~~Während des Boss-Dialogs laufen~~ · ~~Tote Gegner bleiben stehen~~ · ~~Lautstärke-Regler nicht pixelig~~ · ~~Kein Ton beim Hovern im Menü~~ · ~~Spielstand nur mit Entf löschbar (Hover wechselt Auswahl)~~ (alle behoben 14.10.2026) · ~~Tipp-Sound beim Namen, UI-Sounds durchgehend (öffnen/schließen, Umschalter, Fehlversuch, anlegen/löschen)~~ · ~~Farbauswahl beim Spielstand anlegen~~ (14.10.2026, UX1). Globale Optionen: `SaveManager.get_option/set_option` steht bereit.

### B2 – Dorf straffen und freischalten ✓ *(14.10.2026)*

**Dateien:** `meta/meta_progression.gd`, `autoload/save_manager.gd`, `ui/menus/village_ui.gd`, `world/village/village.gd`, `tests/unit/`.

- [x] Stufen und Kosten laut Tabelle in D-087 (28 → 20 Stufen). *(14.10.2026; KONZEPT_ENDLOS §6 verweist auf D-087)*
- [x] Kristall-Tausch aus dem Handelsposten entfernen; Handelsposten = nur Proviant. *(14.10.2026)*
- [x] **Freischaltungen** laut D-087 (Chronik nach dem ersten Run, Handelsposten ab dem ersten Kristall, Goldgier/Dash-Training/Arsenal nach dem ersten Boss). Gesperrte Gebäude sichtbar mit `icon_lock` und „Öffnet nach …“. *(14.10.2026; `meta/meta_unlocks.gd`, gesperrte Verbesserungen erscheinen erst nach Freischaltung, Meldung „Neu freigeschaltet“ beim nächsten Dorfbesuch)*
- [x] Neues Ereignis „erster Boss besiegt“ dauerhaft speichern. *(14.10.2026; StatsTracker speichert sofort beim Boss-Kill, Dorf gleicht zusätzlich mit der Statistik ab)*
- [x] **Spielstand-Migration** (Stufen umrechnen, alte Stände gelten als alles gesehen und freigeschaltet), passend zu den Slots aus MM1. D-059 ergänzen. *(14.10.2026; Version 3, Sicherung `*.v2.bak` vor der Migration; D-059-Text als Vorschlag an den Integrator)*
- [x] Tests: Migration, Freischaltbedingungen, kein Kristall-Tausch mehr. *(14.10.2026: GUT 405/405, validate 0 failed, smoke_test 20 Räume 279 PASS, Lade-Check frischer Stand + echter v2-Slot + Alt-Stand bestanden)*

### B3 – Dorf beleben ✓ *(14.10.2026; Sperrschild über gesperrten Gebäuden vom Integrator als Panel, GUT 426/426)*

**Ziel:** Das Dorf wirkt bewohnt statt wie eine große leere Wiese (Playtest 14.10.2026). Dateien: `world/village/**`, `tools/generate_village.py`, `ui/menus/village_ui.gd` nur falls nötig, neue Tests `tests/unit/test_village_*.gd`.

- [x] **Dichter planen:** Karte verkleinern oder Gebäude enger setzen, sodass von jedem Punkt mehrere Gebäude im Bild sind; klare Wege zwischen Eingang, Gebäuden und Dungeon. *(14.10.2026: Karte 36×24 → 30×19, zwei Straßen, Hauptweg Spawn → Marktplatz → Dungeon; in jeder Kamera-Position mindestens 4 Gebäude zur Hälfte im Bild)*
- [x] **Vorhandene, ungenutzte Grafiken einsetzen:** Wohnhäuser `house_1`–`house_3` als Nachbarhäuser, Fässer, Kisten, Brunnen (`fountain.png`), Marktstand, Laternen. *(14.10.2026: 5 Nachbarhäuser ohne Tür, 4 Fässer, 3 Kisten, Springbrunnen auf dem Marktplatz, 6 Laternen)*
- [x] **Leben:** 2–4 Dorfbewohner, die langsam zwischen Punkten laufen (Platzhalter mit vorhandenen NPC-Sprites, bis eigene Grafik da ist), Glühwürmchen/Blütenpartikel, Rauch aus Schornsteinen; Dorf-Geräuschkulisse gibt es schon (D-097). *(14.10.2026: 3 Dorfbewohner ohne Kollision, 2 Hühner, Rauch aus 5 Schornsteinen, Pollen tagsüber und Glühwürmchen 19–6 Uhr)*
- [x] **Deko-Streuer** mit Regeln (Blumenbeete, Zäune, Büsche, Steine an Wegrändern und Hauswänden, nie auf Wegen und Türen), Y-Sortierung über `SortLift`. *(14.10.2026: `VillageDecor`, fester Seed, 61 Teile ohne Kollision; Gartenzäune, Bank, Heuballen, Teich, Wegweiser fest platziert)*
- [x] **Grafik-Briefing** `docs/SPRITES_V4.md`: Blumenbeete, Gartenzaun-Teile, Heuballen, Karren, Bank, Wegweiser, Teich, Hühner/Katze, 2–3 Dorfbewohner (idle/walk), `sign_home.png`. *(14.10.2026; der Code übernimmt die Dateien automatisch, bis dahin Platzhalter)*
- [x] Tests: keine Deko auf Wegen/Türen/Spawn, alle Gebäude erreichbar; Screenshot-Vergleich vorher/nachher. *(14.10.2026: `test_village_layout` 12/12 mit Physik-Flutfüllung, `test_village_life` 9/9; GUT 426/426, validate 0 failed, smoke_test 20 Räume 279 PASS; Screenshots von 7 Stellen + Übersicht vorher/nachher)*

### B4 – Dorf mit Tageszeit ✓ *(14.10.2026, D-107)*

- [x] Abends dunkler nach lokaler Uhrzeit, Laternen als Lichtinseln, Lichtkreis um den Spieler. *(14.10.2026; GUT test_village_daylight 5/5, Screenshot 04:53 Uhr)*

### BI2 – Boss-Story ✓ *(14.10.2026; Story nur beim ersten Treffen, ca. 10 s)*

- [x] Erste Begegnung je Boss und Spielstand: längeres Intro mit Story; danach 1–2 Sätze. Gesehen über `SaveManager.has_seen`. *(14.10.2026: GUT test_boss_intro 26/26, Vorschau 4 Bosse; Zeilen-Freigabe durch das Projektmitglied offen)*
- [x] Bugfix: tote Gegner bleiben nicht mehr stehen (Tod im eigenen Physik-Frame, Obergrenze für die Todesanimation). *(14.10.2026: GUT test_enemy_death 3/3)*

### C3 – Musik-Übergänge zwischen Biomen ✓ *(14.10.2026, Lagerfeuer-Anschluss mit A6)*

- [x] Kein harter Schnitt beim Biomwechsel: nach dem Boss ausklingen, Geräuschkulisse zuerst, neue Musik langsam ein; Übergänge Dorf ↔ Dungeon und Champion-Räume prüfen. *(14.10.2026: Sieges- und Übergangs-Stinger je Boss/Biom, equal-power-Blenden, Szenen-Übergabe Hauptmenü ↔ Spiel; GUT 349/349, test_music_* 40/40, smoke_test 47 Räume 643 PASS, validate 0 failed; Probelauf mit Musik-Protokoll über die Biomwechsel 16/31/46)*
- [x] *(14.10.2026, A6 ruft `begin_interlude` beim Betreten des Lagerfeuers)* Später mit A6 verbinden: Das Lagerfeuer ist der musikalische Übergang. Haken steht: `MusicPlayer.begin_interlude(next_biome)` (Musik klingt aus, neue Geräuschkulisse setzt ein, der nächste Raum startet mit Stinger und Loop).

---

## Phase 2 – Räume (KONZEPT_RAEUME)

> **Phase 2 in Wellen (14.10.2026, großes Raum-Update).** Mehrere Agenten parallel, jeder mit eigenem Dateibereich; gemeinsame Hotspots (`dungeon_manager.gd`, Zieh-Logik) verdrahtet der Integrator über Haken.
>
> | Welle | Pakete (parallel) | Eigener Dateibereich |
> | --- | --- | --- |
> | 1 ✓ | A6 Lagerfeuer · D1 Türen · A2 Wegfindung (läuft) | `dungeon/rooms/campfire/` · `dungeon/environment/doors/` · `enemies/`, Tilesets |
> | 2 | **A3** Formen und Zutaten · **A5** Arena mit Wellen · **A8** Spezialräume · **A7** Kampf-Varianten + Wagnis-Altar (nach A2) | A3: Generator, `room_tiles.gd`, `room_controller.gd`, `room_sequence.gd`, `dungeon/rooms/combat/` · A5: `dungeon/spawning/` · A8: `dungeon/rooms/special/`, `dungeon/rooms/trials/` · A7: `dungeon/variants/`, `enemies/` |
> | 3 | **A4** Abgrund und Brücken · **A9** Licht-Varianten | A4: `player/`, Physik-Ebene, Abgrund-Teile in Generator/`room_tiles.gd` · A9: `dungeon/variants/light/`, Licht-Abfrage |
> | 4 | **A10** Wegführung (Ausgänge an allen Seiten, Abzweigungen, Geheimräume) | `dungeon_manager.gd` (Raumkette), Generator |
>
> Zieh-Regeln der neuen Inhalte (Varianten 20 %, gewichtete Spezialräume, Wagnis-Altar 12 %) liegen als eigene Tabellen (`.tres`) in den Paketen; der Integrator schließt sie in `room_sequence.gd`/`dungeon_manager.gd` an. Grafiken: [SPRITES_V5.md](SPRITES_V5.md).

### D1 – Türen je Biom und Raumtyp

**Ziel:** Türen erzählen, wohin es geht: eigener Rahmen und eigene Öffnen-Animation je Biom, ein großes Bosstor, Symbole über Spezialraum-Türen. Grafiken: [SPRITES_V4.md](SPRITES_V4.md) §4; bis dahin Platzhalter aus vorhandener Grafik (Einfärben, Fackeln, Partikel, Licht).

- [x] Rahmen + Türblatt je Biom (`door_frame_<biom>`, `door_<biom>_open_4f`), Bosstor (`door_frame_boss`, `door_boss_open_4f`), Spezialraum-Symbole (`door_special_symbols`). *(14.10.2026: `DoorStyle` wählt aus Biom und Zielraum, `Door.configure_for_room`; Fackeln/Glutschalen und ein Licht je Tür, Schild über Türen zu Spezialräumen und Miniboss; Anschluss in `RoomController`/`DungeonManager` durch den Integrator offen)*
- [x] Öffnen mit Staub/Funken, Ton und kurzem Licht-Aufblitzen; verschlossene Bossraum-Tür sichtbar bedrohlich (Glühen, Ketten). *(14.10.2026: `DoorView` folgt `Door.state_changed`; Töne `door_open_stone/_vines/_rune/_gate`, `door_boss_unlock`, `door_boss_close`; rotes Pulsieren + Pulslicht am Bosstor, Runen-/Glut-Glimmen)*
- [x] Automatische Übernahme der Dateien aus SPRITES_V4 §4, Platzhalter bis dahin. *(14.10.2026: `DoorArt`; gelieferte Grafiken sind eingebunden, gezeichnete Platzhalter nur als Rückfall)*
- [x] Tests: Türwahl je Biom/Raumtyp, Rückfall ohne Datei. *(14.10.2026: `test_door_style` 17/17, `test_door_node` 12/12; GUT 460/460, validate 0 failed, smoke_test 20 Räume PASS)*

### UX3 – Sprachen und Einstellungen (D-111, läuft in der Plattform-Sitzung)

- [ ] Englisch Standard, Deutsch zweite Sprache, Systemsprache automatisch, umschaltbar in den Optionen; `localization/` mit `translations.csv` und Hilfsklasse `Loc`.
- [ ] Hauptmenü und Optionen auf Übersetzungsschlüssel umgestellt, Einstellungen ausgebaut (`docs/KONZEPT_SPRACHEN_EINSTELLUNGEN.md`).
- [ ] Schlüsselliste als Vorlage für die zweite Runde (HUD, Dorf, Dungeon-Dialoge – Letztere in UX2).

### UX2 – Gut ins Spiel kommen, einheitliche Dungeon-Menüs (nach A8, D-110)

> Neue und vereinheitlichte Texte direkt als Übersetzungsschlüssel (D-111, `Loc` aus UX3).

**Ziel (Playtest 14.10.2026):** „Die UI-Menüs von Shop, Lagerfeuer usw. im Dungeon sind so stark unterschiedlich … gleiche das an. Gutes UI, übersichtlich, passend zum Spiel. Schau, dass man gut ins Spiel kommt.“

- [ ] **Ein Menü-Baukasten** für alle Dungeon-Dialoge (Upgrade-Wahl, Händler, Waffenwahl, Lagerfeuer, Altar, Pakt, Prüfungstruhe, Tab-Übersicht, Portal, Run-Ende): gleicher Rahmen, Titel, Untertitel, Karten-Layout, Tastenhinweise, Fußzeile, Sounds.
- [ ] **Klare Zustände statt Halbtransparenz:** nicht leistbar = Karte normal sichtbar, Preis rot + Hinweis „zu wenig Gold“ + Schloss/Fehlton beim Klick; ausverkauft/gesperrt eigenes Abzeichen.
- [ ] **Raum-Genres anzeigen** (Banner mit Name und Symbol) für Arena, Katakombe, Abgrund, Varianten, Prüfung, Pakt, Wagnis, Lagerfeuer, Spezialräume; normale Kampfräume ohne Namen.
- [ ] **Erklärkarte beim ersten Mal** je Genre (`room_intro_<genre>`), 1–2 Sätze, nicht pausierend.
- [ ] **Einstieg prüfen:** erste 10 Minuten eines neuen Spielstands durchgehen (Dorf → Raum 1 → erste Wahl → erster Spezialraum → erster Boss) und Reibungen beheben (Reihenfolge der Hinweise, Überladung, fehlende Erklärungen).

### A1 – Raumart-Fundament ✓ *(14.10.2026)*

Raumart und Größe je Vorlage, Ziehung über den Dungeon-RNG (D-095), Katalog `combat_catalog.tres`, Erreichbarkeitsprüfung mit Dash über 1-Tile-Lücken, Tests `test_room_kind.gd`, `test_room_templates.gd`.

- [ ] **Nacharbeit (mit A3):** Raumarten nach D-100 umbenennen: `NORMAL`, `ARENA`, `CHASM` statt `ARENA`, `STRUCTURED`, `ABYSS`; Gewichte Normal 40 / Arena 35 / Abgrund 25.
- [ ] **Nacharbeit (mit A5):** Mehr Gegner als Spawnpunkte → Rest als zusätzliche Welle (`EnemySpawner` verlangt heute genau 5 Punkte).

### A2 – Gegner-Wegfindung

**Ziel:** Gegner finden um Mauern, Säulen und später Abgründe herum. Voraussetzung für die Formen aus A3 (Ring, Kammern, Katakombe). **Parallel zu A3**, wenn A2 die Navigation über die Navigationsebene im TileSet löst und `room_tiles.gd` A3 überlässt.

**Dateien:** `tools/build_tilesets.gd`, `dungeon/environment/*tileset*.tres`, `enemies/enemy_base.gd`, `enemies/enemy_base.tscn`, `tests/`.

- [ ] Navigation für begehbare Boden-Tiles; Wände, Säulen, Innenmauern und Abgründe nicht begehbar.
- [ ] `NavigationAgent2D` am Gegner; Wegpunkte nur ohne freie Sicht zum Ziel (spart Rechenzeit).
- [ ] Fernkämpfer behalten ihr Abstand-Verhalten, suchen ihre Position über Navigation.
- [ ] Mehrere Ziele vorbereiten (Koop): Ziel = nächster lebender Spieler.
- [ ] Leistung: 15+ Gegner ohne Ruckler; automatischer Test „kein Gegner hängt länger als 2 s an einer U-Mauer“.

### A3 – Formen und Zutaten (KONZEPT_RAEUME §3)

**Ziel:** Viele Räume sehen und spielen sich sofort anders, ohne neue Namen.

**Dateien:** `dungeon/rooms/**`, `dungeon/room_sequence.gd`, `tools/generate_room_templates.py`, neue `RoomTemplate`- und `IngredientSet`-Ressourcen, `tests/`.

- [ ] `RoomTemplate`-Resource (Raumart, Form, Größe, Türseiten, Spawnpunkte, erlaubte Biome) statt loser Exporte; Katalog daraus.
- [ ] `RoomTiles.wall_rects` für Innenmauern mit den gelieferten `inner_wall_tiles*.png` (je Biom).
- [ ] **Formen** in S/M/L: Rechteck, L-Form, Kreuz, Ring, Zwei Kammern, Säulenhalle; **Katakombe** (M/L, höchstens zwei Sackgassen, Truhe in der tiefsten).
- [ ] **Zutaten-Streuer** je Biom (`IngredientSet`): Deckung, Fallengruppen, Innenmauern/Säulen, Engstellen/Nischen, Lichtinseln/Dunkelzonen, Explosionsfässer; 2–3 Zutaten je Raum; danach Erreichbarkeitsprüfung.
- [ ] **Unsichtbare Variation:** Gegnergruppen nach Thema, stiller Raum (8 %, gleiche Gesamt-HP).
- [ ] Tests: jede Form erreichbar in jedem Biom, Streuer blockiert nie den Weg, Verteilung über viele Seeds.

### A5 – Arena mit Wellen (KONZEPT_RAEUME §3.1)

- [ ] 2–3 Wellen, Welle 2 startet bei höchstens einem verbleibenden Gegner; Spawn aus Wandlöchern/Toren an mindestens zwei Seiten, Mindestabstand 96 px zum Spieler.
- [ ] Variante **Hinterhalt**: Raum wirkt leer, Gegner brechen beim Schließen der Tür aus den Wänden.
- [ ] Arena-Formen (Rechteck M/L, Kreuz, Säulenhalle); Balance mit `balance_sim.gd` gegenprüfen.

### A6 – Lagerfeuer (KONZEPT_RAEUME §6.3) ✓ *(14.10.2026)*

- [x] Zwischenraum nach jedem Boss, zählt **nicht** als Raum (Raumnummer, Skalierung, Heilung unverändert). *(14.10.2026: eigener Platz im Raumstapel, `RoomSequence`-Slots; smoke_test 47 mit Lagerfeuer nach 15/30/45, GUT test_campfire 18/18)*
- [x] Übergangs-Tiles vom alten ins neue Biom; Musik klingt aus, neue Geräuschkulisse setzt ein (mit C3). *(14.10.2026: Dither-Überblendung in Boden, Wänden und Fels, Übergangs-Overlays aus SPRITES_V4 §5, Fackeln/Licht/Partikel/Dunkelfarbe folgen; `begin_interlude` beim Betreten, kein zweites Blenden in Raum n+1)*
- [x] Eine Wahl: heilen (+4 HP) **oder** ein stapelbares Upgrade um einen Stack stärken. *(14.10.2026: Dialog „Rast am Lagerfeuer“, je Spieler eine Wahl)*
- [x] Exit-Portal am Lagerfeuer (Empfehlung D-103, Bestätigung offen); keine Raum-45-Wahl. *(14.10.2026: hinter `DungeonManager.CAMPFIRE_EXIT_PORTAL`, TESTWERT; aus = Portal wieder im Bossraum wie D-073; Bestätigung durch das Projektmitglied weiter offen)*

### A7 – Kampf-Varianten I und Wagnis-Altar (KONZEPT_RAEUME §4, §5)

- [ ] Gemeinsame Schnittstelle für Varianten (Start, Abschluss, Bonus erfüllt) – der `DungeonManager` behandelt sie wie Kampfräume.
- [ ] Ziehung: ab Raum 6 **20 %** Varianten, nie zwei hintereinander (D-101).
- [ ] **Seelenflamme beschützen**, **Beschwörungsrisse**, **Totengräber** (Krypta), **Kopfgeld**.
- [ ] **Wagnis-Altar** auf 12 % der normalen Kampfräume ab Raum 6 (D-104): Prüfung oder Fluch, Annehmen mit E.
- [ ] Bonus-Truhe bei Erfolg (Belohnung `OFFEN`, Vorschlag KONZEPT_RAEUME §9.4).

### A4 – Abgrund und Brücken (KONZEPT_RAEUME §3.1, D-086)

**Dateien:** `project.godot` (Physik-Ebene), `components/physics_layers.gd`, `dungeon/rooms/room_tiles.gd`, `tools/build_tilesets.gd`, `player/player.gd`, `enemies/enemy_base.gd`, `economy/gold_pickup.gd`, `tools/generate_room_templates.py`, `enemies/enemy_hints.gd`. Grafiken liegen bereit (`abyss_tiles`, `bridge_tiles`, `abyss_mist_4f`, `player_fall_4f`).

- [ ] **Physik-Ebene 7 `pit`** (`PhysicsLayers.PIT = 64`): Gegner haben `pit` in der Maske, Spieler und Geschosse nicht.
- [ ] `RoomTiles.pit_rects` und `bridge_rects`; Navigation (A2) schließt Abgründe aus.
- [ ] **Spieler:** im Dash in der Luft; über Abgrund und nicht im Dash → nach 0,1 s fallen; 0,5 s Animation, Eingaben gesperrt (`set_input_locked`), dann **2 HP = ein ganzes Herz** direkt, Rücksetzen an die letzte sichere Stelle (am Spieler gespeichert), 1 s unverwundbar.
- [ ] **Gegner:** fallen nur bei starkem Rückstoß (> 250 px/s, TESTWERT); Champions, Golems, Bosse nie.
- [ ] Gold, Kisten, Herzen landen nie im Abgrund.
- [ ] Formen: Brückenhalle, Inseln, Steg, Ring um ein Loch; Zutat „kleine Abgrundlöcher“.
- [ ] Ersthinweis: „Mit Space über Abgründe springen – Herunterfallen kostet ein Herz.“
- [ ] Tests: Fallen nur ohne Dash, Rücksetzen, 2 HP am Schild vorbei, Gegner nur bei Rückstoß, Champions nie, Gold nie im Abgrund.

### A8 – Neue Spezialräume (KONZEPT_RAEUME §2, §6.1, §6.2)

- [x] **Gewichtete Spezialraum-Ziehung** (D-102): Shop 35, Waffen 20, Brunnen 15, Extra-Upgrade 15, Prüfung 15; Gewichte als `.tres`. *(14.10.2026: `SpecialTable` + `special_table.tres`, kein Typ zweimal hintereinander, ein Zufallswert je Ziehung; GUT test_special_table 11/11. Anschluss an `DungeonManager._prepare_slot` und Enum `TRIAL` durch den Integrator offen)*
- [x] **Prüfungsräume:** Spießrutenlauf zuerst, dann Bröckelboden (braucht A4), dann Lichtlauf. Direkter Weg zum Ausgang immer frei, Truhe am Ende sichtbar, makellos = +1 Kristall. *(14.10.2026: eigene Vorlage `trial_room.tscn` mit Innenmauern, Spießrutenlauf (Stacheln, Flammenstöße, Pendelklingen) und Lichtlauf; Truhe = Upgrade-Wahl, makellos = +1 Seelenkristall je Spieler (D-109), Fehler ½ Herz, nie tödlich; GUT test_trial_room 13/13, test_trial_run 12/12)*
  - [ ] Bröckelboden: Schnittstelle `CrumbleCourse` steht, Bau nach A4 (Abgrund-API, Fallen).
- [x] **Pakt-Altar** in ⅓ der Extra-Upgrade-Räume; Flüche in der Tab-Übersicht. *(14.10.2026: Wahl Extra-Upgrade oder Pakt (+2 Stufen) gegen einen Fluch je Spieler (`PlayerCurses`); Max-Herz und Brunnen wirken, Gegnertempo und Lichtkreis als Haken für den Integrator; GUT test_pact 15/15)*

### A9 – Licht-Varianten (KONZEPT_RAEUME §4.3, §4.4, §4.7)

- [ ] Gemeinsame Abfrage „Punkt liegt im Licht“ für **beliebig viele** Lichtkreise (Spieler, Fackeln, Kristalle) – gleich für Koop.
- [ ] **Steinwächter**, **Laternenträger**, **Fackelraum** (Schattenreich).

### A10 – Wegführung (KONZEPT_RAEUME §7)

- [ ] Ausgänge oben, links oder rechts; Türen an mehreren Seiten der Vorlagen; Überlappungsprüfung mit den noch existierenden Räumen.
- [ ] **Abzweigungen** (D-105): zwei Ausgänge mit Symbol, beide zu Raum n+1; **Elite-Nest** nur über Abzweigungen.
- [ ] **Geheimräume** hinter rissigen Wänden (Explosionen), Nische mit Truhe/Kristall/seltenem Händler.

### Später (nach Phase 3 oder bei Bedarf)

Langer Korridor, Höhle (Schleimgrotte), Wasser/Schlamm; Gefangener (mit Dorf-Freischaltungen); Mimic als normaler Gegner.

### K1 – Kosmetik (später, Wunsch Projektmitglied 14.10.2026)

Heute gibt es nur die Kleidungsfarbe (beim Anlegen des Spielstands und im Kleiderschrank im Zuhause). Später:

- [ ] Kosmetik-Teile über `CharacterData` (z. B. Hüte, Umhänge, Haarfarbe, Waffen-Skins, Laternen-/Lichtfarbe), nur Optik, kein Spielvorteil.
- [ ] Freischalten über Erfolge/Meilensteine oder Seelenkristalle (Werte `OFFEN`); Anprobieren im Zuhause.
- [ ] Koop: Kosmetik wird mit dem Profil an Mitspieler übertragen (MP2), Spielerfarben dürfen nicht mit der Kleidung kollidieren (`OFFEN`).
- [ ] Grafiken als Briefing in `docs/SPRITES_V4.md` (Ebenen passend zu den Spieler-Animationen).

---

## Erledigt (Ausbau-Runde 13.–14.10.2026)

| Paket | Ergebnis | Nachweis |
| --- | --- | --- |
| A1 Raumart-Fundament | siehe oben | GUT, Smoke-Test 47 Räume |
| B1 Dorf erklären | Erklärung beim ersten Betreten, Schmiede mit echten Werten, Schilder, Run-Start-Banner „Aus dem Dorf“ | GUT 210/210, 14.10.2026 |
| C1 Musik je Biom | 4 Biom-Tracks + `_intense`, 4 Boss-Themen + `_p2`, Geräuschkulissen | GUT 268/268, 14.10.2026 |
| C2 Waffen-Grafiken | Dolch, Hammer, Wurfmesser, vier Spezial-Effekte | GUT, combat/boss_sim, 14.10.2026 |
| UI1 UI nach Mockups | Theme, Pixelify, HUD, Karten, Shop, Dialoge, Boss-Leiste | GUT 244/244, 14.10.2026 |
| BI1 Boss-Intro | Dialog mit Gebrabbel, Boss passiv, Spieler gesperrt | GUT 268/268, Smoke-Test, 14.10.2026 |

Grafiken für Strang A (Abgrund, Brücken, Innenmauern, Fallanimation): geliefert 14.10.2026.

---

## Auftragsvorlage für einen Agenten

> Setze in `C:\Users\bmg18\Documents\Workspace\WebBude\WebBude Labs\Soulwick\soulwick` das Paket **[ID]** aus `docs/ROADMAP_AUSBAU.md` um. Lies vorher `AGENTS.md`, die Abschnitte „Regeln“ und „Koop-Check“, die Paketbeschreibung, für Räume `docs/KONZEPT_RAEUME.md` und die genannten D-Einträge. **Du darfst nur diese Dateien ändern:** [Liste]. Prüfe am Ende mit den Befehlen aus AGENTS.md §7, hake die erledigten Punkte mit Datum ab und beantworte den Koop-Check im Bericht. Kein Commit.

**Weiterlesen:** [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md) · [PRD.md](PRD.md) · [ROADMAP.md](ROADMAP.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [DECISIONS.md](DECISIONS.md)
