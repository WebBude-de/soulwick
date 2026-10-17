# ROADMAP – alle Phasen auf einen Blick

> **Stand:** 17.10.2026 · **Zweck:** Reihenfolge der Phasen, Stand in einer Zeile, Pakete der parallelen Stränge. Was gebaut ist, steht im Code; die Pakete im Detail stehen in den verlinkten Roadmaps (D-178).
> **Grundlage:** [PRODUKT.md](PRODUKT.md) (Ziel, Zielgruppe, Modell), [DECISIONS.md](DECISIONS.md) (vor allem D-173 bis D-179), [GLOSSAR.md](GLOSSAR.md). Arbeitsweise: [AGENTS.md](../AGENTS.md) §5 und §10.
> **Leseregel:** Jedes Paket ist für **einen** Fach-Agenten geschnitten; abgehakt wird nur mit Nachweis (Tests, Datum). `OFFEN` = nicht entschieden, „Vorschlag“ = braucht eine Bestätigung.

## Nordstern

Soulwick ist das Pixel-Roguelite, in das du mit Freunden reinrennst – jeder Run anders, jeder Boss ein Clip (D-173). Man versteht es in einer Minute, startet es über einen Link sofort mit Freunden, und ständig passiert etwas, das man zeigen will.

**Vorrang-Regel:** Was dem Kernsatz dient, geht vor: **Koop** (zusammen spielen ohne Hürde), **Clips** (Bosse, KI-Bosse, Party-Momente zum Teilen) und **Einstieg in einer Minute** (Link antippen, schon im Spiel). Wollen ein Paket aus den parallelen Strängen und ein Paket, das einem dieser drei dient, denselben Agenten oder dieselbe Datei, bekommt es das zweite. Bei Gleichstand gilt die Phasen-Reihenfolge.

## Phasen (D-179)

| # | Phase | Stand (17.10.2026) | Detail |
| --- | --- | --- | --- |
| 1 | **Spielbar** | fertig (14.10.2026) | [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) |
| 2 | **Räume**, 2b Raum-Rework, 2c Makeover | läuft; offen u. a. Höhe (M3), Anschluss der Seitenwege (M5), L-Räume für 3–4 Spieler, Grafiken V8/V9 | [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) |
| 3 | **Koop**: Schnelles Spiel, gemeinsamer Run, **Einladen per Link aus dem Browser**, Gilden, Ranglisten, Steam; **zum Release** | MP1–MP3 gebaut, Testversion läuft gegen die Test-Server; offen: Einladen per Link (MP2b), Koop-Gefühl (MP5), Steam, Ranglisten | [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) |
| 4 | **KI-Bosse** „Traumweber“ („Wünsch dir einen Boss“), der stärkste Clip-Moment; **zum Release** | direkt nach Koop; KI1, KI2 (Baukasten) und KI9 (Clip teilen) brauchen weder KI noch Server und dürfen vorgezogen werden | [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) · [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) |
| 5 | **Party-Modus**: nur Minispiele, 2–4 Spieler gegeneinander, gleiche Grafik; **nach dem Release** | Konzept; Pakete PA0–PA3 unten | [KONZEPT_PARTY_MODUS.md](KONZEPT_PARTY_MODUS.md) |
| – | **Crossplay, Stores, Käufe**: zum Release alle Versionen gemeinsam – Browser, Steam, Android, iOS (D-179) | CP0 bis auf die Fragen 7, 8 und 10 entschieden; Build-Pipeline für alle Stores vorbereitet, noch kein Store-Konto (auch kein Apple-Konto für iOS) | [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) · [STORES.md](STORES.md) · [LAUNCH.md](LAUNCH.md) |

Crossplay ist keine eigene Phase: Konto und Relay (CP1, CP3) gehören zu Phase 3, Stores (CP4, CP7) gehören für alle drei Stores ins Release-Tor (D-179), Käufe und Werbung (CP6) kommen frühestens mit dem Release. Die Plattform (`soulwick-platform`, eigene Roadmap dort) läuft jederzeit parallel.

## Release-Tor (D-179)

**Release-Umfang (VERBINDLICH, D-179):** Koop mit Freunden, KI-Bosse („Wünsch dir einen Boss“), Wick als Begleiter, Dorf ausbauen und Freunde ins Dorf einladen (Dorf besuchen). Der Party-Modus kommt danach. Released wird auf allen Versionen gemeinsam: Browser, Steam, Android und iOS (D-179; ersetzt Steam → Android → iOS aus D-119). Öffentlich (Social Media) geht es erst ab dem Release. Die Website darf vorher in Produktion gehen und beschreibt diesen Umfang schon wie vorhanden; `LIVE_FEATURES=false` schaltet nur Spielen, Installieren, Ranglisten und Gildenseiten ab ([LAUNCH.md](LAUNCH.md) §1).

