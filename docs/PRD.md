# PRD – Soulwick (2D-Dungeon-Roguelite)

> **Status:** Produktanforderungen, Zielbild MVP · **Stand:** 13.10.2026  
> **Verbindliche Quelle:** `GDD Master 1.0 – überarbeitet` (10.10.2026), einschließlich späterer explizit bestätigter Entscheidungen.  
> **Leseregel:** `VERBINDLICH` = beschlossen; `TESTWERT` = vorläufige Balance; `OFFEN` = Teamentscheidung ausstehend; `NACH MVP` = kein Lieferumfang des MVP.  
> **Abgrenzung:** Dieses Dokument beschreibt das **reale Teamprojekt**, nicht das verworfene ChatGPT-Testprojekt.  
> **Produktüberblick für beide Repositories:** [docs/PRODUKT.md](PRODUKT.md); dieses PRD enthält die verbindlichen Spielregeln.

## 1. Was bauen wir?

Ein eigenständiges **2D-Top-down-Dungeon-Roguelite** mit direkter, mausgesteuerter Action. Vom Dorf aus startet der Spieler einen Dungeon-Run. Vorgefertigte, nahtlos miteinander verbundene Räume enthalten Kämpfe, Waffen- und Upgrade-Entscheidungen, Spezialräume und Bosse. Temporäre Run-Fortschritte gehen nach einem Run verloren; ein definierter Teil des Run-Goldes wird dauerhaft gutgeschrieben.

**Produktziel:** Ein vollständig spielbarer, wiederholbarer Kern-Loop, dessen Kampfsystem und Upgrade-Kombinationen technisch erweiterbar und über eindeutige Regeln reproduzierbar sind. Das Dorf dient im MVP vor allem als Einstieg und Rückkehrpunkt, nicht als bereits vollständig ausgebautes Metaprogressionssystem.

## 2. Warum? – Designziele

1. **Direkte Steuerung:** Bewegung, Zielen, Angreifen und Dash sollen sich präzise anfühlen.
2. **Bedeutsame Run-Entscheidungen:** Zwei Waffenslots, kompatibilitätsabhängige Upgrade-Kombinationen und freiwillige Spezialräume schaffen Variation.
3. **Nachvollziehbare Regeln:** Schaden, Schild, Trefferhistorie, Effektauslösung und Goldtransfer haben eine eindeutige Rechen- bzw. Zustandslogik.
4. **Wiederverwendbarer Inhalt:** Neue Raumvorlagen, Gegner, Waffen und Effekte können später ergänzt werden, ohne den Kern neu aufzubauen.
5. **Überschaubarer MVP:** Drei Waffen und genau 15 Upgrades statt eines frühzeitig aufgeblähten Inhaltsumfangs.

## 3. Zielablauf (Core Loop)

1. Im **Dorf** den Dungeon-Eingang mit **E** benutzen; neuer Run startet.
2. Im **Kampfraum** schließt sich der Eingang. Gegner besiegen; danach öffnet der Ausgang.
3. Über den verbindlichen **Fünf-Raum-Zyklus** voranschreiten.
4. **Waffen** und **Upgrades** kombinieren, **Gold** sammeln bzw. freiwillig ausgeben.
5. Per regulärem **Portal** aussteigen oder bei **Tod/Abbruch** zurückkehren.
6. Dauerhafte Goldgutschrift gemäß Exit-Regel; neuer Run beginnt ohne temporäre Ausrüstung.

## 4. Spielfunktionen des MVP

### 4.1 Dungeonstruktur – VERBINDLICH

| Raum im Fünferzyklus | Funktion |
| --- | --- |
| 1 | Normaler Kampfraum |
| 2 | Normaler Kampfraum |
| 3 | Normaler Kampfraum **mit Upgrade-Auswahl erst nach Kampfabschluss** |
| 4 | Spezialraum |
| 5 | Miniboss; auf den absoluten Räumen **15, 30 und 45 stattdessen Boss** |

Ab Raum 6 wiederholt sich der Zyklus. **Nach Raum 45** besteht die Wahl zwischen regulärem Ausstieg (100 % des verbleibenden Run-Goldes) und Fortsetzung des laufenden Runs im Endlosmodus. Die abgeschwächte Skalierung **ab Raum 46** ist noch **OFFEN**.

