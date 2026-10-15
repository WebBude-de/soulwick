# ROADMAP – Meilensteine und Definition of Done

> **Stand der Informationen:** 13.10.2026, Repository-Angaben aktualisiert am 15.10.2026 · **Planquelle:** Überarbeitetes GDD Master 1.0, Kapitel 15–16.  
> **Einordnung:** MVP und Endlos-Ausbau, fast fertig. Die laufende Arbeit steht in [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md); Überblick aller Roadmaps: [README.md](README.md).  
> **Wichtig:** Abgehakt = lokal umgesetzt und automatisch geprüft (13.10.2026). Teamabnahme im echten Repository steht noch aus. Der von ChatGPT erstellte Testprototyp zählt ausdrücklich **nicht** als Fortschritt des echten Teamprojekts.

## 1. Aktueller Stand – nur verifizierte Fakten

| Bereich | Status | Begründung / nächster Schritt |
| --- | --- | --- |
| Zielbild / Anforderungen | **Dokumentiert** | GDD Master 1.0 vom 10.10.2026 ist konsolidierte, verbindliche Basis. |
| Architekturprinzipien | **Dokumentiert** | Godot 4, vier Kern-Autoloads, Zuständigkeiten, Drei-Raum-Streaming und Schnittstellenregeln beschlossen. |
| Team-Repository | **Vorhanden** | Privates GitHub-Repo `WebBude-de/soulwick` (ersetzt das ursprünglich geplante GitLab); Branch `dev` lokal angelegt, erster Push steht an (15.10.2026). |
| Godot-Grundprojekt im echten Repo | **Nicht verifiziert** | Ein leeres Godot-Projekt auf `dev` war als nächster Schritt vorgesehen. Aktueller Commit-/Buildstand ist hier nicht einsehbar. |
| Gameplay-Systeme im echten Repo | **Nicht verifiziert** | Keine Implementierung wird allein wegen des GDD oder eines ChatGPT-Prototyps als fertig betrachtet. |
| Tests / spielbarer MVP | **Nicht verifiziert** | Build, automatische Tests und Spielbarkeit müssen im echten Teamprojekt geprüft werden. |
| Economy-/Dorf-Balance | **OFFEN** | Bewusst später im Team zu entscheiden; keine erfundenen Preise/Gold-Drops. |
| Lokales Godot-Projekt (`soulwick/`) | **Implementiert, lokal automatisch getestet** (13.10.2026) | M0–M6 umgesetzt, in Godot 4.7.2 geprüft. Noch **nicht im Team-Repo**, Teamabnahme offen. Nächster Schritt: Push nach GitHub, Pull Request nach `dev`, Review. |
| Economy-/Boss-Werte | **PLATZHALTER** | Spielbare Vorschläge D-055 … D-061, zentral änderbar; Teamentscheidung ausstehend. |

### Lokaler Prüfstand (13.10.2026, Godot 4.7.2)

| Prüfung | Befehl | Ergebnis |
| --- | --- | --- |
| Alle Skripte/Szenen/Ressourcen laden | `godot --headless -s tools/validate_project.gd` | 0 Fehler |
| Unit-Tests (GUT) | `godot --headless -s addons/gut/gut_cmdln.gd` | 153/153 bestanden |
| Durchlauf Dorf → 47 Räume → Tod → Dorf | `godot --headless --fixed-fps 60 -s tools/smoke_test.gd -- 47` | bestanden |
| Echte Kämpfe mit allen Waffen + Upgrades | `godot --headless -s tools/combat_sim.gd` | bestanden |
| Bosse, neue Gegner, Elites mit echter KI | `godot --headless --fixed-fps 60 -s tools/boss_sim.gd` | bestanden |
| Balance-Bot (ganze Runs) | `godot --headless --fixed-fps 60 -s tools/balance_sim.gd -- runs=3 policy=sword` | siehe D-089 |

Der Smoke-Test prüft u. a.: Fünf-Raum-Zyklus, Bosse 15/30/45, nie mehr als 3 Rauminstanzen, Encounter erst beim Betreten und genau einmal, 1–3 bzw. ab Raum 26 2–3 Gegner, Ausgang erst nach Abschluss, Upgrade-Wahl in Raum 3, Raum-45-Entscheidung, gleiche Spielerinstanz im Dungeon, neue Instanz bei Weltwechsel, 50-%-Auszahlung genau einmal, Speichern auf Platte, keine hängenden Pausengründe.