**Mindestumfang (Vorschlag, braucht die Bestätigung des Projektmitglieds):** Released wird erst, wenn diese Pakete mit Nachweis abgehakt sind. Phase 1 und 2 liegen nach D-179 ohnehin davor; Strang L ist kein Tor.

| Bereich | Muss vor dem Release fertig sein | Darf nach dem Release kommen |
| --- | --- | --- |
| Phase 3 Koop ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md)) | alle offenen MP-Pakete: MP2b (Einladen per Link), MP4, MP5 (Koop-Gefühl), MP6 und MP10 (Steam), MP7 (`production`), MP8 (Gilden), MP9 (Ranglisten); aus [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) CP1 (Spiel-Teil), CP2 (Gerätetest Android und iPhone), CP3 in `production`, CP4 und CP7 für alle drei Stores (Steam, Google Play, App Store; Apple-Konto und Signieren in der CI), Browser-Version in Produktion (D-148) | CP5 (Cloud-Save), CP6 (Käufe, Werbung) |
| Phase 4 KI-Bosse ([ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md)) | KI0–KI5, KI7 (Koop), KI8 (Moderation, Kosten, Steam-Angaben), KI9 Stufe 1 (Bildkarte zum Teilen) | KI6 (Arena der Albträume, Galerie), KI9 Stufe 2 und 3 |
| Strang W (unten) | WK0, WK1 (Wick als Begleiter), WK2 (Outfits zum Freispielen; liegt in der Reihenfolge vor WK5 und WK6), WK5 (Dorf-Deko), WK6 (Dorf besuchen, Freunde ins Dorf einladen) | WK3 (Huhn-Gags), WK4 (Pets), kaufbare Kosmetik (CP6) |

„Dorf ausbauen“ meint die Gebäude-Stufen (schon im Spiel) und das Verschönern mit Deko (WK5); Outfits zum Freispielen (WK2) gehören ebenfalls zum Release. Das ist die Lesart von D-179 (Projektmitglied: „Dorf ausbauen … ist auch schon drin zum Release“; „bau alles schon ready aus … zum Release ist ja dann alles da“), so auch in [PRODUKT.md](PRODUKT.md) §5.

## Parallele Stränge

Laufen neben den Phasen, weil sie eigene Dateien haben. Paket-IDs `LK` (Look) und `WK` (Wick), weil `L1` schon vergeben ist (D-141). Für jedes Paket gilt der Koop-Check aus [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) (fünf Fragen); die Spalte nennt nur, was dazukommt. Geprüft wird immer mindestens mit `validate_project.gd` und GUT (AGENTS.md §7), Fensterläufe stumm.

### Strang L – Moderner Look (D-174)

**Ziel:** Der Pixel-Stil bleibt, wirkt aber wie heute gemacht (in D-174/D-179 ‚Makeover‘ genannt; nicht zu verwechseln mit Phase 2c, dem Raum-Makeover mit den M-Paketen in ROADMAP_AUSBAU). **Schon gebaut, nicht neu planen:** Schein um Lichtquellen und Biomstimmung im Vollbild-Durchgang (D-141), Lichtprofil je Raum (R6), weiche Kamera (M4), Squash and Stretch in der Seitenansicht (M5, D-144), aufspringende Dialoge und ausgeteilte Karten (R8), Dorf mit Tageszeit (B4, R7), Schatten unter Figuren. **Regel:** Jedes Paket hat eine Stufe „Niedrig“ (Option „Lichteffekte“, D-141) und hält im Browser und auf Android die Bildrate (Ziel aus CP2: 60 fps, mindestens 50, TESTWERT).