> **Stand Ausbau:** Es gibt kein Ende und keine Wahl bei Raum 45 mehr (KONZEPT_ENDLOS); der Dungeon geht endlos weiter. Nach jedem Boss folgt ein **Lagerfeuer** (zählt nicht als Raum) mit Rast und festem Exit-Portal (D-103).

**Spezialräume:** Shop, Waffenauswahl, Brunnen, Extra-Upgrade. Die vier Typen werden gleichgewichtet gezogen; der unmittelbar vorherige Typ darf sich nicht wiederholen. Angebote sind freiwillig. In **30 % der Spezialräume** erscheint ein reguläres Exit-Portal; mit **E** plus Bestätigung nutzbar. Die technische Reihenfolge von Portalchance und Raumtypziehung ist **OFFEN**.

> **Stand Ausbau:** Spezialräume werden gewichtet gezogen, neu ist der **Prüfungsraum** (D-102); in einem Drittel der Extra-Upgrade-Räume steht der **Pakt-Altar** (D-112). Kampfräume können ab Raum 6 **Kampf-Varianten** (D-101) oder einen **Wagnis-Altar** (D-104) haben; Raumarten Normal/Arena/Abgrund und Formen nach D-100, Anzeige nach D-110, Belohnungen D-109. Details: [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md).

### 4.2 Gegner, Spawning und Schwierigkeit – VERBINDLICH

- Normale Kampfräume: **1–3 Gegner**, ab **Raum 25** **2–3**; maßgeblich ist der **Raumtyp** (Raum 25 ist Miniboss, erster betroffener normaler Kampfraum ist Raum 26).
- Jede Kampfraumvorlage hat **genau fünf** im Editor positionierte `Marker2D`-Spawnpunkte; die tatsächlich belegten Punkte werden **ohne Zurücklegen** gewählt.
- Gegnertypen werden **pro Spawn unabhängig** gezogen: **Slime 50 %**, **Skeleton 35 %**, **Archer 15 %**.
- Slime: langsame Verfolgung/Annäherung; Skeleton: schnelle Nahkampf-Verfolgung; Archer: Distanzkampf.
- Gegner blockieren einander, verursachen **kein Friendly Fire**, kündigen Angriffe sichtbar an und zeigen ihre HP-Leiste. Treffer verursachen leichten konfigurierbaren Rückstoß; nach dem Tod folgt eine kurze Animation und Gold-Drop.
- Normale Gegner besitzen **keine generellen Treffer-I-Frames**; dieselbe Hit-ID darf aber nicht mehrfach auf dasselbe Ziel wirken.
- Skalierungsblock `k(r) = floor((r - 1) / 5)`; ab jedem neuen Block: Gegner-HP `× 1,20`, Gegnerschaden `× 1,10`. Miniboss ist ein zufälliger Standardgegner mit jeweils zusätzlichem Faktor `× 1,50`.
- Konkretes Bossverhalten, spezielle Bossfaktoren und Endlos-Balance sind **OFFEN**.

### 4.3 Spieler und Eingaben – VERBINDLICH

| Eingabe | Aktion |
| --- | --- |
| WASD | Bewegung; diagonale Eingaben normalisieren |
| Maus | Durchgängiges 360°-Zielen/Ausrichten |
| Linke Maustaste (halten) | Wiederholte Normalangriffe nach effektiver Attack-Rate |
| Space | Dash in Bewegungsrichtung; ohne Bewegungsinput in Zielrichtung |
| Q | Zwischen zwei Waffenslots wechseln |
| E | Interaktion (Dorf-Eingang, Portal usw.) |
| Tab | Pausierte Übersicht erworbener Upgrades |
| Esc | Pausemenü |

- Spieler startet mit **6 HP = drei Herzen**, Anzeigeschritte von **0,5 HP** (Viertelherz).
- Alle **fünf abgeschlossenen Räume** automatische Heilung von **1 HP**, maximal bis zur HP-Obergrenze.
- **Schild vor HP**; keine passive Schildregeneration; keine harte Schildobergrenze. Erhöhungen oberhalb **50 Schild** wirken nur zu **50 %**; interne Werte in **0,5er-Schritten**.
- Dash bricht aktuelle Angriffe ab, verbietet weitere während des Dashs und gibt unabhängig von Treffer-I-Frames Schutz. **Dash-TESTWERTE:** Dauer `0,2 s`, Geschwindigkeit `450 px/s`, Cooldown `1,5 s`.
- Jeder **tatsächlich schadenswirksame Treffer gegen Schild oder HP** löst **0,5 s konfigurierbare Treffer-Unverwundbarkeit** aus. Vollständig blockierte Treffer verursachen weder Schaden noch schadensabhängige Effekte.

