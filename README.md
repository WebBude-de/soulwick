# Soulwick (Godot 4.7.2)

**Soulwick** – 2D-Top-down-Dungeon-Roguelite: das letzte Licht im endlosen Dunkel. Zusammenarbeit mit KI-Agenten: [AGENTS.md](AGENTS.md). Server, Website und Admin-Panel: Nachbar-Repo `../soulwick-platform` (D-093). Anforderungen und Regeln: [docs/PRD.md](docs/PRD.md) · Architektur: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · Entscheidungen: [docs/DECISIONS.md](docs/DECISIONS.md) · Plan und Stand: [docs/ROADMAP.md](docs/ROADMAP.md) (Vision: [Multiplayer](docs/ROADMAP_MULTIPLAYER.md), [Ausbau](docs/ROADMAP_AUSBAU.md), [KI-Boss](docs/ROADMAP_KI_BOSS.md)) · Grafiken: [docs/SPRITES.md](docs/SPRITES.md)

## Starten

1. **Godot 4.7.2 stable, Standard-Version** (nicht .NET) von <https://godotengine.org/download/windows/> laden und entpacken ([D-051](docs/DECISIONS.md)).
2. Godot starten → *Importieren* → `project.godot` in diesem Ordner wählen.
3. **F5** startet das Spiel: Hauptmenü → Dorf → mit **E** am Dungeon-Eingang einen Run beginnen.

## Steuerung

| Taste | Aktion |
| --- | --- |
| WASD | Bewegen |
| Maus | Zielen |
| Linke Maustaste (halten) | Angreifen |
| Space | Dash |
| Q | Waffe wechseln |
| E | Benutzen (Eingang, Brunnen, Shop, Podest, Altar, Portal) |
| Tab | Upgrade-Übersicht |
| Esc | Pause / Dialog schließen |

## Ablauf eines Runs

Endloser Dungeon in Fünf-Raum-Zyklen: Kampf · Kampf · Kampf + Upgrade-Wahl · Spezialraum (Shop, Waffe, Brunnen oder Altar, 30 % mit Exit-Portal) · Champion. Alle 15 Räume ein Boss (Knochenkönig, Schleimkönigin, Schattenlord, Glutgolem, danach stärker von vorn) und ein neues Biom; nach jedem Boss erscheint ein Exit-Portal. Tod oder Abbruch bringt 50 % des Run-Goldes ins Dorf (aufgerundet), das Portal 100 %. Im Dorf: Schmiede (dauerhafte Verbesserungen), Handelsposten (Proviant gegen Seelenkristalle), Chronik, Gilde.

Der Dungeon ist dunkel: Du siehst nur einen Lichtkreis um dich, Fackeln, Geschosse und Münzen leuchten. Achte auf Skelette (Schildstoß betäubt), Schattenwesen (blenden), Bomber (explodieren), leuchtende Elite-Gegner, Stachelfallen und zerschlagbare Kisten.

## Prüfen

| Was | Befehl (im Projektordner, `godot` = Pfad zur Godot-EXE) |
| --- | --- |
| Unit-Tests (GUT 9.7.1) | `godot --headless -s addons/gut/gut_cmdln.gd` |
| Alle Dateien laden | `godot --headless -s tools/validate_project.gd` |
| Durchlauf über N Räume | `godot --headless --fixed-fps 60 -s tools/smoke_test.gd -- 20` |
| Echte Kämpfe mit Upgrades | `godot --headless -s tools/combat_sim.gd` |
| Bosse, neue Gegner, Elites | `godot --headless --fixed-fps 60 -s tools/boss_sim.gd` |
| Screenshots (öffnet ein Fenster) | `godot -s tools/screenshots.gd -- <ordner>` |

Im Editor laufen die Unit-Tests auch über das Panel *GUT* → *Run All*.

## Inhalte anpassen

