# PRD – Soulwick: Anforderungen an das Spiel

> **Stand:** 15.10.2026 · **Gilt für:** das Spiel in diesem Repository. Die Anforderungen an API, Website und Admin-Panel stehen im Repo `soulwick-platform` (`docs/PRD.md`).
> **Abgrenzung:** [PRODUKT.md](PRODUKT.md) = Überblick für beide Repositories (Pitch, Säulen, Zielgruppe, Status) · dieses PRD = was das Spiel leisten muss · [GLOSSAR.md](GLOSSAR.md) = Begriffe Deutsch ↔ Englisch · [DECISIONS.md](DECISIONS.md) = Zahlen und Ausgestaltung; bei Widerspruch gilt die jüngere D-Entscheidung.
> **Herkunft:** Abschnitte 2–6 stammen aus dem GDD Master 1.0 (10.10.2026, MVP); später beschlossene Änderungen sind eingearbeitet und mit D-Nummer markiert.
> **Leseregel:** `VERBINDLICH` = beschlossen · `TESTWERT` = vorläufige Zahl · `VORGESCHLAGEN` = braucht Bestätigung · `OFFEN` = nicht entschieden, nicht still festlegen.

## 1. Was ist Soulwick?

Ein **2D-Top-down-Dungeon-Roguelite** in Pixel-Art mit direkter, mausgesteuerter Action. Vom Dorf aus startet man einen Run in einen endlosen, dunklen Dungeon aus vorgefertigten, nahtlos verbundenen Räumen: Kämpfe, Minispiele, Spezialräume und alle 15 Räume ein Boss. Waffen, Upgrades und Run-Gold gelten nur im Run; ein Teil des Golds bleibt und baut das Dorf dauerhaft aus.

**Produktziel:** Ein vollständig spielbarer, wiederholbarer Kern-Loop, dessen Kampf- und Upgrade-System nach eindeutigen Regeln funktioniert und sich um Inhalte (Räume, Gegner, Waffen, Effekte) erweitern lässt, ohne den Kern neu zu bauen. Später kommen Koop für bis zu vier Spieler, Gilden, Ranglisten und Store-Veröffentlichung dazu (§7).

## 2. Designziele

1. **Direkte Steuerung:** Bewegung, Zielen, Angreifen und Dash fühlen sich präzise an.
2. **Bedeutsame Run-Entscheidungen:** Zwei Waffenslots, kombinierbare Upgrades und freiwillige Spezialräume schaffen Variation.
3. **Nachvollziehbare Regeln:** Schaden, Schild, Trefferhistorie, Effektauslösung und Goldtransfer folgen einer eindeutigen Rechen- bzw. Zustandslogik.
4. **Wiederverwendbarer Inhalt:** Neue Raumvorlagen, Gegner, Waffen und Effekte sind Daten oder Szenen, kein Umbau des Kerns.
5. **Ein Raum, eine Aufgabe:** Jeder Raum ist in einem Satz erklärbar und kündigt sich vorher an (D-120).

## 3. Kern-Loop

1. Im **Dorf** den Dungeon-Eingang mit **E** benutzen; ein neuer Run startet ohne Ausrüstung aus dem letzten Run, aber mit den dauerhaften Dorf-Verbesserungen.
2. Im Raum schließt sich der Eingang; erst nach erfüllter Aufgabe (meist: alle Gegner besiegt) öffnet der Ausgang.
3. Über den **Fünferzyklus** (§4.1) voranschreiten, alle 15 Räume ein Boss, danach ein **Lagerfeuer** mit Ausgangsportal (D-103).
4. **Waffen** und **Upgrades** kombinieren, **Gold** sammeln und freiwillig ausgeben.
5. Per **Portal** aussteigen (100 % des Run-Golds) oder bei **Tod/Abbruch** zurückkehren (50 %).
6. Mit Gold und Seelenkristallen im Dorf ausbauen; der nächste Run beginnt.

## 4. Anforderungen an den Kern

