# ROADMAP Ausbau – Phase 1 und 2: spielbar machen, Räume

> **Status:** Aktuell (Rest von Phase 2: M3, M5, L-Pläne, Fehlerliste 2b)
> **Stand:** 17.10.2026 · Übersicht aller Phasen: [ROADMAP.md](ROADMAP.md) (D-179). Hier stehen die **offenen Pakete** der Phasen 2b und 2c vollständig und alles Erledigte als eine Zeile je Paket; was gebaut ist, steht im Code (D-178).
> **Für Räume gilt** [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md). **Abhaken** nur mit Nachweis (Tests grün, Datum), danach das Paket in die Erledigt-Liste schieben. Jedes Paket ist für **einen Agenten** geschnitten.

## Regeln für jeden Agenten

1. Vorher lesen: [AGENTS.md](../AGENTS.md), die genannten D-Einträge, [ARCHITECTURE.md](ARCHITECTURE.md), für Räume [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md).
2. Zahlen als Konstanten oder `@export` mit Kommentar `TESTWERT`, Gewichte als `.tres` (Balancing ohne Code).
3. Prüfen: `validate_project.gd`, GUT, `smoke_test.gd -- 47`; bei Kampf zusätzlich `combat_sim.gd` und `boss_sim.gd` ([AGENTS.md](../AGENTS.md) §7).
4. Den Koop-Check (unten) im Bericht beantworten; Namen, die `online/` nutzt, nicht umbenennen ([MULTIPLAYER.md](MULTIPLAYER.md) §6).
5. Fehlende Grafik als Briefing in das neueste offene `docs/design/sprites/SPRITES_V*.md` ([design/sprites/](design/sprites/README.md)).

## Koop-Check für jedes Paket (D-088)

Jeder Bericht beantwortet diese fünf Fragen mit „ja“:

- Kein neues `get_first_node_in_group(&"player")`; Spieler kommen als Parameter oder als Liste aller Spieler.
- Entscheidungen (fällt jemand, ist die Flamme aus, ist ein Punkt im Licht) an **einer** Stelle als Funktion; Effekte getrennt über Signale.
- Zufall nur über den Dungeon-RNG (`DungeonContext`); `randf()` nur für Optik.
- Keine neuen globalen Pausen, kein `Engine.time_scale` außer HitStop; Sperren je Spieler (`Player.set_input_locked`).
- Zustand je Spieler (letzte sichere Stelle, Fluch, getragene Laterne) liegt am Spieler, nicht in Autoloads.

## Offen

### Phase 2b – Rest

- [ ] Bekannte Fehler aus der Durchsicht (14.10.2026) prüfen und beheben, soweit noch vorhanden: Seitentür-Platzhalter wie Leiter, Geheimnische vor dem Öffnen sichtbar und über die Mauer ragend, Bruchkante in falscher Biomfarbe, ausgefranste Lochränder, Nachbarräume schauen ins Bild, veraltete Banner bei schnellem Spiel.
- [ ] **L-Pläne für 3–4 Spieler** (D-084, D-127): 13 L-Pläne liegen vor, seit M1 im Fels-Stil (`dungeon/rooms/plans/*/…_l.txt`); `DungeonManager.get_room_sizes()` gibt ab 3 Spielern L zurück, wenn L-Vorlagen da sind. Offen: Nachweis im Koop mit 3 Spielern (Raumkette, Reichweite `_get_combat_reach`, Gegnerzahl), dann abhaken.
  - [ ] `RoomVariants.plan_mode_for` auf `DungeonManager.get_room_sizes()` umstellen: prüft heute nur `RoomSequence.SOLO_ROOM_SIZES`, nicht die Raumgrößen der Gruppe (Multiplayer-Vertrag, offener Punkt f).

### M3 – Höhe (nach M1)