### Umgesetzt je Meilenstein (lokal, Teamabnahme offen)

| Meilenstein | Umsetzung |
| --- | --- |
| M0 | `project.godot` (Input-Map, Physik-Layer, Autoloads), vier Autoloads, `main.tscn` → `game.tscn`, GUT 9.7.1, Prüfskripte in `tools/` |
| M1 | `DamageProcessor` (0,5-Rundung, Schild vor HP), Hit-IDs, Dash-/Treffer-I-Frames, Spieler und drei Gegnertypen mit Sprites, Telegraph, HP-Leiste, Rückstoß, Schadenszahlen |
| M2 | `DungeonManager` (Streaming, max. 3 Räume), `RoomController`, `EnemySpawner`, `RoomSequence`, 6 Raumvorlagen, Türen, Miniboss, Platzhalter-Boss |
| M3 | Drei Waffen, 15 Upgrades als `.tres`, `UpgradeManager` (OR/AND-Tags, Limits, Angebote), Doppelschuss, Durchschlag, Abprall, Explosion, ON_KILL |
| M4 | Shop, Waffenpodest, Brunnen, Altar, Exit-Portal (30 %), Gold-Drops, atomare Käufe, Run-Ende 50/100 % |
| M5 | Dorf mit Dungeon-Eingang, Weltwechsel, `SaveManager` (ConfigFile, Version, Validierung) |
| M6 | HUD (Herzen in Viertelschritten, Schild, Gold, Raum, Waffen mit effektiven Werten, Dash), Esc-Pause, Tab-Übersicht, alle Menüs pausieren die Simulation |

**Statusvokabular:** `Dokumentiert` = fachlich beschlossen, `Offen` = noch zu entscheiden, `Nicht verifiziert` = tatsächliche Umsetzung unbekannt, `In Arbeit` und `Abgenommen` erst **nach** Prüfung im Team vergeben. Für neue Stände Commit/MR-Link und Prüfer ergänzen.

## 2. Meilensteine in beschlossener Umsetzungsreihenfolge

### M0 – Repositorium und technisches Fundament

**Ziel:** Ein gemeinsames, startbares Godot-Grundprojekt, nachvollziehbare Aufgabenverteilung und verlässlicher Git-Workflow (GitHub).

- [x] Godot-4-Minor-/Patchversion im Team festlegen und dokumentieren. *(4.7.2, D-051)*
- [x] Test-Framework installieren und Headless-Lauf prüfen. *(GUT 9.7.1, D-052)*
- [ ] Tatsächliches `dev`-Projekt mit `project.godot`, Startszene und vereinbarter Ordnerhierarchie prüfen. *(offen: Projekt liegt erst lokal)*
- [ ] Haupt-Branch und `dev` schützen; Review durch mindestens eine andere Person sicherstellen. *(offen: Branch-Schutz auf GitHub)*
- [x] `.godot/` ignorieren, Quellen-Assets/`.tscn`/`.tres`/`.uid` versionieren.
- [x] Vier Autoloads (`GameManager`, `RunManager`, `SaveManager`, `EventBus`) als definierte Verträge anlegen.
- [x] Typisierte Definitions-Resources, fachlichen Event-/Signalfluss und Fehlerkonventionen spezifizieren.

**Fertig, wenn:** Frischer Clone des echten Repositories in der vereinbarten Engine-Version ohne Parse-/Importfehler startet, vier Verantwortlichkeiten getrennt sind und ein Test-Pull-Request mit Review regulär nach `dev` gelangt.

### M1 – Spieler, Gegner und zentraler Kampfpfad

**Ziel:** Reproduzierbarer Kampf ohne noch unbestimmte Economy.