| ID | Ziel | Dateien/Ordner | Agent | Prüfung | Koop-Check |
| --- | --- | --- | --- | --- | --- |
| LK0 | Look-Ziel festlegen: Galerie des heutigen Stands, Referenzen (Dead Cells, Eastward, Celeste), Briefing an Claude Design für Dorf, Menü und Licht; Ergebnis als D-Eintrag | `tools/scene_gallery.gd` (nur ausführen), `docs/design/` (Briefing, Galerie in `docs/design/gallery/`) | Orchestrator | Galerie vorher/nachher | – |
| LK1 | Licht 2.0: weiches Bloom in der Lichtfarbe, weiche Schatten, die von nahen Lichtquellen weg fallen | `components/visual/` (`vision.gdshader`, `light_palette.gd`, `light_source.gd`, `drop_shadow.gd`) | `fx-audio-dev` | Screenshots je Biom und Dorf, Browser-Lauf bis Raum 2, Bildrate auf Android | nur Optik je Rechner; logische Sicht (`LightQuery`, D-067) bleibt |
| LK2 | Unschärfe hinter Menüs und weiche Übergänge (Dorf ↔ Dungeon, Menüseiten) | `ui/effects/` (neu: Menü-Hintergrund), Haken im Dialog-Baukasten `ui/menus/modal.gd` (Integrator) | `fx-audio-dev` | Screenshots aller Dialoge, GUT `test_fx*` | im Gruppenspiel pausiert nichts (D-085): Unschärfe nur im eigenen Bild |
| LK3 | Lebendige Welt: Wind in Gras, Stoff und Fahnen, Staub im Licht, Funken, Glühwürmchen | `components/visual/` (neu: Wind-Shader, Umgebungspartikel), Haken in `dungeon/environment/deco/` und `world/village/` | `fx-audio-dev` | Screenshots, Bildrate auf Android | `randf()` nur für Optik |
| LK4 | Squash and Stretch und Nachschwingen auch von oben: Dash, Landung, Treffer, Gegner-Sprung, Münzen, Truhen | `components/visual/sprite_fx.gd` (und neue Hilfsklasse daneben); Haken `player/player.gd`, `enemies/enemy_base.gd` (Integrator) | `fx-audio-dev` | combat_sim und boss_sim unverändert grün, Screenshots | Clients spielen es aus vorhandenen Ereignissen ab, kein neues Netzpaket |
| LK5 | UI in Bewegung: Hauptmenü mit Leben (Ebenen, Wick), Knopf-Animationen, Seitenwechsel, HUD-Ereignisse (Gold fliegt in die Kasse) | `ui/main_menu/`, `ui/hud/`, `art/ui/theme.tres` | `player-dev` (Freigabe `ui/main_menu/**`) | GUT `test_main_menu`, Screenshots, Touch-Lauf im Browser | HUD nur für den lokalen Spieler |
| LK6 | Dorf heller und lebendiger: wärmere Tagespalette, mehr Leben (Bewohner, Tiere, Blumen); braucht die Antwort auf D-174 OFFEN „Palette fürs Dorf heller?“ | `world/village/`, `tools/generate_village.py` | `village-dev` | GUT `test_village*`, Screenshots Tag und Abend | Dorf des Hosts sieht bei allen gleich aus (kein ungesteuerter Zufall) |
| LK7 | Moderne Musik: Weg festlegen (Komponist oder Werkzeug, D-174 OFFEN), dann Dorf, Biome und Bosse neu; Übergänge bleiben | `audio/music/`, `components/audio/`, `docs/AUDIO.md` | `fx-audio-dev` | GUT `test_music*`, Hörprobe durch das Projektmitglied | – |

**Reihenfolge:** LK0 zuerst; danach LK1 ‖ LK5 ‖ LK6 (getrennte Ordner); LK2, LK3, LK4 nacheinander (alle in `components/visual/`); LK7, sobald der Weg entschieden ist.

### Strang W – Wick, Begleiter, Kosmetik, Dorf-Deko, Dorf besuchen (D-175, D-176, D-179)

**Konzept:** [KONZEPT_BEGLEITER_KOSMETIK.md](KONZEPT_BEGLEITER_KOSMETIK.md) · **Grafik:** [SPRITES_V12.md](design/sprites/SPRITES_V12.md) · ersetzt das Paket K1 „Kosmetik (später)“ aus ROADMAP_AUSBAU.