- **Balance:** Waffen `weapons/data/*.tres`, Gegner `enemies/data/*.tres`, Upgrades `upgrades/data/*.tres`, Preise und Gold `economy/data/economy_config.tres`. Werte mit **PLATZHALTER** sind noch nicht im Team abgestimmt ([D-055](docs/DECISIONS.md) ff.).
- **Räume:** `dungeon/rooms/**.tscn` sind normale Szenen (Größe, Türen, Säulen am Node `Tiles`; 5–14 `Marker2D` unter `SpawnPoints` je Kampfvorlage, S ≥ 5, M ≥ 8, L ≥ 12, D-086; Art und Größe am Root als `room_kind`, `room_size_class`). Neu erzeugen: `python tools/generate_room_templates.py`.
- **TileSets** aus den Tileset-PNGs neu bauen: `godot --headless -s tools/build_tilesets.gd`.
- **Audio:** Soundeffekte `python tools/generate_audio.py`, Musik `python tools/generate_music.py`. Eigene Dateien gleichen Namens in `audio/sfx/` bzw. `audio/music/` ersetzen die erzeugten. Details siehe [Audio](#audio).
- **Mauszeiger:** `python tools/generate_cursors.py` (oder eigene `art/ui/cursor_*.png`).

## Audio

Musik und Geräuschkulissen erzeugt `python tools/generate_music.py` (reines Python, ca. 55 s auf allen Kernen; `--list` zeigt Tempo/Tonart, `--measure` Länge, Pegel und Loop-Naht der Dateien, ein Wort als Argument erzeugt nur passende Stücke, z. B. `python tools/generate_music.py crypt`). Danach `godot --headless --path . --import`.

| Datei | Wann sie läuft |
| --- | --- |
| `audio/music/village.wav` | Dorf und Hauptmenü |
| `audio/music/dungeon_<biom>.wav` | normale Räume und Spezialräume des Bioms (`crypt`, `slime_grotto`, `shadow_realm`, `ember_forge`) |
| `audio/music/dungeon_<biom>_intense.wav` | Champion-Räume (gleiches Stück mit mehr Trommeln, blendet an derselben Stelle über) |
| `audio/music/boss_<boss>.wav`, `boss_<boss>_p2.wav` | Bossraum (`bone_king`, `slime_queen`, `shadow_lord`, `ember_golem`), `_p2` ab Bossphase 2 |
| `audio/music/dungeon.wav`, `boss.wav` | Rückfall, wenn eine Biom- oder Bossdatei fehlt |
| `audio/ambient/ambient_<biom>.wav`, `ambient_village.wav` | leise Geräuschkulisse unter der Musik (Tropfen, Wind, Blubbern, Flüstern, Glut, Vögel) |
| `audio/music/transition_<biom>.wav` | einmaliger Übergang (4–6 s plus 1,5 s Nachhall) beim Betreten eines Bioms, auch Dorf → Krypta; endet auf einem Taktstrich, dort setzt der Biom-Loop ein |
| `audio/music/victory_<boss>.wav` | einmaliger Abschluss (≈ 6 s, Kadenz bVI–bVII–I nach Dur) nach dem Bosssieg; danach nur Geräuschkulisse bis zum nächsten Biom |

- **Eigene Musik:** Datei mit gleichem Namen ablegen; `.ogg` und `.mp3` haben Vorrang vor der erzeugten `.wav`. Loops werden als ganze Datei geloopt, `transition_*`/`victory_*` einmal abgespielt. Bei eigenen Übergängen gilt: Die **letzten 1,5 s** sind Nachhall (`MusicRules.STINGER_TAIL`), dort beginnt Takt 1 des Biom-Loops – das Musikalische sollte also genau davor auf einem Taktstrich enden.
- **Zuordnung:** In `dungeon/biomes/<biom>.tres` stehen `music_track`, `boss_music_track`, `ambient_track`, `transition_track` und `victory_track` (Dateiname ohne Endung; leer = Rückfall bzw. keine Geräuschkulisse/kein Stinger).
- **Übergänge** (D-097, Zeiten als TESTWERT in `music_player.gd`): Nie werden zwei verschiedene Loops gegeneinander geblendet; Überblendungen sind „equal power“ (sin/cos), Biom-Track ↔ Champion-Fassung linear an derselben Taktstelle.
  - *Dorf → Dungeon und Biom → Biom:* Geräuschkulisse blendet in 4 s über, alte Musik in 1,8 s aus, dann der Übergangs-Stinger, danach setzt der Loop auf Takt 1 mit halber Lautstärke ein und schwillt in 3,5 s an.
  - *Bosssieg:* Bossmusik in 1,5 s aus, nach 1 s (hinter dem „Raum geschafft“-Klang) der Sieges-Stinger, dann nur die Geräuschkulisse – kein Zurückspringen auf den alten Biom-Track.
  - *Boss-Intro:* Biom-Musik blendet in 2 s aus, die Bossmusik setzt mit dem Brüllen ein (Signale `ending`/`finished` des Intros). Sicherung: 30 s (pausierbar); läuft das Intro dann noch, wird alle 5 s erneut geprüft, höchstens 120 s.
  - *Run-Ende:* Musik blendet unter der Zusammenfassung in 3 s aus, die Geräuschkulisse bleibt; im Dorf kommt zuerst die Dorf-Kulisse, nach 1,5 s blendet die Dorfmusik in 4 s ein.
  - *Zwischenraum (später Lagerfeuer, A6):* `MusicPlayer.begin_interlude(next_biome)` lässt die Musik ausklingen und blendet schon die neue Geräuschkulisse ein; der nächste Raum startet mit Stinger und Loop.
  - *Hauptmenü ↔ Spiel:* Der Musik-Player der alten Szene übergibt Stück und Position, der neue spielt weiter statt neu anzufangen (und blendet ggf. in 2,5 s zum eigenen Stück über).
- **Lautstärke:** Musik und Geräuschkulisse laufen über den Bus `Music` (Regler „Musik“ im Pausemenü), Effekte über `SFX`. Die Stücke sind auf die gleiche Lautheit wie `dungeon.wav` abgestimmt, die Übergangs-Stinger 1 dB, die Sieges-Stinger 2 dB und die Geräuschkulissen ca. 15 dB leiser.
- **Logik:** `components/audio/music_rules.gd` wählt die Datei und formt die Blendkurven, `music_player.gd` steuert die Übergänge (Raum, Biom, Champion, Bossphase 2, Boss-Intro, Bosssieg, Run-Ende), `music_channel.gd` blendet je Kanal (Musik, Geräuschkulisse, Stinger) mit drei Playern, sodass auch eine unterbrochene Überblendung nie schneidet.

## Konventionen

Code und Kommentare Englisch, Doku Deutsch; `snake_case` für Dateien, Variablen, Methoden; `PascalCase` für Klassen. Details: [docs/TECHSTACK.md](docs/TECHSTACK.md).
