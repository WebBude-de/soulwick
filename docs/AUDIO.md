# Audio – Musik, Geräuschkulissen, Übergänge

> **Stand:** 17.10.2026 · Entscheidungen: D-068, D-072, D-092, D-097, D-166, Klangrichtung D-174 in [DECISIONS.md](DECISIONS.md). Klangbeschreibungen für neue Effekte: [design/responses/09_audio.md](design/responses/09_audio.md). Wie es abläuft, steht im Code: `components/audio/music_rules.gd` (Dateiwahl, Blendkurven), `music_player.gd` (Übergänge, Zeiten als `TESTWERT`), `music_channel.gd` (ein Kanal mit mehreren Playern).

## Richtung

Chiptune-Wurzeln, aber modern produziert (Bässe, Hall, gemischte Instrumente), nicht nur Piepen (D-174). Die synthetischen Stücke und Effekte aus `tools/generate_*.py` sind **Platzhalter**; OFFEN ist, ob ein Komponist oder ein Werkzeug sie ersetzt.

## Erzeugen

- Effekte: `python tools/generate_audio.py` (`side` bzw. `village` als Argument erzeugt nur diesen Block, z. B. Boost-Feld bzw. Dorftiere; neue Klänge kommen ans Ende ihres Blocks, damit alle älteren bytegleich bleiben); Musik und Geräuschkulissen: `python tools/generate_music.py` (`--list` zeigt Tempo und Tonart, `--measure` Länge, Pegel und Loop-Naht; ein Wort als Argument erzeugt nur passende Stücke, z. B. `crypt`).
- Danach `godot --headless --audio-driver Dummy --path . --import`.
- Ton liegt in Git LFS (`.gitattributes`).

## Dateien und wann sie laufen

| Datei | Wann |
| --- | --- |
| `audio/music/village.wav` | Dorf und Hauptmenü |
| `audio/music/dungeon_<biom>.wav` | normale Räume und Spezialräume des Bioms (`crypt`, `slime_grotto`, `shadow_realm`, `ember_forge`) |
| `audio/music/dungeon_<biom>_intense.wav` | Champion-Räume (gleiches Stück mit mehr Trommeln, blendet an derselben Stelle über) |
| `audio/music/boss_<boss>.wav`, `boss_<boss>_p2.wav` | Bossraum, `_p2` ab Phase 2 (`bone_king`, `slime_queen`, `shadow_lord`, `ember_golem`) |
| `audio/music/dungeon.wav`, `boss.wav` | Rückfall, wenn eine Biom- oder Bossdatei fehlt |
| `audio/ambient/ambient_<biom>.wav`, `ambient_village.wav` | leise Geräuschkulisse unter der Musik |
| `audio/music/transition_<biom>.wav` | einmaliger Übergang beim Betreten eines Bioms (auch Dorf → Krypta) |
| `audio/music/victory_<boss>.wav` | einmaliger Abschluss nach dem Bosssieg; danach nur Geräuschkulisse bis zum nächsten Biom |

Die Zuordnung je Biom steht in `dungeon/biomes/<biom>.tres` (`music_track`, `boss_music_track`, `ambient_track`, `transition_track`, `victory_track`; leer = Rückfall bzw. nichts).

## Regeln

- **Eigene Dateien ersetzen die erzeugten:** gleicher Name, `.ogg` und `.mp3` haben Vorrang vor `.wav`. Loops werden als ganze Datei geloopt, `transition_*` und `victory_*` einmal gespielt.
- **Übergänge enden auf einem Taktstrich:** Die letzten **1,5 s** eines Übergangs sind Nachhall (`MusicRules.STINGER_TAIL`); dort beginnt Takt 1 des Biom-Loops.
- **Nie zwei verschiedene Loops gegeneinander blenden:** alte Musik aus, Übergang, dann der neue Loop. Überblendungen sind „equal power“; Biom-Stück ↔ Champion-Fassung an derselben Taktstelle.
- **Kein Neustart bei wiederholten Wünschen:** Läuft das gewünschte Stück schon, spielt es weiter; Absenken ist eine Blende (D-166).
- Bosssieg: kein Zurückspringen auf das alte Biom-Stück; das Lagerfeuer ist der musikalische Übergang ins nächste Biom (`MusicPlayer.begin_interlude`).
- Zwischen Hauptmenü und Spiel spielt die Musik weiter statt neu anzufangen.
- **Busse:** Musik und Geräuschkulisse über `Music`, Effekte über `SFX`, alles über `Master`. Gleiche Lautheit wie `dungeon.wav`; Übergänge etwas, Siegesstücke mehr und Geräuschkulissen deutlich leiser.
- Agenten und Werkzeuge starten Godot immer ohne Ton (`--audio-driver Dummy`, AGENTS.md §7).
