# DECISIONS – Verbindliche Projektentscheidungen

> **Stand:** 13.10.2026 · **Quelle:** Überarbeitetes GDD Master 1.0 (10.10.2026), einschließlich darin konsolidierter GDD 01–11 und bestätigter GitLab-Regeln.  
> **Zweck:** Getroffene Entscheidungen sichtbar halten. Nicht ohne neue Fakten, protokollierten Grund und Teamfreigabe erneut aufrollen.  
> **Abgrenzung:** Beschlüsse hier stammen **nicht** aus dem später verworfenen ChatGPT-Testprojekt.

## 1. Hierarchie, Status und Änderungsprozess

**Priorität bei Widersprüchen:**

1. Eine **spätere, ausdrücklich gemeinsam bestätigte** Änderung ersetzt ältere Varianten.
2. Sonst gilt das **überarbeitete GDD Master 1.0** als konsolidierte Referenz.
3. `TESTWERT` beschreibt einen balancierbaren Ausgangswert, keine unumstößliche Balance.
4. `OFFEN` darf nicht als implizit entschieden behandelt werden.
5. Implementierungsdetails des verworfenen Testprojekts begründen **keine** Entscheidung.

**Änderungsverfahren:** Betroffene Regel/ID benennen → Problem und neue Belege beschreiben → Folgen für Gameplay, Formeln, Tests und Datenmigration prüfen → Teamentscheidung dokumentieren → GDD/Dokumente aktualisieren → Umsetzung per Merge Request (mindestens ein Review). Keine stille Änderung am Designvertrag durch einzelne Codeänderungen.

## 2. Produkt und Dungeon

| ID | Status | Entscheidung | Grund / Konsequenz |
| --- | --- | --- | --- |
| D-001 | VERBINDLICH | Lokales **2D-Top-down-Dungeon-Roguelite** mit Dorf als Ausgangspunkt, direktem mausgesteuertem Kampf. | Klare Core Loop: Dorf → Run → Rückkehr; kein umfassendes Hub-/Metasystem im ersten MVP. |
| D-002 | VERBINDLICH | **Fünf-Raum-Zyklus:** 1 und 2 normal, **3 normal + Upgrade nach Kampf**, 4 Spezial, 5 Miniboss. | Upgrade ist Belohnung für abgeschlossenen Kampfraum, kein eigenständiger Raumtyp. |
| D-003 | VERBINDLICH | **15, 30, 45** sind Bossräume **anstelle** des regulären Minibosses. | Der Zyklus bleibt erhalten. |
| D-004 | VERBINDLICH | Nach Raum 45 **regulärer Exit oder Weiterspielen im selben Run**. | Freiwillige Risiko-/Belohnungsentscheidung; genaue Endlos-Balance OFFEN. |
| D-005 | VERBINDLICH | Spezialräume: **Shop, Waffe, Brunnen, Extra-Upgrade** gleichgewichtet; keine identischen Typen direkt hintereinander; optional nutzbar. | Variierende Angebote ohne Zwangskauf/-nutzung. |
| D-006 | VERBINDLICH | **30 %** Portalchance in Spezialräumen; Benutzung **E + Bestätigung**, regulärer Ausstieg. | Kontrollierter Exit vor Run-Ende; Ziehreihenfolge zur Spezialraumwahl OFFEN. |
| D-007 | VERBINDLICH | Vorgefertigte, editierbare `.tscn`-Räume; nahtloser Übergang mit **maximal drei gleichzeitig existierenden Rauminstanzen**. | Editorworkflow und begrenzter Laufzeitressourcenbedarf. `queue_free()` ist dabei nicht sofortige Freigabe. |
| D-008 | VERBINDLICH | Start eines Encounters **erst beim Betreten**, **genau einmal** pro Raum. Türen: Kampfraum-Eingang schließt, Ausgang öffnet nach Abschluss. | Kein mehrfaches Spawning durch wiederholte Trigger; kein Spawn durch bloßes Vorladen. |
| D-009 | VERBINDLICH | Fünf feste `Marker2D`-Spawnpunkte; zufällig **1–3** normale Gegner, ab Raum 25 **2–3**, Punkte ohne Zurücklegen. | Kein doppelter Spawn auf demselben Marker; Schwelle trifft normale Kampfräume (zuerst Raum 26) und nicht Raum 25 als Miniboss. |
| D-010 | VERBINDLICH | Gegnertypen pro Spawn unabhängig: **Slime 50 %, Skeleton 35 %, Archer 15 %**. | Verteilung ist statistisch, kein fixer Mix pro Raum. |
| D-011 | VERBINDLICH | Gegner pro abgeschlossenem Fünf-Raum-Block: **HP ×1,20**, **Schaden ×1,10**; Miniboss zusätzlich **je ×1,50**. | Reproduzierbare Schwierigkeit bis Raum 45; Boss-/Endlos-Sonderfaktoren OFFEN. |

## 3. Spieler und Kampf

| ID | Status | Entscheidung | Grund / Konsequenz |
| --- | --- | --- | --- |
| D-012 | VERBINDLICH | **WASD** normalisiert, **Maus** 360°-Zielrichtung, **linke Maustaste halten** für wiederholte Angriffe, **Space Dash**, **Q Waffenwechsel**, **E Interaktion**, **Tab Upgrade-Übersicht**, **Esc Pause**. | Konsistente direkte Steuerung. |
| D-013 | VERBINDLICH | **6 Start-HP = 3 Herzen**, Anzeige in **0,5-HP-Schritten**; +1 HP nach je fünf abgeschlossenen Räumen. | Abgestuftes Trefferfeedback und regelmäßige kleine Heilung. |
| D-014 | VERBINDLICH | Schild absorbiert **vor HP**, regeneriert nicht passiv, hat **keine harte Obergrenze**. Ab **50 Schild** wirken zusätzliche Schildgewinne nur noch zu 50 %. | Softcap statt hartem Limit. |
| D-015 | VERBINDLICH | Schild intern auf **0,5er-Schritten**; Behandlung sehr kleiner Schildgewinne über Softcap **OFFEN**. | Schwache Teilgewinne dürfen nicht versehentlich die Softcap-Regel aushebeln. |
| D-016 | VERBINDLICH | Dash unterbricht Angriffe und sperrt Angriffe während der Bewegung. Dash-I-Frames und Treffer-I-Frames sind **unabhängige Ursachen**. | Kein Schadensfenster durch fälschlich gemeinsam genutzte Schutz-Timer. |
| D-017 | VERBINDLICH | **Jeder tatsächlich wirksame Treffer auf Schild ODER HP** startet **0,5 s konfigurierbare Treffer-I-Frames**. Blockierter Hit: kein Schaden, keine schadensabhängigen Folgeeffekte. | Auch reiner Schildverlust schützt vor direkt anschließenden Treffern. Gleichzeitige Hits werden seriell behandelt. |
| D-018 | VERBINDLICH | Sowohl Spieler- **als auch Gegnerschaden** einmalig am Ende der Formel auf **0,5** runden; nicht blockierter, gültig schadenswirksamer Hit mindestens **0,5**. | Ein einheitlicher DamageProcessor; nicht mehr frühere ungerundete Gegnervariante. |
| D-019 | VERBINDLICH | Flache Boni addieren, Prozentboni addieren, situative Multiplikatoren multiplizieren; **keine** Rüstung, Krit-/Resistenztypen als MVP-System. | Vorhersagbare Balance und einfache zentrale Schadensberechnung. |
| D-020 | VERBINDLICH | **Hit-ID/Projektil-Trefferhistorie** verhindert mehrfaches Treffen durch dieselbe Angriffsinstanz; normale Gegner haben **keine allgemeinen I-Frames**. | Mehrere verschiedene Angriffe dürfen zeitnah treffen, derselbe nicht doppelt. |
| D-021 | VERBINDLICH | Gegner kollidieren, **kein Friendly Fire**; Angriffstelegraph, HP-Leiste, Rückstoß, kurze Todesanimation und Gold-Drop. | Nachvollziehbares Gegnerverhalten und Trefferfeedback. |

## 4. Waffen, Upgrades und Effekte

| ID | Status | Entscheidung | Grund / Konsequenz |
| --- | --- | --- | --- |
| D-022 | VERBINDLICH | Genau **zwei Waffenslots**, eine aktive Waffe; keine doppelten Typen; bei voller Belegung ist Slotersatz nötig. | Klar definierte Ausrüstung, kein separates Inventarsystem. |
| D-023 | VERBINDLICH | **Drei Startwaffentypen**: Schwert, Bogen, Magierstab; weitere Waffen erst nach MVP. | Begrenzter Implementierungsumfang und gemeinsame Waffenschnittstelle. |
| D-024 | VERBINDLICH | **Magierstab:** langsames, größeres Geschoss; beim Einschlag **ein einziger primärer AOE-Treffer** einschließlich direktem Ziel. | Direktschaden wird **nicht** zusätzlich zum Basis-AOE gerechnet. |
| D-025 | VERBINDLICH | **Attack-Rate** = Angriffe pro Sekunde; Prozentsätze additiv. | Konsistente Waffenwerte und DPS-Berechnung; kein Begriffswechsel zu „Attack Delay“. |
| D-026 | VERBINDLICH | MVP-Pool besteht aus **genau 15 Upgrades**: 7 Attribute, 5 Mechaniken, 3 Effekte (Liste in [PRD.md](PRD.md)). | Frühere Feuer-/Gift-/Zusatzvorschläge sind **nicht** im MVP. |
| D-027 | VERBINDLICH | Upgrades sind **runweit**, bleiben nach Waffenersatz erhalten und wirken auf kompatible Angriffe; Auswahl bis zu **3 unterschiedliche verfügbare** Angebote. | Keine Upgrades an einzelne Waffeninstanzen binden. |
| D-028 | VERBINDLICH | Tag-Anwendbarkeit mit **OR** (mindestens ein passender Tag), `required_tags` zusätzlich vollständig nötig. | Eindeutige Filterregel ohne implizites All-Tags-Erfordernis. |
| D-029 | VERBINDLICH | Numerische Upgrades mehrfach stapelbar; Mechanik-Stufenlimits: **Durchschlag 3**, **Wandabprall 1**, **Doppelschuss 1**, **Schwungwinkel 3**, **AOE-Radius 3**. | Stack-Grenzen bleiben reproduzierbar. |
| D-030 | VERBINDLICH | **Sekundäreffekte dürfen keine sekundären Effekte auslösen.** | Verhindert unbegrenzte Explosions-/Effektrekursion. |
| D-031 | VERBINDLICH | Eine Upgrade-Explosion darf das **Primärziel zusätzlich** treffen; primärer Magierstab-AOE löst **höchstens eine** Zusatzexplosion aus, auch bei mehreren Zielen. | Sekundärschaden ist getrennt vom primären Treffer, aber pro Primär-AOE begrenzt. |
| D-032 | VERBINDLICH | Kills durch Sekundäreffekte gewähren reguläre **ON_KILL**-Belohnungen (Heilung/Schild), ohne neue Sekundärkette. | Reguläre Kill-Belohnung unabhängig von der verursachenden Schadensquelle. |
| D-033 | VERBINDLICH | Doppelschuss-Projektile haben **separate** Trefferhistorien; Durchschlag und Abprall werden je Projektil geführt; Radiusboni sind **additiv**. | Einzelne Projektile und ihre Limits bleiben korrekt isoliert. |
| D-034 | VERBINDLICH | Effektive Werte in **Waffenvergleich und Angriff** werden durch denselben `StatCalculator` berechnet. | UI soll keine abweichenden Schadens-/Ratewerte zeigen. |
| D-035 | VERBINDLICH | Seltenheit als Datenfeld vorbereitet, **ohne Einfluss auf MVP-Spielwerte oder Shops**. | Zukunftsfähigkeit ohne zusätzliche Balance-Regel. |

### Beschlossene Testwerte (änderbar nach Messungen)

| Bereich | TESTWERTE |
| --- | --- |
| Schwert | Schaden **12**, Rate **1,5/s**, Reichweite **75 px**, Winkel **100°** |
| Bogen | Schaden **9**, Rate **1,2/s**, Reichweite **600 px**, Pfeiltempo **550 px/s** |
| Magierstab | Schaden **8**, Rate **0,8/s**, Reichweite **450 px**, Projektiltempo **300 px/s**, AOE **45 px** |
| Dash | Dauer **0,2 s**, Geschwindigkeit **450 px/s**, Cooldown **1,5 s** |
| Attribut-Upgrades | globaler Schaden +10 %, Nahkampf +2, Attack-Rate +15 %, Pfeilschaden +20 %, Magieschaden +20 %, Projektiltempo +20 %, Schildgewinn +10 |
| Mechanik-Upgrades | Durchschlag +1 Zusatzgegner, 1 Abprall, +1 Projektil, Schwungwinkel +20 % je Stufe, AOE-Radius +20 % je Stufe |
| Effekt-Upgrades | Explosiver Treffer 50 % Auslöseschaden, ON_KILL +2 HP/Stack, ON_KILL +2 Schild/Stack |

**Nicht neu diskutieren, sofern nicht die Balance-Messung Anlass gibt:** Zahlen sind bewusst *TESTWERTE*, die Mechanik- und Stackingregeln dagegen **VERBINDLICH**.

## 5. Economy, Permanenz, UI und Architektur

| ID | Status | Entscheidung | Grund / Konsequenz |
| --- | --- | --- | --- |
| D-036 | VERBINDLICH | Shop **max. 6 gültige Angebote**: 2 Upgrades, 2 kaufbare und noch nicht besessene Waffen, 1 Heilung (+2 HP), 1 Schild (+4). | Keine nicht kaufbaren Scheinangebote; kein Füllersatz. |
| D-037 | VERBINDLICH | Brunnen gewährt einmalig **+3 HP gratis** bis Max-HP. | Fest definierter Spezialraum-Nutzen. |
| D-038 | VERBINDLICH | **Atomare Käufe**; Run-Gold gehört ausschließlich `RunManager`, Preis-/Kaufregel `EconomySystem`. | Keine getrennten Goldkonten und keine halb fertigen Einkäufe. |
| D-039 | VERBINDLICH | **50 %** verbleibendes Run-Gold bei Tod/Abbruch, **100 %** bei regulärem Ausstieg; Auszahlung einmalig. | Risiko des Runs, aber nicht kompletter Verlust; Doppelgutschrift verboten. |
| D-040 | VERBINDLICH | Nur **permanenter** Fortschritt wird gespeichert, kein Save/Resume eines laufenden Runs. | Begrenzter MVP-Speicherumfang. |
| D-041 | VERBINDLICH | Dorf ↔ Dungeon: **neue Spielerinstanz**; Raum ↔ Raum im Dungeon: **dieselbe Instanz**. | Eindeutige Trennung zwischen Weltenwechsel und Raum-Streaming. |
| D-042 | VERBINDLICH | UI: kompaktes Rand-HUD; drei Herzen/0,5er-Schritte, Schildsymbol/-zahl, Schadenszahlen und effektive Waffenwerte. | Informationen sollen gut sichtbar und konsistent sein. |
| D-043 | VERBINDLICH | Shop-, Waffen-, Upgrade-Auswahl, Tab-Übersicht und Esc-Pause halten **gesamte Simulation inklusive Projektilen und Timern** an; UI bedienbar. | Keine versteckten Echtzeitvorteile oder Treffer während Menüs. |
| D-044 | VERBINDLICH | **Genau vier Kern-Autoloads** (`GameManager`, `RunManager`, `SaveManager`, `EventBus`); andere Manager lokal/szenenbezogen. | Zustandsklarheit; EventBus bleibt signal-only. |
| D-045 | VERBINDLICH | **Godot 4 + GDScript**, `.tscn`-Szenen, **typisierte `.tres`-Resources**, keine JSON-Gameplay-Definitionsdaten im MVP. | Wartbare, editorfreundliche Architektur. |
| D-046 | VERBINDLICH | Direkte typisierte Methoden für Reads/Aktionen, Signale **nach** erfolgreicher Änderung, EventBus nur für systemübergreifende Ereignisse. | Nachvollziehbarer Datenfluss und Testbarkeit. |
| D-047 | VERBINDLICH | **GitLab**: `master`/`dev` geschützt, Änderungen per MR, **mindestens ein fremdes Review**, `feature/*`, `fix/*`, `hotfix/*`, Conventional Commits. | Team-Integration mit überprüfbaren Änderungen. |
| D-048 | VERBINDLICH | Automatisierte Tests für Damage, Upgrades, Goldtransaktionen und Speicherung; manuelle Szenentests zusätzlich. | Regressionsschutz an den risikoreichsten Regeln. |
| D-049 | VERBINDLICH | Code-Namen und Kommentare Englisch; `snake_case` für Variablen/Methoden/Dateien, `PascalCase` für Klassen, `UPPER_SNAKE_CASE` für Konstanten. | Konsistente Teamkonventionen. |
| D-050 | VERBINDLICH | **Das ChatGPT-Testprojekt und Hotfixes sind keine Basis des realen Startprojekts.** | Nur GDD, frühere tatsächliche Teammaßnahmen und der reale Repository-Stand zählen. |

## 6. Rechenregeln, die nicht still geändert werden dürfen

**Schaden** (für Spieler und Gegner):

```text
D_raw = (D_base + sum(flat_bonus)) * (1 + sum(percent_bonus)) * product(context_multiplier)
D_hit = 0.5 * round(2 * max(0, D_raw))
```

Bei tatsächlich gültigem, nicht blockiertem Schaden **mindestens 0,5**; blockierter oder ausdrücklich nicht schädigender Hit = **0**. Rundung erst **einmal nach sämtlichen Modifikatoren**.

**Attack-Rate:**

```text
R_eff = (R_base + sum(flat_rate_bonus)) * (1 + sum(percent_rate_bonus))
cooldown_between_attacks = 1 / R_eff
single_target_DPS_approx = D_hit * R_eff
```

**Skalierung:**

```text
k(room) = floor((room - 1) / 5)
HP_enemy = HP_base * 1.20^k * (1.50 if miniboss else 1.00)
D_enemy_raw = D_base * 1.10^k * (1.50 if miniboss else 1.00)
```

**Schild-Softcap:**

```text
normal_gain = min(requested_gain, max(0, 50 - shield_old))
effective_gain = normal_gain + 0.5 * (requested_gain - normal_gain)
shield_new = shield_old + round_to_half(effective_gain)
```

Beispiel gemäß GDD: `45` Schild + angeforderte `20` → **57,5** Schild, nicht 65. Der Umgang mit kleinen Rundungsresten oberhalb 50 bleibt **OFFEN**.

**AOE-Radius:** `R_eff = R_base * (1 + sum(radius_percent_bonus))`; Beispiel Magierstab `45 * (1 + 3 * 0,20) = 72 px`.

**Goldtransfer:** `remaining_run_gold * 0,50` bzw. `* 1,00`, aber die **Ganzzahlrundung im 50-%-Fall ist noch OFFEN**. Weder Abrunden noch kaufmännisches Runden stillschweigend einsetzen.

## 7. Offene Entscheidungen – keine Beschlüsse vorwegnehmen