### 4.1 Dungeonstruktur – VERBINDLICH

| Platz im Fünferzyklus | Funktion |
| --- | --- |
| 1, 2 | Kampfraum (ab Zyklus 2 auch Minispiel) |
| 3 | Kampfraum (auch Arena oder Minispiel), **Upgrade-Wahl erst nach Abschluss** |
| 4 | Spezialraum (Ruhe oder Prüfung) |
| 5 | Miniboss (Champion, D-077); auf jedem 15. Raum stattdessen der **Boss** des Bioms |

- **Endlos** (D-073): kein Ende und keine Wahl bei Raum 45; der Zyklus wiederholt sich unbegrenzt, alle 15 Räume wechselt das Biom (D-075), nach jedem Boss folgt ein Lagerfeuer, das nicht als Raum zählt (D-103).
- **Raumarten und Minispiele** nach [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) (D-120): Säubern, Arena, acht Minispiele (ab Zyklus 2, 30–40 % der Kampfräume, TESTWERT), Wagnis-Altar, Elite-Nest über Abzweigungen, Geheimnischen. Misserfolg in einem Minispiel kostet nur den Bonus, nie den Run.
- **Spezialräume:** Händler, Waffenauswahl, Brunnen, Upgrade-Altar (in einem Drittel als Pakt-Altar, D-112) und Prüfungsraum (D-102), gewichtet gezogen, der direkt vorherige Typ wiederholt sich nicht. Angebote sind freiwillig.
- **Portal:** In **30 %** der Spezialräume steht zusätzlich ein Ausgangsportal (E plus Bestätigung). Reihenfolge von Typ- und Portalziehung: ursprünglich `OFFEN`, umgesetzt nach Vorschlag D-058 (Typ zuerst, Portal unabhängig), Bestätigung im Team ausstehend.

### 4.2 Gegner, Spawning und Schwierigkeit – VERBINDLICH (Zahlen TESTWERT)

- Gegner blockieren einander, verursachen **kein Friendly Fire**, kündigen Angriffe sichtbar an und zeigen ihre HP-Leiste. Treffer verursachen leichten Rückstoß; nach dem Tod folgt eine kurze Animation und Gold-Drop.
- Normale Gegner haben **keine allgemeinen Treffer-I-Frames**; dieselbe Hit-ID wirkt aber nur einmal auf dasselbe Ziel.
- **Spawning:** Gegner erscheinen aus sichtbaren Quellen des Grundrisses mit 1 s Warnung, bevorzugt hinter dem Spieler (D-132); gezogen wird ohne Zurücklegen. Die frühere Regel „genau fünf Spawnpunkte“ ist ersetzt (D-086: 5–14 je Vorlage, heute die Quellen der Pläne).
- **Gegnertypen** je Biom aus eigener Tabelle (D-075); in der Krypta gelten die Grundgewichte Slime 50 % / Skelett 35 % / Bogenschütze 15 % (D-010).
- **Anzahl, Wellen und Skalierung** steigen mit der Raumnummer: Werte nach D-074 und D-118 (ersetzen die MVP-Werte „1–3 Gegner, ×1,20 HP, ×1,10 Schaden“). Mehr, aber einzeln schwächere Gegner; Slimes in Rudeln, Nahkämpfer flankieren (D-130).
- **Miniboss** = Champion: Gegner des Bioms mit Elite-Eigenschaft, mehr HP und Begleitern (D-077). **Bosse:** vier (Knochenkönig, Schleimkönigin, Schattenlord, Glutgolem), je zwei Phasen, nach jedem vollen Zyklus eine Stufe stärker (D-065, D-076).

### 4.3 Spieler und Eingaben – VERBINDLICH