- [x] Spieler mit normalisiertem WASD, 360°-Mauszielrichtung, normalem Angriff und Dash.
- [x] 6 HP (drei Herzen), Schild, Health/Hurtbox/Hitbox, Schadenszahlen und Rückstoß.
- [x] `DamageProcessor`: Hit-ID-Prüfung; einheitlicher Spieler-/Gegnerschaden; **einmalige 0,5er-Rundung**; zuerst Schild, dann HP.
- [x] Treffer-I-Frames (0,5 s ab echtem Schild-/HP-Treffer) und separate Dash-I-Frames.
- [x] Slime, Skeleton und Archer mit Basis-KI, klarer Angriffsankündigung, Gegnerkollision und sichtbaren HP-Leisten.
- [x] **Neu:** Gemeinsames Projektil-Grundsystem (Archer braucht es in M1; Bogen/Stab bauen in M3 darauf auf, inkl. Trefferhistorie je Projektil).
- [x] **Neu:** Basiswerte für Gegner und Spielertempo als TESTWERTE bestätigen *(D-064)*
- [x] **Neu:** Debug-HUD (HP/Schild/Waffe als Text) und Kampf-Testarena, damit M1 ohne Dungeon manuell prüfbar ist; das finale HUD bleibt in M6. *(inzwischen durch das finale HUD ersetzt; Testarena: `tests/manual/combat_sandbox.tscn`)*
- [x] Automatisierte Schadens- und Unverwundbarkeitstests.

**Fertig, wenn:** Gleiche Angriffsinstanz ein Ziel nicht mehrfach trifft; Dash und Treffer-I-Frames korrekt überlappen; Blockierungen folgenlos bleiben; normale Gegner keine allgemeinen Treffer-I-Frames erhalten; Testfälle mit HP und Schild reproduzierbar passen.

### M2 – Dungeon, Raumfolge, Streaming und Enemy-Spawning

**Ziel:** Durchgehende, nahtlose Raumprogression im GDD-Zyklus.

- [x] `dungeon.tscn`, `room_base.tscn`, RoomController und DungeonManager verbinden.
- [x] Fünf-Raum-Zyklus: normal, normal, normal + Upgrade nach Kampf, Spezial, Miniboss; Bosse auf 15/30/45 ersetzen Miniboss.
- [x] Drei-Raum-Fenster: `N−1`, `N`, `N+1`; entfernten Raum **vollständig freigeben, bevor** ein neuer instanziiert wird.
- [x] Genau fünf `Marker2D`-Punkte je Kampfraumvorlage; ohne Zurücklegen 1–3 bzw. ab Raum 25 2–3 Gegner spawnen.
- [x] Gewichte pro Spawn Slime 50 % / Skeleton 35 % / Archer 15 %.
- [x] Begegnung nur beim Betreten beginnen, höchstens einmal; Türen/Exit anhand Encounter-Status.
- [x] Boss/Miniboss separater Spawnpfad; keine Standardwelle im Spezialraum.
- [x] Skalierungsformeln und Raum-Streaming-Abnahmetests.
- [x] **Neu – Abhängigkeit zu M3:** Raum 3 meldet in M2 nur das Signal „Upgrade-Auswahl fällig“; das Auswahlmenü selbst kommt mit M3. Ebenso Spezialräume in M2 nur als leere Raumtypen, Inhalt in M4.

**Fertig, wenn:** Bei realen Wechseln **nie vier** Rauminstanzen existieren (auch nicht während `queue_free()`); gleicher Raum nicht doppelt spawnt; Raum 3 Upgrade **nach** Kampf anbietet; Raum 26 als erster normaler Raum nach der 25er-Schwelle 2–3 Gegner zieht; bei fehlenden Markern ein Fehler und **kein falscher Raumabschluss** erfolgt.

### M3 – Drei Waffen, 15 Upgrades und einheitliche Statistik

**Ziel:** Vollständiger, kombinierbarer MVP-Kampfpool.

- [x] Zwei Waffenslots, Q-Wechsel, Startschwert, Waffenersatz-Dialog, keine doppelten Typen.
- [x] Schwert (ein Hit je Schwung/Ziel), Bogen (Pfeile), Magierstab (genau **ein** Basis-AOE mit direktem Ziel).
- [x] Attack-Rate als Angriffe/s; Berechnung flacher und additiver Prozentboni über `StatCalculator`.
- [x] **Sieben Attribut-, fünf Mechanik- und drei Effekt-Upgrades** als `.tres`/typisierte Definitionen.
- [x] Tag-Matching per **OR**, erforderliche `required_tags` zusätzlich per **AND**.
- [x] Mechanik-Caps 3/1/1/3/3; numerische Upgrades wiederholbar; 3 unterschiedliche Angebote.
- [x] Doppelschuss, Durchschlag, Wandabprall, größere AOE, Explosion und `ON_KILL`-Belohnungen korrekt verketten.
- [x] Keine Sekundärrekursion; Magierstab höchstens eine zusätzliche Explosionsauslösung je primärem AOE.
- [x] Waffenvergleich verwendet dieselben effektiven Werte wie Angriffe.