| Prio | Punkt | Folge / Entscheidungszeitpunkt |
| --- | --- | --- |
| Hoch | Wie ungerades Restgold bei 50 % gerundet wird | Vor Economy-Abschluss |
| Hoch | Gold-Drops, Preisstufen, Preis-/Goldwachstum und permanente Dorfkosten | Team-Balancing vor Shop-/Dorf-Release |
| Hoch | Kleine Schildgewinne oberhalb 50: Restwertkonto oder andere Rundungsstrategie | Vor Implementierung der Shield-Komponente |
| Mittel | Reihenfolge Portal-30-%-Ziehung vs. Spezialraum-Auswahl | Vor Room-Generator-Finalisierung |
| Mittel | Bossdesign, Bossfaktoren, Endlos-Skalierung ab Raum 46 | Bei Boss-/Endlos-Feature |
| Mittel | Gleichzeitige ON_KILL-Ursachen in einem Frame | Bei Damage-/Effekttests |
| Mittel | Exakte Trefferfeedback-Bounds, Knockback- und Animationsdetails | UI-/Combat-Polish |
| Mittel | Finale Resource-Felder, Save-Format, Versionierung und Migration | Vor betroffenem Code-Freeze |
| Mittel | Rückwärtsnavigation, Türkoordinaten und Raumfehler-Fallbacks | Bei Dungeon-Implementierung |
| Hoch | Basiswerte Gegner (HP/Schaden/Tempo) und Spielertempo als TESTWERTE (aktuell PLATZHALTER, D-055) | Vor M1-Abnahme |
| Technik | Export-/CI-Ziel (Godot-Version: D-051, Test-Runner: D-052) | Teamentscheidung vor jeweils betroffener Arbeit |
| Vision | Menüs/Pause im Multiplayer und Verbindungsabbruch (Vorschlag D-085) | Vor [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP3 |
| Vision | Details Gilden-Fortschritt (Vorschlag D-081) und Ranglisten-Wertung (Vorschlag D-082) | Vor MP8 / MP9 |
| Vision | Steam: Zeitpunkt, Steamworks-Konto, Rechte am Spiel, Lizenzen | Vor MP10 |
| Idee | KI-Wunschbosse „Traumweber“: ob und wann, echte Personen/Marken, Bild-Anbieter, Kontingent und Kosten ([KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) §11) | Vor [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) KI3 |

## 7a. Neue Entscheidungen ab 13.10.2026

### D-051 – Engine-Version Godot 4.7.2

- **Status:** VERBINDLICH
- **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied im Gespräch; Bestätigung per MR ausstehend
- **Kontext:** TECHSTACK verlangte eine gemeinsam fixierte Godot-Version vor Beginn der Integration.
- **Beschluss:** **Godot 4.7.2 stable, Standard-Build** (nicht .NET, da GDScript). `project.godot` trägt `config/features = "4.7"`.
- **Gründe / verworfene Alternativen:** Aktuelle stabile Version; .NET-Build unnötig ohne C#.
- **Folgen:** Alle Teammitglieder installieren genau diese Version. Upgrade nur per neuer Entscheidung.
- **Ersetzt:** Offenen Punkt „Gemeinsame Godot-Patchversion“ (§7).

### D-052 – Test-Framework GUT 9.7.1

- **Status:** VERBINDLICH
- **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied im Gespräch; Bestätigung per MR ausstehend
- **Kontext:** D-048 verlangt automatisierte Tests, ein Framework war nicht gewählt.
- **Beschluss:** **GUT 9.7.1** (MIT-Lizenz), versioniert unter `addons/gut/`. Tests liegen in `tests/unit/` (`test_*.gd`), Konfiguration in `.gutconfig.json`. Headless-Lauf: `godot --headless -s addons/gut/gut_cmdln.gd`.
- **Gründe / verworfene Alternativen:** Reines GDScript, kommandozeilenfähig; GdUnit4 mächtiger, aber für den MVP-Umfang schwergewichtiger.
- **Folgen:** CI kann später denselben Headless-Befehl nutzen.
- **Ersetzt:** Offenen Punkt „konkreter Test-Runner“ (§7).

### D-053 – Physik-Layer und Friendly Fire

- **Status:** VORGESCHLAGEN
- **Kontext:** D-021 verlangt „kein Friendly Fire“; Hitbox/Hurtbox brauchen eine feste Layer-Belegung.
- **Beschluss:** Layer 1 `world`, 2 `player`, 3 `enemies`, 4 `player_hurtbox`, 5 `enemy_hurtbox`, 6 `interaction` (Konstanten in `components/physics_layers.gd`). Gegnerangriffe maskieren nur `player_hurtbox`, Spielerangriffe nur `enemy_hurtbox`; Friendly Fire ist damit strukturell ausgeschlossen.
- **Folgen:** Neue Szenen müssen diese Belegung verwenden.

### D-054 – Auslegung „blockierter Treffer“ und Hit-ID-Historie

- **Status:** VORGESCHLAGEN
- **Kontext:** D-017 (blockiert = folgenlos) und D-020 (Hit-ID wirkt nur einmal) lassen offen, ob ein blockierter Kontakt die Hit-ID „verbraucht“.
- **Beschluss:** Nur **wirksame** Treffer werden in der Historie einer Angriffsinstanz vermerkt. Ein während Dash/I-Frames blockierter Angriff kann dasselbe Ziel noch treffen, wenn er danach noch aktiv ist und überlappt.
- **Gründe:** Ein blockierter Treffer hat „nicht gewirkt“; Dash schützt, macht einen noch laufenden Angriff aber nicht nachträglich wirkungslos.
- **Folgen:** `Hitbox._handle_contact()`; ändern, falls das Team anders entscheidet.

### D-055 – Platzhalter-Grafik und PLATZHALTER-Werte

- **Status:** VORGESCHLAGEN
- **Kontext:** Asset-Packs sind nicht gewählt; das GDD nennt keine Basiswerte für Gegner (HP, Schaden, Tempo), Spielertempo, Schwungdauer oder Knockback.
- **Beschluss:** Bis zur Entscheidung geometrische Platzhalter (`PlaceholderShape`) und im Code/`.tres` als **PLATZHALTER** markierte Werte: Spieler 180 px/s; Slime 20 HP/1 Schaden/55 px/s; Skeleton 28 HP/1 Schaden/120 px/s; Archer 16 HP/1 Schaden/80 px/s; Schwerttreffer-Fenster 0,12 s.
- **Folgen:** Werte sind nicht als Balance zu verstehen und müssen im Team als TESTWERTE bestätigt oder ersetzt werden.

### D-056 – Eine Upgrade-Explosion pro Angriffsinstanz

- **Status:** VORGESCHLAGEN
- **Kontext:** D-031 begrenzt den Magierstab auf eine Zusatzexplosion je primärem AOE; für Schwert und Durchschlag-Pfeile ist nichts festgelegt.
- **Beschluss:** „Explosiver Treffer“ löst höchstens **eine** Explosion pro Hit-ID aus (ein Schwerthieb, ein Pfeil, ein Stab-Einschlag). Explosion am Einschlagpunkt (AOE) bzw. am ersten getroffenen Ziel, Schaden = 50 % des gerundeten auslösenden Treffers, Radius **48 px (PLATZHALTER)**.
- **Folgen:** `upgrades/effects/upgrade_effects.gd`.

### D-057 – Economy-Platzhalter und Rundung der 50-%-Auszahlung

- **Status:** VORGESCHLAGEN (ersetzt nichts, füllt OFFENE Punkte aus §7 bis zur Teamentscheidung)
- **Beschluss:** Alle Werte zentral in `economy/data/economy_config.tres`:
  - Gold-Drops: Slime 2, Skeleton 3, Archer 3, Boss 30; Miniboss ×5; +10 % je Fünf-Raum-Block.
  - Shoppreise: Upgrade 25, Waffe 30, Heilung 15, Schild 15; +15 % je Block.
  - **50 %-Auszahlung bei ungeradem Betrag: abrunden** (`RunManager.calculate_payout`).
- **Folgen:** Werte sind spielbar, aber keine abgestimmte Balance. Änderungen nur in der `.tres` bzw. einer Funktion.

### D-058 – Reihenfolge Spezialraum-Typ und Portal

- **Status:** VORGESCHLAGEN
- **Beschluss:** Zuerst wird der Spezialraum-Typ gezogen (gleichgewichtet, ohne direkte Wiederholung), danach **unabhängig** die 30-%-Portalchance. Das Portal steht zusätzlich zum Raum-Inhalt.
- **Folgen:** `dungeon/room_sequence.gd`, `DungeonManager._prepare_room()`.

### D-059 – Speicherformat

- **Status:** VORGESCHLAGEN
- **Beschluss:** Godot-`ConfigFile` unter `user://savegame.cfg`, Abschnitt `[meta] version` (aktuell **2**, Migration v1 → v2 behält Gold, Freischaltungen und Lautstärke), `[progress]` (Gold, Kristalle, Freischaltungen, zweite Startwaffe), `[meta_upgrades]`, `[boosts]`, `[stats]`, `[settings]`. Fehlende Datei → Neustart mit 0; unlesbare, falsche Version oder ungültige Werte → Neustart mit 0 und Sicherung als `*.bak`.
- **Ergänzung 14.10.2026 (B1, D-087):** Abschnitt `[seen]` mit `all` (bool) und `ids` (z. B. `intro_forge`) für einmalige Erklärungen. Fehlt `[seen]` in einer v1/v2-Datei, setzt `migrate()` `all = true` (alte Stände gelten als „alles gesehen“); Version bleibt **2**. Die v3-Migration (B2) muss das beibehalten.
- **Ergänzung 14.10.2026 (MM1, Wunsch Projektmitglied: Spielstände im Hauptmenü):** Bis zu **3 Spielstände** als `user://saves/slot_1..3.cfg`, gleiches Format, Version bleibt **2** (v3 ist für B2 reserviert). Neuer Abschnitt `[profile]` (`name`, `character`, `color` als Hex, leer = Standard, `created`, `last_played` als Unix-Zeit), additiv. `[settings]` steht nicht mehr im Slot: Lautstärke und zuletzt gespielter Slot liegen global in `user://settings.cfg` (`[meta] version=1`, `[audio]`, `[slots] last`, `legacy_imported`), beim ersten Start aus dem alten `[settings]` übernommen. Der alte `user://savegame.cfg` wird einmal unverändert in den ersten freien Slot kopiert und bleibt liegen. Gelöschte Slots bleiben einmal als `slot_<n>.cfg.deleted` erhalten. „Alles gesehen“ alter Stände gilt nicht für `boss_intro_*` (`SEEN_ALL_EXCLUDED_PREFIXES`). Die v3-Migration (B2) muss `[profile]` und diese Ausnahme beibehalten. Charakter und Kleidungsfarbe: `characters/` (`CharacterData`, heute nur „Lichtträger“); Umkleiden im Dorf beim **Zuhause**, nicht im Hauptmenü.
- **Ergänzung 14.10.2026 (B2, D-087):** Version **3**. `migrate()` rechnet v1/v2-Schmiedestufen auf die D-087-Tabelle um (`ceil(alte Wirkung / neue Schrittweite)`, höchstens Maximalstufe: Schärfe `ceil(L/2)`, Startschild und Goldgier `ceil(2L/3)`, die übrigen unverändert; kein Gold zurück). Alte Stände erhalten die Ereignisse `event_first_run`, `event_first_crystal`, `event_first_boss` (alles freigeschaltet, ohne Meldung). `[seen]` inkl. `SEEN_ALL_EXCLUDED_PREFIXES` und `[profile]` bleiben. Vor jeder Migration wird die Datei einmal als `<datei>.v<alt>.bak` gesichert und nie überschrieben; jeder Slot wird beim Laden migriert. Neue Ereignisse speichert `StatsTracker`, Regeln in `MetaUnlocks`; Signal `SaveManager.content_unlocked`.
- **Ergänzung 14.10.2026 (UX1):** `settings.cfg` hat den Abschnitt `[options]` (`SaveManager.get_option/set_option`) mit `fullscreen` (bool, Standard false, F11 schaltet um) und `screen_shake` (bool, Standard true, schaltet `CameraShake.enabled`). Gesehen-Flag `hint_controls` für die Steuerungs-Hinweise im ersten Raum (einmal je Spielstand, TESTWERT 16 s je Schritt). Die Farbe des Charakters wird schon beim Anlegen des Spielstands gewählt (`create_slot(..., color)`), umziehen im Zuhause.
- **Folgen:** `autoload/save_manager.gd`, `meta/save_slots.gd`, `meta/meta_unlocks.gd`, `ui/main_menu/`, Tests in `tests/unit/test_save_manager.gd`, `test_save_seen.gd`, `test_save_slots.gd`, `test_meta_unlocks.gd`, Fixtures `tests/fixtures/save_v2_*.cfg`.

### D-060 – Platzhalter-Boss und Endlosmodus

- **Status:** VORGESCHLAGEN
- **Beschluss:** Boss in Raum 15/30/45 ist der „Knochenkönig“ (vergrößertes, getöntes Skelett): 240 HP, 1,5 Schaden, Nahkampf-Schlag, jeder 3. Angriff eine Ring-Salve aus 12 Pfeilen. Es gilt nur die normale Block-Skalierung (D-011), keine Boss-Sonderfaktoren. Ab Raum 46 läuft dieselbe Skalierungsformel unverändert weiter.
- **Folgen:** `enemies/data/boss_bone_king.tres`. Bossdesign und Endlos-Balance bleiben fachlich OFFEN.

### D-061 – Darstellungsmaßstab

- **Status:** VORGESCHLAGEN
- **Beschluss:** 32-px-Pixel-Art wird in der Welt mit **Faktor 2** gezeichnet (1 Tile = 64 px), damit die px-Werte des GDD (Reichweiten, Tempo) unverändert gelten. Räume werden nach Norden aneinandergereiht; der Ausgang eines Raums liegt exakt am Eingang des nächsten.
- **Folgen:** `SpriteStrip.PIXEL_SCALE`, `RoomTiles.TILE_WORLD`.

### D-062 – Rundung der 50-%-Auszahlung: aufrunden

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Bei Tod/Abbruch wird `ceil(remaining_run_gold * 0,5)` gutgeschrieben (7 → 4).
- **Ersetzt:** Rundungsvorschlag aus D-057.

### D-063 – Skalierung im Endlosmodus

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Ab Raum 46 gilt dieselbe Formel wie D-011 (HP ×1,20, Schaden ×1,10 je Block), **keine Abschwächung**.
- **Ersetzt:** Die Formulierung „abgeschwächte Skalierung ab Raum 46“ in PRD 4.1.

### D-064 – Balancewerte als TESTWERTE

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied („gute Spielentscheidungen treffen“)
- **Beschluss:** Die bisherigen PLATZHALTER (D-055, D-057) gelten als **TESTWERTE**: änderbar nach Playtests, aber offiziell spielbare Startwerte.

### D-065 – Drei Bosse

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Raum 15 **Knochenkönig** (Schlag, Ring-Salve, Schildstoß mit Stun), Raum 30 **Schleimkönigin** (Sprung-Stampfer, beschwört Slimes), Raum 45 **Schattenlord** (Teleport, blendende Geschosse, Salven). Grafik vorerst getönte, vergrößerte vorhandene Sprites; eigene Boss-Sprites können später ersetzt werden.
- **Ersetzt:** D-060.

### D-066 – Stun durch Skelett-Schildstoß

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Skelette führen gelegentlich einen deutlich angekündigten Schildstoß (Ansturm) aus. Ein wirksamer Treffer betäubt den Spieler **0,8 s** (keine Bewegung, kein Angriff, kein Dash). Blockierte Treffer (Dash, I-Frames) betäuben nicht (D-017). Der Knochenkönig besitzt denselben Angriff.

### D-067 – Sicht und Dunkelheit

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Der Dungeon ist **grundsätzlich abgedunkelt**; sichtbar ist ein Lichtkreis um den Spieler (TESTWERT 300 px) sowie Fackeln, Projektile, Explosionen, Münzen, Elite-Gegner und Bosse. Ab Raum 6 sind 25 % der Kampfräume **extra-dunkel** (190 px), der Schattenlord-Raum immer. Treffer des **Schattenwesens** blenden 4 s (110 px). Das Dorf bleibt hell, **Spezialräume sind hell** (sichere Räume). Darstellung in **Pixel-Optik** (grobes Raster, Bayer-Dithering), Lichter verschmelzen weich.

### D-068 – Audio

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Chiptune-Musik (Dorf, Dungeon, Boss) und Soundeffekte werden per Skript (`tools/generate_audio.py`) synthetisiert, lizenzfrei und jederzeit durch eigene Dateien gleichen Namens ersetzbar. Busse `Music` und `SFX`, Lautstärke im Pausemenü. **Kein zusätzlicher Autoload** (D-044): Musik ist ein Node in `game.tscn`/`main.tscn`, Effekte laufen über den statischen Helfer `Sfx`.

### D-069 – Erweiterte Gegner, Fallen, Zerstörbares

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied (Erweiterung über den MVP-Umfang hinaus)
- **Beschluss:**
  - **Neue Gegner:** Schattenwesen (blendet) und Bomber (läuft auf den Spieler zu und explodiert). Ab Raum 6 wird ein Spawn mit 20 % Chance durch einen dieser Typen ersetzt; sonst gelten die Gewichte aus D-010 unverändert.
  - **Elite-Gegner:** ab Raum 6 mit 12 % (+1 % je Block), Eigenschaft Schnell, Gepanzert oder Explosiv, leuchtender Umriss, doppeltes Gold.
  - **Fallen:** Stachelfallen mit sichtbarer Vorwarnung; sie treffen nur den Spieler.
  - **Zerstörbares:** Kisten und Fässer lassen sich zerschlagen und lassen Gold oder ein Herz fallen.
- **Folgen:** PRD 6 („nicht gebaut“) gilt für diese Punkte nicht mehr.

### D-070 – Dialoge erst nach kurzer Pause

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Nach dem letzten Kill erscheint zuerst ein Banner („Raum geschafft!“), Gold fliegt ein; Belohnungsdialoge öffnen frühestens nach **1,5 s**.

### D-071 – Eigener Mauszeiger

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied
- **Beschluss:** Im Spiel ein Pixel-Fadenkreuz (Hotspot Mitte), in Menüs und Dialogen ein Pixel-Pfeil. Grafiken `art/ui/cursor_*.png` (erzeugt von `tools/generate_cursors.py`, ersetzbar).

### D-072 – Musik neu komponiert

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied („Musik klingt krächzend“)
- **Beschluss:** Die zufällig generierte Musik ist ersetzt durch **handkomponierte Melodien** mit bandbegrenzten, gefilterten Klängen, Echo und Limiter (`tools/generate_music.py`). Eigene Musik kann jederzeit unter gleichem Dateinamen in `audio/music/` abgelegt werden.

### D-073 – Immer endlos, Portal nach jedem Boss

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-13 / Projektmitglied (Playtest bis Raum 101)
- **Beschluss:** Kein Ende bei Raum 45 und kein Endlos-Dialog mehr. Alle 15 Räume ein Boss; nach jedem Boss erscheint immer ein Exit-Portal (Gold sichern). Spezialraum-Portale (30 %) bleiben.
- **Ersetzt:** D-004, D-063 (Teil „nach Raum 45“), PRD 4.1 „Nach Raum 45“.

### D-074 – Schwierigkeitskurve und Schild-Nerf

- **Status:** VERBINDLICH (Werte = TESTWERTE) · **Datum:** 2026-10-13 / Projektmitglied („viel zu easy“)
- **Beschluss:** Werte siehe [KONZEPT_ENDLOS.md](KONZEPT_ENDLOS.md) §3: Gegner pro Raum 1–2 → bis 3–5, Wellen (2 ab Raum 30, 3 ab Raum 60), HP ×1,18 und Schaden ×1,14 je Block, Angriffstempo und Lauftempo steigen, Elite-Chance +2 %/Block (max. 50 %), Schildverstärkung +4, Schild/Heilung bei Tötung +0,5, Shop-Schild +3, Schild-Softcap ab 15.
- **Ersetzt:** D-009 (Anzahl), D-011 (Faktoren), Zahlenwerte aus D-014, D-036 (Schild +4 → +3).

### D-075 – Biome

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Alle 15 Räume wechselt das Biom: Krypta, Schleimgrotte, Schattenreich, Glutkammer, danach von vorn. Jedes Biom hat eigene Gegner-Tabelle, Farbstimmung und Gefahren (`dungeon/biomes/*.tres`). Die Krypta behält die Gewichte aus D-010 für die drei Grundgegner.

### D-076 – Boss-Zyklus mit Stufen

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Bosse wechseln sich ab (Knochenkönig, Schleimkönigin, Schattenlord, Glutgolem). Nach jedem vollen Zyklus steigt die Stufe: +40 % HP, größere Salven, häufigere Spezialangriffe, ab Stufe 2 zusätzliche Diener. Jeder Boss hat zwei Phasen.
- **Ersetzt/erweitert:** D-065.

### D-077 – Champions statt einfacher Minibosse

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied („Minibosse zu easy“)
- **Beschluss:** Der Miniboss ist ein Champion: zufälliger Gegner des Bioms, ×3 HP, ×1,5 Schaden, immer mit Elite-Eigenschaft, beschwört Diener und kommt mit Begleitern (1 + Block/3).
- **Ersetzt:** Minibossfaktor ×1,5 aus D-011.

### D-078 – Dorf mit Inhalten und Meta-Progression

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Begehbare Gebäude: Schmiede (dauerhafte Verbesserungen gegen Gold), Handelsposten (Seelenkristalle als zweite Währung, Tausch, Proviant für den nächsten Run), Chronik (Statistiken), Gilde (Multiplayer-Lobby in Vorbereitung).
- **Folgen:** Konkretisiert die bisher OFFENEN „Dorf-Freischaltungen“; Speicherformat wird versioniert erweitert (D-059, v2). Multiplayer-Planung: [MULTIPLAYER.md](MULTIPLAYER.md).
- **TESTWERTE (Vorschlag):** 1 Kristall verkaufen = 25 Gold, kaufen = 60 Gold; Proviant (in Kristallen): Heiltrank +2 Max-HP (1), Glücksamulett +1 zufälliges Upgrade (2), Goldbeutel +25 % Gold (2); Kristalle: Boss 3, Champion 1; Arsenal Stufe 1 = Bogen, Stufe 2 = Bogen oder Stab wählbar.

### D-079 – Gegner-Kennzeichen und Ersthinweise

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Besondere Gegner tragen kleine Symbole (Elite-Art, Champion, Stun, Blendung, Beschwörer, Explosion). Beim ersten Kontakt mit einem neuen Gegnertyp erscheint ein kurzer Hinweis.

## 7b. Vision nach dem MVP (ab 13.10.2026)

> Grundlage: [PRD.md](PRD.md) Abschnitt 7. Pläne: [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md), [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md). Balance- und Detailwerte hat das Projektmitglied an Claude delegiert („mach einfach“); sie sind **TESTWERTE** und jederzeit per neuer Entscheidung änderbar.

### D-080 – Zwei Gruppenmodi: Schnelles Spiel und Gilde

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Im Gildengebäude gibt es zwei Wege, zusammen zu spielen:
  - **Schnelles Spiel:** Host lädt beliebige Leute ein (z. B. Bekannte von Discord), keine Bindung, nach dem Run löst sich die Gruppe auf.
  - **Gilde:** dauerhaft gründen, beitreten, jederzeit verlassen. Ein Spieler ist in **höchstens einer** Gilde (TESTWERT), max. **30 Mitglieder** (TESTWERT). Beitritt per Einladungscode bzw. später Steam-Einladung. An einem **Gilden-Run** dürfen nur Mitglieder teilnehmen.
- **Folgen:** Gilden brauchen einen Server (D-083). Ersetzt die offene Frage „Gruppe oder dauerhaft“ aus PRD 7.2: **beides**.

### D-081 – Multiplayer-Fortschritt getrennt vom Einzelspieler, gemeinsame Goldkasse

- **Status:** VERBINDLICH (Grundsatz) · Details **VORGESCHLAGEN** · **Datum:** 2026-10-13 / Projektmitglied, Details Claude
- **Beschluss (Grundsatz):** Multiplayer ist vom Einzelspieler-Spielstand getrennt: Man startet ohne die eigenen Dorf-Verbesserungen und ohne gute Waffen. Run-Gold ist im Multiplayer eine **gemeinsame Kasse**; jeder darf daraus im Shop kaufen.
- **Vorschlag (Details):**
  - **Schnelles Spiel:** keine Meta-Boni, keine dauerhafte Auszahlung. Alle starten gleich.
  - **Gilden-Run:** Die Gilde hat einen **eigenen Fortschritt** auf dem Server: Gildenkasse (Auszahlung des Runs nach der normalen 50-/100-%-Regel) und eine **Gilden-Schmiede** mit denselben Verbesserungen wie die Schmiede (D-087). Alle Mitglieder profitieren in Gilden-Runs davon.
  - Waffen, Upgrades und Upgrade-Angebote bleiben **je Spieler**.
- **Folgen:** `MetaProgression` liest später aus einer austauschbaren Quelle (lokaler Spielstand oder Gilden-Server). Kein Mischen der Stände.

### D-082 – Ranglisten für Spieler und Gilden

- **Status:** VERBINDLICH (Ziel) · Wertung **VORGESCHLAGEN** · **Datum:** 2026-10-13 / Projektmitglied, Wertung Claude
- **Beschluss:** Spieler und Gilden sehen sich in Ranglisten.
- **Vorschlag Wertung:**
  - **Spieler-Rangliste**, getrennt nach **Solo** und **Gruppe**: höchster erreichter Raum in einem Run, bei Gleichstand kürzere Run-Zeit. Schnelle Spiele zählen für die Gruppen-Rangliste.
  - **Gilden-Rangliste:** höchster Raum eines Gilden-Runs, bei Gleichstand kürzere Zeit; zusätzlich Anzahl Mitglieder sichtbar.
  - **Allzeit** und **Saison** (monatlich, TESTWERT).
- **Folgen:** Der Host meldet am Run-Ende einen Run-Bericht (Modus, Teilnehmer, Raum, Zeit, Seed, Spielversion) an den Server. Ranglisten sind **nicht fälschungssicher** (der Host rechnet); Plausibilitätsprüfungen auf dem Server (z. B. Mindestzeit je Raum) und ein Melde-/Löschweg für Admins. Ranglisten aus der Testphase werden zum Steam-Start zurückgesetzt.

### D-083 – Server: VPS mit Dokploy (Docker)

- **Status:** VERBINDLICH (Infrastruktur) · Technik **VORGESCHLAGEN** · **Datum:** 2026-10-13 / Projektmitglied, Technik Claude
- **Beschluss:** Gilden, Gildenfortschritt und Ranglisten laufen auf dem **virtuellen Server mit Dokploy** des Projektmitglieds (Docker-Container). Das reine Webhosting von WebBude wird dafür nicht genutzt.
- **Vorschlag Technik:** Container `soulwick-api` (TypeScript mit Hono, passend zur vorhandenen TypeScript-Erfahrung) und `soulwick-db` (PostgreSQL); HTTPS und Domain über Dokploy; regelmäßige Datenbank-Backups. Quellcode im Ordner `server/` dieses Repos. Der Steam-Web-API-Schlüssel liegt **nur** auf dem Server.
- **Folgen:** Kein Echtzeit-Spielverkehr über den Server (Host-Modell bleibt). Ein Headless-Godot-Server als weiterer Container ist später möglich, aber nicht geplant. Ändert für die Zeit nach dem MVP die Regel „kein Backend“ aus ARCHITECTURE.md.
- **Ergänzt durch D-119** (Weiterleitung ja, Spiellogik nein: Echtzeit-Pakete laufen über den eigenen Relay `soulwick-relay`, gerechnet wird weiter nur beim Host) und D-093 (Quellcode im Repo `soulwick-platform` statt `server/`).

### D-084 – Skalierung nach Spielerzahl

- **Status:** TESTWERT · **Datum:** 2026-10-13 / an Claude delegiert
- **Beschluss** (`n` = Spielerzahl 1–4, bei `n = 1` alles unverändert):

| Größe | Formel | 2 Spieler | 3 Spieler | 4 Spieler |
| --- | --- | ---: | ---: | ---: |
| Gegneranzahl je Welle | `× (1 + 0,6 · (n − 1))`, gerundet | ×1,6 | ×2,2 | ×2,8 |
| HP normaler Gegner | `× (1 + 0,2 · (n − 1))` | ×1,2 | ×1,4 | ×1,6 |
| HP Champion, Miniboss, Boss | `× (1 + 0,7 · (n − 1))` | ×1,7 | ×2,4 | ×3,1 |
| Gegnerschaden, Elite-Chance, Gold je Gegner | unverändert | | | |
| Raumgröße | 1–2 Spieler: S/M, 3–4 Spieler: L | | | |

- **Wiederbeleben:** Bei 0 HP geht ein Spieler **zu Boden**. Mitspieler beleben ihn, indem sie **2 s** neben ihm stehen (er steht mit **2 HP** auf). Ist der Raum geschafft, stehen alle Gefallenen mit 2 HP auf. Liegen **alle** am Boden, endet der Run.
- **Folgen:** Mehr Spawnpunkte nötig (D-086); Werte mit der Balance-Simulation (1–4 Bots) prüfen.

### D-085 – Menüs und Pause im Multiplayer, Verbindungsabbruch

- **Status:** VERBINDLICH seit D-123 (14.10.2026); vorher VORGESCHLAGEN (Projektmitglied hatte um Erklärung gebeten) · **Datum:** 2026-10-13 / Claude
- **Kontext:** Heute **friert jedes Menü das ganze Spiel ein** (D-043): Shop, Upgrade-Wahl, Waffenwahl, Tab-Übersicht und Esc halten Gegner, Geschosse und Timer an. Im Multiplayer würde ein Spieler, der den Shop öffnet, das Spiel für alle anhalten.
- **Vorschlag:**
  - **Einzelspieler:** unverändert (D-043 gilt weiter).
  - **Multiplayer:** Menüs halten das Spiel **nicht** an. Wer ein Menü offen hat, ist **geschützt**: kann nicht getroffen werden, wird von Gegnern ignoriert, kann aber auch nicht angreifen. Das betrifft kaum etwas, weil Upgrade-Wahl und Shop ohnehin in sicheren Momenten kommen (Raum geschafft, Spezialraum).
  - Esc öffnet im Multiplayer ein Menü ohne Pause. HitStop (kurzes Einfrieren bei Treffern) ist im Multiplayer **aus**.
  - **Verbindungsabbruch:** Fällt ein Client heraus, läuft der Run weiter, die Gegneranzahl passt sich ab dem nächsten Raum an. Fällt der **Host** heraus, endet der Run für alle (Auszahlung wie Tod, 50 %). Kein Host-Wechsel, kein Wiederbeitreten im laufenden Run (später möglich).
- **Folgen:** Ersetzt D-043 nur im Multiplayer; Entscheidung des Teams nötig (getroffen in D-123).

### D-086 – Raumarten und Abgründe

- **Status:** VERBINDLICH (Idee des Projektmitglieds) · Ausgestaltung **TESTWERT** · **Datum:** 2026-10-13 / Projektmitglied, Ausgestaltung Claude
- **Beschluss:**
  - Normale Kampfräume (Positionen 1–3 im Fünf-Raum-Zyklus) haben eine **Raumart**: **Arena** (groß, offen, Wellen), **Strukturiert** (Mauern, Engstellen, Säulen, mehrere Bereiche), **Abgrund** (Abgründe, Brücken, Plattformen). **Rätselräume** sind eine Idee für später. Spezial-, Miniboss- und Bossräume bleiben unverändert. Raumart und Biom sind unabhängig.
  - **Ziehung:** Raum 1–5: Arena 50 % / Strukturiert 50 %. Ab Raum 6: Arena 35 % / Strukturiert 40 % / Abgrund 25 %. Kein Abgrundraum direkt nach einem Abgrundraum. Erster Abgrundraum zeigt einen Hinweis (wie D-079).
  - **Springen = Dash.** Keine neue Taste (D-012 bleibt). Während des Dashs ist der Spieler in der Luft und überquert Abgründe. Abgründe zum Überspringen sind **höchstens 1 Tile** (64 px) breit (Dash-Weite 90 px); breitere Abgründe brauchen eine Brücke.
  - **Herunterfallen:** Steht der Spieler nach Dash-Ende bzw. **0,1 s** Schonzeit über einem Abgrund, fällt er (0,5 s Animation), verliert **2 HP = ein ganzes Herz direkt** (am Schild vorbei, kann töten; Projektmitglied 14.10.2026, vorher 1 HP), erscheint an der **letzten sicheren Stelle** und ist **1 s** unverwundbar.
  - **Gegner** laufen nicht in Abgründe (Abgründe blockieren sie wie Wände). Starker **Rückstoß** kann normale Gegner und Elites hineinstoßen: Sie sterben (zählt als Kill, Gold fällt am Rand). Champions, Golems, Bosse fallen nie. Geschosse fliegen über Abgründe.
  - **Spawnpunkte:** Kampfraumvorlagen haben **5 bis 14** Spawnpunkte statt genau 5 (Größe S ≥ 5, M ≥ 8, L ≥ 12), alle auf erreichbarem Boden. Reicht die Zahl nicht, kommt der Rest als zusätzliche Welle.
  - **Größenklassen** (Tiles): S ≈ 15×9, M ≈ 19×11, L ≈ 25×15.
- **Ersetzt:** D-009 (genau fünf Spawnpunkte).

### D-087 – Verständliches Dorf

- **Status:** VERBINDLICH (Wunsch des Projektmitglieds) · Werte **TESTWERT** · **Datum:** 2026-10-13 / Projektmitglied, Werte Claude
- **Beschluss:**
  - Jedes Gebäude erklärt beim **ersten Betreten** seine Rolle in einem Satz (Schmiede: „Dauerhaft stärker werden – kostet Gold.“; Handelsposten: „Proviant für den nächsten Run – kostet Seelenkristalle.“; Chronik: „Deine Rekorde und Statistiken.“; Gilde: „Mit Freunden spielen.“).
  - Verbesserungen zeigen **konkrete Werte** („Max-HP 6 → 7“). Der Run-Start fasst alle Dorf-Boni in einem Banner zusammen.
  - **Freischaltungen:** Am Anfang Schmiede mit Vitalität, Schärfe, Startschild, dazu Gilde und Dungeon. Chronik nach dem ersten Run. Handelsposten ab dem ersten Seelenkristall. Goldgier, Dash-Training und Arsenal nach dem **ersten besiegten Boss**.
  - **Kristall-Tausch entfällt**; Kristalle gibt es nur noch für Proviant.
  - **Weniger Stufen** (28 → 20):

| Verbesserung | Stufen | je Stufe | Kosten (Gold) |
| --- | ---: | --- | --- |
| Vitalität | 5 | +1 Max-HP | 40 · 80 · 140 · 220 · 320 (unverändert) |
| Startschild | 3 | +3 Schild | 40 · 90 · 160 |
| Schärfe | 4 | +10 % Schaden | 70 · 150 · 260 · 400 |
| Goldgier | 3 | +15 % Gold | 60 · 140 · 250 |
| Dash-Training | 3 | −0,15 s | 60 · 140 · 260 (unverändert) |
| Arsenal | 2 | zweite Startwaffe | 80 · 160 (unverändert) |

- **Migration (Spielstand v2 → v3):** neue Stufe = alte Wirkung aufgerundet auf die neue Schrittweite, höchstens Maximalstufe (Schärfe `ceil(L/2)`, Startschild `ceil(2L/3)`, Goldgier `ceil(2L/3)`). Kein Gold zurück. Gesehene Erklärungen und Freischaltungen werden gespeichert; bestehende Spielstände gelten als „alles gesehen und freigeschaltet“.
- **Ersetzt:** Kristall-Tausch und Stufen aus D-078 bzw. KONZEPT_ENDLOS §6.

### D-088 – Reihenfolge: erst Ausbau, dann Multiplayer, mit Leitplanken

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Zuerst wird das Spiel ausgebaut ([ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md)), danach Multiplayer ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md)). Neuer Code hält sich an die **Multiplayer-Leitplanken** (ROADMAP_AUSBAU, Abschnitt „Leitplanken“), damit der spätere Umbau klein bleibt.
- **Folgen:** Umsetzung durch eigene Agenten je Arbeitspaket.