| Eingabe | Aktion |
| --- | --- |
| WASD | Bewegung; diagonale Eingaben normalisiert |
| Maus | durchgängiges 360°-Zielen |
| Linke Maustaste (halten) | wiederholte Normalangriffe nach effektiver Angriffsrate |
| Rechte Maustaste | Spezialangriff der aktiven Waffe mit Abklingzeit (D-090) |
| Leertaste | Dash in Bewegungsrichtung, ohne Bewegung in Zielrichtung |
| Q | zwischen den zwei Waffenslots wechseln |
| E | Interaktion (Dorf-Eingang, Portal, Händler, Altar …) |
| Tab | pausierte Übersicht der Upgrades |
| Esc | Pausemenü |

- Start mit **6 HP = drei Herzen**, Anzeige in halben Herzen (0,5 HP).
- Alle **fünf abgeschlossenen Räume** heilt der Spieler **1 HP**, höchstens bis zur HP-Obergrenze.
- **Schild vor HP**; keine passive Regeneration, keine harte Obergrenze. Gewinne über einer Schwelle wirken nur zur Hälfte (Softcap; Schwelle TESTWERT, heute 15 nach D-074; Rundung nach D-091).
- Dash bricht laufende Angriffe ab, verbietet neue während des Dashs und schützt unabhängig von Treffer-I-Frames. Dauer, Tempo und Abklingzeit sind TESTWERTE am Spieler.
- Jeder **tatsächlich schadenswirksame Treffer** gegen Schild oder HP löst **0,5 s** Treffer-Unverwundbarkeit aus. Vollständig blockierte Treffer verursachen weder Schaden noch schadensabhängige Effekte.

### 4.4 Waffen – VERBINDLICH (Werte TESTWERT)

Zwei Slots, genau eine aktive Waffe, **kein Waffentyp doppelt**. Bei zwei belegten Slots muss beim Kauf oder in der Waffenauswahl ein Slot ersetzt werden. Run-Upgrades bleiben erhalten. Seltenheit ist technisch vorgesehen, hat aber **keine spielerische Auswirkung**. Zahlenwerte stehen in `weapons/data/*.tres`.

- **Schwert:** Schwungangriff in Zielrichtung, je Schwung und Ziel höchstens ein Treffer; jeder dritte Schlag ist ein Finisher (D-090).
- **Bogen:** schneller Pfeil; Durchschlag und Wandabprall nur über Upgrades.
- **Magierstab:** langsames magisches Geschoss mit **einem einzigen Flächentreffer** beim Einschlag, der das direkt getroffene Ziel einschließt (kein zusätzlicher Direktschaden).
- **Dolche** (schnell, Hinterhalt ×2) und **Kriegshammer** (langsamer Flächenschlag), seit D-090.
- Angriffsrate = **Angriffe pro Sekunde**; Bonusprozente werden addiert.

### 4.5 Upgrades – genau 15 Typen

Alle Upgrades gelten **runweit** für passende Angriffe. Eine Auswahl bietet bis zu **drei verschiedene verfügbare** Upgrades, keine Dubletten. Gibt es keines mehr, wird keine Ersatzbelohnung erfunden. Tag-Filter: **ODER** über die anwendbaren Tags; zusätzliche `required_tags` müssen **alle** zutreffen.

| Kategorie | Upgrade | Wirkung je Stufe (MVP-TESTWERT; geändert durch D-074, D-091, aktuell in `upgrades/data/*.tres`) | Limit |
| --- | --- | --- | --- |
| Attribut | Verstärkter Angriff | +10 % Schaden | ∞ |
| Attribut | Krafttraining | +2 Nahkampfschaden | ∞ |
| Attribut | Schneller Angriff | +15 % Angriffsrate | ∞ |
| Attribut | Präzise Pfeile | +20 % Pfeilschaden | ∞ |
| Attribut | Magische Verstärkung | +20 % Magieschaden | ∞ |
| Attribut | Schnelle Geschosse | +20 % Projektilgeschwindigkeit | ∞ |
| Attribut | Schildverstärkung | +10 Schild sofort (vor Softcap) | ∞ |
| Mechanik | Durchschlag | +1 weiterer Gegner je Pfeil | 3 |
| Mechanik | Wandabprall | 1 Abprall je Projektil | 1 |
| Mechanik | Doppelschuss | +1 Projektil je Angriff | 1 |
| Mechanik | Größerer Schwung | +20 % Angriffswinkel | 3 |
| Mechanik | Größere Explosion | +20 % Flächenradius | 3 |
| Effekt | Explosiver Treffer | Zweitexplosion mit 50 % des auslösenden Treffers | 1 |
| Effekt | Heilung bei Tötung | +2 HP je Kill und Stufe, bis Max-HP | ∞ |
| Effekt | Schild bei Tötung | +2 Schild je Kill und Stufe (heute gedeckelt, D-091) | ∞ |

