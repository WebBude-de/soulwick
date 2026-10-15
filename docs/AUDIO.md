# Audio – Musik, Geräuschkulissen, Übergänge

> **Stand:** 15.10.2026 (aus der README hierher verschoben) · Entscheidungen: D-068, D-072, D-092, D-097 in [DECISIONS.md](DECISIONS.md). Soundeffekte erzeugt `python tools/generate_audio.py`; Klangbeschreibungen für neue Effekte: [design/claude_design_antwort/09_audio.md](design/claude_design_antwort/09_audio.md).

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