### D-089 – Balance nach Bot-Messung

- **Status:** VERBINDLICH (TESTWERTE) · **Datum:** 2026-10-13 / Claude im Auftrag des Projektmitglieds („du balancest das“)
- **Messung:** `tools/balance_sim.gd` (Bot, Reaktionswahrscheinlichkeit 0,8, sieht keine Dunkelheit), je 3 Runs pro Waffe, Ergebnis in erreichten Räumen.

| Waffe | vorher | nachher |
| --- | --- | --- |
| Schwert | 16 · 32 · 45 | 22 · 45 · 60 |
| Bogen | 93 · 95 · 100 | 30 · 40 · 42 (vor Feinschliff Schaden 7,5 → 8) |
| Stab | 45 · 45 · 100 | 40 · 45 · 45 |

- **Beschluss:** Schwert-Schaden 12 → 14; Bogen-Schaden 9 → 8, Reichweite 600 → 480; Gegner-Lauftempo +3 % je Block (max. +50 %); Schattenlord 400 → 340 HP. Ziel: ohne Dorf-Verbesserungen enden Runs meist zwischen Raum 40 und 80.
- **Ersetzt:** Zahlenwerte aus D-074 (Tempo) und den Waffen-TESTWERTEN in §4.

### D-090 – Waffen-Erweiterung

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Neue Waffen **Dolche** (schnell, Hinterhalt ×2) und **Kriegshammer** (langsamer Flächenschlag); **Spezialangriff auf der rechten Maustaste** je Waffe mit Abklingzeit; **Schwert-Combo** (jeder 3. Schlag ist ein Finisher). „Größerer Schwung“ gilt jetzt für Waffen mit Tag `swing`.
- **Ersetzt:** D-023 (nur drei Waffen).

### D-091 – Schild- und Gold-Balance nach Playtest

- **Status:** VERBINDLICH (TESTWERTE) · **Datum:** 2026-10-13 / Claude im Auftrag des Projektmitglieds („Balancen“)
- **Anlass:** Playtest bis Raum 43 mit mehrfach „Schild bei Tötung“: **97 Schild** und **944 Gold**. Ursache Schild: 0,5 pro Kill ist über dem Softcap rechnerisch 0,25, wurde aber wieder auf 0,5 **auf**gerundet, der Softcap griff also nie; dazu unbegrenzt stapelbar. Ursache Gold: Das Einkommen pro Raum wächst schon über mehr Gegner und Wellen, zusätzlich wuchs jeder einzelne Drop um 10 % je Block.
- **Beschluss:**
  - Schildgewinne werden auf 0,5 **ab**gerundet; der Rest wird zum nächsten Gewinn übertragen (zwei Kills über dem Softcap = +0,5). Klärt D-015 (kleine Gewinne über dem Softcap).
  - „Schild bei Tötung“ lädt nur bis **10 Schild** auf, **+2 je weiterem Stapel**, höchstens 20. Andere Schildquellen (Schildverstärkung, Shop, Dorf) dürfen darüber hinaus.
  - Gold je Gegner: Faktor **0,7** auf alle Drops (mindestens 1), **kein Wachstum je Block** mehr (0,10 → 0). Shop-Preise wachsen **+30 %** je Block (vorher +15 %).
- **Messung** (`balance_sim.gd`, Schwert, Wahl „tank“): Schild bei Raum 43 jetzt 14–18 statt 97. Gold beim Tod (Schwert, Wahl „greedy“, Raum 15 und 28): 55–58, der Bot gibt es im Shop aus. Nach dem nächsten Playtest prüfen, ob es zu knapp ist.
- **Ersetzt:** Zahlenwerte aus D-057 (Gold-Wachstum, Preiswachstum); ergänzt D-014/D-074 (Softcap).

### D-092 – Musik je Biom

- **Status:** VERBINDLICH (Wunsch des Projektmitglieds) · Umsetzung **geplant** (ROADMAP_AUSBAU C1) · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Jedes Biom bekommt einen **eigenen Dungeon-Track** (Krypta: düster, Orgel/Glocken; Schleimgrotte: blubbernd, Tropfen, verspielt-bedrohlich; Schattenreich: kalt, Hall, Flüstern; Glutkammer: treibend, Trommeln, Amboss). Bosskämpfe behalten die **intensivere Musik**, je Boss eine eigene Variante; Phase 2 wird noch einmal intensiver (schneller oder zusätzliche Spur). Champion-Räume dürfen eine gesteigerte Fassung des Biom-Tracks nutzen. Beim Biomwechsel blendet die Musik über (wie heute zwischen Dorf und Dungeon).
- **Technik (Vorschlag):** `BiomeData.music_track` und `BiomeData.boss_music_track`; `MusicPlayer` wählt beim Raumwechsel nach Biom. Die Tracks erzeugt `tools/generate_music.py`; eigene Dateien gleichen Namens ersetzen sie.

### D-093 – Zwei Repositories: Spiel und Plattform

- **Status:** VERBINDLICH (Projektmitglied, nach Abwägung Monorepo vs. getrennt) · Technik **VORGESCHLAGEN** · **Datum:** 2026-10-13 / Projektmitglied, Technik Claude
- **Beschluss:** Spiel und Online-Plattform liegen in **zwei** Repositories:

| Repository | Inhalt | Technik (Vorschlag) |
| --- | --- | --- |
| **`soulwick`** (Team-Repo auf GitLab, dieses; Ordner vorher `gdd`) | Godot-Spiel, Spiel-Doku, Produkt-Entscheidungen (D-Nummern), Spiel-Roadmaps | Godot 4.7.2, GDScript, GUT |
| **`soulwick-platform`** (Nachbarordner `../soulwick-platform`, eigenes Repo) | pnpm-Monorepo mit eigener Doku (`docs/PRD.md`, `docs/ROADMAP.md`, technische `docs/DECISIONS.md` mit P-Nummern): `apps/api` (Anmeldung, Gilden, Run-Berichte, Ranglisten, Admin-Funktionen), `apps/web` (öffentliche Website), `apps/admin` (Admin-Panel), `packages/contracts` (API-Verträge), `infra/` (Docker-Compose, Dokploy) | TypeScript, Hono, Drizzle, PostgreSQL, Next.js, zod |

- **Warum getrennt:** kein gemeinsamer Code (GDScript kann die TypeScript-Verträge nicht nutzen), verschiedene Werkzeuge und Tests, verschiedene Veröffentlichungszyklen (der Server muss ohnehin ältere Spielversionen bedienen), das Spiel-Repo bleibt schlank, Server-Zugänge und Admin-Panel bleiben beim Betreiber.
- **Schnittstelle:** HTTPS-API mit Versionsangabe (`API_VERSION`, Spielversion im Run-Bericht). Quelle der Wahrheit sind die Verträge in `soulwick-platform/packages/contracts`; der GDScript-Client im Spiel wird danach von Hand angepasst. Der Server unterstützt mindestens die aktuelle und die vorige Spielversion.
- **Admin-Rollen:** `admin` (alles) und `moderator` (sperren, entsperren, Runs markieren). Jede Admin-Aktion landet im Protokoll. Gesperrte Spieler bekommen bei jedem Server-Aufruf „gesperrt“ mit Grund und Ende; das Spiel bleibt offline spielbar.
- **Ersetzt:** Ordner `server/` aus D-083 und ROADMAP_MULTIPLAYER MP7 → Repository `soulwick-platform`. Ergänzt TECHSTACK §6. Arbeitsweise mit Agenten: [AGENTS.md](../AGENTS.md).

### D-094 – Spielname „Soulwick“

- **Status:** VERBINDLICH · **Datum:** 2026-10-13 / Projektmitglied
- **Beschluss:** Das Spiel heißt **Soulwick** (Docht + Seele: der Lichtkreis als letztes Licht im Dunkel, Seelenkristalle als Währung). Untertitel im Hauptmenü: „Das letzte Licht im endlosen Dunkel“. Kurzsuche am 13.10.2026: kein Spiel dieses Namens auf Steam/itch gefunden; **vor dem Steam-Start Marken- und Domainprüfung** (MP10).
- **Folgen:** Godot-Projektname `Soulwick` → Spielstand-Ordner `%APPDATA%/Godot/app_userdata/Soulwick/`; ein alter Stand aus `…/Dungeon Roguelite/` wird beim ersten Start kopiert. Der Projektordner `gdd` wurde in `soulwick` umbenannt (GitLab-Projektname nach Teamabsprache).

### D-095 – Raumart-Ziehung und Vorlagenwahl (Ausgestaltung D-086)

- **Status:** VERBINDLICH (Regeln D-086) · Ausgestaltung **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Beschluss:**
  - Gewichte wie D-086, Abgrund ab Raum 6 (`RoomSequence.ABYSS_FROM_ROOM`). Die Ziehung verbraucht genau eine Zufallszahl des Dungeon-RNG.
  - „Kein Abgrund nach Abgrund“ gilt für den direkt vorigen Kampfraum und richtet sich nach der **tatsächlich benutzten** Art. In der Sperre wird der Abgrund-Anteil anteilig auf Arena (35/75) und Strukturiert (40/75) verteilt; effektiv ≈ 22 % Abgrund.
  - Vorlagenwahl gleichverteilt unter den Vorlagen der Art in Größe S oder M (Einzelspieler). Fehlt die Art: Arena → beliebige Vorlage der Größe → beliebige Vorlage. Art und Größe stehen an der Vorlage (`room_kind`, `room_size_class`), der Generator schreibt `combat_catalog.tres`.
  - Generator-Prüfung: Ausgang und alle Spawnpunkte vom Eingang erreichbar (Laufen + Dash über 1-Tile-Lücken), kein Spawnpunkt auf Falle/Kiste/Fass oder ≤ 2 Tiles vom Eingang.
  - Raumart und Größe werden im Spiel **nicht** angezeigt (Projektmitglied 14.10.2026: Räume sollen sich nur unterscheiden, nicht beschriftet sein). Das Test-Banner `DungeonManager.SHOW_ROOM_KIND_BANNER` ist aus; der Smoke-Test gibt die Art weiter aus.
- **Offen:** Überlauf „mehr Gegner als Spawnpunkte → zusätzliche Welle“ (Haken in `enemy_spawner.gd`, heute nicht erreichbar).
- **Folgen:** `dungeon/room_sequence.gd`, `dungeon/rooms/room_catalog.gd`, `room_controller.gd`, `room_tiles.gd`, `tools/generate_room_templates.py`, Tests `test_room_kind.gd`, `test_room_templates.gd`.

### D-096 – Spiel-UI nach den Design-Mockups

- **Status:** VERBINDLICH (mit * markierte Punkte: Projektmitglied) · Rest **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied, Claude
- **Beschluss:**
  - Vorlage sind `docs/design/` (Screens, `ui_spec.json`) und `art/ui/theme.tres`. Alle UI-Maße stehen in Mockup-Pixeln (480 × 270) und laufen über **eine** Konstante `UiKit.UI_SCALE` (heute 1280/480); Pixelgrafik wird ganzzahlig über `UiKit.ART_SCALE` skaliert. Die Spielauflösung bleibt 1280 × 720 (`canvas_items`); ein Wechsel auf 480 × 270 ist **OFFEN** und hieße nur `UI_SCALE = 1`.
  - \* Schrift Pixelify Sans ohne Kantenglättung (Import: Antialiasing, Hinting, Subpixel aus).
  - \* Das HUD bleibt in Menüs sichtbar; das Menü-Overlay (höhere CanvasLayer) dunkelt es mit der Szene ab.
  - \* Zahlen mit Dezimalpunkt (international), nicht mit Komma.
  - Neue Eingaben: Upgrade-Wahl 1–3 + Enter, Waffenwahl 1/2, Enter löst den Standard-Button aus (beim Portal „Verlassen“); Leertaste bleibt Dash. **Freigabe durch das Projektmitglied steht noch aus.**
  - Interaktions-Prompt als Panel „E <Text>“ über dem Kopf; Portal-Dialog mit Zeilen „Run-Gold“ / „Gutschrift (100 %)“; HUD-Detailzeile „nächste Heilung in N“ (`DungeonManager.heal_countdown_changed`).
  - Gegner-HP-Leiste 20 × 4 Art-Pixel `#e0463a` auf `#1c1a2b` (Elites nicht mehr eingefärbt), Badges 4 Art-Pixel darüber, Elite-Name bzw. „Champion“ als 6-px-Label daneben.
  - Die Raum-45-Entscheidung aus Screen 10 entfällt (KONZEPT_ENDLOS: kein Ende bei Raum 45).
- **Folgen:** `ui/ui_kit.gd`, `ui/menus/*`, `ui/hud/hud.gd`, `ui/widgets/`, `project.godot` `[gui]`, `player/player.gd` (Prompt), `enemies/enemy_base.gd` (HP-Leiste), Test `test_ui_kit.gd`.

### D-097 – Musik je Biom umgesetzt, Geräuschkulissen (Ausgestaltung D-092)