**Effektregeln:** Sekundäreffekte lösen **keine weiteren Sekundäreffekte** aus, dürfen aber normale Kills erzeugen; deren Tötungsbelohnungen (Heilung, Schild) gelten. Eine Upgrade-Explosion darf das schon getroffene Ziel noch einmal treffen. Beim Magierstab entsteht aus **einem** primären Flächentreffer höchstens **eine** Upgrade-Explosion, auch bei mehreren Getroffenen (für alle Waffen eine je Hit-ID, Vorschlag D-056). Doppelschuss-Projektile haben getrennte Trefferhistorien. Radiusboni wirken additiv.

### 4.6 Händler, Gold und Run-Ende – VERBINDLICH

- **Händler:** bis zu **sechs gültige Angebote** (2 Upgrades, 2 Waffen, 1 Heilung, 1 Schild; Mengen TESTWERT, D-036, D-074); nicht verfügbare oder nicht kaufbare Angebote werden weggelassen, nicht ersetzt.
- **Waffenauswahl:** bis zu **zwei nicht besessene Waffen**, ggf. mit Slotersatz. **Brunnen:** einmal kostenlos +3 HP bis Max-HP (D-037).
- Käufe sind **atomar**: Abbuchung und Lieferung zusammen oder gar nicht.
- **Tod oder Abbruch:** **50 %** des verbleibenden Run-Golds werden dauerhaft gutgeschrieben, aufgerundet (D-062). **Portal:** **100 %**. Jeder Run wird **genau einmal** ausgezahlt.
- Gold-Drops, Preise und Wachstum sind TESTWERTE (D-064, D-091, D-118); Seelenkristalle als zweite Währung (D-078, D-109).

### 4.7 UI, Pause, Sprache und Speicherung – VERBINDLICH

- Kompaktes HUD am Rand: Herzen, Schild mit Symbol, Run-Gold, aktive Waffe mit Werten; Aufgabenleiste für Minispiele (D-133).
- Schadenszahlen über Gegnern, Schild- und HP-Schaden unterscheidbar, Trefferfeedback mit Aufblitzen und Rückstoß.
- Waffenvergleich und Händler zeigen **effektive Werte inklusive Upgrades**.
- Händler, Waffen- und Upgrade-Auswahl, Tab-Übersicht und Esc-Menü **pausieren im Einzelspieler die ganze Simulation** (auch Projektile und Timer); Menüs bleiben bedienbar, mehrere Pausengründe können gleichzeitig gelten. Im Multiplayer pausieren Menüs nicht (§7.1).
- Texte in **Englisch (Standard) und Deutsch**, Systemsprache automatisch, umschaltbar (D-111).
- Gespeichert werden **nur dauerhafte Werte** (Dorf-Fortschritt, Gold, Kristalle, Statistik, Einstellungen) in mehreren Spielständen; **kein Fortsetzen eines Runs** nach Neustart. Format: Godot-`ConfigFile` mit Version und Migration (D-059, VORGESCHLAGEN).
- Dorf ↔ Dungeon erzeugt eine neue Spielerinstanz; Raum ↔ Raum im Dungeon behält dieselbe.

### 4.8 Dorf und Meta-Progression – VERBINDLICH (D-078, D-087)