### 4.4 Waffen – drei Typen im MVP

Zwei Slots, maximal eine aktive Waffe, **keine doppelten Waffentypen**. Beim neuen Waffenkauf/bei Waffenwahl und zwei belegten Slots muss ein Slot ersetzt werden. Globale Run-Upgrades bleiben erhalten. Technische Seltenheit ist vorgesehen, hat im MVP **keine spielerische Auswirkung**.

| TESTWERTE | Schwert | Bogen | Magierstab |
| --- | ---: | ---: | ---: |
| Basisschaden | 12 | 9 | 8 |
| Attack-Rate | 1,5/s | 1,2/s | 0,8/s |
| Reichweite | 75 px | 600 px | 450 px |
| Projektilgeschwindigkeit | – | 550 px/s | 300 px/s |
| Trefferbereich | 100° | Direkt | 45 px AOE |

- **Schwert:** Bogen-/Schwungangriff in Mauszeigerrichtung, je Schwung und Ziel maximal ein Treffer.
- **Bogen:** Schneller Pfeil; Durchschlag und einmaliger Wandabprall nur über passende Upgrades.
- **Magierstab:** Größeres, langsames magisches Geschoss; **ein einziger AOE-Grundtreffer** beim Einschlag, einschließlich direkt getroffenen Gegners (**kein zusätzlicher Direktschaden**).
- Attack-Rate ist **Angriffe pro Sekunde**, nicht Cooldown in Sekunden; Bonusprozente werden addiert.

### 4.5 Upgrades – exakt 15 Typen

Alle Upgrades gelten **runweit** für kompatible Angriffe. Pro Auswahl bis zu **drei verschiedene verfügbare** Upgrades; keine Dubletten in derselben Auswahl. Ohne verfügbares Upgrade wird keine Ersatzbelohnung erfunden. Tag-Filter: **OR** über anwendbare Tags; separat definierte `required_tags` müssen zusätzlich vollständig zutreffen.

| Kategorie | Upgrade | Effekt pro Stack/Stufe (Balancewerte = TESTWERTE) | Limit |
| --- | --- | --- | --- |
| Attribut | Verstärkter Angriff | +10 % Schaden global | ∞ |
| Attribut | Krafttraining | +2 Nahkampfschaden | ∞ |
| Attribut | Schneller Angriff | +15 % Attack-Rate global | ∞ |
| Attribut | Präzise Pfeile | +20 % Pfeilschaden | ∞ |
| Attribut | Magische Verstärkung | +20 % Magieschaden | ∞ |
| Attribut | Schnelle Geschosse | +20 % Projektilgeschwindigkeit | ∞ |
| Attribut | Schildverstärkung | +10 Schild vor Softcap, sofort | ∞ |
| Mechanik | Durchschlag | +1 zusätzlich treffbarer Gegner je Pfeil | 3 |
| Mechanik | Wandabprall | 1 Abprall pro Projektil | 1 |
| Mechanik | Doppelschuss | +1 Projektil pro Angriff | 1 |
| Mechanik | Größerer Schwung | +20 % Angriffswinkel | 3 |
| Mechanik | Größere Explosion | +20 % AOE-Radius | 3 |
| Effekt | Explosiver Treffer | Sekundäre Explosion = 50 % des auslösenden Treffers | 1 |
| Effekt | Heilung bei Tötung | +2 HP pro Kill/Stack, bis Max-HP | ∞ |
| Effekt | Schild bei Tötung | +2 Schild pro Kill/Stack, vor Softcap | ∞ |

**Effektregeln:** Sekundäreffekte dürfen **keine weiteren Sekundäreffekte** auslösen. Sie dürfen jedoch reguläre Kills erzeugen; normale `ON_KILL`-Belohnungen (Heilung/Schild) werden gewährt. Eine Upgrade-Explosion darf das durch den Primärtreffer bereits getroffene Ziel nochmals beschädigen. Beim Magierstab entsteht aus **einem primären Flächentreffer höchstens eine Upgrade-Explosion**, auch bei mehreren getroffenen Gegnern. Projektile aus Doppelschuss besitzen getrennte Trefferhistorien. AOE-Radiusboni wirken additiv.

### 4.6 Shop, Gold und Run-Ende