- **Status:** VERBINDLICH (Wunsch Projektmitglied: mehr Atmosphäre) · Ausgestaltung **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Beschluss:**
  - Je Biom `dungeon_<biom>` und `_intense` (Champion-Räume, taktgleich übergeblendet); je Boss `boss_<boss>` und `_p2` (Phase 2, ca. 12 % schneller, doppelte Trommeln). Rückfall `dungeon`/`boss`.
  - Neu: leise Geräuschkulisse je Biom und fürs Dorf (`audio/ambient/`), ca. 15 dB unter der Musik, über den Bus `Music`. Eigener Bus/Regler „Atmosphäre“ ist eine Idee für später.
  - Zuordnung über `BiomeData.music_track`, `boss_music_track`, `ambient_track`. Eigene `.ogg`/`.mp3` ersetzen die erzeugten `.wav`.
  - Der `MusicPlayer` schaltet nur über Signale (Raum, Biom, Champion, `Enemy.phase_changed`, Boss-Intro). Die Bossmusik setzt erst mit dem Brüllen am Ende des Boss-Intros ein (Sicherung 12 s).
  - TESTWERTE: Überblendzeiten 1,2 / 2,5 / 1,5 / 0,6 / 3,0 s.
- **Ergänzung 14.10.2026 (C3, Wunsch Projektmitglied: keine harten Cuts zwischen Biomen, TESTWERTE):** Zwei verschiedene Loops werden nie gegeneinander geblendet; Blenden equal power, Biom ↔ Champion-Fassung linear an derselben Taktstelle. Biom betreten (auch Dorf → Dungeon): Kulisse zuerst (4 s), alte Musik 1,8 s aus, Übergangs-Stinger `transition_<biom>`, dann der Loop auf Takt 1, leise einsetzend und in 3,5 s auf voll. Bosssieg: Bossmusik 1,5 s aus, Sieges-Stinger `victory_<boss>`, danach nur die Kulisse bis zum nächsten Biom (Zustand „Übergang läuft“, Haken `begin_interlude` für das Lagerfeuer, D-103). Bossmusik nach dem Intro wartet auf dessen Ende (Sicherung 30 s, pausierbar, höchstens 120 s; ersetzt 12 s). Run-Ende: Musik 3 s aus, Kulisse bleibt. Szenenwechsel Hauptmenü ↔ Spiel übergibt Stück und Position. Neue Felder `BiomeData.transition_track`, `victory_track`.
- **Offen:** Repo-Größe (`audio/` ≈ 77 MB unkomprimierte WAVs): Git LFS, kürzere/weniger Fassungen oder so lassen – Teamentscheidung.
- **Folgen:** `tools/generate_music.py`, `components/audio/music_player.gd`, `music_rules.gd`, `music_channel.gd`, `dungeon/biome_data.gd`, `dungeon/biomes/*.tres`, README „Audio“.

### D-098 – Boss-Intro mit Gebrabbel

- **Status:** VERBINDLICH (Idee des Projektmitglieds) · Ausgestaltung **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied, Claude
- **Beschluss:**
  - Beim Betreten eines Boss-Raums ein kurzes, bedrohliches Intro (≈ 4,5–5 s): Abdunkeln, Vignette in Boss-Farbe, Kinobalken, Dialog mit Porträt, Name und Text Buchstabe für Buchstabe; am Ende Brüllen und Kamera-Ruck.
  - **Text in echten deutschen Worten, der Ton ist Gebrabbel** (Projektmitglied): synthetische Silben je Boss, synchron zum Text, ohne Bedeutung (`audio/sfx/babble_<boss>_1..6.wav`).
  - Keine globale Pause (D-088): Der Boss ist passiv und unverwundbar. Der Spieler steht still (Projektmitglied 14.10.2026): Eingabesperre je Spieler `Player.set_input_locked(&"boss_intro")`, nur Zielen bleibt; gelöst bei Intro-Ende, Sicherungszeit oder Tod des Bosses. Überspringen mit E/Leertaste/Klick/Enter nach 0,4 s Schonzeit; Sicherung: Boss gibt sich nach Dauer + 2 s selbst frei.
  - Zeilen je Boss in `enemies/data/boss_*.tres` (`intro_lines`), Wahl nach Boss-Stufe ohne Zufall. Ohne Daten: das bisherige Boss-Banner.
  - TESTWERTE: 0,04 s je Buchstabe, 0,14 s nach Satzzeichen, 0,42 s Haltezeit je Zeile.
- **Ergänzung 14.10.2026 (BI2, Wunsch Projektmitglied: „jedes Mal, beim ersten Mal länger mit Story, später 1–2 Sätze“):** Erste Begegnung je Boss und Spielstand = **Story** mit 6 Zeilen (`EnemyData.intro_story`, 1,1 s Lesezeit je Zeile, ca. 15–19 s); später eine **Kurzfassung** mit 1–2 Sätzen (`intro_lines`, `|` trennt Zeilen), gewählt nach (Boss-Stufe + gestartete Runs) ohne Zufall. Story: Tippen zeigt die Zeile ganz bzw. springt weiter, **0,7 s Halten** überspringt alles (Balken im Dialog); Kurzfassung: Tippen überspringt. Gesehen-Flag `boss_intro_<boss>` (`SaveManager.mark_seen`); alte Stände mit „alles gesehen“ zählen dafür **nicht** als gesehen. Das Intro hält die Bossmusik je Zeile zurück. TESTWERTE: Lesezeit, Haltezeit.
- **Ergänzung 14.10.2026 (Projektmitglied):** Die Story kommt **nur beim ersten Treffen** und dauert **etwa 10 s**: je Boss 4 Zeilen, die Welt und Boss erklären, Lesepause 0,7 s je Zeile (TESTWERT, 9–11 s je nach Sprechtempo). Lore (das „Erste Licht“, die vier gefallenen Hüter, der Spieler als Docht, Seelenkristalle als Reste verloschener Seelen) ist damit freigegeben, solange sie zum Spiel beiträgt.
- **Folgen:** `ui/boss_intro/`, `enemies/boss_intro_rules.gd`, `enemy_base.gd`, `enemy_data.gd`, `dungeon_manager.gd` (`_announce_boss`), `dungeon_ui.gd` (Hinweiskarte erst nach dem Intro), `tools/generate_audio.py`, Test `test_boss_intro.gd`.

### D-099 – Waffen-Grafiken und Effekte über Signale (C2)

- **Status:** VERBINDLICH · **Datum:** 2026-10-14 / Claude
- **Beschluss:** Dolche und Kriegshammer nutzen die gelieferten Sprites/Icons (SPRITES_V3 §1), die Dolch-Spezialattacke das Wurfmesser. Der `WeaponController` entscheidet und macht Schaden; Effekte laufen nur über seine Signale (`muzzle_flashed`, `spin_started`, `area_resolved`, `attack_cancelled`, `slam_swing_started`) und werden von `WeaponFx` bzw. `Player` dargestellt (Multiplayer: entfernte Spieler spielen dieselben Signale ab). Effektgrößen entsprechen dem echten Trefferradius inkl. AoE-Bonus. Der Hammer schwingt einseitig auf das Ziel und bleibt 0,15 s liegen (TESTWERT). Nova-Farbe = Projektilfarbe des Stabs.
- **Folgen:** `player/weapon_controller.gd`, `weapons/effects/weapon_fx.gd`, `weapons/data/dagger.tres`, `hammer.tres`, `player/player.gd`, Test `test_weapon_art.gd`.

### D-100 – Raumarten Normal / Arena / Abgrund, Formen statt „Strukturiert“

- **Status:** VERBINDLICH (Raumkonzept vom Projektmitglied bestätigt) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Raumarten sind **Normal** (`normal`), **Arena** (`arena`, Wellen) und **Abgrund** (`chasm`). Die Raumart „Strukturiert“ entfällt: Innenmauern, Säulen, Engstellen sind **Formen** und **Zutaten** des normalen Kampfraums ([KONZEPT_RAEUME.md](KONZEPT_RAEUME.md) §3). Gewichte ab Raum 6: Normal 40 / Arena 35 / Abgrund 25, kein Abgrund zweimal hintereinander; Raum 1–5 nur normale Kampfräume. Raumarten, Formen und Größen werden im Spiel **nie angezeigt**.
- **Ersetzt:** D-086 (Raumart-Liste und Gewichte; Abgrund-Regeln bleiben), PRD 7.4. Umsetzung: Nacharbeit A1 in ROADMAP_AUSBAU.

### D-101 – Kampf-Varianten

- **Status:** VERBINDLICH · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Ab Raum 6 sind **20 %** der Kampfräume (Plätze 1–3) Kampf-Varianten (Seelenflamme, Beschwörungsrisse, Steinwächter, Laternenträger, Totengräber, Kopfgeld, Fackelraum; Elite-Nest nur über Abzweigungen), nie zwei hintereinander. Eine Variante ist abgeschlossen, wenn alle Gegner besiegt sind; Misserfolg kostet nie den Run, Erfolg gibt eine Bonus-Truhe (Inhalt `OFFEN`, KONZEPT_RAEUME §9.4).

### D-102 – Gewichtete Spezialräume, neuer Typ Prüfungsraum

- **Status:** VERBINDLICH · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Platz 4 im Zyklus wird **gewichtet** gezogen: Shop 35, Waffenauswahl 20, Brunnen 15, Extra-Upgrade 15 (davon ⅓ als Pakt-Altar), **Prüfungsraum** 15 (Spießrutenlauf, Bröckelboden, Lichtlauf). Der vorherige Typ wiederholt sich nicht, die 30-%-Portalchance bleibt. Prüfungen: direkter Weg zum Ausgang immer frei, Fehler kosten Schaden (meist ½ Herz), nie den Run; makellos = +1 Kristall.
- **Ersetzt:** D-005 (gleichgewichtete Spezialräume), PRD 4.1.

### D-103 – Lagerfeuer nach jedem Boss

- **Status:** VERBINDLICH · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Nach jedem Boss (15, 30, 45 …) folgt ein **Lagerfeuer** als Zwischenraum, der nicht als Raum zählt (Raumnummer, Skalierung, Heilung alle fünf Räume unverändert). Übergangs-Tiles vom alten ins neue Biom, Musik klingt aus. Eine Wahl: heilen (+4 HP) oder ein stapelbares Upgrade um einen Stack stärken. Koop: jeder wählt für sich.
- **Umgesetzt 14.10.2026 (A6), vom Projektmitglied bestätigt, abschaltbar über `DungeonManager.CAMPFIRE_EXIT_PORTAL`:** Das Portal nach dem Boss steht nicht mehr im Bossraum (ändert D-073), sondern am Lagerfeuer; der Bossraum zeigt das Banner „Ein Lagerfeuer wartet“. TESTWERTE: Heilen +4 HP, Dunkelheit 0,9. Empfehlung: Am Lagerfeuer steht immer ein **Exit-Portal** (100 % Gold, wie D-006). So gibt es nach jedem Boss einen sicheren Ausstieg und die Entscheidung „Gold sichern oder tiefer“ bekommt einen festen Rhythmus. Die Raum-45-Wahl aus KONZEPT_RAEUME §6.3 entfällt (KONZEPT_ENDLOS: kein Ende bei Raum 45); das zufällige Portal in Spezialräumen (30 %) bleibt.
- **Ergänzt:** D-005.

### D-104 – Wagnis-Altar

- **Status:** VERBINDLICH · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Auf **12 %** der normalen Kampfräume ab Raum 6 steht hinter dem Eingang ein Altar mit **einer** Bedingung (Prüfung: kein Treffer, unter 30 s, nur Zweitwaffe; oder Fluch: Lichtkreis −40 %, Gegner +15 % Tempo, keine Heilung im Raum). Annehmen mit E, solange die Tür offen ist. Erfolg: Belohnung (`OFFEN`), Misserfolg: keine weitere Strafe. Koop: Bedingung gilt für die Gruppe.

### D-105 – Wegführung: Ausgänge an allen Seiten, Abzweigungen zu Raum n+1

- **Status:** VERBINDLICH · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Ausgänge liegen oben, links oder rechts, nie auf der Eingangsseite. Höchstens einmal pro Zyklus ab Raum 6 gibt es eine **Abzweigung** mit zwei Ausgängen und Symbolen; beide führen zu Raum **n+1**, Zyklus, Raumnummer und Skalierung bleiben gleich. Geheimräume hinter rissigen Wänden zählen nicht als Raum. Koop: Tür öffnet, wenn alle davor stehen; bei Uneinigkeit nach 10 s Mehrheit, sonst Zufall (Dungeon-RNG).

### D-106 – Reihenfolge: erst spielbar und alle Räume, dann Multiplayer, KI-Bosse zuletzt

- **Status:** VERBINDLICH · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Bestätigt und präzisiert D-088: Phase 1 „spielbar für mich“ (Hauptmenü, Spielstände, UX, Dorf), Phase 2 **der gesamte Raum-Content** aus KONZEPT_RAEUME als Einzelspieler, Phase 3 Multiplayer und Plattform, Phase 4 KI-Bosse (KI1/KI2 dürfen vorgezogen werden). Das Plattform-Repo darf jederzeit parallel entwickelt werden. Jedes Paket der Phase 2 beantwortet den **Koop-Check** in ROADMAP_AUSBAU, damit MP1 klein bleibt; Abgrund (A4) und Licht-Varianten (A9) sind die Pakete mit dem meisten Koop-Bezug und werden besonders darauf geprüft.
- **Gründe:** Das Projektmitglied will zuerst den ganzen Einzelspieler-Content spielen. Der Mehraufwand für MP1 bleibt durch die Leitplanken gering; das Risiko liegt vor allem in Spielerzustand und Lichtabfragen, die das Raumkonzept bereits mehrspielerfähig beschreibt.
- **Ergänzt:** D-088.

### D-107 – Dorf mit Tageszeit

- **Status:** VERBINDLICH (Wunsch Projektmitglied: „abends dunkler, an Zeit anpassen“) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** Das Dorf folgt der **lokalen Uhrzeit**: tagsüber (7–17:30 Uhr) hell, Abenddämmerung bis 20 Uhr in warmem Violett, Nacht (20–5 Uhr) in tiefem Blau mit Dunkelheit 0,6, Morgendämmerung bis 7 Uhr. Umsetzung über das Vision-Overlay wie im Dungeon (D-067): Der Spieler hat einen Lichtkreis (320 px), jede Laterne eine Lichtquelle (170 px; seit R7 192 px = 3 Kacheln, D-138). Glühwürmchen ab 19 Uhr, Pollen tagsüber (B3). Reine Optik, keine Spielwirkung.
- **Folgen:** `world/village/village_daylight.gd`, `scenes/world_controller.gd`, `world/village/village.gd`, Test `test_village_daylight.gd`.

### D-108 – Zielbild Crossplay: Steam, Google Play, App Store

- **Status:** VORGESCHLAGEN (Ziel vom Projektmitglied genannt am 14.10.2026; Details **OFFEN**) · **Datum:** 2026-10-14 / Projektmitglied, Ausarbeitung Claude
- **Kontext:** D-083 und ROADMAP_MULTIPLAYER planen bisher nur PC über Steam (Steam-Lobbys, Steam-Relay) und eine Anmeldung über Steam-ID oder Geräte-ID. Das Projektmitglied will Soulwick zusätzlich auf Google Play und im App Store anbieten und **plattformübergreifend zusammen spielen** lassen (wie Among Us). Steam-Lobbys funktionieren nur zwischen Steam-Konten; Mobil-Spieler brauchen eine plattformneutrale Stelle.
- **Beschluss:**
  - **Zielbild:** Soulwick erscheint auf **Steam, Google Play und im App Store**; Spieler aller drei Plattformen können **gemeinsam** spielen und sich in gemeinsamen Gilden und Ranglisten finden (Details in CP0).
  - **Konto-Modell als Grundlage:** Ein **Soulwick-Konto** (Spieler auf dem Server), an dem **mehrere Plattform-Identitäten** hängen (`steam`, `device`, `google_play`, `game_center`), ohne E-Mail und Passwort; Geräte werden per Verknüpfungscode verbunden; Konto löschen in-App (Store-Pflicht). Jetzt wird nur die Datenbank vorbereitet (`player_identities`, Plattform P-014 / ROADMAP P11); Verknüpfungs-Routen erst nach CP0/CP1.
  - **Geschäftsmodell OFFEN:** mobil kostenlos + PC bezahlt (wie Among Us) oder überall kostenlos mit Kosmetik später; entscheidet das Projektmitglied mit dem Team (CP0, CP6).
  - **Empfehlung des Spiel-Orchestrators (Vorschlag, Entscheidung in CP0):** eigene Lobbys mit Raumcode und ein eigener Relay-Container `soulwick-relay` auf dem eigenen Server statt reinem Steam-Relay; Steam-Einladungen (MP6) bleiben als Zusatz für PC-Gruppen.
- **Gründe / verworfene Alternativen:** Nur Steam (kein Crossplay) widerspricht dem genannten Ziel. Reine Plattform-Konten ohne Verknüpfung machen Cross-Progression und gemeinsame Gilden unmöglich. Ein E-Mail-Konto bringt Passwort-Reset und mehr personenbezogene Daten ohne Nutzen. Zwei Identitätsspalten am Spieler (`steam_id`, `device_id`) skalieren nicht auf vier Provider; der Umbau ist vor dem ersten Deployment am billigsten.
- **Folgen:**
  - Erweitert die Datenkategorien aus D-083, D-093 und AGENTS.md Regel 6 der Plattform („nur Steam-ID bzw. Geräte-ID“) um **Google-Play-Games-** und **Game-Center-IDs** (jeweils nur die Nutzer-ID des Providers); Datenschutzerklärung entsprechend ergänzen (eRecht24, Plattform P-013).
  - Lobby/Relay **perspektivisch auf dem eigenen Server**: Fällt CP0 Frage 3 für den eigenen Relay aus, wird D-083 („kein Echtzeit-Spielverkehr über den Server“) zu „Weiterleitung ja, Spiellogik nein“ geändert; das Host-Modell bleibt.
  - Plattform: Tabelle `player_identities` ersetzt `players.steam_id`/`device_id` (P-014, ROADMAP P11); der Vertrag von `/auth/dev` und `/auth/steam` bleibt unverändert.
  - Neue Roadmap [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) (CP0–CP6) als Phase nach dem Multiplayer; Verweise in AGENTS.md §3 und ROADMAP_MULTIPLAYER „Überblick“. Website (Plattform P9): Steam, Google Play, App Store als „geplant“ mit Crossplay-Hinweis.
  - **Zu entscheiden vor MP2** (CP0): Geschäftsmodell, Konto-Modell, Lobby/Relay, Plattform-Reihenfolge, Touch-Steuerung, Altersfreigabe, Ranglisten je Plattform oder gemeinsam.
- **Ergänzt:** D-083, D-093. **Ersetzt:** keine.
- **Teilweise entschieden in D-119, D-121, D-122** (Relay, Plattform-Reihenfolge und Publisher; Konto-Modell; Zusammenführen von Konten). Geschäftsmodell, Touch, Altersfreigabe, Ranglisten je Plattform und Relay-Regionen bleiben OFFEN (CP0).

### D-109 – Belohnungen der neuen Räume

- **Status:** VERBINDLICH · Werte **TESTWERT** · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:**
  - **Bonus-Truhen** (Kampf-Varianten bei Erfolg, tiefste Katakomben-Sackgasse, Ende eines Prüfungsraums) geben eine **Upgrade-Auswahl** über den vorhandenen Dialog.
  - **„Makellos“** (Prüfung ohne Treffer) und erfüllter **Wagnis-Altar** geben **Seelenkristalle** (TESTWERT 1 bzw. 1–2). Gold vorerst nicht, solange die Goldwerte im PRD OFFEN sind.
  - Der seltene **wandernde Händler** in Geheimräumen nutzt die Preisformel des normalen Händlers, bietet aber seltenere Ware (z. B. seltene Upgrades).
  - **Koop-Skalierung** der Varianten (Seelenflamme-HP, Anzahl Risse/Wächter, Truhen je Spieler) wird jetzt nur als Parameter vorbereitet und in MP5 (Koop-Gefühl) mit echten Tests festgelegt.
- **Ergänzt:** D-101, D-102, D-104, D-105; beantwortet KONZEPT_RAEUME §9.4.

### D-110 – Raum-Genres anzeigen und beim ersten Mal erklären, einheitliche Mauern

- **Status:** VERBINDLICH (Playtest-Rückmeldung) · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:**
  - **Normale Kampfräume** (alle Formen: Rechteck, L, Kreuz, Ring, Kammern, Säulenhalle) werden **nicht** benannt.
  - **Räume mit eigenem Gameplay** zeigen beim Betreten ihren Namen als Banner: Arena, Katakombe, Abgrund, jede Kampf-Variante (z. B. „Seelenflamme“), Prüfungsraum, Pakt-Altar, Wagnis-Altar, Lagerfeuer und die Spezialräume.
  - **Beim ersten Mal je Spielstand** erscheint zusätzlich eine kurze Erklärkarte (1–2 Sätze, was zu tun ist und was es bringt), einmal pro Raum-Genre (`SaveManager.has_seen("room_intro_<genre>")`), ohne globale Pause, im Stil der Steuerungs-Hinweise.
  - **Mauern:** Jede Mauer sieht aus wie die Außenwand (Krone mit heller Kante zu jedem angrenzenden Boden, eine Reihe Ziegel-Vorderseite nach Süden), Grafik-Briefing `SPRITES_V6.md`.
- **Ersetzt:** D-100 (Satz „Raumarten werden im Spiel nie angezeigt“) und D-095 (Anzeige) für die genannten Genres.

### D-111 – Zwei Sprachen: Englisch Standard, Deutsch zweite Sprache

- **Status:** VERBINDLICH · **Datum:** 2026-10-14 / Projektmitglied (übermittelt über die Plattform-Sitzung)
- **Beschluss:** Spiel und Website gibt es auf **Englisch (Standard)** und **Deutsch**. Das Spiel erkennt die Sprache aus dem System und lässt sie in den Optionen umschalten. Spieltexte laufen über Übersetzungsschlüssel (`localization/translations.csv`, Hilfsklasse `Loc`, Registrierung zur Laufzeit über `TranslationServer`); Doku bleibt Deutsch. Website: playsoulwick.com.
- **Folgen:** Paket UX3 (Sprachen und Einstellungen, Hauptmenü und Optionen), danach Migration der übrigen UI-Texte (Dungeon-Dialoge in UX2, HUD, Dorf). Neue UI-Texte ab jetzt als Schlüssel.

### D-112 – Prüfungsräume und Pakt-Altar: Ausgestaltung (A8)