- Begehbare Gebäude: Schmiede (dauerhafte Verbesserungen gegen Gold), Handelsposten (Proviant für den nächsten Run gegen Seelenkristalle), Chronik (Rekorde, Statistik), Zuhause (Kleidungsfarbe), Gildenhaus (Koop, in Vorbereitung).
- Jedes Gebäude erklärt beim ersten Betreten seine Rolle in einem Satz; Verbesserungen zeigen konkrete Werte („Max-HP 6 → 7“); der Run-Start fasst alle Dorf-Boni zusammen.
- Schrittweise Freischaltung: anfangs drei Verbesserungen, Chronik nach dem ersten Run, Handelsposten ab dem ersten Kristall, der Rest nach dem ersten Boss.

### 4.9 Stimmung

- Der Dungeon ist dunkel: Lichtkreis um den Spieler, Fackeln, Geschosse und Münzen leuchten (D-067, Licht D-141).
- Musik je Biom und Boss mit weichen Übergängen, Geräuschkulissen (D-092, D-097; [AUDIO.md](AUDIO.md)).

## 5. Abnahme

Der MVP ist abgenommen, wenn ein regulärer Run vom Dorf aus möglich ist, Spieler, Gegner und Waffen korrekt kämpfen, Raum- und Bossfolge stimmen, Spezialräume und Upgrade-Regeln gelten, Treffer, Gold-Drops und Run-Ende korrekt verarbeitet werden und nach einem Neustart nur dauerhafte Zustände vorhanden sind. Das Projekt muss frisch geklont startbar und getestet sein. Detailkriterien und Prüfstand: [ROADMAP.md](ROADMAP.md); jede Erweiterung wird in ihrer Roadmap mit Nachweis (Tests, Datum) abgehakt.

## 6. Bewusst nicht vorgesehen

- Spielmechanisch wirksame Seltenheiten bei Waffen.
- Andere Upgrade-Typen als die 15 aus §4.5, insbesondere Feuer- oder Gift-Statussysteme.
- Rüstungs- oder Resistenzsystem, kritische Treffer.
- Fortsetzen eines unterbrochenen Runs nach Programmneustart.
- Endgültig ausbalancierte Werte: alle Zahlen bleiben TESTWERTE, bis das Team sie festlegt.

## 7. Ausbau nach dem Kern (Vision)

> Ziele beschlossen (D-080 bis D-088, D-108, D-119), Umsetzung nach Phasen: Räume ([ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md)) → Multiplayer ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md), Technik [MULTIPLAYER.md](MULTIPLAYER.md)) → Crossplay ([ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md)) → KI-Bosse ([ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md)). Was online dazukommt, beschreibt [PRODUKT.md](PRODUKT.md) §5. Als „Vorschlag“ markierte Punkte brauchen noch eine Bestätigung.

### 7.1 Koop mit Freunden

- **2–4 Spieler** in einem Run, auch über das Internet. Ein Spieler ist **Host** und rechnet die Spielwelt; die Pakete laufen über einen eigenen Relay mit Raumcode, Spiellogik gibt es nur im Spiel (D-119).
- **Zwei Wege** im Gildenhaus (D-080): **Schnelles Spiel** (ohne Bindung) und **Gilde** (§7.2).
- **Getrennt vom Einzelspieler** (D-081): ohne eigene Dorf-Verbesserungen; Run-Gold ist eine **gemeinsame Kasse**, Waffen und Upgrades bleiben je Spieler.
- **Menüs pausieren nicht**; wer ein Menü offen hat, ist geschützt. Fällt der Host aus, endet der Run (Vorschlag D-085).

### 7.2 Gilden und Ranglisten