- Shop: **bis zu sechs gültige Angebote**: `2 Upgrades + 2 Waffen + 1 Heilung (+2 HP) + 1 Schild (+4)`; nicht verfügbare/nicht kaufbare Optionen nicht anzeigen oder ersetzen.
- Waffenauswahl-Spezialraum: Bis zu **zwei nicht besessene Waffen**, gegebenenfalls mit Slotersatz.
- Brunnen: **einmalig kostenlos +3 HP** bis Max-HP.
- Einkäufe sind **atomar**: Abbuchung und Lieferung gemeinsam oder gar nicht.
- **Tod** oder **vorzeitiger Abbruch**: **50 %** des maßgeblichen verbleibenden Run-Goldes permanent verbuchen.
- **Regulärer Ausstieg**: **100 %** permanent verbuchen.
- **Fortsetzen ab Raum 45**: Kein Run-Ende, Gold verbleibt im Run.
- **OFFEN:** Gold-Drops, Shoppreise, Gold-/Preiswachstum, konkrete permanente Dorf-Freischaltungen und **Rundung ungerader Goldbeträge bei 50 %**. Keine stillschweigenden Platzhalterwerte als finale Balance übernehmen.

### 4.7 UI, Pause und Speicherung

- Kompaktes HUD am Bildschirmrand: HP-Herzen, numerischer Schild mit Symbol, Run-Gold, aktive Waffenwerte.
- Schadenszahlen über Gegnern; Schild- und HP-Schaden visuell unterscheidbar. Trefferfeedback enthält Aufblinken/Rückstoß.
- Waffenvergleich und Shop zeigen **effektive Werte inklusive Upgrades**.
- Shop-, Waffen-, Upgrade-Auswahl und Tab-Upgrade-Übersicht **pausieren die gesamte Spielsimulation**, einschließlich Projektile und Gameplay-Timer. Menüs sind während Pause bedienbar. Mehrere Pausengründe können parallel aktiv sein.
- Auf Datenträger werden im MVP **nur permanente Werte** (z. B. permanentes Gold/Freischaltungen) gespeichert, **keine fortsetzbaren Runs**.
- Dorf ↔ Dungeon erzeugt einen neuen Spieler aus `player.tscn`; **Raum ↔ Raum im Dungeon erhält dieselbe Spielerinstanz**.

## 5. MVP-Abnahme – nutzerseitig beobachtbar

Der MVP ist akzeptierbar, wenn ein regulärer Run vom Dorf aus möglich ist, Spieler/Gegner/Waffen korrekt kämpfen, die spezifizierte Raum- und Bossfolge funktioniert, Spezialräume und Upgrade-Interaktionen gültig sind, wirksame Treffer/Golddrops/Run-Ende korrekt verarbeitet werden und nur permanente Zustände nach Neustart vorhanden sind. Außerdem muss das Projekt auf dem Team-Repository nachvollziehbar startbar und getestet sein. Detailkriterien und der **nicht verifizierte Implementierungsstand** stehen in [ROADMAP.md](ROADMAP.md).

## 6. Was wird NICHT gebaut? – NACH MVP

- Mehr als drei Waffentypen oder spielmechanisch wirksame Seltenheiten.
- Andere Upgrade-Typen als die verbindlichen 15, insbesondere Feuer-/Gift-Statussysteme.
- Eigenständiges Rüstungs-/Resistenzsystem und kritische Treffer.
- Verbindliche Hitstop-/Kamerawackel-Features (nur optionale spätere Verbesserungen).
- Fortsetzen eines unterbrochenen Dungeon-Runs nach Programmneustart.
- Vollständig ausgebautes Dorf bzw. abschließend ausbalancierte Metaprogression.
- Bereits endgültig ausbalancierter Endlosmodus ab Raum 46.

Was **nach** dem MVP kommen soll, steht in Abschnitt 7.

## 7. Ausbauziele nach dem MVP – Vision

> **Stand:** 13.10.2026 · **Status:** Ziele beschlossen (D-080 … D-088 in [DECISIONS.md](DECISIONS.md)), **noch nichts gebaut**. Balancewerte sind `TESTWERT`; als „Vorschlag“ markierte Punkte brauchen noch eine Bestätigung.  
> **Reihenfolge (D-088):** zuerst [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) (7.4, 7.5), danach [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) (7.1–7.3, 7.6). Technik: [MULTIPLAYER.md](MULTIPLAYER.md).

### 7.1 Online-Koop mit Freunden