**Fertig, wenn:** Die 15 definierten Upgrades vollständig testbar sind, ihre Auswahl- und Stackregeln eingehalten werden, Doppelprojektil-Historien getrennt bleiben und Sekundäreffekte keine neue Explosion auslösen, aber reguläre Kills/Heilung/Schild gewähren.

### M4 – Spezialräume, Shop und Run-Ende

**Ziel:** Entscheidungen im Run und korrekte, permanente Goldübertragung.

- [x] Shop, Waffenauswahl, einmaliger Brunnen (+3 HP), Extra-Upgrade als vier gleichgewichtete Spezialräume.
- [x] Unmittelbare Spezialraum-Duplikate verhindern; Angebote freiwillig.
- [x] Portal in 30 % der Spezialräume, Interaktion E und Exit-Bestätigung.
- [x] Shop maximal 2 Upgrades, 2 tatsächlich kaufbare unbesessene Waffen, 1 Heilung (+2 HP), 1 Schild (+4); nur gültige Angebote.
- [x] Käufe atomar; kein doppelter Run-Gold-Zustand.
- [x] Exit/Tod/Abbruch: 100 % / 50 % / 50 %; einmalige permanente Gutschrift.
- [x] Ab Raum 45 Entscheidung Exit oder Endlos-Fortsetzung im selben Run.
- [x] **VOR IMPLEMENTIERUNG KLÄREN:** Goldrundung bei 50 % und ungerader Menge, Gold-Drops, Shoppreise/-skalierung, Reihenfolge Portalchance/Typwahl. *(entschieden: D-062, D-064; Portal-Reihenfolge als Vorschlag D-058)*
- [x] Transaktions- und Abschluss-Tests automatisieren.

**Fertig, wenn:** Kein ungültiges Angebot erscheint, Abbuchung und Lieferung unteilbar sind, jeder Run genau einmal ausgezahlt wird und weder künstliche Preise noch eine unbegründete Rundung als verbindliche Regeln in den Code gelangen.

### M5 – Dorf, Weltenwechsel und permanentes Speichern

**Ziel:** Vollständiger Start-/Rückkehr-Loop und zuverlässige Permanenz.

- [x] `village.tscn` mit DungeonEntrance (`Area2D`/E) und relevanten Spawnpunkten.
- [x] `game.tscn` tauscht Dorf/Dungeon als aktive Welt aus.
- [x] Player wird bei Dorf ↔ Dungeon neu erzeugt; innerhalb eines Dungeons bleibt Player erhalten.
- [x] SaveManager mit Versionierung, Validierung und kontrollierter Behandlung defekter/fehlender Dateien.
- [x] Nur permanentes Gold/Freischaltungen speichern; keine Run-Wiederaufnahme nach Neustart.
- [x] Dorf-/Meta-Funktionsumfang und Preise **erst nach Teambeschluss** erweitern. *(eingehalten: Dorf ohne Meta-Funktionen)*
- [x] Tests: Neustart, Save-Fehler, Duplikatgutschrift, Run-Verlust.

**Fertig, wenn:** Start im Dorf, Dungeon-Eintritt, Tod/Exit, dauerhafte Goldübertragung und Neustart reproduzierbar funktionieren und Run-Zustände nach Neustart nicht wiederhergestellt werden.

### M6 – HUD, Pause, Integration und MVP-Abnahme

**Ziel:** Spielbarer und getesteter MVP im echten Team-Repository.

- [x] Kompaktes Rand-HUD, drei Herzen/Viertelherzen, Schildsymbol/Zahl, Run-Gold und Waffenstatus.
- [x] Schadenszahlen über Gegnern, HP-/Schild-Unterscheidung, Trefferfeedback.
- [x] Alle Shop-/Waffen-/Upgrade-Menüs und Tab-Übersicht pausieren die Simulation; Esc-Pause ebenso.
- [x] Projektile, Physik und gameplayrelevante Timer sind während Pause eingefroren, Menüs bleiben bedienbar.
- [ ] Manuelle E2E-Durchläufe über Raumzyklus, Portal und Tod. *(automatisierter E2E-Lauf über 47 Räume ✓; manueller Durchlauf durch das Team offen)*
- [ ] Automatisierte Tests für Damage, Upgrades, Economy, Save; manuelle Tests für Streaming, Input, HUD/UI. *(automatisiert ✓ 73 Tests + 4 Simulationen; manuelle Tests offen)*
- [ ] Alle offenen MVP-blockierenden Entscheidungen umgesetzt und in `DECISIONS.md` begründet; verbleibende Nach-MVP-Arbeiten separat markieren. *(Blocker entschieden; nicht blockierende Restpunkte in Abschnitt 3)*
- [ ] Release via geprüftem Pull Request in den Haupt-Branch und Versions-Tag. *(offen: GitHub)*