- [x] Plateaus mit Klippe, Treppen (`stairs_cut`, Gegner nutzen sie) und Leitern (nur Spieler), zwei Boden-Ebenen mit Umschalt-Areas, Projektile über Ebenen, Z-Sortierung; 1–2 Plateaus je Höhlenraum (D-186). *(18.10.2026: `dungeon/rooms/height/`, Pläne Rundhöhle, Weiche Höhle (Leiter-Insel mit Truhe), Kreuzgang, Halbmond in allen Biomen; Generator ohne Abweichung; GUT 2003/2005 (2 ausstehend: API-Umgebung), neu `test_height_layout`, `test_height_room`, `test_height_templates`; smoke_test 47 mit Seeds 424242 und 33 PASS (Plateau-Räume gespielt, Höhe live geprüft), combat_sim und boss_sim PASS, validate 0 failed; Sichtprüfung alle Biome.)*

### M3b – Höhe in Modus- und L-Plänen, Quellen auf Plateaus

- [ ] Plateaus in Modus-Plänen (Flamme auf dem Plateau, Geleit-Pfad unter einem Plateau, Arena-Truhe oben) und in L-Plänen; Gegnerquellen auf Plateaus mit Treppe, bevorzugt Fernkämpfer (Projektmitglied 18.10.2026, D-186).

### M5 – Gang-Segmente in Seitenansicht: Rest

- [x] **Anschluss fertigstellen:** Leiter-Weg einer Abzweigung (`BranchOption`, Symbol `ladder`; Entscheidung D-144: liegt vor Raum n+1) und `smoke_test.gd` fährt Segmente mit `SideBot`. Schon im Code, beim Abhaken mit Nachweis belegen: Segmente nach dem Lagerfeuer und nach Ruhe-Räumen (`DungeonManager._plan_side_way`, D-144 Runde 3, im Koop mit `net_run_smoke side=1` am 15.10.2026 geprüft), Eingabe `side_dash`, Option „Seitenwege auslassen“. *(18.10.2026: Leiter-Weg statt des sicheren Wegs in `BranchRules.LADDER_SHARE` = 40 % (TESTWERT) der Kampf-Abzweigungen, keine zusätzliche Dungeon-RNG-Zahl, nur Pläne mit Truhen-Nische; Koop: Host plant den Weg nach der Wahl (`branch_chosen_net` vor `side_way_net`), Client übernimmt über `plan_side_way`. Schalter im Tab Allgemein (Abschnitt „Spiel“). smoke_test 47 PASS mit Seed 424242 zweimal (42 gleiche chain-Zeilen), 33 und 77: je ein Leiter-Weg mit Truhe, drei Lagerfeuer-Segmente, bei 77 eines nach einem Ruhe-Raum, 0 Stürze; nie vor dem Boss, nie zweimal. GUT 1981/1983 (2 ausstehend: API-Umgebung), neu `test_side_ways`, `test_side_options`, `test_branch_rules` +4; side_check 48 Abläufe und Hakenpfad PASS; validate 0 failed.)*

### K1 – Kosmetik → Strang W in ROADMAP.md

Wird hier nicht mehr geplant, damit es keine doppelte Planung gibt: Das Kosmetik-System ist Paket **WK2** im Strang W von [ROADMAP.md](ROADMAP.md) (Entscheidungen vorher in WK0). Absicht, Regeln (nur Optik, Lesbarkeit im Koop, Übertragung über das Profil) und offene Fragen (freispielbar oder kaufbar) stehen in [KONZEPT_BEGLEITER_KOSMETIK.md](KONZEPT_BEGLEITER_KOSMETIK.md) §5 und §9, die Grafik in [SPRITES_V12.md](design/sprites/SPRITES_V12.md) (D-175, D-176).

### Später (nach Phase 3 oder bei Bedarf)

Langer Korridor, Höhle (Schleimgrotte), Wasser/Schlamm als Grundrisse; Gefangener (mit Dorf-Freischaltungen); Mimic als normaler Gegner; Koop-Räume aus KONZEPT_RAEUME_V2 §3.11 (MP5).

## Erledigt

Einzelheiten stehen in den D-Einträgen, im Code und in der Git-Historie.