**Ziel:** 2–4 Spieler spielen gemeinsam einen Dungeon-Run, auch über das Internet.

- **Ein Spieler ist Host** und berechnet die Spielwelt; für das Spielen selbst ist **kein eigener Gameserver** nötig.
- **Zwei Wege** im Gildengebäude (D-080): **Schnelles Spiel** (beliebige Leute einladen, z. B. von Discord, ohne Bindung) und **Gilde** (dauerhaft, siehe 7.2).
- **Getrennt vom Einzelspieler** (D-081): Im Multiplayer startet man ohne eigene Dorf-Verbesserungen und ohne gute Waffen. Run-Gold ist eine **gemeinsame Kasse**. Waffen und Upgrades bleiben je Spieler.
- **Testphase:** direkte IP bzw. virtuelles LAN (Tailscale/ZeroTier). **Später:** Steam-Lobbys, Einladen über die Freundesliste, Steam-Relay (7.6).
- **Menüs pausieren im Multiplayer nicht**; wer ein Menü offen hat, ist geschützt. Fällt der Host heraus, endet der Run (Vorschlag D-085).

### 7.2 Gilden und Ranglisten

- **Gilde** (D-080): gründen, per Einladungscode beitreten, jederzeit verlassen; höchstens eine Gilde je Spieler, max. 30 Mitglieder. Gilden-Runs nur mit Mitgliedern.
- **Gilden-Fortschritt** (Vorschlag D-081): Gildenkasse und Gilden-Schmiede auf dem Server, alle Mitglieder profitieren in Gilden-Runs. Schnelles Spiel hat keine Meta-Boni und keine Auszahlung.
- **Ranglisten** (D-082): Spieler (Solo und Gruppe) und Gilden, gewertet nach dem höchsten erreichten Raum, bei Gleichstand nach Zeit; Allzeit und monatliche Saison (Wertung als Vorschlag).
- **Server** (D-083): eigener VPS mit Dokploy, Container für API (TypeScript) und Datenbank (PostgreSQL). Nur Gilden-, Run- und Ranglisten-Daten, **kein Echtzeit-Spielverkehr**. Das Spiel funktioniert ohne Server weiter (Einzelspieler, Schnelles Spiel).
- **Datenschutz:** nur Steam-ID bzw. Geräte-ID, Name, Gilde und Run-Berichte; Löschung auf Wunsch. *Zielbild D-108 (Vorschlag): zusätzlich die Nutzer-IDs von Google Play Games und Game Center.*

### 7.3 Schwierigkeit nach Spielerzahl (D-084, TESTWERTE)

- Gegneranzahl `× (1 + 0,6 · (n − 1))`, HP normaler Gegner `× (1 + 0,2 · (n − 1))`, HP von Champion/Miniboss/Boss `× (1 + 0,7 · (n − 1))`; Schaden, Elite-Chance und Gold je Gegner unverändert.
- Raumgröße: 1–2 Spieler S/M, 3–4 Spieler L.
- **Wiederbeleben:** Bei 0 HP zu Boden; Mitspieler belebt durch 2 s Danebenstehen (2 HP); Raum geschafft → alle stehen auf; alle am Boden → Run-Ende.
- Jeder Spieler hat einen eigenen Lichtkreis.

### 7.4 Raumarten – intensivere Dungeons (D-086)

**Problem heute:** Kampfräume sind große, recht leere Flächen mit Gegnern.

| Raumart | Inhalt |
| --- | --- |
| **Arena** | groß und offen, mehrere Wellen, reiner Kampf |
| **Strukturiert** | Innenmauern, Engstellen, Säulen als Deckung, getrennte Bereiche |
| **Abgrund** | Abgründe, Brücken, Plattformen; über Lücken springen, herunterfallen möglich |
| **Rätsel** | Idee für später (Schalter, Druckplatten, Kisten, Licht; Koop-Rätsel) |

- Gilt für normale Kampfräume; Spezial-, Miniboss- und Bossräume bleiben. Raumart und Biom sind unabhängig.
- **Springen = Dash** (keine neue Taste): Überquert Abgründe bis 1 Tile Breite. **Herunterfallen:** ein ganzes Herz (2 HP) direkt, zurück an die letzte sichere Stelle.
- Gegner meiden Abgründe, können aber durch starken Rückstoß hineingestoßen werden (nicht Champions, Golems, Bosse).
- Raum 1–5 ohne Abgründe; danach Arena 35 % / Strukturiert 40 % / Abgrund 25 %, kein Abgrund zweimal hintereinander.
- Kampfraumvorlagen haben 5–14 Spawnpunkte (ersetzt „genau fünf“, Abschnitt 4.2) und Größenklassen S/M/L.