**Fertig, wenn:** Eine Person aus dem Team das Projekt frisch klonen, starten, vom Dorf aus einen Run spielen und korrekte Rückkehr/Goldspeicherung nachweisen kann; definierte GDD-Abnahmetests bestehen; keine unbegründeten Wirtschaftsannahmen im Release stehen.

### M7 – Atmosphäre, Shader und Game Feel

**Ziel:** Das Spiel wirkt lebendig und bedrohlich.

- [x] Dungeon grundsätzlich abgedunkelt, Lichtkreis um den Spieler, Fackeln/Projektile/Explosionen leuchten (D-067).
- [x] Extra-dunkle Räume ab Raum 6; Blendung durch Schattenwesen.
- [x] Sprite-Shader: Treffer-Weißblitz, Auflösen beim Tod, Elite-Umriss.
- [x] Bildschirm-Shader: Schaden-Rand, pulsierende Low-HP-Vignette.
- [x] Screenshake mit Trauma-System, Hitstop, Partikel (Treffer, Tod, Zerbrechen), Zeitlupe beim Tod.
- [x] Banner „Raum geschafft!“/Boss-Titel; Dialoge erst nach Verzögerung (D-070).

### M8 – Audio

- [x] Soundeffekte für Waffen, Treffer, Tod, Dash, Gold, Heilung, Türen, Fallen, Stun, Blendung, UI.
- [x] Chiptune-Musik: Dorf, Dungeon, Boss; Überblendung beim Wechsel. *(neu komponiert, D-072)*
- [x] Audio-Busse `Music`/`SFX`, Lautstärkeregler im Pausemenü.
- [x] **Neu:** Eigener Mauszeiger (Fadenkreuz im Spiel, Pfeil in Menüs, D-071).
- [x] **Neu:** Spezialräume hell, Lichtkreise in Pixel-Optik (D-067).

### M9 – Erweitertes Gameplay

- [x] Skelett-Schildstoß mit Stun 0,8 s (D-066).
- [x] Schattenwesen (blendet) und Bomber (explodiert) (D-069).
- [x] Elite-Gegner: Schnell, Gepanzert, Explosiv.
- [x] Stachelfallen und zerstörbare Kisten/Fässer mit Gold/Herz.
- [x] Drei Bosse: Knochenkönig, Schleimkönigin, Schattenlord (D-065).

### M10 – Balance und Abschluss

- [x] Rundung aufrunden (D-062), Endlos ohne Abschwächung (D-063), Werte als TESTWERTE (D-064).
- [x] Automatisierte Tests und Smoke-Test für alle Erweiterungen.

### M11 – Endlos und Schwierigkeit (D-073 … D-077)

- [x] Immer endlos, Boss alle 15 Räume, Portal nach jedem Boss.
- [x] Neue Schwierigkeitskurve, Wellen, Schild-/Heilungs-Nerf, Champions.
- [x] Biome mit eigenen Gegner-Tabellen und Farbstimmung; neue Gegner Splitterschleim, Golem, Nekromant; 4. Boss Glutgolem.
- [x] Boss-Phasen, gefährlichere Champions, Biom-Gefahren (Agent „Gegner & Bosse“).
- [x] Balance mit Bot-Simulation messen und nachjustieren (Agent „Balance“).

### M12 – Lesbarkeit und Effekte

- [x] Gegner-Kennzeichen und Ersthinweise (D-079).
- [x] Kein Schwarz um die Räume, Schatten unter Figuren.
- [x] Post-Processing: Treffer-Farbversatz, Kippen bei Stun, Unschärfe bei Blendung, Low-HP-Entsättigung.

### M13 – Waffen

- [x] Spezialangriff (rechte Maustaste) je Waffe, Schwert-Combo.
- [x] Zwei neue Waffen (Dolche, Kriegshammer).

### M14 – Dorf und Meta-Progression (D-078)