| Paket | Titel | erledigt | D |
| --- | --- | --- | --- |
| A1 | Raumart-Fundament | 14.10.2026 | D-095, D-100 |
| B1 | Dorf erklären | 14.10.2026 | D-087 |
| C1 | Musik je Biom | 14.10.2026 | D-092, D-097 |
| C2 | Waffen-Grafiken und Effekte | 14.10.2026 | D-099 |
| UI1 | UI nach den Mockups | 14.10.2026 | D-096 |
| BI1 | Boss-Intro | 14.10.2026 | D-098 |
| MM1 | Hauptmenü, Spielstände, Charakterauswahl | 14.10.2026 | D-059 |
| UX1 | Spielbar-Pass (Optionen, Steuerungs-Hinweis, Run-Ende) | 14.10.2026 | – |
| B2 | Dorf straffen und freischalten | 14.10.2026 | D-087 |
| B3 | Dorf beleben | 14.10.2026 | – |
| B4 | Dorf mit Tageszeit | 14.10.2026 | D-107 |
| BI2 | Boss-Story beim ersten Treffen | 14.10.2026 | – |
| C3 | Musik-Übergänge zwischen Biomen | 14.10.2026 | D-097 |
| D1 | Türen je Biom und Raumtyp | 14.10.2026 | – |
| UX3 | Sprachen und Einstellungen | 14.10.2026 | D-111 |
| UX2 | Einstieg, einheitliche Dungeon-Menüs, Raum-Genres | 14.10.2026 | D-110 |
| A2 | Gegner-Wegfindung | 14.10.2026 | D-113 |
| A3 | Formen und Zutaten | 14.10.2026 | D-113 |
| A5 | Arena mit Wellen | 14.10.2026 | D-113 |
| A6 | Lagerfeuer | 14.10.2026 | D-103 |
| A7 | Kampf-Varianten I und Wagnis-Altar | 14.10.2026 | D-114 |
| A4 | Abgrund und Brücken | 14.10.2026 | D-115 |
| A8 | Neue Spezialräume (Prüfungen, Pakt) | 14.10.2026 | D-112 |
| A9 | Licht-Varianten | 14.10.2026 | D-116 |
| A10 | Wegführung und Balance nach dem Raum-Ausbau | 14.10.2026 | D-117, D-118 |
| 2b-0 | Szenen-Galerie, Briefing, Design-Antwort, Pakete geschnitten | 14.10.2026 | D-120 |
| 2b-G | Gegner-Verhalten „mehr los, von hinten“ | 14.10.2026 | D-130 |
| R1 | Grundrisse aus Plänen, einheitliches Wand-System | 14.10.2026 | D-131 |
| R2 | Gegner-Quellen | 14.10.2026 | D-132 |
| R3 | Intro-Muster, Aufgabenleiste, Banner-Warteschlange | 14.10.2026 | D-133 |
| R4a | Minispiele Geleit, Seelen sammeln, Einsturz | 14.10.2026 | D-135 |
| R4b | Minispiele aus den Varianten, Modus-Tabelle und Ziehung | 14.10.2026 | D-136 |
| R5 | Türen, Gänge, Abzweigung ohne Aufploppen | 14.10.2026 | D-137 |
| R6 | Licht | 14.10.2026 | D-133, D-141 |
| R7 | Dorf und Dungeon-Eingang | 14.10.2026 | D-138 |
| R8 | UI-Rework | 14.10.2026 | D-139 |
| R9 | Töne der Räume | 14.10.2026 | D-133 |
| M1 | Fels statt Mauer, organische Pläne (mit V9-Grafik) | 15.10.2026 | D-142 |
| M2 | Ein Tor pro Übergang, Tunnel | 15.10.2026 | D-143 |
| M4 | Kamera 1,25× | 14.10.2026 | D-140 |
| M5 (Teil) | Gang-Segmente in Seitenansicht: Segment, Physik, Kamera, Vorlagen, Runde 2 (Rest oben offen) | 15.10.2026 | D-144 |