### 7.5 Verständliches Dorf statt Upgrade-Flut (D-087)

- Jedes Gebäude erklärt beim ersten Betreten seine Rolle in einem Satz.
- Verbesserungen zeigen konkrete Werte („Max-HP 6 → 7“); der Run-Start fasst alle Dorf-Boni zusammen.
- Schrittweise Freischaltung: zu Beginn nur drei Verbesserungen; Chronik nach dem ersten Run, Handelsposten ab dem ersten Kristall, die restlichen Verbesserungen nach dem ersten Boss.
- Weniger Stufen (28 → 20), Kristall-Tausch entfällt.

### 7.6 Veröffentlichung auf Steam

> **Zielbild (D-108, Vorschlag):** zusätzlich Google Play und App Store mit Crossplay; Details und offene Punkte in [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md).

- **Vor Steam:** Windows-Build, Schnelles Spiel über direkte IP und virtuelles LAN.
- **Steam-Entwicklung:** Plugin GodotSteam, Test-AppID 480 (Lobbys und Einladungen ohne eigene App).
- **Eigene App:** Steam Direct (einmalige Gebühr), danach Steam Playtest oder Beta-Branch für Freunde; Steam-Anmeldung am eigenen Server.
- **Optional:** Achievements, Steam-Cloud für Spielstände.
- **OFFEN:** Zeitpunkt, wer das Steamworks-Konto führt, Rechte am Spiel im Team, Lizenzen für den Verkauf, Preis.

### 7.7 KI-Wunschbosse „Traumweber“ (Idee für später, OFFEN)

- Nach einem Boss beschreibt der Spieler einem Traumweber im Chat seinen eigenen Albtraum-Boss; eine KI erzeugt im Hintergrund Verhalten, Werte, Texte und Sprites **im Stil des Spiels**; wenige Räume später kommt der Kampf. Später auch als eigener Modus „Arena der Albträume“ und zum Teilen.
- **Leitprinzip:** Die KI wählt nur aus einem festen **Baukasten** (Daten, kein Code); Budget nach gewählter Schwierigkeit; das Spiel prüft alles selbst nach und lädt Daten und Bilder ohne Neukompilieren.
- Echte Personen und Marken nur als fiktive Hommage (Empfehlung); Moderation, Melden, Kostengrenzen, Steam-Angaben zu KI-Inhalten.
- Details: [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) · Plan: [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md)

## 8. Begriffe

Spielbegriffe mit englischer Entsprechung (Biom, Dorf, Seelenkristall, Gilde, Saison …): [PRODUKT.md](PRODUKT.md) §10. Hier stehen die technischen MVP-Begriffe.

| Begriff | Bedeutung |
| --- | --- |
| **Run** | Ein zusammenhängender Dungeon-Durchlauf; besitzt temporäre Waffen, Upgrades und Gold. |
| **MVP** | Erstes spielbares Zielpaket mit verbindlichem, bewusst begrenztem Umfang. |
| **Resource** | Typisierte Godot-Definition (`.tres`), nicht identisch mit Laufzeitstatus. |
| **Hit-ID** | Eindeutige Kennung einer Angriffs-/Trefferinstanz zur Verhinderung von Mehrfachregistrierung. |
| **I-Frames** | Zeitfenster ohne Wirkung normaler, blockierter Treffer. |
| **Softcap** | Reduzierte Wirksamkeit jenseits einer Schwelle, keine starre Obergrenze. |
| **Primäreffekt** | Direkter Angriff oder primärer Magierstab-AOE-Treffer. |
| **Sekundäreffekt** | Vom Primärtreffer ausgelöster zusätzlicher Effekt ohne erneute Sekundärkette. |
| **Host** | Spieler, dessen Spiel im Multiplayer die Spielwelt berechnet; die anderen sind **Clients**. |
| **Raumart** | Aufbau eines Raums (Arena, strukturiert, Sprung, Rätsel); unabhängig vom **Biom** (Optik, Gegner). |

**Weiterlesen:** [ARCHITECTURE.md](ARCHITECTURE.md) · [TECHSTACK.md](TECHSTACK.md) · [ROADMAP.md](ROADMAP.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) · [DECISIONS.md](DECISIONS.md)