- **Status:** VERBINDLICH (Regeln D-102, D-109) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Beschluss:**
  - Prüfungsraum mit eigener Vorlage (17×10): Der Ausgang ist immer ohne Parcours erreichbar, die Truhe ist von Anfang an sichtbar, nach der Truhe öffnet ein Tor als Rückweg. Spießrutenlauf und Lichtlauf je 50 %, Bröckelboden erst mit A4.
  - Fehler kosten 1 HP (½ Herz) und lassen mindestens 0,5 HP übrig, danach 0,6 s Sperre; im Dash kein Fehler. Dunkelheit im Lichtlauf: 1 HP pro 2 s am Stück. „Makellos“ = kein Fehler im ganzen Raum → +1 Kristall je Spieler. Die Truhe öffnet einmal für die Gruppe (Schalter `CHEST_FOR_EVERY_PLAYER` für MP5).
  - Pakt-Altar: Fluch wird je Raum gezogen und am Altar angezeigt; Pakt = Auswahl aus 3 Upgrades, das gewählte steigt um +2 Stufen. Flüche je Spieler (`PlayerCurses`), jeder Fluch höchstens einmal, −1 Max-Herz nie unter 1 Herz.
  - Prüfungen tragen ihr Schild im Raum („Spießrutenlauf“, „Lichtlauf“), passend zu D-110. Ein Seltenheitssystem für Pakt-Upgrades ist eine Idee für später.

### D-113 – Raumformen, Zutaten, Arena-Wellen und Wegfindung: Ausgestaltung (A2, A3, A5)

- **Status:** VERBINDLICH (Regeln D-086, D-100, D-109, D-110) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Formen (A3):** 26 Vorlagen mit `RoomTemplate`-Resource: Normal = Rechteck, L-Form, Kreuz, Ring, Zwei Kammern, Säulenhalle je S/M/L sowie Katakombe M/L (1 Tile breite Gänge, genau 2 Sackgassen, höchstens 2 Abzweigungen, Truhe in der tiefsten Sackgasse); Arena = Rechteck M/L, Kreuz M/L, Säulenhalle M/L. Fehlt eine Vorlage der gezogenen Art, gilt Normal. Mauern außen und innen aus einer Boden-Maske (Krone, Kante zum Boden, eine Reihe Front nur über Boden), ausgesparte Bereiche wie Fels außerhalb.
- **Zutaten (A3):** 2–3 je Raum aus einem Satz je Biom (Deckung, Fallengruppe, Innenmauer-Stück, Engstelle/Nische, Lichtinsel + Dunkelzone, Explosionsfässer ab Raum 3 in Krypta/Glutkammer); ein Wurf aus dem Dungeon-RNG je Raum; jede vorher erreichbare Kachel bleibt erreichbar. Fass: Schaden Spieler 1 / Gegner 30, Radius 96 px, Zündung 0,7 s. Dunkelzone Sichtfaktor 0,6. Gegnergruppen ab Raum 6: gemischt 70 / Fernkampf 15 / Schwarm 15; stiller Raum 8 % (nur Normal, 1–2 Gegner, gleiche Gesamt-HP). Vorlagen-Fackeln mindestens 4 Tiles von der Tür.
- **Arena (A5):** 2 Wellen, ab Raum 15 drei; Wellengröße normaler Wurf ×0,75 (mindestens 2 und der kleinste Normalwert); nächste Welle bei höchstens 1 übrig (normale Räume: 0). 5 feste Tore auf mindestens 2 Wänden, jede Welle aus mindestens 2 Wänden und mindestens 96 px von jedem Spieler; Gegner 0,55 s verborgen + 0,35 s Heraustreten (passiv, unverwundbar). Hinterhalt 25 % der Arenen: leer bis die Eingangstür schließt, dann nach 0,3 s aus mindestens 3 Wänden. Überlauf: mehr Gegner als Punkte/Tore → zusätzliche Welle (erledigt den offenen Punkt aus D-095).
- **Wegfindung (A2):** Navigation über die Navigationsebene der Dungeon-Tilesets (Boden und Brücken begehbar, Wände/Innenmauern/Abgrund nicht), eine Navigationskarte je Raum; Pfad nur, wenn Tiles die Sicht blockieren; Ziel = nächster lebender Spieler, neu gewählt alle 0,5 s, Wechsel ab 48 px Vorsprung. Sichtcheck 0,15 s, Pfad 0,35 s.
- **Offen (Balance-Agent):** Arenen sind laut Bot merklich härter (Raum 16–29 mehr Tode, +55 % Zeit je Kampfraum); der Knochenkönig ist seit der Wegfindung tödlicher. Nachmessen und Werte anpassen.
- **Nachtrag 16.10.2026 (Claude, TESTWERT):** Die Sichtprüfung der Wegfindung schaut an bis zu `EnemyNavigation.LOOK_PAST_BODIES = 2` Körpern außerhalb der Navigation (Requisiten wie Fackelständer, Kristalle) vorbei auf Wand oder Abgrund dahinter. Vorher galt eine Requisite vor einer Wand als bloße Requisite, der Gegner lenkte ohne Pfad um sie herum und pendelte an der Wand. Test: `tests/unit/test_enemy_nav_props.gd`; `tools/boss_sim.gd` nimmt jetzt `-- seed=N` und wartet auf den Navigationsabgleich statt fester Frames.

### D-114 – Kampf-Varianten I und Wagnis-Altar: Ausgestaltung (A7)

- **Status:** VERBINDLICH (Regeln D-101, D-104, D-109) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Ziehung:** `dungeon/variants/variant_table.tres`; ab Raum 6 je normalem Kampfraum (Plätze 1–3) 20 % Variante, gleich gewichtet (Seelenflamme, Beschwörungsrisse, Totengräber nur Krypta, Kopfgeld), nie direkt nach einer Variante (tatsächlicher Anteil dadurch ca. 17,6 %). Von den übrigen Kampfräumen 12 % Wagnis-Altar. Ein Variantenraum ist Raumart Normal; passt die Variante nicht in die Form (Flamme braucht 3×3 freie Fläche), bleibt der Raum normal. Drei Zufallswerte je normalem Kampfraum, einer mehr beim Anhängen.
- **Seelenflamme:** 16 Grundtreffer, skaliert mit dem Gegnerschaden; 40 s Angriffswellen alle 10 s oder bei ≤ 1 Gegner (Abstand ≥ 3 s, Größe 60 % eines normalen Wurfs, mindestens 2); 70 % der Gegner greifen die Flamme an, nur Gegnerschaden zählt; erloschen = keine Truhe, Lichtkreis ×0,8, der Kampf geht weiter. Der Raum schließt nicht vor Ende der Angriffszeit.
- **Beschwörungsrisse:** 2–3 an Wänden, 40 HP (skaliert), rufen alle 4 s einen Gegner (0,7 s Vorwarnung), solange < 6 leben; erste Welle ×0,7.
- **Totengräber:** Skelette mit Gewicht ×3; Knochenhaufen 5 s, dann Aufstehen mit 50 % HP, höchstens einmal je Skelett; Zerstören durch Treffer oder Drüberlaufen; Gold beim endgültigen Tod.
- **Kopfgeld:** ein Gegner mit Krone sieht Spieler bis 320 px bei freier Sicht und flieht mit ×1,1 Tempo zu einem Loch ≥ 5 Tiles entfernt; nach 12 s ist er weg (ohne Gold), der Raum schließt normal.
- **Erfolg:** Bonus-Truhe (Upgrade-Auswahl, D-109), eine für die Gruppe. Bei Rissen und Totengräber gilt vorerst „Raum geschafft = Bonus“ (Schalter `GRAVEDIGGER_BONUS_NEEDS_NO_RISE` für die strengere Regel).
- **Wagnis-Altar:** neben dem Eingang, Annehmen mit E nur vor dem Betreten; Prüfungen kein Treffer / unter 30 s / nur Zweitwaffe (nur mit zweiter Waffe), Flüche Lichtkreis −40 % / Gegner +15 % Tempo / keine Heilung im Raum; Erfolg 2 Kristalle („kein Treffer“), sonst 1, je Spieler.
- **Koop-Parameter (für MP5):** Flamme +50 % HP je weiterem Spieler, +1 Riss je weiterem Spieler, Truhen je Spieler aus.
- **Offen (Projektmitglied):** Bonus beim Totengräber nur ohne Aufstehen? Wagnis-Kristalle 2/1 passend? Variantenanteil auf echte 20 % ausgleichen? Wagnis-Banner schon beim Öffnen der Tür?

### D-115 – Abgrund und Brücken: Ausgestaltung (A4)

- **Status:** VERBINDLICH (Regeln D-086, D-100, D-110, D-112) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Physik:** Ebene 7 `pit` (`PhysicsLayers.PIT = 64`): Gegner haben sie in der Maske, Spieler und Geschosse nicht. Abgründe haben keine Navigation; Brücken sind begehbar.
- **Spieler:** Fallprüfung an den Füßen mit 8 px Toleranz an Kante und Brücke; im Dash in der Luft; ohne Dash über dem Abgrund nach 0,1 s Sturz, 0,5 s Animation mit gesperrter Eingabe, **2 HP (ein ganzes Herz)** am Schild vorbei (kann töten), Rücksetzen an die letzte sichere Stelle (≥ 20 px vom Abgrund, am Spieler gespeichert), 1 s unverwundbar. Todesursache „Abgrund“.
- **Gegner:** fallen nur bei Rückstoß > 250 px/s, wenn der Abgrund auf dem Rückstoßweg liegt; zählt als Kill, Gold am Rand. Champions, Golems und Bosse fallen nie; Sprünge, Teilungen und Teleports landen nie im Abgrund.
- **Abgrundräume:** Brückenhalle, Inseln, Steg, Ring um ein Loch je S/M/L, ab Raum 6; jeder Boden zu Fuß erreichbar (keine Dash-Inseln), mindestens eine Dash-Abkürzung über 1 Tile; Zutaten nur Deckung, Fallen, Licht, Fässer.
- **Kleine Löcher:** 1–2 je Raum, Gewicht 0,7, ab Raum 6, nicht in Katakombe und Abgrundraum; erstes Loch erklärt einmal den Dash.
- **Bröckelboden-Prüfung:** je Bahn eine offene Lücke, Platten brechen 0,6 s nach dem Betreten und wachsen nach 5 s nach, 40 % feste Platten je Spalte; Sturz = Fehler, landet auf der letzten festen Kachel, kostet 2 HP, gedeckelt auf mindestens 0,5 HP Rest. Ziehung je ⅓ Spießrutenlauf, Lichtlauf, Bröckelboden.
- **Einstieg:** Katakombe frühestens ab Raum 2 (`RoomTemplate.min_room`).
- **Hindernisse und Navigation (Integrator):** Jede feste Requisite (Kiste, Fass, Schutt, Lichtsockel) nimmt ihrer Kachel die Navigation, bis sie zerbricht.
- **Offen (Projektmitglied):** Bröckelboden-Sturz ganzes Herz oder ½ Herz wie andere Prüfungsfehler? Löcher auch in Arenen (heute ja)?

### D-116 – Licht-Varianten: Ausgestaltung (A9)

- **Status:** VERBINDLICH (Regeln D-101, D-109) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Licht-Abfrage (`LightQuery`):** Ein Punkt ist „im Licht“, wenn er im Kreis eines lebenden Spielers liegt (sichtbarer Radius − 75 px, Radius als Zustand am Spieler) oder im Kreis einer Lichtquelle mit `counts_as_light` (80 % ihres Radius: Lichtinseln, Laterne, Fackeln, Sockel, im Steinwächter-Raum die Wandfackeln). Blitze, Geschosse und Gegner-Glühen zählen nie. Der Lichtlauf nutzt denselben Kreistest.
- **Ziehung:** Steinwächter (Krypta, Schattenreich), Laternenträger (alle Biome), Fackelraum (nur Schattenreich), gleich gewichtet mit den Varianten aus D-114.
- **Steinwächter:** 2–4 (+1 je weiterem Spieler, MP5), 48 HP, Schaden 1, Tempo 140; im Licht erstarrt und verwundbar, im Dunkeln unverwundbar; Angriff nur Sprung-Stampfer (0,8 s Vorwarnung, Radius 64), Licht bricht das Ausholen ab, ein begonnener Sprung wird beendet; normale Gegner ×0,7; Raum geschafft = Bonus.
- **Laternenträger:** Laterne liegt am Eingang (KONZEPT_RAEUME §4.4), Sockel vor dem Ausgang; Lichtkreis ×0,55; Träger ×0,75 Tempo, kein Angriff, Dash bleibt (Zustand `LanternCarry` am Spieler); Welle ×0,6 beim ersten Aufnehmen, 60 % der Gegner bevorzugen den Träger; Bonus nur bei Einsetzen in 40 s, danach kehrt die Laterne von selbst heim; der Ausgang öffnet erst mit Laterne im Sockel.
- **Fackelraum:** 4–6 Fackeln (Treffer oder E), Lichtkreis ×0,5 bis ×1 je nach Anteil brennender Fackeln; Gegner im Fackellicht ×0,8 Schaden; alle Fackeln brennen = Bonus.
- **Offen (Projektmitglied):** Laterne am Eingang statt bei einem Gegner? Heimkehr nach 40 s ohne Bonus? Sprung aus dem Dunkeln als Steinwächter-Bedrohung? Markierung für geschwächte Gegner im Fackellicht?

### D-117 – Wegführung: Ausgestaltung (A10)

- **Status:** VERBINDLICH (Regeln D-101, D-105, D-109, D-110) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Ausgänge:** Nord 50 / Ost 25 / West 25, nie die Eingangswand; vor Spezial-, Miniboss-, Boss- und Lagerfeuerraum immer Nord. Eingang gegenüber dem vorigen Ausgang; Katakombe nur Süd/Nord. `entrance_x`/`exit_x` sind der Platz entlang der jeweiligen Wand.
- **Überlappung:** Lebende Räume dürfen nur Fels auf Fels teilen; bei Kollision verlängert sich der Eingangsgang (höchstens 24 Kacheln, im Test 0–5). Abbiegungen, die einen längeren Gang bräuchten, entfallen schon bei der Ziehung.
- **Abzweigungen:** ab Raum 6, höchstens 1 je Zyklus, 30 % der Kampfräume ohne Variante. Vor Platz 4 zwei verschiedene Spezialräume (Nordtüren), sonst Elite-Nest 60 % oder unbekannte Variante 40 % gegen den sicheren Weg (West/Ost). Raum n+1 entsteht bei der Wahl, die andere Tür wird versiegelt; Koop: alle vor einer Tür sofort, sonst nach 10 s Mehrheit, Gleichstand über den Dungeon-RNG.
- **Elite-Nest:** 65 % 2–3 Elites, 35 % 1 Champion mit 1–2 Begleitern; Bonus-Truhe und 2 Kristalle für die Gruppe.
- **Geheimnische:** 1/8 der Normal- und Abgrundräume ab Raum 6, nicht in Arenen; hinter einer rissigen Wand (Nordwand oder dicke Innenmauer), öffnet nur durch Explosionen und Flächentreffer. Inhalt Truhe 55 / 2 Kristalle 35 / wandernder Händler 10 (3 Mechanik- oder Effekt-Upgrades zum Shop-Preis).
- **Zufall:** je normalem Kampfraum 8 zusätzliche Werte des Dungeon-RNG (Ausgang 1, Abzweigung 4, Nische 3).
- **Offen (Projektmitglied):** längerer Gang statt „nach oben ausweichen“ ok? Elite-Nest 2 Kristalle richtig? Händler nur Mechanik-/Effekt-Upgrades? Abzweigung ohne Bestätigung im Einzelspieler? Abzweigung in etwa zwei Dritteln der Zyklen zu oft?

### D-118 – Balance nach dem Raum-Ausbau und Playtest „mehr los, einzeln schwächer“

- **Status:** VERBINDLICH (TESTWERTE) · **Datum:** 2026-10-14 / Claude im Auftrag des Projektmitglieds (Balance delegiert; Playtest-Rückmeldung 14.10.2026 umgesetzt, sie hat Vorrang vor dem Bot)
- **Anlass:** Nach Phase 2 erreichte der Bot mit dem Schwert nur noch Raum 16–22. Messung mit `balance_sim.gd` und einer Mess-Kopie (feste Dungeon-Seeds, Todesursache je Fallenart, Raumart/Variante/Gegnergruppe je Raum, Giftpfützen und Lavaspalten werden wie Stachelfallen umgangen): Knochenkönig tötete 38 % der Schwert-Bots, Schattenlord 100 % aller Waffen; Seelenflamme und Beschwörungsrisse waren die tödlichsten Kampfräume (Risse mit Bogen: Tod in 50 % der Rissräume); reine Fernkampf-Gruppen fünfmal so viel Schaden wie gemischte. **Fallen** als Todesursache waren fast nur Giftpfützen der Schleimgrotte, die der Bot nicht umgeht (Messartefakt; mit Umgehen 0–1 Tode je 80 Runs, Stachelfallen 1–2; Prüfungsräume können nicht töten, Abgründe kosten den Bot nichts, weil er nie fällt). Playtest: Balance insgesamt gut, aber zu wenig los (ein Gegner, nächster Raum), Arena zu früh und zu dünn (Raum 6: 1 Slime, sofort „Welle 2 von 2“).
- **Messung** (Mess-Kopie, Gift/Lava umgehen, gleiche Dungeon-Seeds, Schwert 40 / Bogen 20 / Stab 20 Runs; erreichte Räume Median, Boss 15/30/45 geschlagen):

| Waffe | vorher | nachher |
| --- | --- | --- |
| Schwert | Median 18 · 57 % / 29 % / 0 % | Median 34 · 92 % / 68 % / 8 % |
| Bogen | Median 36 · 87 % / 73 % / 0 % | Median 45 · 100 % / 87 % / 27 % |
| Stab | Median 42,5 · 100 % / 90 % / 0 % | Median 44 · 95 % / 95 % / 10 % |

  `balance_sim.gd` ohne Änderung (Seeds 11–18 / 21–24 / 31–34, je 3 Runs): Schwert Median 16,5 → 32,5, Bogen 29,5 → 37, Stab 30,5 → 45 (Bogen nachher 6 Runs, zwei Prozesse abgestürzt). Schaden je normalem Kampfraum 1–15 unverändert (0,10–0,11 HP), aber 4–5 statt 2–3 Gegner und 25–50 % längere Kämpfe. Schild bei Raum 45 (Wahl „tank“) 13–16, Gold beim Tod 130–166 (2–3 Shop-Käufe).
- **Beschluss (Zahlen, alt → neu):**
  - **Mehr, aber schwächere Gegner (Playtest):** Gegner je Welle Raum 1–3 1–2 → 2–4, Raum 4–14 2–3 → 4–5, Raum 15–29 2–4 → 4–6, ab Raum 30 3–5 → 5–8 (`RoomSequence.get_enemy_count_range`). Alle normalen Gegner HP ×0,6 und Schaden ×0,65: Slime 20/1 → 12/0,65, Skelett 28/1 → 17/0,65, Bogenschütze 16/1 → 10/0,65, Bomber 12/1,5 → 7/1, Schattenwesen 16/1 → 10/0,65, Splitterschleim 26/1 → 16/0,65, Mini-Slime 6/0,5 → 4/0,35, Golem 90/2 → 54/1,3, Nekromant 30/1 → 18/0,65. Ein Treffer kostet damit in Raum 1–10 ½ statt 1 HP, ab Raum 36 1,5 statt 2,5–3 HP. Gold: `gold_drop_factor` 0,7 → 0,4, Champion-Gold ×5 → ×9 (Einkommen je Raum ungefähr wie vorher).
  - **Arena (Playtest):** erst ab Raum 10 (`ARENA_FROM_ROOM` und `RoomSequence.CHASM_FROM_ROOM` 6 → 10, damit die Raumart-Ziehung passt; Abgrundräume damit auch erst ab Raum 10, kleine Löcher weiter ab Raum 6), Wellengröße ×0,75 → ×1,0, mindestens 2 → 3 Gegner, nächste Welle erst, wenn die laufende leer ist (bei ≤ 1 → 0 übrig), dritte Welle ab Raum 15 → 30.
  - **Fernkampf gezielt:** Bogenschütze Abklingzeit 1,6 → 1,8 s; Nekromant Abklingzeit 1,5 → 1,8 s, Beschwörung jeder 3. → 4. Angriff; reine Fernkampf-Gruppen 15 → 10 % (`THEME_WEIGHTS` 0,7/0,15/0,15 → 0,75/0,1/0,15).
  - **Varianten:** Seelenflamme Angriffszeit 40 → 24 s, Mindestabstand der Wellen 3 → 8 s, Wellengröße ×0,6 → ×0,5 (vorher 4–7× der Schaden eines normalen Raums, jetzt 2–3×). Beschwörungsriss 40 → 30 HP. Totengräber, Kopfgeld, Steinwächter, Laterne, Fackelraum, Elite-Nest und Geheimnischen liegen im Bot nahe am normalen Raum: unverändert.
  - **Bosse nur gezielt (Playtest):** Knochenkönig Schaden 1,5 → 1,25 (Treffer in Raum 15: 2 → 1,5 HP), Schleimkönigin Schaden 1,5 → 1,25 (Raum 30: 3 → 2,5 HP), Schattenlord Schaden 1,5 → 0,9 und Abklingzeit 0,9 → 1,1 s (Raum 45: 4,5 → 2,5 HP je Treffer; vorher 0 % Siege). Boss-HP unverändert.
  - **Schwert** Grundschaden 14 → 15 (Startwaffe, im Bot 10 Räume hinter Bogen und Stab).
- **Offen:** Schattenlord bleibt die größte Hürde (Bot gewinnt 10–40 %), Glutgolem (Raum 60) kaum gemessen. Schwert-Bot endet seltener zwischen Raum 40 und 80 als die Fernkampfwaffen (28 % gegen 55–67 %). Champions sind durch die schwächeren Grundwerte rund 40 % schwächer (Champion-Faktor ×3 HP / ×1,5 Schaden ist kein TESTWERT, D-077). Nach dem neuen Gegnerverhalten (Slime-Banden, Flankieren) neu messen.
- **Ersetzt:** Zahlenwerte aus D-074 (Gegneranzahl), D-086/D-100/D-115 (Arena und Abgrundraum ab Raum 6), D-089 (Schwert 14), D-091 (Goldfaktor 0,7), D-113 (Arena-Wellengröße, nächste Welle bei 1, drei Wellen ab Raum 15, Gruppen 70/15/15), D-114 (Seelenflamme 40 s, 3 s, ×0,6; Riss 40 HP) und die Gegner- und Boss-TESTWERTE aus §4 bzw. D-055/D-064.