| ID | Ziel | Dateien/Ordner | Agent | Prüfung | Koop-Check |
| --- | --- | --- | --- | --- | --- |
| WK0 | Entscheidungen aus dem Konzept §9: Name und Aussehen von Wick, Namenskonflikt mit der Spielfigur „Wick“, Rolle (Lichtquelle?), Pets mit Fähigkeiten, freispielbar oder kaufbar | `docs/DECISIONS.md` | Orchestrator mit dem Projektmitglied | D-Einträge | – |
| WK1 | Wick als Begleiter ab dem ersten Start: folgt, schwebt, reagiert (Freude, Angst, Licht-Puls), zeigt im Dorf den Weg; Platzhalter bis SPRITES_V12 | neu `companions/`; Haken `player/player.gd` (Begleiter am Spieler) | `player-dev` | GUT (neue `test_companion*`), smoke_test 47, Screenshots | ein Wick je Spieler als Kind des Spielers; Clients zeichnen ihn aus der Spielerposition, kein eigenes Netzpaket |
| WK2 | Kosmetik-System: Teile je Platz (Spielfigur: Kopf, Rücken, Lichtfarbe; Wick: Hut, Flammenfarbe), Besitz, Anprobieren am Spiegel, Übertragung im Profil | `characters/`, neu `cosmetics/`; Plattform-Vertrag `PlayerAppearance` in `packages/contracts` zuerst | `player-dev` (Freigabe `characters/**`), Vertrag `api-dev` | GUT (neue `test_cosmetic*`), Profil-Test gegen die lokale API | Kosmetik kommt über das Profil (`PATCH /me`, P-034), nie über Spielpakete; nur Optik |
| WK3 | Huhn als Neben-Maskottchen: Gags mit Wick im Dorf, seltene Auftritte im Dungeon | `world/village/`, Haken für Dungeon-Auftritte (Integrator) | `village-dev` | GUT `test_village*`, Screenshots | Auftritte im Dungeon nur über den Dungeon-RNG |
| WK4 | Pets: weitere Begleiter auf dem Gerüst aus WK1, freischaltbar | `companions/`, `cosmetics/` | `player-dev` | GUT `test_companion*` | wie WK1; im Dungeon nur Wick (Vorschlag, Lesbarkeit bei 4 Spielern) |
| WK5 | Dorf-Deko: Deko kaufen (Gold), setzen, drehen, wegräumen; je Welt gespeichert | `world/village/`, `meta/`, `autoload/save_manager.gd` (Eigentümer `village-dev`) | `village-dev` | GUT `test_save*`, `test_village*`, Spielstand-Migration | Koop-Gäste sehen das Dorf des Hosts mit seiner Deko |
| WK6 | Dorf besuchen: Dorf-Schnappschuss auf dem Server, Freunde und Gilde schauen es an (nur ansehen) | Plattform: `packages/contracts`, `packages/db`, `apps/api`; Spiel: `online/`, `world/village/` | `api-dev`, danach `village-dev` | Plattform `bun run check`, `typecheck`, `test`; GUT; Live-Test gegen die lokale API | Besuch ohne Besitzer ist eine Einzelspieler-Ansicht; gemeinsam geht es über einen Koop-Raum |

**Reihenfolge:** WK0 → WK1 → WK2 (braucht den Vertrag) → WK3 ‖ WK4 ‖ WK5 → WK6 (braucht Konten und Gilden, MP8). Kaufbare Kosmetik erst mit CP6. Zum Release gehören WK1 und WK6 (D-179), WK0, WK2 und WK5 nach der Lesart im Release-Tor.

## Phase 5 – Pakete Party-Modus

Regeln und offene Fragen: [KONZEPT_PARTY_MODUS.md](KONZEPT_PARTY_MODUS.md). Beginnt nach Phase 4 und kommt nach dem Release (D-179); PA0 darf früher fallen.

| ID | Ziel | Dateien/Ordner | Agent | Prüfung | Koop-Check |
| --- | --- | --- | --- | --- | --- |
| PA0 | Entscheidungen aus dem Konzept §8 (Runden, Wertung, Belohnung, Teams, online oder lokal) | `docs/DECISIONS.md` | Orchestrator mit dem Projektmitglied | D-Einträge | – |
| PA1 | Party-Rahmen: Modus „Party“, Lobby wie im Koop (Raumcode, Link), Rundenablauf, Punktestand, Siegerbild | neu `party/`, `ui/menus/party/`; Haken in `online/` und `scenes/world_controller.gd` (Integrator) | `player-dev` (Freigabe `online/**`) | GUT, `tools/mp_local_sim.gd` mit Bots, Netz-Smoke über den lokalen Relay | Host rechnet die Wertung, Clients zeigen sie; keine globale Pause |
| PA2 | Drei erste Wettkampf-Minispiele aus den vorhandenen (Vorschlag: Seelen sammeln, Einsturz, Prüfungs-Rennen) | `dungeon/modes/*` (eigene Party-Regeln je Modus), Party-Pläne in `dungeon/rooms/plans/` | `rooms-dev` | GUT, Party-Runde im Smoke-Test | Party-Regeln getrennt von den Abstieg-Regeln, die unverändert bleiben |
| PA3 | Weitere Minispiele, Clip-Moment am Ende (KI9), Feinschliff nach Playtest | wie PA2, `party/` | `rooms-dev`, `player-dev` | wie PA1 und PA2 | wie PA1 und PA2 |

**Weiterlesen:** [PRODUKT.md](PRODUKT.md) · [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) · [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) · [DECISIONS.md](DECISIONS.md)