- **Gilde** (D-080): gründen, per Einladungscode beitreten, jederzeit verlassen; bis zu 5 Gilden je Spieler, höchstens 30 Mitglieder (D-147); Gilden-Runs nur mit Mitgliedern. Gildenkasse und Gilden-Schmiede auf dem Server (Vorschlag D-081); Schnelles Spiel hat keine Meta-Boni und keine Auszahlung.
- **Ranglisten** (D-082): Solo, Gruppe und Gilden, gewertet nach höchstem Raum, bei Gleichstand nach Zeit; Allzeit und Monats-Saison.
- **Server** (D-083, D-119): eigener Server mit API, Datenbank und Relay im Repo `soulwick-platform`. Das Spiel bleibt ohne Server spielbar; jeder Aufruf darf scheitern.
- **Datenschutz:** nur Plattform-IDs, Name, Gilde und Run-Berichte; Löschen auf Wunsch (Details im Plattform-PRD).

### 7.3 Schwierigkeit nach Spielerzahl (D-084, TESTWERTE)

- Mehr Gegner und mehr HP je zusätzlichem Spieler, deutlich mehr bei Champions und Bossen; Schaden, Elite-Chance und Gold je Gegner bleiben. Formeln in D-084.
- **Wiederbeleben:** Bei 0 HP zu Boden; ein Mitspieler belebt durch 2 s Danebenstehen; Raum geschafft → alle stehen auf; alle am Boden → Run-Ende.
- Jeder Spieler hat einen eigenen Lichtkreis.

### 7.4 Raumarten

Umgesetzt und in §4.1 eingearbeitet; maßgeblich ist heute [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) (D-120, ersetzt Teile von D-086 und D-100). Koop-exklusive Raumideen sind für MP5 vorgemerkt.

### 7.5 Verständliches Dorf

Umgesetzt, siehe §4.8 (D-087).

### 7.6 Veröffentlichung

- **Reihenfolge** (D-119): Steam → Android → iOS, Crossplay über alle (Zielbild D-108, Details [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md)). **Publisher:** WebBude.
- **Vor Steam:** Windows-Build und Test-Builds für Freunde über den Relay.
- **Steam:** GodotSteam, Test-AppID 480 für Lobbys und Einladungen in der Entwicklung, danach Steam Direct und Playtest bzw. Beta-Branch; Steam ist Zusatz zum eigenen Relay (Anmeldung, Freunde einladen). Optional: Achievements, Steam-Cloud.
- **OFFEN:** Geschäftsmodell und Preis (CP0 Frage 1), Zeitpunkt, Rechte am Spiel im Team und Lizenzen für den Verkauf (MP10), Touch-Steuerung (Prototyp CP2).

### 7.7 KI-Wunschbosse „Traumweber“ (Idee, OFFEN)

Nach einem Boss beschreibt der Spieler einem Traumweber seinen eigenen Albtraum-Boss; eine KI stellt daraus aus einem festen **Baukasten** (Daten, kein Code) Verhalten, Werte, Texte und Sprites im Stil des Spiels zusammen, das Spiel prüft alles selbst. Echte Personen und Marken nur als fiktive Hommage (Empfehlung). Details: [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) · Plan: [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md).

## 8. Technische Begriffe

Spielbegriffe (Run, Raumart, Biom, Host …) stehen im [GLOSSAR.md](GLOSSAR.md). Hier nur die Begriffe der Regeln oben:

| Begriff | Bedeutung |
| --- | --- |
| **Resource** | typisierte Godot-Definition (`.tres`), nicht der Laufzeitzustand |
| **Hit-ID** | eindeutige Kennung einer Angriffsinstanz gegen Mehrfachtreffer |
| **I-Frames** | Zeitfenster, in dem normale Treffer blockiert sind |
| **Softcap** | verringerte Wirkung oberhalb einer Schwelle statt harter Obergrenze |
| **Primär-, Sekundäreffekt** | direkter Angriff bzw. Flächentreffer des Stabs; davon ausgelöster Zusatzeffekt ohne weitere Kette |

**Weiterlesen:** [ARCHITECTURE.md](ARCHITECTURE.md) · [TECHSTACK.md](TECHSTACK.md) · [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) · [DECISIONS.md](DECISIONS.md)