### D-119 – Crossplay-Architektur: Host + eigener Relay, Steam → Android → iOS, Publisher WebBude

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (ROADMAP_CROSSPLAY CP0 Fragen 3 und 4, Publisher); Ausarbeitung Claude
- **Kontext:** D-108 nennt das Zielbild Crossplay über Steam, Google Play und App Store, ließ aber Lobby/Relay (CP0 Frage 3) und die Plattform-Reihenfolge (Frage 4) offen. D-083 schloss Echtzeit-Spielverkehr über den Server aus; ROADMAP_MULTIPLAYER plante ENet, ein virtuelles LAN (Tailscale) und den Steam-Relay. Keiner dieser Wege bringt Handy und PC in einen Raum.
- **Beschluss:**
  - **Netzwerk:** Host-Modell wie Among Us (ein Spieler rechnet) plus **eigener Relay** `soulwick-relay` auf dem eigenen Server (CP0 Frage 3a). Der Relay vergibt Raumcodes, prüft das Spieler-Token und leitet Pakete weiter; Spiellogik gibt es nur im Spiel.
  - **Transport in Phase 1:** WebSocket-Relay über eine eigene `MultiplayerPeerExtension` in GDScript (`online/relay_peer.gd`) auf Godots eingebautem `WebSocketPeer`; ohne GDExtension auf allen Zielplattformen, keine Portfreigaben. Spielpakete als Rahmen `{from, to, channel, mode, data}`.
  - **Später, ohne Umbau der Spiellogik:** WebRTC-Direktverbindung (Relay bzw. TURN als Rückfall) und ein dedizierter Godot-Server (Export „Dedicated Server“) als Aufrüstungen; ENet bleibt nur optional für LAN und Entwicklung.
  - **Steam ist Zusatz** (folgt aus 3a): Anmeldung, Freunde einladen und „Beitreten“ über Rich Presence mit dem Raumcode; die Verbindung läuft auch für Steam-Spieler über den Relay. Technische Ausgestaltung: Plattform P-017 (VORGESCHLAGEN).
  - **Reihenfolge:** Steam → Android → iOS (CP0 Frage 4); iOS kommt später, weil kein Mac vorhanden ist (Cloud-Mac in der CI).
  - **Publisher:** WebBude (Firmenkonten bei Steam, Google, später Apple).
  - **Weiter OFFEN:** Geschäftsmodell (CP0 Frage 1), Regel für das Zusammenführen zweier Konten (nur Vorschlag), Touch-Schema (der Prototyp in CP2 entscheidet), Relay-Regionen (CP0 Frage 10).
- **Gründe / verworfene Alternativen:** Steam-Lobbys und Steam-Relay verbinden nur Steam-Konten. Ein virtuelles LAN verlangt Zusatzsoftware bei jedem Spieler. ENet über UDP scheitert ohne Portfreigabe oder Hole-Punching an NAT, besonders im Mobilfunk. WebRTC hat weniger Latenz, braucht aber auf dem Desktop eine GDExtension und STUN/TURN-Betrieb; deshalb als spätere Aufrüstung. Ein dedizierter Server bedeutet mehr Betrieb und Kosten und ist nicht nötig, solange ein Spieler hostet. WebSocket ist in Godot auf allen Plattformen eingebaut, TLS übernimmt Traefik.
- **Folgen:**
  - **D-083** gilt mit Änderung: „Weiterleitung ja, Spiellogik nein“. Echtzeit-Pakete laufen über den Relay, gerechnet wird weiter nur beim Host.
  - **D-108** ist teilweise entschieden (CP0 Fragen 3, 4 und Publisher); der Rest bleibt VORGESCHLAGEN bzw. OFFEN.
  - **Überholt** und bei der nächsten Überarbeitung der Dateien anzupassen: ARCHITECTURE.md („Netzwerk-/Server-API: Nicht vorgesehen“, „kein Backend“), MULTIPLAYER.md §1 („kein Matchmaking“) und §4a Stufe 2 (virtuelles LAN), PRODUKT.md („Relay OFFEN“).
  - Roadmaps: ROADMAP_MULTIPLAYER MP2–MP6 auf den Relay umgestellt (MP4 Test-Build über den Relay statt Tailscale, MP6 Steam als Zusatz); ROADMAP_CROSSPLAY CP0, CP3 (Relay), neu CP7 (Build-CI und Stores), Abschnitte „Lokal testen“ und „Dedizierter Server (später)“.
  - Plattform: neuer Dienst `apps/relay` (P-016), Steam nur Zusatz (P-017), Domains `play.playsoulwick.com` und Umgebungen (P-018); Pakete P13–P17 in `soulwick-platform/docs/ROADMAP.md`, Konzept `soulwick-platform/docs/KONZEPT_ONLINE.md`.
  - Datenschutz: Relay-Verbindungsdaten (IP, Spieler-ID, Zeitpunkt, keine Inhalte) und die Plattform-IDs in die Datenschutzerklärung (eRecht24).
- **Ergänzt:** D-083, D-108. **Ersetzt:** keine.

### D-120 – Räume v2: klare Modi, Minispiele, Abgrund-Raumart gestrichen

- **Status:** VERBINDLICH (Gameplay) · Look folgt aus Claude Design · **Datum:** 2026-10-14 / Projektmitglied
- **Beschluss:** [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) gilt: ein Raum = eine Aufgabe in einem Satz, Tür-Erkennung, Intro-Muster (Kameraschwenk, Banner, Countdown), Aufgabenleiste, Misserfolg kostet nur den Bonus. Raumarten: Säubern, Arena (erst kurz vor dem 1. Boss), Minispiele (Geleit, Flamme hüten, Reliquie holen, Seelen sammeln, Risse schließen, Jagd, Lichtfeuer, Einsturz), Ruhe-Räume, Prüfung, Wagnis, Elite-Nest, Miniboss, Boss, Lagerfeuer, Geheimnische. **Hauptsächlich Kämpfen, 30–40 % Minispiele** ab Zyklus 2. **Abgrund als eigene Raumart gestrichen** (nur noch Bauteil der Grundrisse und Kern von Einsturz). Gegner kommen aus sichtbaren Quellen je Biom; mehr, aber schwächere Gegner, Rudel und Flankieren. Eskorte-Figur: verirrter Dorfbewohner, selten ein Huhn (Look offen). Koop-exklusive Raum-Ideen für MP5 vorgemerkt (Konzept §3.11).
- **Folgen:** Phase 2b (ROADMAP_AUSBAU) vor dem Multiplayer; Claude Design liefert Look, Grundrisse, Wand-System, Türen, Dorf und UI (`docs/design/claude_design_antwort/`); danach SPRITES_V8 und Pakete. Ersetzt Teile von D-100, D-101, D-104, D-110, D-114–D-117 (Varianten werden zu Minispielen, Hinterhalt entfällt).

### D-121 – Konto-Modell: ein Soulwick-Konto mit verknüpften Plattform-Identitäten

- **Status:** VERBINDLICH · Werte **TESTWERT** · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (an Claude delegiert), Ausarbeitung Claude
- **Kontext:** D-108 schlug ein Soulwick-Konto mit mehreren Plattform-Identitäten vor; ROADMAP_CROSSPLAY CP0 Frage 2 war OFFEN. Die Plattform hat die Tabelle `player_identities` schon (P11, P-014); Store-Anmeldungen (P14) und Verknüpfen (P15) warten auf diese Entscheidung.
- **Beschluss:**
  - Je Spieler ein **Soulwick-Konto** (der Spieler auf dem Server), **ohne E-Mail und Passwort**. Daran hängen beliebig viele **Plattform-Identitäten**: `steam`, `device`, `google_play`, `game_center` (je Provider nur dessen Nutzer-ID). Jede Anmeldung findet oder erzeugt eine Identität; eine neue Identität ohne Konto erzeugt ein Konto.
  - **Verknüpfen wie bei Among Us:** Ein angemeldetes Gerät erzeugt einen **6-stelligen Code** (Alphabet wie die Raumcodes), **10 Minuten gültig**; das zweite Gerät löst ihn angemeldet ein, seine Identität hängt danach am Konto des ersten. Hat das zweite Gerät schon ein eigenes Konto, gilt D-122.
  - Eine Identität darf entkoppelt werden, die letzte eines Kontos nicht.
  - **Konto löschen** in der App (Konto-Panel → Bestätigung → `DELETE /me`) **und** als Web-Formular für den Löschantrag (Google-Play-Pflicht; Website `/delete-account`, Ablauf mit Löschcode als Vorschlag in `soulwick-platform/docs/KONZEPT_ONLINE.md` §3.7).
  - Entscheidet ROADMAP_CROSSPLAY **CP0 Frage 2: (a)**.
- **Gründe / verworfene Alternativen:** (b) nur Plattform-Konten ohne Verknüpfung macht Cross-Progression und gemeinsame Gilden über Plattformen hinweg unmöglich. (c) E-Mail und Passwort bringen Passwort-Reset, mehr personenbezogene Daten und Angriffsfläche ohne Nutzen; die Store-Anmeldungen reichen. Der Code-Weg braucht keine Zusatzdaten und ist vielen Spielern von Among Us vertraut.
- **Folgen:** Plattform: `player_identities` existiert (P11, P-014); Anmeldung je Provider in **P14**, Verknüpfungscode und Löschantrag-Seite in **P15** (Verträge zuerst in `packages/contracts`). Spiel: Konto-Panel in CP1 (`ui/options/account_panel.gd`), Konto und Token in `online/session.gd` (Node in `game.tscn`, kein Autoload, D-044). Datenschutzerklärung: nur Provider-Nutzer-IDs (eRecht24, P-013). Ohne Konto bleibt das Spiel offline spielbar.
- **Ersetzt:** keine; macht den Konto-Teil von D-108 verbindlich.

### D-122 – Konten zusammenführen

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (an Claude delegiert), Ausarbeitung Claude
- **Kontext:** Beim Verknüpfen (D-121) kann das zweite Gerät schon ein eigenes Konto haben. D-119 und `soulwick-platform/docs/KONZEPT_ONLINE.md` §3.6 ließen die Regel OFFEN (nur Vorschlag); Plattform P15 wartet darauf.
- **Beschluss:** Wird ein Verknüpfungscode eingelöst und beide Geräte haben schon Konten:
  - **Leeres Konto** (keine Gilde, keine Runs): Die Identität wandert ohne Rückfrage, das leere Konto wird gelöscht (KONZEPT_ONLINE §3.5).
  - **Sonst** zeigt das Spiel vorher, welches Konto bleibt, und führt erst nach Bestätigung zusammen (nie still; bis dahin antwortet die API `409 account_has_progress`). Dann gilt:
    - **Bleibendes Konto** ist das **ältere** (früheres `created_at`); es erhält alle Identitäten des anderen.
    - **Name:** der des bleibenden Kontos.
    - **Gilde:** Die Mitgliedschaft des bleibenden Kontos bleibt. Ist es gildenlos, übernimmt es die Mitgliedschaft des anderen.
    - **Run-Berichte** beider bleiben bestehen; die Teilnahmen des anderen Kontos werden auf das bleibende umgehängt.
    - Das **andere Konto wird gelöscht**.
  - **Sperren:** Ist eines der beiden Konten gesperrt, wird **nicht** zusammengeführt; die API lehnt ab, ein Admin prüft manuell.
- **Gründe / verworfene Alternativen:** Die Regel ist vorhersagbar und ohne Vergleich von Inhalten umsetzbar; das ältere Konto hat meist den längeren Verlauf. Niemand verliert unbemerkt seine Gilde, und es entsteht keine doppelte Mitgliedschaft (höchstens eine Gilde je Spieler, D-080). Gesperrte Konten werden nicht automatisch zusammengeführt, damit niemand eine Sperre durch Verknüpfen umgeht oder ein unbeteiligtes Konto mitsperrt. Verworfen: freie Wahl durch den Spieler (fehleranfällig, mehr Oberfläche), „das neuere Konto gewinnt“.
- **Folgen:** Plattform P15: `POST /me/link` führt in **einer** Transaktion zusammen, Tests für leeres Konto, Konflikt mit Bestätigung, Gildenfälle, Sperre; Hinweis im Admin-Panel bei abgelehnter Zusammenführung. Spiel CP1: Bestätigungsdialog im Konto-Panel. `soulwick-platform/docs/KONZEPT_ONLINE.md` §0, §3.6 und §8 von OFFEN auf D-122 bringen (Plattform-Sitzung). **Offen (Plattform P15):** Was mit der Gründerrolle passiert, wenn das gelöschte Konto eine Gilde gegründet hat.
- **Ersetzt:** keine; beantwortet den offenen Punkt „Zusammenführen zweier Konten“ aus D-119 und ROADMAP_CROSSPLAY CP1.

### D-123 – Menüs, Pause und Verbindungsabbruch im Multiplayer

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (an Claude delegiert), Ausarbeitung Claude
- **Kontext:** D-085 stand seit 2026-10-13 nur als Vorschlag da. MP1 (Pause und HitStop je Modus) und MP3 (Menüs, Abbruch) brauchen eine feste Regel.
- **Beschluss:** **D-085 gilt inhaltlich unverändert als VERBINDLICH.** Kurzfassung:
  - **Einzelspieler:** unverändert, Menüs pausieren das Spiel (D-043).
  - **Multiplayer:** Menüs (Shop, Upgrade-Wahl, Waffenwahl, Tab-Übersicht, Esc) halten das Spiel **nicht** an. Wer ein Menü offen hat, ist geschützt: nicht treffbar, von Gegnern ignoriert, kann selbst nicht angreifen. HitStop ist im Multiplayer aus.
  - **Verbindungsabbruch:** Fällt ein Client heraus, läuft der Run weiter, die Gegneranzahl passt sich ab dem nächsten Raum an. Fällt der Host heraus, endet der Run für alle (Auszahlung wie Tod, 50 %). Kein Host-Wechsel, kein Wiederbeitreten im laufenden Run (später möglich). Über den Relay (D-119) gilt: Verliert der Host die Verbindung zum Relay, ist das ein Host-Abbruch.
- **Gründe / verworfene Alternativen:** Eine globale Pause würde im Koop alle Spieler anhalten. Upgrade-Wahl und Shop kommen ohnehin in sicheren Momenten, der Schutz kostet daher kaum Spielgefühl. Host-Wechsel und Wiederbeitreten sind im Host-Modell aufwendig und für den Anfang nicht nötig.
- **Folgen:** Status von D-085 auf VERBINDLICH gesetzt. ROADMAP_MULTIPLAYER: MP0 (Bestätigung erledigt), MP1 (Pause und HitStop je Modus), MP3 (Menüs, Verbindungsabbruch). Keine neuen globalen Pausen (AGENTS.md Regel 6).
- **Ersetzt:** D-043 nur im Multiplayer (wie in D-085 vorgeschlagen).

### D-124 – Netzwerk-Reihenfolge

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (an Claude delegiert), Ausarbeitung Claude
- **Kontext:** ROADMAP_MULTIPLAYER und MULTIPLAYER.md planten ENet zuerst (MP2 per IP, MP4 über ein virtuelles LAN) und den Steam-Relay in MP6; der HTTP-Client im Spiel stand erst in MP7. D-119 macht den eigenen Relay zum Hauptweg, und der Relay verlangt ein Spieler-Token.
- **Beschluss:** Reihenfolge der Spiel-Pakete:
  1. **MP1:** Code verträgt mehrere Spieler, noch ohne Netzwerk.
  2. **MP1b – API-Client im Spiel:** `online/api_client.gd` (HTTP mit Token), Dev-Anmeldung über `POST /auth/dev` mit Geräte-ID, Sitzung in `online/session.gd`; vorgezogen aus MP7.
  3. **MP2** über den Relay (D-119): Raum erstellen, Raumcode eingeben; braucht den Relay (ROADMAP_CROSSPLAY CP3 Teil A, Plattform P13; lokal im Plattform-Repo).
  4. **MP3:** gemeinsamer Dungeon-Run, ebenfalls über den Relay.
  - **ENet** nur optional für LAN-Tests und Entwicklung, hinter derselben `MultiplayerPeer`-Schnittstelle.
  - **Steam** erst in **MP6** und nur als Zusatz (Anmeldung, Einladung mit Raumcode), nicht als Transport.
- **Gründe / verworfene Alternativen:** Internet-Koop braucht ohnehin Anmeldung und Relay; ein ENet-Zwischenschritt (IP, virtuelles LAN) würde Lobby, Fehlermeldungen und Testanleitung doppelt bauen. Der API-Client ist klein, ohne Netzwerk-Spiellogik testbar und Voraussetzung für das Relay-Token.
- **Folgen:** ROADMAP_MULTIPLAYER: neues Paket MP1b zwischen MP1 und MP2, Reihenfolge-Zeile; MULTIPLAYER.md §2 und §4a. MP2 bis MP6 folgen D-119 (Raumcode statt IP, Test-Build über den Relay, Steam als Zusatz).
- **Ersetzt:** die Stufen „ENet direkt → virtuelles LAN → Steam“ (MULTIPLAYER.md §4a) und „Warum ENet zuerst“ (ROADMAP_MULTIPLAYER).

### D-125 – Lobby im Dorf und Netz-Testwerte (MP2)

- **Status:** VERBINDLICH (Lobby-Ort, Ablauf) · Zahlen **TESTWERT** · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (an Claude delegiert), Ausarbeitung Claude
- **Kontext:** MP2 verbindet Spieler über den Relay (D-119) mit Raumcode. Es brauchte einen Ort im Dorf, einen Ablauf und Zahlen für Synchronisation und Zeitlimits.
- **Beschluss:**
  - **Ort:** Das Gildengebäude zeigt „Schnelles Spiel“ mit „Raum erstellen“ und „Raum beitreten“ (Raumcode, 6 Zeichen ohne verwechselbare Zeichen). Im Raum: Code groß, Spielerliste mit Name, Host, Plattform und Koop-Farbe P1–P4; „Starten“ folgt mit MP3. Gilden-Räume bleiben „in Vorbereitung“ bis MP8.
  - **Ablauf:** Nach dem Beitritt wird die Sitzung `QUICK`, das Dorf lädt neu, der Host erzeugt jeden Mitspieler, sobald dessen Profil (Name, Figur, Farbe) da ist. Endet die Sitzung (Host weg, Kick, Relay beendet), geht es mit Hinweis ins Solo-Dorf zurück (D-123).
  - **Host-Autorität:** Der Host synchronisiert Position, Bewegung, Zielrichtung und gehaltene Tasten; der eigene Spieler eines Clients läuft lokal sofort los und gleitet zur Host-Position zurück. „Interagieren“ (E) wird nie übertragen.
  - **TESTWERTE:** API-Zeitlimit 5 s, Verbindungsaufbau 10 s, Leave-Bestätigung 2 s, Synchronisation 30/s, Sprung statt Gleiten ab 96 px Abweichung, Eingabe bei Änderung oder alle 10 Frames.
  - **Anmeldung am Relay (P-027, 15.10.2026):** Das Sitzungs-Token (30 Tage) bleibt nur für die API; vor jeder Relay-Verbindung holt das Spiel per `GET /auth/token` ein JWT (15 min) und erneuert es, wenn weniger als 60 s übrig sind (TESTWERT). 401 löscht die Sitzung und meldet einmal neu an.
  - **Proviant** (Einmal-Boosts aus dem Dorf) wird nur im Solo verbraucht, im Schnellen Spiel bleibt er liegen (D-081).
- **Gründe:** Das Gildengebäude ist der vorhandene Ort für Online-Funktionen; Raumcodes funktionieren auf allen Plattformen gleich. Leichte Vorhersage beim eigenen Spieler hält die Steuerung direkt, ohne die Host-Autorität aufzugeben.
- **Folgen:** `online/` (Konfiguration, API-Client, Sitzung, Relay-Peer, Lobby, Netz-Spieler), `ui/menus/village_ui.gd`, `LOBBY_*`-Texte; Test `tools/net_smoke.gd`. Zahlen in MULTIPLAYER.md §3b.

### D-126 – Gemeinsamer Dungeon-Run (MP3): Host-Autorität, Raumwechsel, Wiederbeleben, Run-Ende

- **Status:** VERBINDLICH (Grundsätze, vom Projektmitglied vorgegeben) · Zahlen **TESTWERT** · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (Grundsätze 1–8), Ausarbeitung und Testwerte Claude
- **Kontext:** MP2 brachte zwei bis vier Spieler über den Relay zusammen ins Dorf (D-119, D-125). Für MP3 brauchte der gemeinsame Run feste Regeln: wer rechnet, wie alle denselben Dungeon bekommen, wann der nächste Raum beginnt, was mit Upgrades, Shop, Gefallenen und dem Run-Ende passiert.
- **Beschluss:**
  1. **Host-Autorität:** Nur der Host rechnet Gegner-KI, Schaden, Drops, Raumlogik und den Dungeon-Zufall. Clients schicken ihre Eingabe (wie MP2) und zeigen, was der Host repliziert.
  2. **Gleicher Dungeon über den Seed:** Der Host startet („Starten“ im Gildengebäude oder am Dungeon-Eingang), schickt Seed und Spielerzahl; jeder baut die Räume selbst. Vor jedem weiteren Raum schickt der Host den Zustand des Dungeon-RNG, die Spielerzahl und den gewählten Weg (Abzweigung), damit der Client trotz anderer Zufallszüge genau denselben Raum baut (Prüfung über eine Raum-Signatur). Alles Dynamische entscheidet der Host.
  3. **Replikation** (eigene RPCs statt Spawner, `online/net_enemies.gd`): Gegner als Ereignis (Spawn mit Szene, Daten-ID, Champion/Elite/Stufe, HP) plus Schnappschüsse 15/s (Position, Animation, Warnkreis/-linie, HP); Treffer und Tod als Ereignis. Gegnergeschosse einmal als Ereignis (Start, Richtung, Tempo, Aussehen), Münzen/Herzen und zerbrochene Kisten als Ereignis. Treffer-Funken, Töne und Wackeln laufen lokal aus diesen Ereignissen; Schadenszahlen nur für eigene Treffer und eigenen erlittenen Schaden. Auf dem Client sind Treffer auf Gegner und Kisten aus (seine Angriffe sind nur Bild, die Kopie beim Host trifft).
  4. **Je Spieler:** HP, Schild, Waffen, Upgrades, Dash. Upgrade-Wahl nach Raum 3: jeder wählt selbst (eigener Dialog, keine Pause); der Ausgang öffnet, wenn alle lebenden Spieler gewählt haben oder nach **30 s** (dann die erste Karte). Shop: Angebote des Hosts für alle, Kauf aus der gemeinsamen Kasse (D-081), der Host prüft, wer zuerst kauft, bekommt das Einzelstück. Waffenraum, Brunnen, Altar und Lagerfeuer wählt jeder für sich, der Host übernimmt das Ergebnis. **Prüfungsräume** gibt es im gemeinsamen Run vorerst nicht (Gewicht 0, bis sie repliziert sind).
  5. **Raumwechsel (geändert 16.10.2026, Wunsch Projektmitglied nach dem Online-Test):** Der Ausgang öffnet, wenn der Raum geschafft ist. Der nächste Raum beginnt erst, wenn **alle lebenden Spieler in ihm stehen**; kein Countdown, kein Teleport. Bis dahin sieht, wer drin ist, „Warte auf <Name> …“, der Nachzügler „<Name> wartet im nächsten Raum – beeil dich!“ mit Pfeil zum Eingang. Gefallene zählen nicht und werden beim Start hineingeholt (D-128); wer die Verbindung verliert, zählt nicht mehr. Ein Spieler mit offenem Menü muss selbst im Raum stehen. Die aktive Waffe reist als Zustand im Spielerzustand, nicht als nachgespielter Tastendruck. Raum 1 beginnt, wenn alle Clients geladen haben (höchstens **30 s** warten).
  6. **Am Boden und Wiederbeleben (D-084):** Bei 0 HP geht ein Spieler zu Boden, solange ein anderer steht; wer **2 s** innerhalb von **56 px** neben ihm steht, holt ihn mit **2 HP** zurück (danach 1,5 s unverwundbar); ein geschaffter Raum holt alle Gefallenen zurück; liegen alle, endet der Run. Gegner ignorieren geschützte und gefallene Spieler.
  7. **Skalierung (D-084)** wendet der Host an, mit der Spielerzahl der Sitzung (Gefallene zählen mit): Gegneranzahl ×(1 + 0,6(n−1)) über die Encounter-Gruppe, HP normaler Gegner ×(1 + 0,2(n−1)), Champions/Minibosse/Bosse ×(1 + 0,7(n−1)), Raumgröße L ab 3 Spielern. Verlässt ein Client den Run, gilt die neue Zahl ab dem nächsten vorbereiteten Raum (D-123).
  8. **Run-Ende:** Portal = **100 %** der Kasse für jeden Spieler ins eigene Dorf, Tod, Aufgeben und Host weg = **50 %** (D-081/D-123; Schnelles Spiel ohne Meta-Boni). Das Portal darf jeder benutzen, es beendet den Run für alle. Gibt ein Client auf, verlässt er den Raum (50 % für ihn), die anderen spielen weiter. Danach geht die Gruppe ins gemeinsame Dorf zurück, der Host kann erneut starten. Der Host meldet den Run an die API (`POST /runs`, Modus `quick`, Teilnehmer = Konten im Raum beim Start), wenn er angemeldet ist; Fehler werden nur protokolliert.