- [x] Begehbare Gebäude mit stimmigen Proportionen.
- [x] Schmiede, Handelsposten (Seelenkristalle, Proviant), Chronik, Gilde (Multiplayer vorbereitet).

### M15 – Eigene Grafiken (Claude Design)

- [x] Grafiken laut [SPRITES_V2.md](design/sprites/SPRITES_V2.md) erzeugt und eingebaut (Gegner, Bosse, Kennzeichen, Biome, Dorf, Icons).
- [ ] Waffen-Grafiken aus SPRITES_V2 §8 (Dolche, Kriegshammer, Effekte). *(Hinweis 15.10.2026: laut D-099 und SPRITES_V3 §1 geliefert und eingebaut; Haken nach Prüfung setzen)*

### Weitere Roadmaps (nach dem MVP)

Diese Themen sind zu groß für einzelne Meilensteine und haben eigene Pläne. Anforderungen: [PRD.md](PRD.md) Abschnitt 7.

| Roadmap | Inhalt |
| --- | --- |
| [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) | **aktuell:** Phase 1 spielbar machen, Phase 2 Räume, 2b Räume v2 mit Minispielen, 2c Makeover |
| [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) | Phase 3: Schnelles Spiel, Testversion für Freunde, Skalierung, Gilden, Ranglisten, Server, Steam, Release |
| [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) | nach dem Multiplayer: Google Play, App Store, Crossplay |
| [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) | **Idee für später:** KI-generierte Wunschbosse („Traumweber“), Konzept in [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) |

**Reihenfolge (D-088, D-106):** zuerst ROADMAP_AUSBAU (Phasen 1, 2, 2b, 2c), danach ROADMAP_MULTIPLAYER (Phase 3, Crossplay schließt an) und ROADMAP_KI_BOSS (Phase 4). Neuer Code hält sich an die Multiplayer-Leitplanken (Koop-Check in ROADMAP_AUSBAU).

## 3. Offene Entscheidungen und Blocker (vor dem jeweiligen Feature klären)

| Priorität | Entscheidung | Spätestens vor | Aktueller Platzhalter |
| --- | --- | --- | --- |
| ✅ | Rundung der 50-%-Auszahlung bei ungeradem Restgold | – | **Entschieden: aufrunden (D-062)** |
| ✅ | Basis-Gold-Drops, Shoppreise und Preis-/Goldwachstum | – | **Entschieden: TESTWERTE (D-064)** |
| ✅ | Basiswerte Gegner (HP/Schaden/Tempo) und Spielertempo | – | **Entschieden: TESTWERTE (D-064)** |
| Hoch | Kleine Schildgewinne >50: Restwertführung oder einmalige Rundung | M1/M3 | Einmalige Rundung auf 0,5 (Formel aus §6) |
| Mittel | Portalziehung gegenüber Spezialraumwahl | M4 | Typ zuerst, Portal unabhängig (D-058) |
| ✅ | Bossdesign, besondere Bossfaktoren, Endlos-Skalierung ab Raum 46 | – | **Entschieden: drei Bosse (D-065), Endlos ohne Abschwächung (D-063)** |
| Mittel | Gleichzeitige ON_KILL-Auslöser im selben Frame | M3 | Jeder Kill einzeln, seriell |
| Mittel | Bounds/Feedback für Schadenszahlen, Knockback | M6 | Knockback-Werte in den `.tres` (PLATZHALTER) |
| Mittel | Finale Resource-Properties, Speicherformat und Migration | vor M5 | ConfigFile v1 (D-059), Migration noch keine |
| Mittel | Explosion „Explosiver Treffer“: Radius und Regel für Schwert/Pfeile | M3 | 48 px, eine pro Angriffsinstanz (D-056) |
| Teamtechnik | CI, Exportziel, Branch-Schutz auf GitHub | M0 / Release | – (CI und Exporte: ROADMAP_CROSSPLAY CP7) |

**Regel für Fortschrittsupdates:** Abgehakt am 13.10.2026 auf Basis der lokalen automatischen Prüfungen (Abschnitt 1); offene Punkte sind markiert. Nach dem Merge ins Team-Repo erneut prüfen. Neben jeder abgeschlossenen Teilaufgabe bei Bedarf **MR/Commit, Tester, Datum** notieren. Das GDD selbst ist **kein Nachweis einer Implementierung**.

**Weiterlesen:** [PRD.md](PRD.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [TECHSTACK.md](TECHSTACK.md) · [DECISIONS.md](DECISIONS.md)