- **TESTWERTE:** Upgrade-Wahl 30 s (Uhr startet erst, wenn der Dialog erscheint; der Host wartet ab der Meldung „Wahl sichtbar“ des Clients, Nachfrist 3 s, höchstens 2 × 30 + 3 s), Warten auf Clients 30 s, Wiederbeleben 2 s / 56 px / 2 HP / 1,5 s I-Frames, Gegner-Schnappschüsse 15/s, Spielerwerte 10/s, Weltwechsel des Hosts 0,5 s nach der Startnachricht.
- **Gründe / verworfene Alternativen:** Host-Autorität passt zum Relay-Modell (D-119) und macht Schummeln nur beim Host möglich. Den RNG-Zustand je Raum zu senden ist billiger als ganze Räume zu übertragen und hält den Einzelspieler-Ablauf unverändert (gleiche Zufallszüge). `MultiplayerSpawner` für Gegner wurde verworfen: Gegner leben in wechselnden Raum-Instanzen, eigene Ereignisse mit Raum-Slot sind robuster und kompakter. Die Spieler bleiben beim Spawner (MP2); ihre Sichtbarkeit hängt jetzt am Synchronizer des Spielers, damit Weltwechsel keine Spawns verlieren.
- **Folgen:** `online/net_run.gd`, `net_dungeon.gd`, `net_enemies.gd`, `coop_rules.gd`; Haken in `dungeon_manager.gd`, `room_controller.gd` (zwei), `enemy_base.gd` (eine Zeile) und weiteren Dateien (MULTIPLAYER.md §3c); Test `tools/net_run_smoke.gd`. **Offen (MP5):** Varianten ab Raum 6 (Seelenflamme, Risse, Laterne …), Geheimnischen, Arena-Tore und Fallen-Takt laufen auf Clients nur lokal; Flüche des Pakt-Altars werden nicht zum Host übertragen; kein Wiederbeitreten.
- **Ergänzt:** D-081, D-084, D-085/D-123, D-125. **Ersetzt:** den Vorschlag „Schnelles Spiel ohne dauerhafte Auszahlung“ aus D-081 (jetzt 100/50 % wie im Einzelspieler).

### D-127 – Raumgröße für 3–4 Spieler ohne L-Pläne

- **Status:** VERBINDLICH bis L-Pläne existieren · **Datum / Teamfreigabe:** 2026-10-14 / Projektmitglied (an Claude delegiert), Ausarbeitung Claude
- **Kontext:** D-084 sieht ab 3 Spielern Räume der Größe L vor. Seit den Plan-Räumen (D-131) gibt es keine L-Vorlagen; ab 3 Spielern brachen Ausgangsregeln mit Skriptfehlern.
- **Beschluss:** `DungeonManager.get_room_sizes()` gibt ab 3 Spielern L zurück, **wenn L-Vorlagen vorhanden sind**, sonst die größte vorhandene Größe (heute M). Mehr Gegner als Quellen-Plätze werden zu weiteren Wellen (D-086). Sobald L-Pläne geliefert sind, gilt D-084 wieder ohne Codeänderung.
- **Gründe:** Kein Absturz, keine leeren Platzhalterräume; die Gegnerzahl skaliert trotzdem nach D-084.
- **Folgen:** Raum-Rework: L-Pläne für Gruppen sind erwünscht (Hinweis an den Raum-Strang). MULTIPLAYER.md §3e.

### D-128 – Koop mit Toren und Seitenwegen (Makeover)

- **Status:** VERBINDLICH · Zahlen **TESTWERT** · **Datum / Teamfreigabe:** 2026-10-15 / Projektmitglied (an Claude delegiert), Ausarbeitung Claude
- **Kontext:** Das Makeover (D-140, D-143, D-144) bringt ein Tor pro Übergang, eine Kamera mit 1,25× und Gang-Segmente in Seitenansicht. D-143 ließ offen, was mit Spielern hinter einem geschlossenen Tor passiert.
- **Beschluss:**
  - **Tor:** Nur der Host schließt Tore, und erst wenn alle lebenden Spieler im neuen Raum sind; Clients bekommen das Schließen gespiegelt. Nachzügler werden beim Raumwechsel auf begehbaren Boden hinter dem Tor geholt.
  - **Aufstehen hinter dem Tor:** Wer außerhalb des aktiven Raums wiederbelebt wird und dessen Tor zu ist (oder dessen Raum entladen ist), erscheint beim nächsten stehenden Mitspieler.
  - **Kamera:** im Koop die Mitte aus lokalem Spieler und stehenden Mitspielern im Umkreis von 380×200 px (TESTWERT); der lokale Spieler bleibt immer im Bild.
  - **Seitenwege:** Alle Spieler der Sitzung gehen gemeinsam hindurch; die Segmentkamera folgt der Gruppe, wer länger als 3 s außerhalb des Bildes ist, wird zurückgeholt (Host). Ob Seitenwege ausgelassen werden, entscheidet die Option des Hosts. Neue Taste „Seiten-Dash“ (Umschalt) für die Seitenansicht.
- **Gründe:** Niemand bleibt allein hinter einem Tor zurück; die Gruppe sieht sich gegenseitig, ohne dass der eigene Spieler aus dem Bild fällt.
- **Folgen:** `online/net_dungeon.gd`, `online/net_side.gd`, `online/coop_rules.gd`; Haken im Multiplayer-Vertrag (MULTIPLAYER.md §3e).

### D-130 – Gegner-Verhalten: Slime-Banden, Flankieren, Seitenwechsel

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude im Auftrag des Projektmitglieds (Playtest: „mehr Gegner, die hinter einen kommen“)
- **Beschluss:** Eine Koordination je Raum (`EnemyPack`, Regeln in `EnemyTactics`) verteilt je Ziel (nächster lebender Spieler oder Köder, Koop-fähig) Plätze. Slimes (Tag `swarm`) bilden Rudel aus 3–5 Tieren, die nacheinander springen (0,3 s Ducken mit hellem Landering, 0,4 s Flug ohne Schaden/Kollision, Landung neben oder hinter dem Spieler, nie näher als 40 px). Nahkämpfer verteilen sich auf Ringplätze; ab Raum 6 schneidet etwa ein Drittel einem fliehenden Ziel den Weg ab. Fernkämpfer wechseln ab etwa Raum 4 alle 6–10 s die Seite. Stärke sanft ab Raum 1, voll ab Raum 10. Bosse und Champions ausgenommen, ihre Begleiter nicht. Zufall aus einem vom Dungeon-Seed und der Raumnummer abgeleiteten Generator.
- **Messung (Bot Schwert, 24 Seeds × 3):** Median Raum 30 → 30; Schaden je Kampfraum Raum 1–5 0,094 → 0,056, Raum 6–10 0,148 → 0,101. Ob es sich „von hinten“ genug anfühlt, zeigt der Playtest.
- **Folgen:** `enemies/ai/`, `enemy_base.gd` Zustand `HOP`; Töne `slime_hop`/`slime_land` fehlen noch (bis dahin stumm). Ergänzt D-118, D-120.

### D-131 – Räume aus Plänen, einheitliches Wand-System (R1)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach Claude-Design-Antwort (D-120)
- **Beschluss:** Alle Raumvorlagen entstehen aus ASCII-Plänen (`dungeon/rooms/plans/`, Legende aus `docs/design/claude_design_antwort/02_grundrisse.md` plus `a F D Z m j`); je Biom eigene Vorlagen (Bodenquellen wechseln auf die Biomquelle), Spiegelungen als eigene Vorlagen. Der Generator prüft: Wandregel (Krone + Vorderseite, Nordwand 2 Kronen + 1 Vorderseite, Pfeiler 2×2), Einbauten bündig in der Vorderseite, Türen frei, jede Bodenkachel zu Fuß erreichbar, keine Deko im einzigen Gang, Fallen nur mit Grund, höchstens 1 Deko-Gruppe je 20 Bodenkacheln (Auffüllen bis 1 je 30). Keine Zufallsstreuung von Requisiten mehr. Raumart-Gewichte ab Raum 10: Normal 0,65 / Arena 0,35 / Abgrund 0. Boss-, Miniboss- und Ruheräume je Biom aus eigenen Plänen. Wasser bremst Spieler auf 70 %. Geheimnische bis zum Sprengen als Fels gemalt, Bruchkante in Biomfarbe.
- **Stand:** 39 Pläne → 124 Kampf- und 25 weitere Vorlagen; Säubern je Biom 11–16 Pläne.

### D-132 – Gegner-Quellen: Warnung, Erscheinen, Wahl hinter dem Spieler (R2)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude im Auftrag des Projektmitglieds („deutlicher, woher Gegner kommen; aus dem Boden, in der Arena aus der Wand“)
- **Beschluss:** Jeder Gegner eines Kampf- oder Champion-Raums kommt aus einer Quelle (Grab, Sarkophag, Pfütze, Bodenriss, Lavaspalte, Wandtor, Wandriss; Marker `Sources` aus den Plänen). Ablauf: 1 s Warnung (Licht in Quellenfarbe, Bodenring, Ton), 0,5 s Erscheinen (passiv, unverwundbar, ohne Körper), dann Kampf. Je Schub mindestens 3 Quellen, nie alle (bei ≥ 3 höchstens 60 %), Abstand ≥ 160 px zu jedem lebenden Spieler (Tore 96 px), bevorzugt hinter (3) bzw. neben (2) statt vor (1) dem nächsten Spieler; Quellen des letzten Schubs zuletzt. Arena nur aus Toren, jede Welle andere Tore. Elites nehmen freie Sarkophage, Champions steigen aus einem Sarkophag, Bosse behalten ihr Intro. Ohne Plan-Marker werden alte Spawnpunkte zu Quellen in Biomart. Hinterhalt entfällt (`AMBUSH_CHANCE` 0). Zufall aus Dungeon-Seed + Raumnummer.

### D-133 – Intro-Muster, Aufgabenleiste, Licht (R3, R6, R9)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach Claude-Design-Antwort
- **Intro (R3):** Räume mit Aufgabe (zuerst die Arena) beginnen mit Tür zu → Kamera auf das Ziel (Sperre je Spieler) → Ziel-Banner in Modusfarbe → 3-2-1 → los; beim ersten Mal je Spielstand mit Erklärkarte, danach kurz (ca. 2,2 s, ohne Kamera und Sperre); Überspringen mit E. Bewegung ist während 3-2-1 erlaubt. `RoomObjective` meldet Fortschritt, Zeit und Gefahr an die Aufgabenleiste oben Mitte; die Bossleiste ersetzt sie. Zwischen Arena-Wellen 2 s Pause mit „Welle n/N“ und Gong. Banner und Weltbeschriftungen teilen sich eine Warteschlange; veraltete Banner fallen weg.
- **Licht (R6):** Umgebung je Biom 0,53–0,60 Dunkelheit statt 0,97 (40–50 % sichtbar), Spielerkreis gezeichnet ×1,45 (ca. 5 Kacheln), für die Spiellogik unverändert 300 px; absichtlich dunkle Räume 0,84. Lichtfarben nach Regel warm = sicher, kalt = Ziel, rot = Gefahr. Helligkeits-Regler vorbereitet (Haken in den Optionen offen).
- **Töne (R9):** 27 neue synthetische Töne (Quellen, Intro, Countdown, Gong, Seelen, Einsturz, Geleit, Reliquie, Feuer, Slimes, Steinwächter, Laterne).

### D-134 – Absturz im Audio-Mischthread: Bildraten-Grenze und Bot ohne Ton

- **Status:** VERBINDLICH (Wert **TESTWERT**) · **Datum:** 2026-10-14 / Claude
- **Befund:** Etwa jeder dritte Balance-Bot-Prozess (Bogen/Stab) stürzte ab: `0xC0000005` in `AudioServer::_mix_step` (Godot 4.7.2), weil ersetzte Bus-Daten positionaler Sounds zwei Frames später freigegeben werden, während der Mischthread sie noch liest. Tritt nur bei sehr hohen Bildraten auf (headless unbegrenzt, im Spiel nur ohne VSync).
- **Beschluss:** Ohne VSync begrenzt das Spiel auf 240 FPS (`GameOptions.MAX_FPS_WITHOUT_VSYNC`). `tools/balance_sim.gd` läuft standardmäßig ohne Ton (`audio=1` zur Diagnose). Andere Headless-Tools sollen nachziehen. Godot-Issue melden (ohne Debug-Symbole keine genaue Zeile).

### D-135 – Minispiele Geleit, Seelen sammeln, Einsturz (R4a)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach KONZEPT_RAEUME_V2 §3.3/§3.6/§3.10
- **Geleit:** verirrter Dorfbewohner (5 % Huhn) läuft einen sichtbaren Pfad zum Ausgang; Köder für 60 % der Gegner, bleibt bei Gegner < 3 Kacheln stehen und ruft, 1,2× schneller neben einem Spieler, 4 Herzen (+1 je weiterem Spieler). Ankunft: Restgegner zerfallen (zählen als Kill), Bonus-Truhe, Rettung im Spielstand (`rescued_villagers`/`rescued_chickens`). Sturz: kein Bonus.
- **Seelen:** 12 Seelen nacheinander, je 6 s, 45 s gesamt, 1 Gegner je Seele im 1,5-s-Takt; Kristalle 12/9/6 → 3/2/1.
- **Einsturz:** 30 s, 2×2-Felder brechen von außen nach innen mit 1 s Warnung, nie Inseln; Gegner fallen mit, Spieler landen auf dem Restweg (D-115); Restweg 3 Kacheln breit mit Bonus-Truhe.
- **Erstes Auftreten:** Raum 6 / 11 / 16.

### D-136 – Minispiele aus den Varianten, Modus-Tabelle (R4b)

- **Status:** VERBINDLICH (Regeln D-120) · Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude
- **Ziehung:** `VariantTable` ist die Modus-Tabelle, Modi stehen in `ModeRegistry` (Id, Skript, Plan-Modus, erster Raum, Gewicht, Biome). Ab Raum 6 sind 35 % der Kampfräume (Plätze 1–3) Minispiele, höchstens 2 je Zyklus, nie derselbe Modus zweimal hintereinander, kein Modus zweimal im Zyklus, noch nicht gesehene Modi zuerst. Erste Räume: Flamme und Geleit 6, Reliquie und Seelen 11, Risse, Jagd, Lichtfeuer, Einsturz 16. Der Zug nennt den Plan-Modus; passt kein Plan, nimmt der Modus eigene Plätze. Wagnis-Altar 12 % der übrigen Kampfräume; Elite-Nest nur über Abzweigungen; Arena bleibt Raumart.
- **Modi:** Flamme hüten (40 s, Schübe alle 8 s, 70 % zielen auf die Flamme, unversehrt +1 Kristall), Reliquie holen (Träger ×0,75 ohne Angriff, 40 s für den Bonus, ab Raum 26 zwei Reliquien), Risse schließen (Wandrisse mit HP, Schub alle 6 s, unter 40 s +1 Kristall), Jagd (Fluchtloch 15 s, Beute Gold ×6, 30 % Upgrade), Lichtfeuer (Feuer anzünden, Steinwächter nur im Licht verwundbar; jedes Licht zählt wie D-116).
- **Totengräber:** Eigenschaft der Krypta ab Raum 3, 35 % der Skelette stehen einmal mit halben HP auf.
- **Gemeinsam:** Intro beim Betreten, Aufgabenleiste, Wachen aus dem Plan, Gegner nur aus Quellen, Misserfolg kostet nur den Bonus.
- **Ersetzt:** die Varianten aus D-114 und D-116; D-101 „nie zwei Varianten hintereinander“ wird „nie derselbe Modus zweimal hintereinander“.

### D-137 – Türen zeigen den nächsten Raum, Gänge, Abzweigung ohne Aufploppen (R5)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach D-120
- **Türen:** Jede Ausgangstür zeigt den Modus des schon gebauten nächsten Raums (Symbol über Torbogen bzw. Seitengang, Lichtkegel in Modusfarbe); Säubern Biomfarbe ohne Symbol; Spezial/Ruhe/Lagerfeuer ihr Symbol in Gold; Miniboss und Bosstor rot. Der unbekannte Weg einer Abzweigung zeigt sein Modus-Symbol statt „?“ (weicht von D-117 ab). Seitentüren mit `door_side_<biom>`; Torbogen in allen Vorlagen ganz (Test `test_door_arch_fit`).
- **Gänge:** Stil je Gang (gerade / Tropfstelle / Nische / Treppe, 35/25/20/20) per Hash aus Seed, Raum und Wand, ohne Dungeon-RNG; Platzhalter bis zu den Gang-Grafiken (SPRITES_V8).
- **Nichts ploppt auf:** Jeder vorbereitete Raum liegt unter einem dunklen Schleier (0,62) und wird beim Betreten des Eingangsgangs hell. Eine Abzweigung baut beim Betreten beide Wege (höchstens 4 lebende Räume während der Wahl), der nicht gewählte blendet in 0,9 s aus. Abzweigung nur, wenn beide Wege Platz haben. Gleicher Seed = gleiche Räume.

### D-138 – Dorf mit Platz, Geretteten und inszeniertem Eingang (R7)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach Claude Design `06_dorf.md`
- **Beschluss:** Karte 32×20 ohne Wegekreuz: gepflasterter Platz mit Brunnen, Gassen nach Westen, Süden (Spawn) und Osten. Der Weg zum Dungeon steigt über eine Treppe in einer Felskante zur Ruine (Fackeln, Ketten, Seelen-Rune, Seelenflammen-Becken, Raben, die bei Nähe auffliegen). Gerettete aus dem Geleit (D-135) laufen als Dorfbewohner herum (höchstens 6, abends mit Laterne), gerettete Hühner in festen Revieren (höchstens 4). Laternen 192 px (ändert D-107), Fenster leuchten abends. Gebäudenamen nur bei Nähe und nie zusammen mit einem Hinweis; gesperrte Gebäude ohne Textschild. Platzhalter bis zu den Grafiken aus SPRITES_V8.

### D-139 – UI-Rework: Karten-Dialoge, HUD, Banner (R8)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach Claude Design `07_ui.md`
- **Beschluss:** Dialoge höchstens 60 % der Bildschirmhöhe, Szene bleibt sichtbar (Overlay 0,62), Karten werden ausgeteilt, Akzentstreifen in Modusfarbe. Upgrade-Karten mit Kategorie-Band und Stufen-Punkten; Händler kompakt; Run-Ende mit Knöpfen in der Tastenleiste. HUD: Werte hüpfen bei Änderung, Tasten als Tastenkappen, Bossleiste ersetzt die Aufgabenleiste. Option Helligkeit −100…+100 %. Alle Texte im Dungeon über Übersetzungsschlüssel (D-111). Das Hinterhalt-Genre ist entfernt (D-120).
- **Offen (Projektmitglied):** Tastennamen „RMT/Space“ oder „Rechtsklick/Leertaste“; Begriff „Geheimnische“ auf Englisch.

### D-140 – Kamera 1,25× mit Überblick beim Betreten (M4)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach Makeover 3 §9 und Playtest („Bildschirm bewegt sich zu viel“)
- **Zoom:** Dungeon 1,25×; Bossraum, Lagerfeuer und Dorf 1,0×; das HUD skaliert nie mit. Beim Betreten eines Raums 0,35 s heraus auf 1,0×, 1 s Überblick (länger, solange das Raum-Intro schwenkt, höchstens 4 s), 0,8 s zurück; im Überblick neigt sich das Bild bis 240 px zur Raummitte.
- **Folgen:** Totzone 64×48, Vorlauf höchstens 48×36 px, linear mit 24 px/s (kein Über- und kein Zurückschwingen beim Umdrehen); beim Laufen ohne Verzögerung, nur Sprünge gleiten; nach 0,8 s Stillstand zurück auf den Spieler. Wackeln wird durch den Zoom geteilt.
- **Koop:** Die Kamera folgt `camera_targets()`; die Gruppenkamera setzt die MP-Sitzung über `set_targets_provider`.
- **Offen:** Miniboss- und Arena-Räume 1,0× wie der Bossraum? Bis zur Antwort 1,25×.

### D-141 – Licht und Shader (L1)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach Playtest („mehr mit Lichtern und Shadern arbeiten“)
- **Beschluss:** Alle Lichteffekte laufen im einen Vollbild-Durchgang `vision.gdshader`. Schein um jede Quelle in ihrer Farbe (Feuer, Lava, Magie, Blitze; Türkegel ohne Schein), Selbstleuchten heller, satter Pixel, Feuer flackert in der Helligkeit, Seelen- und Magielichter atmen (±14 %, 2,6 s), Biomfackeln leuchten in ihrer Flammenfarbe, Partikel-Blitze ab 8 Partikeln. Biomstimmung je Biom (`BiomeGrade.TABLE`: Schattenfarbe, Lichtertönung, Vignette, Nebel), Dorf nachts blau mit warmen Laternen. Bis 32 Lichter je Bild, Gameplay-Lichter haben Vorrang. Option „Lichteffekte: Hoch / Niedrig“ (Standard Hoch).
- **Grenze:** reine Optik; `LightQuery`, `counts_as_light` und die logischen Sichtwerte bleiben (D-067, R6).
- **Nachtrag 15.10.2026 (Playtest „Licht hart abgeschnitten“):** Selbstleuchten nur für kleine helle Details (Kontrast zur Umgebung, `emissive_area` 1,6), nicht für große helle Flächen wie Lichtkegel; Lichter in Räumen unter dem Schleier werden um 90 % gedämpft gezeichnet (`LightSource.get_veil_factor()`, `LightQuery` unverändert). Werte **TESTWERT**.
- **Nebenbei:** Optionenfenster mit fester Größe über alle Tabs.

### D-142 – Fels-Terrain, eine weiche Palette, organische Pläne (M1)

- **Status:** VERBINDLICH (Werte **TESTWERT**) · **Datum:** 2026-10-14 / Claude nach Makeover 2/3 und Playtest
- **Wände:** 47-Kacheln-Terrain mit Vorderseiten auf einer eigenen Ebene; jede Boden/Fels-Grenze hat denselben Rand, auch an Ecken. Kollision und Navigation bleiben auf dem Raum-Layer.
- **Looks:** Höhle und gemauert (Ruhe, Boss, Miniboss, Lagerfeuer, drei Krypta-Hallen) teilen je Biom **eine** weiche Palette (`crypt_soft` als Vorlage, andere Biome per Palettentausch, Schalter `RockTerrain.SOFT_BIOMES`).
- **Pläne:** Höhlen 17×11 bis 23×13, kein Rechteck, Felsblock/Empore/Abgrund innen, gerade Kanten ≤ 8, Boden ≤ 60 %. Für alle Pläne: keine 1-Kachel-Spalten (0 oder ≥ 2 Kacheln), keine Mauerfront direkt über dem Abgrund, kein Fels neben Türplätzen, nichts überlappt, feste Objekte 1 Kachel Abstand, alles erreichbar (Test `test_room_terrain`).
- **Deko:** weniger, größere Gruppen an Ecken und Buchten; Overlays nur an Wänden und Gruppen, nie in Tor- und Gangfeldern; alles nur auf begehbarem Boden; 2–3 bewegte Punkte je Raum; Wasser mit runder Kontur. Zufall aus der Vorlagen-ID, nicht aus dem Dungeon-RNG.
- **Höhe (`^ L &`)** ist vorbereitet und bis M3 Fels.

### D-143 – Ein Tor pro Übergang, 1-Kachel-Gang, kein Zurück (M2)

- **Status:** VERBINDLICH (Wunsch Projektmitglied 14.10.2026: „Die Tore sollen zugehen, wenn man in den nächsten Raum gegangen ist“) · Werte **TESTWERT** · **Datum:** 2026-10-14
- **Gang:** Zwischen Tor und Boden des nächsten Raums liegt genau eine Gangkachel; wo sich Räume überdecken, behält jeder Boden und Mauern (`PassageSeam`). Ein längerer Gang bleibt Notfall (D-117).
- **Tor:** genau eins je Übergang, im Ausgang des verlassenen Raums: Steinblock (Krypta, Schattenreich) bzw. Fallgitter (Grotte, Glutkammer, jede Arena), 0,4 s mit Ton; Lichtkegel 30 % geschlossen, 100 % offen. Der Eingang des nächsten Raums ist ein offener Höhlenmund bzw. Torbogen ohne Türblatt. Türöffnungen und Portal sind durchsichtig. Bosstor und Seitentüren bleiben.
- **Kein Zurück:** Sind alle lebenden Spieler im neuen Raum, schließt das Tor dahinter für immer (auch für Gegner), nie solange jemand im Gang steht.
- **Durchgänge sind Tunnel (Projektmitglied 15.10.2026):** Fels bzw. Krone mit Lichtkante läuft geschlossen über den ganzen Durchgang (auch den Notfall-Gang), der Spieler ist darin unsichtbar; alles in der Öffnung folgt der Bogenform des Sprites (weicher Innenschatten ≈ 18 px); Weglicht nur auf der Raumseite, Kegel so breit wie die Öffnung, `CONE_ALPHA` 0,5 (TESTWERT); keine Fackel an Seitentoren. Im Risse-Modus zeigt die Wand nur den Riss, kein zweites Loch; Bonustruhen nie auf oder neben einem Spieler.
- **Ersetzt:** den Tür-Teil von D-008 („Kampfraum-Eingang schließt“); ergänzt D-117 und D-137.
- **Koop:** Wer hinter einem geschlossenen Tor wieder aufsteht, erscheint beim nächsten stehenden Mitspieler (D-128 der Multiplayer-Sitzung, feature/multiplayer).

### D-144 – Gang-Segmente in Seitenansicht (M5)

- **Status:** VERBINDLICH im Grundsatz (Projektmitglied 15.10.2026), Werte **TESTWERT** · **Datum:** 2026-10-14 / Claude nach Makeover 3 und Mockup 29
- **Beschluss:** Zwischen manchen Räumen liegt ein kurzes Jump'n'Run-Segment in Seitenansicht: Tor → Schwarzblende 0,3 s → Banner „Abstieg“ (die ersten 3 Male mit Tastenhinweis) → Segment → Tür → Schwarzblende → nächster Raum. Immer nach dem Lagerfeuer, als Leiter-Weg einer Abzweigung (noch nicht angeschlossen), 10 % nach Ruhe-Räumen; nie vor dem Boss, nie zweimal hintereinander, abschaltbar. 4 Pläne je Biom, gespiegelt 8.
- **Physik:** Schwerkraft 1800 px/s² (Fallen ×1,4), Sprung 2,5 Kacheln (759 px/s), Kojote 0,1 s, Puffer 0,12 s, variable Höhe, Laufen 1,3 × Bewegungstempo, Dash waagerecht. Zufall nur aus Run-Seed + Slot, Zustand je Spieler am Spieler.
- **Runde 2 (Projektmitglied 15.10.2026: „soll ruhig Herzen kosten, ganz normal“, „Gameplay geiler, Double Jump“; Werte an Claude delegiert):** Grube = wie Abgrund im Raum (D-115, 1 Herz am Schild vorbei, kann töten), danach zurück auf die letzte Plattform. Doppelsprung (+2 Kacheln, Salto, Staubring), Wandrutschen und Wandsprung an Felswänden, Scheitel-Schweben, schnelleres Fallen, Squash/Stretch, Staub und Kamera-Stoß bei harter Landung, bröckelnde Vorsprünge (0,6 s, zurück nach 3 s). Je Plan genau eine Besonderheit: 8 Pläne verlangen den Doppelsprung, 8 haben einen bröckelnden Vorsprung; die goldene Münze braucht immer den Doppelsprung. Physik **TESTWERT** in `SideRules` (Schwerkraft 2400, Fallen ×1,6, Sprung 876, Doppelsprung 784, Kojote 0,1 s, Puffer 0,12 s).
- **Belohnung (TESTWERT, Maßstab: ein Segment lohnt sich wie ein Kampfraum):** 6–7 Münzen je 1 Gold × Wellenzahl des Raums, goldene Münze = 2 Münzen, Goldgier gilt; kein Seelenkristall, Segment-Gegner ohne Gold; Truhe nur auf dem Leiter-Weg einer Abzweigung. Ersetzt Münzen ×1,5 und Kristall aus Runde 1.
- **Offen:** ersetzt der Leiter-Weg den Raum n+1 oder liegt er davor (Leiter-Weg noch nicht angeschlossen); bewegte Plattformen als späteres Paket.
- **Runde 3 (16.10.2026, Projektmitglied: „minimal öfter, schöner, Türme“):** nach Ruhe-Räumen 18 % statt 10 % (TESTWERT), 6 Pläne je Biom (12 mit Spiegelung), Türme in 50 % der Abschnitte (D-151), Becken (verlangsamt) und Stachel-Wellen, Parallax-Mittelebene, Deko und Licht je Biom; im Koop entscheidet der Host über Türme und Fallen.

### D-145 – Dev-Feedback mit F9 (lokal)

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-15 / Projektmitglied („bleibt lokal für Dev drin“)
- **Beschluss:** Nur in Debug-Builds friert F9 das Spiel über `GameManager.request_pause(&"dev_feedback")` ein, nimmt einen Screenshot auf, auf dem man Bereiche markiert und eine Notiz schreibt; gespeichert wird beides samt Kontext (Szene, Raum, Biom …) nach `user://dev_feedback`. `tools/collect_feedback.py` sammelt die Einträge nach `docs/feedback/` (gitignored außer README), als Grundlage für den Grafik-Rework.
- **Folgen:** `ui/dev/*`, Haken in `autoload/game_manager.gd`, `tests/unit/test_dev_feedback.gd`, [feedback/README.md](feedback/README.md).

### D-146 – Repositories auf GitHub (WebBude-de)

- **Status:** VERBINDLICH · **Datum / Teamfreigabe:** 2026-10-15 / Projektmitglied
- **Beschluss:** Beide Repositories liegen privat in der GitHub-Organisation `WebBude-de`: `soulwick` (Spiel) und `soulwick-platform` (Website, API, Relay, Admin). Das Branch-Modell aus D-047 bleibt (`feature/*`, Pull Request mit Review statt Merge Request). Dokploy baut die Plattform aus GitHub. **OFFEN:** Name des Haupt-Branches (`main` oder `master`, D-047), CI für Spiel-Builds (CP7 plante GitLab-CI, jetzt GitHub Actions zu prüfen).
- **Ersetzt:** die GitLab-Angaben in D-047 und in der Repo-Tabelle von D-093.

### D-147 – Online-Menü: Schnelles Spiel und mehrere Gilden

- **Status:** VERBINDLICH (Aufbau, Projektmitglied 15.10.2026 nach dem ersten Online-Test) · Zahlen **TESTWERT** (Claude)
- **Beschluss:**
  - Ein **Online-Menü** erreicht man aus dem Hauptmenü („Online spielen“) und im Dorf über das Gildengebäude. Es hat zwei Bereiche: **Schnelles Spiel** (Raum erstellen, Raumcode eingeben) und **Gilden**.
  - **Gilden-Bereich:** Liste der eigenen Gilden; oben rechts „Gilde erstellen“ und „Gilde beitreten“ (Einladungscode). Ohne Gilde nur zwei große Knöpfe „Gilde erstellen“ / „Gilde beitreten“. Eine Gilde zeigt Mitglieder, Einladungscode, Gildenkasse und „Gilden-Raum erstellen“ (nur Mitglieder dürfen beitreten) sowie „Verlassen“.
  - Ein Spieler darf in **bis zu 5 Gilden** sein (TESTWERT), max. **30 Mitglieder** je Gilde (TESTWERT, D-080).
- **Ersetzt:** „höchstens eine Gilde je Spieler“ aus D-080. Rest von D-080/D-081 gilt weiter.
- **Folgen:** Plattform (Verträge, API, Relay-Prüfung „nur Mitglieder“, Admin), Spiel (`online/`, Online-Menü, Gildengebäude, Hauptmenü).

### D-148 – Open Source, Releases über GitHub Actions, Browser-, Linux- und macOS-Version

- **Status:** VERBINDLICH (Projektmitglied 16.10.2026: Spiel und Plattform sind Open Source, Web-, Linux- und macOS-Version, Releases per GitHub Actions) · Umsetzung **VORGESCHLAGEN** (Claude)
- **Beschluss:**
  - `soulwick` und `soulwick-platform` sind öffentlich. Nie Schlüssel, Keystores oder Dev-Keys ins Repo oder in Workflow-Logs.
  - Ein Tag `v<version>` baut über `.github/workflows/release.yml` Windows, Linux, macOS und Android und veröffentlicht ein GitHub-Release; Tags mit Zusatz (`v0.9.1-beta.1`) werden Pre-Releases gegen die Dev-Server. `ci.yml` prüft jeden Pull Request (validate + GUT). Anleitung: [RELEASE.md](RELEASE.md).
  - **Browser-Version** selbst gebaut und gehostet auf Dokploy (`Dockerfile`, `deploy/web/`, App `soulwick-game`), nicht über GitHub Actions: `game-dev.playsoulwick.com` (Branch `dev`) bzw. `game.playsoulwick.com`, als App installierbar (PWA); Single-Thread-Export (keine COOP/COEP-Header nötig), Compatibility-Renderer; Anmeldung wie auf dem PC als Gast. Plattformkennung `web` (Vertrag `ClientPlatform`). „Beenden“ ist im Browser ausgeblendet.
  - **macOS** als Universal-App, nur ad-hoc signiert und nicht notarisiert (kein Apple-Konto); **Windows** unsigniert. Signieren und Notarisieren kommen erst mit einem Store-Release.
  - Server-Umgebung normaler Releases über die Repository-Variable `RELEASE_ENV` (Standard `development`, bis die Produktiv-Server laufen).
  - Umsetzung (16.10.2026, Claude): jeder development-Build ist ein Pre-Release; manueller Start („Run workflow“) taggt `v<version>-dev.<Lauf>` bzw. `-rc.<Lauf>`; GitHub Pages entfällt. Android-Secrets: `ANDROID_DEBUG_KEYSTORE_BASE64` (Updates über lokal gebaute APKs) sowie `ANDROID_KEYSTORE_BASE64`/`_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` für production; fehlen sie, signiert die Pipeline mit einem Wegwerf-Schlüssel und markiert das Release als „nur Test“. Details: `docs/RELEASE.md`.
- **Lizenz** (Projektmitglied 16.10.2026: „GPL“): beide Repos unter **GPL-3.0-or-later** (`LICENSE`), fremde Bestandteile in `THIRD_PARTY.md`.
- **OFFEN:** Freigabe der Browser-Version in Produktion (Domain `game.playsoulwick.com` gewählt, 16.10.2026; Website-Knöpfe „Im Browser spielen“/„Web-App installieren“ über `GAME_URL`, in Produktion noch leer).
- **Folgen:** `export_presets.cfg` (Vorlagen „macOS“, „Web“), `tools/export_build.sh`/`.ps1` (`macos`, `web`), `tools/build_readme.txt`, `online/online_config.gd`, Haupt- und Pausenmenü, `.github/`; Plattform: `packages/contracts/src/lobby.ts` (`web`), `CORS_ORIGINS` der API.
- **Ersetzt:** keine.

### D-150 – Gegner im Dunkeln unsichtbar

- **Status:** VERBINDLICH (Grundsatz, Projektmitglied 15.10.2026: „Gegner außerhalb des Radius wirklich nicht sehen, erst reinfaden; Finsternis kleinerer Radius“) · Werte **TESTWERT** (Claude)
- **Beschluss:** Gegner außerhalb des gezeichneten Lichts des **lokalen** Spielers sind unsichtbar (mit Lebensbalken, Abzeichen, Name, Schatten, Leuchten, Schadenszahlen) und blenden in 0,2 s ein, Randband 24 px. Licht = eigener Kreis bei halber Helligkeit und jede gezeichnete Lichtquelle außer dem Leuchten von Gegnern (bis 0,65 r, ab Stärke 0,35), im Koop auch die Kreise der Mitspieler. Immer sichtbar: Bosse, Champions im Miniboss-Raum, Risse, der Gekrönte, Gegner-Projektile und Bodenexplosionen; Telegraphen dort, wo sie im Licht liegen. Helle Räume (Dunkelheit < 0,3) verstecken nichts. Nur Darstellung (D-088), 12 Hz.
- **Werte:** Umgebung je Biom +0,06 (0,59–0,66); Finsternis Aufschlag 0,16, Kreis 190 px mit Rand 105 px (Sichtgrenze ≈ 138 px statt ≈ 156 px).
- **Folgen:** `components/visual/darkness_visibility.gd`, `ui/effects/vision_overlay.gd`, `lighting_profile.gd`, `light_source.gd` (`draw_factor`), `sprite_fx.gdshader`; offen: Lichtkreise der Mitspieler zeichnen (MP5).
- **Ergänzt:** D-067, D-141.

### D-151 – Turm-Gegner und Verlangsamung

- **Status:** VERBINDLICH (Projektmitglied 16.10.2026: „etwas, das mehr schießt, nicht viel Damage, sondern slowt; stationär“) · Werte **TESTWERT**
- **Beschluss:** Stationäre Türme je Biom (Knochenturm, Schleimspeier, Schattenauge, Glutkessel) in normalen Kampfräumen ohne Arena, Variante oder Modus ab Raum 4 (Raum 4–14: 40 % ein Turm; ab 15: 50 %, davon 30 % ein zweiter; ab 30: 60 %, davon 45 % ein zweiter), an Wänden oder Ecken, nie an Türen und nie im Weg. Sie tauchen aus dem Boden auf, zählen für das Säubern (Welle 1) und geben 1 Münze. Schuss auf den nächsten lebenden Spieler in Sicht und Reichweite (300 px): 0,6 s Aufleuchten mit Ziellinie, Kugel 150 px/s, 0,5 HP, Verlangsamung −35 % für 1,5 s (frischt auf, stapelt nicht, nur bei wirksamen Treffern), Abklingzeit 1,8 s (mit der Tiefe bis ×0,75). Auch in der Seitenansicht (50 % der Abschnitte, 8 Kacheln Sicht). Zufall aus Seed + Raumnummer, nicht aus dem Dungeon-RNG. Im Koop rechnet der Host, die Verlangsamung reist mit dem Treffer.
- **Folgen:** `enemies/turret/**`, `components/combat/slow_status.gd`, `DamageData.slow_*`, Haken in `room_controller.gd` und `player.gd`, Grafiken SPRITES_V10 §5.

### D-152 – Ein Charakter pro Konto, Spielstände sind Welten

- **Status:** VERBINDLICH (Projektmitglied 16.10.2026) · Zahlen **TESTWERT**
- **Beschluss:** Ein Konto hat **einen** Charakter: Anzeigename und Aussehen (4 Figuren, je Farbe für Haare, Kleidung, Haut, Akzent aus 8 Stufen), alles frei wählbar. Spielstände sind nur noch „Welten“ (wie mehrere Maps), der Kontoname kommt nicht mehr vom Spielstand. Beim ersten Start „Wie heißt du?“ und Figurenwahl; ändern in der Lobby (eigener Slot) und im Dorf (Spiegel/Schneider). Name und Aussehen liegen am Konto auf dem Server (`PATCH /me`, Plattform P-034) und gelten auf allen Geräten; Namenswechsel höchstens 3 je 24 h.
- **Umgesetzt 16.10.2026:** `characters/player_profile.gd` (`user://profile.cfg`), Figuren `wick`, `ember`, `moss`, `frost` (`characters/*.tres`, Look über `PlayerLook`), Spielstand v4 (`[world] name`, Altdaten nach `[legacy_profile]`, Sicherung `.v3.bak`), Editor beim ersten Start, im Hauptmenü („Figur“), im Dorf (Spiegel) und in der Lobby; Lobby-Plätze mit Figur, Krone, Status, Ping. Server-Profil gewinnt beim Login, wenn lokal nichts geändert wurde. **TESTWERTE:** 8er-Paletten und Startfarben je Figur (Figurwechsel setzt die Startfarben), Namenslänge 16 im Spiel, Ping-Teilen alle 2 s, Ping-Grenzen 80/160 ms, Spiegel 112 px rechts vom Zuhause.
- **Folgen:** Profil-Klasse und Welten-Auswahl im Spiel, Lobby-Slots, Grafiken SPRITES_V10 §7; offen: Filter gegen anstößige Namen (Store-Pflicht), endgültige Figurennamen.

### D-155 – Touch: zwei Sticks (laufen links, zielen und angreifen rechts)

- **Status:** VERBINDLICH (Projektmitglied 16.10.2026: „zwei Joysticks, links laufen, rechts schießen … in die Richtung, in die ich gucke, schlage ich automatisch … Special-Button links, wo ich laufe … Jump-Buttons trotzdem rechts“) · Werte **TESTWERT** (Claude)
- **Beschluss:** Linker Stick läuft. Rechter Stick zielt; ab der Auto-Angriffs-Schwelle greift die Figur in Stick-Richtung automatisch an (alle Waffen), darunter dreht er nur die Figur. Spezial-Knopf links neben dem Lauf-Stick, löst in Ziel- bzw. Blickrichtung aus und pausiert den Auto-Angriff, solange er gehalten wird. Dash, Benutzen, Waffe wechseln, in der Seitenansicht Springen und Seiten-Dash liegen rechts um den Ziel-Stick; der Angriffsknopf entfällt. Ohne rechten Stick gilt die Laufrichtung als Blickrichtung, die alte Zielhilfe auf den nächsten Gegner (200 px) ist entfernt. Seitenansicht: Der rechte Stick zielt und greift dort genauso an. Maus, Tastatur und Gamepad unverändert. Setzt CP0 Frage 5 (ROADMAP_CROSSPLAY) praktisch als (b) „zwei Sticks“ um.
- **Werte (TESTWERT):** Tot-Zone Ziel-Stick 0,2 des Radius (90 px), Auto-Angriff ab 0,25 nach der Tot-Zone (≈ 40 % Radius), angetippter Spezial-Angriff bleibt 15 Frames angefordert, Ziel-Stick startet im rechten 45-%-Streifen (Knöpfe haben Vorrang); Lauf-Stick unverändert (Tot-Zone 0,18).
- **OFFEN:** leichte Zielhilfe für den Ziel-Stick (Einrasten in einem kleinen Kegel, v. a. Bogen) – Frage an das Projektmitglied; Gerätetest auf 20:9-Handys.
- **Folgen:** `ui/touch/touch_overlay.gd`, `ui/touch/touch_stick.gd` (neu), `ui/touch/touch_art.gd` (optional `touch_stick_aim_base.png`, SPRITES_V10 §1), `player/input/touch_input.gd`, `player/input/touch_state.gd`, `tests/unit/test_touch_input.gd`; Doku der alten Zielhilfe in `docs/MULTIPLAYER.md` und `docs/ROADMAP_CROSSPLAY.md` nachziehen (Multiplayer-Sitzung).
- **Ersetzt:** die Touch-Zielhilfe aus MP1/CP0 (Angriffsknopf mit Zielhilfe).

## 8. Vorlagen für spätere Entscheidungen

Neue Einträge sollten im gleichen Format dokumentiert werden:

```markdown
### D-051 – [Kurztitel]

- **Status:** VORGESCHLAGEN | VERBINDLICH | ERSETZT
- **Datum / Teamfreigabe:** YYYY-MM-DD / [MR oder Protokoll]
- **Kontext:** Welches konkrete Problem lösen wir?
- **Beschluss:** Eindeutige Regel mit Zahlen und Sonderfällen.
- **Gründe / verworfene Alternativen:** Warum diese Entscheidung?
- **Folgen:** Betroffene Dateien, APIs, Migrationen und Tests.
- **Ersetzt:** D-... oder keine.
```

**Weiterlesen:** [PRD.md](PRD.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [TECHSTACK.md](TECHSTACK.md) · [ROADMAP.md](ROADMAP.md)
