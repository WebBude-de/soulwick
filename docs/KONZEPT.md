# Konzept Release 1.0 – Soulwick als Vollversion

> **Stand:** 22.10.2026 · **Status:** Die Absichten des Projektmitglieds vom 22.10.2026 sind **VERBINDLICH** (D-194): Extraktion, Level mit Talentpunkten, Schwierigkeit wächst mit dem Spieler (Rang im Licht-Motiv), drei Säulen im Dorf (Schmiede, Handelsposten, Zuhause mit Talentbaum), weniger Seelenkristalle, Flint als Begleiter, der Dorf, Dungeon und neue Räume erklärt, Schnelles Spiel mit dem Solo-Charakter und Gilden mit eigenen Gilden-Charakteren, KI-Bosse zum Release. **Alle Zahlen sind TESTWERT**, die Ausgestaltung ist **VORGESCHLAGEN**; Antworten und Restfragen stehen in §12.
> **Ersetzt** die früheren Konzepte (Begleiter und Kosmetik, Konto und Fortschritt, KI-Boss, Party-Modus; D-193). Die volle frühere Fassung liest man mit `git show 6f6eab3:docs/<DATEI>.md`; Raumregeln stehen in [RAEUME.md](RAEUME.md), Text- und Optionsregeln in [SPRACHEN.md](SPRACHEN.md).
> **Umsetzung:** [ROADMAP.md](ROADMAP.md) · **Grafik:** [design/sprites/SPRITES_V13.md](design/sprites/SPRITES_V13.md) · **Begriffe:** [GLOSSAR.md](GLOSSAR.md) · **Leseregel:** `VERBINDLICH` = beschlossen · `TESTWERT` = vorläufige Zahl · `VORGESCHLAGEN` = braucht Bestätigung · `OFFEN` = nicht still festlegen.

## 1. Was wir aus der Demo gelernt haben

Die Demo hat gezeigt: Kampf, Räume, Koop und Dorf funktionieren, aber das Spiel hat noch **keinen Grund, wiederzukommen**. Die ersten Räume bleiben auch nach 30 Runs leicht, die Schmiede ist nach ein paar Abenden leer, Seelenkristalle gibt es zu viele, und niemand erklärt, was man tun soll. Die Vollversion baut deshalb den Kern um:

1. **Rein, plündern, raus:** Jeder Run ist eine Wette. Wer durch ein Seelentor aussteigt, nimmt alles mit; wer stirbt, verliert das meiste (§2).
2. **Du wirst stärker, die Welt auch:** Level geben Talentpunkte für den eigenen Charakter; dafür startet jeder neue Run gefährlicher, passend zu Level und Können (§3, §4). Der Rang zeigt, wie gut man gerade ist.
3. **Drei klare Säulen im Dorf:** Schmiede = Waffen und Ausrüstung (Gold), Handelsposten = Glück und Meta-Vorteile (Kristalle), Zuhause = Talentbaum und Zauber (Level) (§5, §6).
4. **Flint führt dich:** Das kleine Docht-Wesen ist immer dabei, macht Licht und erklärt Dorf, Steuerung und jede neue Raumart beim ersten Mal (§7).

**Kernschleife:** Dorf (ausgeben, umskillen) → Dungeon mit der eigenen Gefahrenstufe → tiefer gehen oder durchs Seelentor raus → Gold, Kristalle, XP → Level, Rang, nächster Run.

## 2. Run und Extraktion (VERBINDLICH: „man soll extracten können“)

**Absicht:** Gold ist eine Entscheidung (PRD §4.6), aber heute verliert man beim Tod nur die Hälfte, also lohnt Aussteigen kaum. Künftig ist jede Tür eine Frage: „Sichere ich jetzt oder wage ich noch einen Raum?“

| Regel | Heute (Code) | Release (Vorschlag, TESTWERT) |
| --- | --- | --- |
| Seelentor (bisher „Ausgangsportal“) | immer am Lagerfeuer nach jedem Boss, in 30 % der Spezialräume | am Lagerfeuer wie heute; dazu am Platz 4 (Spezialraum) in 50 % der Zyklen, **nie zwei Zyklen in Folge ohne Tor** |
| Auszahlung beim Seelentor | 100 % Gold und Kristalle | 100 % |
| Auszahlung bei Tod oder Abbruch | 50 % (aufgerundet) | **25 %** (aufgerundet); mit dem Proviant „Seelenanker“ 50 % |
| Tiefenbonus | Gold je Gegner wächst nicht (`growth per block 0.0`) | Gold je Gegner und Boss-Kristalle **+10 % je Fünferblock** |
| XP | gibt es immer, Portal +20 XP | bleibt; XP gibt es auch beim Tod, das Level fällt nie |
| Rückkehrstein | – | Proviant: öffnet einmal je Run überall ein Seelentor (nicht im Boss- oder Arenakampf) |

- **Der Moment am Tor** zeigt beide Seiten: „Jetzt sichern: 240 Gold · 3 Kristalle“ gegen „Weiter: Tiefenbonus +40 %, nächstes Tor frühestens in 5 Räumen“.
- **Run-Waffen und Upgrades** bleiben wie heute nur im Run (Roguelite-Kern). Mitgenommen werden Gold, Kristalle, XP und Freischaltungen.
- **Koop:** Das Seelentor darf jeder benutzen und beendet den Run für alle; wer aufgibt, verlässt den Run mit der Tod-Auszahlung, die anderen spielen weiter (D-126). Ausgezahlt wird aus der gemeinsamen Kasse (§9).

## 3. Schwierigkeit: zwei Achsen

**Achse 1 – im Run (gebaut, bleibt):** Jeder Fünferblock macht Gegner stärker, schneller und zahlreicher; alle 15 Räume ein Boss und ein neues Biom, nach jedem vollen Bosszyklus steigt die Boss-Stufe (D-074, D-076, D-154; `enemies/enemy_scaling.gd`, `dungeon/room_sequence.gd`).

**Achse 2 – zwischen den Runs (neu, VERBINDLICH: „je mehr Erfahrung, desto schwerer schon von Anfang an“):** Jeder Run startet mit einer **Gefahrenstufe G**. Sie hängt an zwei Dingen:

| Teil | Formel (TESTWERT) | Warum |
| --- | --- | --- |
| Erfahrung (Level L) | `G_level = floor((L − 1) / 2)` | wer viel gespielt und geskillt hat, bekommt keine leichten Anfangsräume mehr |
| Können (letzte Runs) | `G_können = floor(Median(tiefster Raum der letzten 5 Runs) / 5) + 1`; bei weniger als 3 Runs gilt `G_level` | die Stufe passt sich an, wie gut man **gerade** ist, und kann sinken (wie Matchmaking) |
| **Gefahrenstufe** | `G = min(G_level, G_können)` | Level ist der Deckel, Können die Feinsteuerung |

- **Gleichgewicht:** Wer auf Stufe G im Mittel Raum 5·G erreicht, bleibt dort; wer tiefer kommt, steigt, wer früh stirbt, sinkt. So landet jeder Spieler dort, wo es knapp wird.
- **Keine eigene Wahl** (D-196): Die Stufe kommt aus dem Rang; am Dungeon-Eingang zeigt Flint Rang und Stufe nur an. Die Belohnung folgt der Stufe.

**Wirkung je Stufe (TESTWERT, linear, damit der Balance-Agent sauber messen kann):**

| Größe | je Stufe G |
| --- | --- |
| Gegner-HP (auch Champions und Bosse) | +6 % |
| Gegner-Schaden | +4 % |
| Elite-Chance | +1,5 Prozentpunkte (Deckel wie heute 50 %) |
| Gold, Kristalle und XP | +5 % |
| ab G 3 | erste Champions schon im ersten Zyklus |
| ab G 6 | Gegner aus dem nächsten Biom mischen sich ein (je Biom eine Gegnerart, Dungeon-RNG) |
| ab G 9 | „Gefahr-Zeichen“: eine zufällige Raum-Regel je Zyklus (z. B. schnellere Quellen, dunklere Räume); Liste im Paket KE2, OFFEN |

### 3.1 Rang (VERBINDLICH: Ränge wie Matchmaking, Level bleiben, Namen im Licht-Motiv)

Der **Rang** ist der Name der eigenen Gefahrenstufe und zeigt, wie gut man gerade ist; das **Level** zeigt, wie viel man gespielt hat. Level steigen nur, Ränge können fallen.

| Gefahrenstufe | Rang (Deutsch / English) |
| --- | --- |
| 0–2 | Funke I–III / Spark I–III |
| 3–5 | Kerze I–III / Candle I–III |
| 6–8 | Flamme I–III / Flame I–III |
| 9–11 | Laterne I–III / Lantern I–III |
| 12–14 | Leuchtfeuer I–III / Beacon I–III |
| 15 und mehr | Seelenmeister 1, 2, … / Soul Master 1, 2, … |

- Sichtbar: Hauptmenü (Abzeichen neben dem Level), Dungeon-Eingang, Lobby-Platz, Gilde, Rangliste, Run-Ende („Rang gestiegen: Kerze II“). Abzeichen je Rang: SPRITES_V13 §B3.
- Ranglisten (MP9) bekommen eine Ansicht „nach Rang“ zusätzlich zu „tiefster Raum“ (Vorschlag).
- **Rang fällt richtig** (D-205): Der Rang folgt der Gefahrenstufe in beide Richtungen, damit Gruppen im Schnellen Spiel fair bleiben; kein Schutz der ersten Stufenmarke.
- Namen im Licht-Motiv (Projektmitglied 22.10.2026: „Licht klingt cool“): vom ersten Funken bis zum Seelenmeister; „Kerze“ statt „Glut“, damit der Rang nicht wie der Talent-Pfad der Glut heißt.

### 3.2 Gefahr im Koop

- **Gruppen-Stufe** = gerundeter Mittelwert der Stufen aller Spieler im Raum (Schnelles Spiel und Gilden-Run); niemand senkt sie von Hand (D-196). Die Koop-Skalierung nach Spielerzahl (D-084) kommt obendrauf.
- Alle bekommen Beute und XP nach der Gruppen-Stufe; jeder Run zählt für die „letzten 5 Runs“ jedes Spielers.
- In Gilden-Runs zählen Gilden-Level und letzte Gilden-Runs statt Konto-Level und Solo-Runs (§9).
- Die Stufe rechnet nur der Host (D-119); Clients zeigen sie.

## 4. Level, XP und Talentpunkte

**VERBINDLICH (Projektmitglied 22.10.2026):** Man levelt mit XP, und Level geben Punkte für den Talentbaum im Zuhause. **Das ersetzt D-188 Punkt 4** („Konto-Level nur Optik“): Das Level hat jetzt eine Spielwirkung, aber nur über den Talentbaum.

- **XP-Quellen und Kurve** bleiben wie gebaut (KF2, `meta/account_progress.gd`): Raum 5, Champion 10, Boss 50, neuer Konto-Rekord 5 je Raum, Seelentor 20, erster Run des Tages 25, Koop +20 %; Level L ab `50 · L · (L − 1)` XP (TESTWERT). Neu: XP × (1 + 0,05 · G) (§3).
- **Je Level 1 Talentpunkt** (Level 2 gibt den ersten). Wer Level 50 erreicht, hat 49 Punkte; der Baum kostet rund 60 Punkte, also geht nie alles gleichzeitig, und Umskillen lohnt sich.
- **Alle 5 Level** zusätzlich ein Kosmetik-Teil oder Titel (wie D-188 §5.5, nur Optik).
- **Gilt je Konto**, über alle Welten und Geräte (wie das Level). Gold, Kristalle, Schmiede und Handelsposten bleiben je Welt (D-152). In Gilden-Runs spielt man stattdessen den **Gilden-Charakter** mit eigenem Gilden-Level und eigenen Talentpunkten (§9).
- Was man über Level bekommt, kann man nie kaufen (D-176: kein Pay-to-win).

## 5. Das Dorf: drei Säulen

**VERBINDLICH:** Schmiede nur Waffen und technische Verbesserungen; Zuhause mit Talentbaum (und später einrichten); Handelsposten für Meta-Vorteile wie doppeltes Gold, mehr Glück oder Schutz vor Blindheit, bezahlt mit Kristallen. Jedes Gebäude erklärt sich weiter beim ersten Besuch (D-087), jetzt durch Flint (§7).

| Säule | Währung | Wofür | Gilt für |
| --- | --- | --- | --- |
| **Schmiede** | Gold | Waffen freischalten und schmieden, Ausrüstung | die Welt |
| **Handelsposten** | Seelenkristalle | Proviant für den nächsten Run, dauerhafte Glücks- und Handelsstufen | die Welt |
| **Zuhause** | Talentpunkte (Level) | Talentbaum, Zauber ausrüsten, Spiegel (Profil), später Möbel und Pets | das Konto |

Chronik (Statistiken, neu mit Rang-Verlauf), Gilde (Online) und Dungeon-Eingang bleiben. Der Traumweber kommt mit den KI-Bossen dazu (§11).

### 5.1 Schmiede – Waffen und Ausrüstung (Gold)

| Stufe | Wirkung (TESTWERT) | Kosten (Gold, TESTWERT) |
| --- | --- | --- |
| **Arsenal** | Waffe für die Startwahl freischalten: Bogen, Stab, Dolche, Hammer (Schwert hat man immer) | 80 · 120 · 160 · 200 |
| Zweiter Startplatz | mit zwei Waffen starten | 300 |
| **Waffe schmieden I–V** (je Waffe) | +8 % Schaden je Stufe; Stufe III verstärkt das Spezial (Rechtsklick); Stufe V „Meisterstück“ mit eigenem Glanz | 60 · 120 · 200 · 320 · 480 |
| **Schildplatte** (bisher Startschild) | +3 Schild zu Beginn je Stufe, 3 Stufen | 40 · 90 · 160 |
| **Laterne** | +10 % Lichtradius je Stufe, 3 Stufen | 50 · 110 · 200 |

- Schmiede-Stufen gelten nur für Waffen, die man im Run findet oder mitnimmt; die Wirkung zeigt der Dialog als Zahl („Schaden 4 → 4,3“, D-087).
- **Wandert in den Talentbaum:** Vitalität, Dash-Training. **Wandert in den Handelsposten:** Goldgier (als Proviant „Goldregen“). **Entfällt:** Schärfe (+10 % auf alles), ersetzt durch „Waffe schmieden“.
- **Migration (Spielstand v5, KE4):** Gold für Vitalität, Schärfe, Goldgier und Dash-Training wird voll erstattet; Startschild → Schildplatte gleiche Stufe; Arsenal 1 → Bogen frei, Arsenal 2 → Bogen und Stab frei. Ein Hinweis im Dorf sagt, was passiert ist.

### 5.2 Handelsposten – Glück und Meta-Vorteile (Kristalle)

**Proviant** (gilt nur für den nächsten Run, wird beim Start verbraucht; erst 1 Platz, mit Handelsstufen bis 3):

| Proviant | Wirkung (TESTWERT) | Kristalle |
| --- | --- | ---: |
| Goldregen | doppeltes Gold im nächsten Run | 4 |
| Glücksamulett | Start mit einem seltenen Upgrade | 3 |
| Klarsicht | immun gegen Blindheit und Düsternis (Flüche, Dunkel-Fallen, Lichtfeuer-Dunkel) | 2 |
| Heiltrank | +2 Max-HP für den Run | 2 |
| Seelenanker | beim Tod 50 % statt 25 % behalten | 3 |
| Rückkehrstein | einmal überall ein Seelentor öffnen (§2) | 5 |
| Spürnase | Geheimnischen schimmern, Abzweigungen zeigen ihre Belohnung | 2 |

**Dauerhafte Handelsstufen** (das Sparziel für Kristalle):

| Stufe | Wirkung (TESTWERT) | Kristalle |
| --- | --- | --- |
| Proviant-Platz 2 · 3 | zwei bzw. drei Proviant gleichzeitig | 8 · 15 |
| Glück I–III | seltene Upgrades in der Auswahl +10 % je Stufe | 6 · 12 · 20 |
| Händlerfreund I–II | Dungeon-Händler −10 % je Stufe | 5 · 10 |

### 5.3 Seelenkristalle: weniger und wertvoller (VERBINDLICH: „viel zu viele“)

Heute kommen Kristalle aus neun Quellen und gelten auch beim Tod zur Hälfte. Ziel (TESTWERT, misst KE9): **ein früher Run bringt 0–2, ein Run bis zum ersten Boss 3–5, ein tiefer Run 8–12 Kristalle**.

| Quelle | heute | Release (Vorschlag) |
| --- | ---: | --- |
| Boss | 3 | 3 (+ Tiefenbonus, + Gefahrenstufe) |
| Champion | 1 | 30 % Chance auf 1 |
| Geheimnische, Elite-Nest | 2 | 1 |
| Wagnis-Altar | 1–2 | 1 |
| Prüfung makellos, Flamme voll, Risse schnell | 1 | Gold-Bonus statt Kristall |
| Seelen sammeln 12/9/6 | 3/2/1 | 2/1/0 |
| Tod | 50 % | 25 % (§2) |

### 5.4 Gold-Fluss

Gold bleibt die Hauptwährung für die Schmiede. Ziel (TESTWERT, KE9): Ein Run bis Raum 10 mit Seelentor bringt etwa 100–150 Gold, also in den ersten Abenden eine Schmiede-Stufe je 1–2 Runs; die vollen Waffen-Stufen (25 Stufen, gut 5 000 Gold) sind das lange Ziel. Dungeon-Preise (Händler, Heilung) bleiben wie heute.

## 6. Zuhause: Talentbaum und Zauber

**Absicht (VERBINDLICH):** Mit den Talentpunkten baut man seinen Charakter immer wieder anders, z. B. auf Schnelligkeit und schnelle Waffen oder auf Zauber. Das Zuhause ist beim ersten Betreten schon gemütlich eingerichtet (D-205: „eingerichtet, aber basic cozy“) und bekommt dafür einen **Innenraum** (Tür → eigene Szene, zurück an dieselbe Stelle im Dorf): Kerzen-Altar mit dem Talentbaum, Spiegel (Profil, D-152), später Möbel und Pets (§8).

### 6.1 Drei Pfade

Jeder Pfad hat vier Ränge; ein Rang öffnet sich nach 0, 3, 7 und 11 Punkten im selben Pfad. **Umskillen** geht jederzeit im Zuhause: Punkte setzen ist frei, Zurücknehmen kostet Seelenkristalle, 10 % der zurückgenommenen Punkte, aufgerundet, mindestens 1 (D-196, TESTWERT). Alle Werte TESTWERT; keine kritischen Treffer und keine Rüstungswerte (D-019).

| Rang | **Pfad des Windes** (Tempo) | **Pfad der Glut** (Kraft) | **Pfad der Seele** (Zauber) |
| --- | --- | --- | --- |
| 1 | Leichtfuß 3×: +5 % Lauftempo | Vitalität 5×: +1 Max-HP | **Lichtblitz** (erster Zauber, schaltet den Zauberplatz frei) |
| 1 | Dash-Training 3×: −0,15 s Dash-Abklingzeit | Wucht 3×: +8 % Schaden mit Schwert und Hammer | Zauberkraft 3×: +10 % Zauberschaden |
| 2 | Flinke Klinge 3×: +8 % Angriffstempo mit Dolchen und Bogen | Standfest 2×: −25 % Rückstoß und Betäubung | Konzentration 3×: −8 % Zauber-Abklingzeit |
| 2 | Ausweichkunst 2×: nach einem Dash 1 s +15 % Schaden | Schildbrecher 2×: +20 % Schaden gegen Champions und Schildträger | **Seelenschild** · **Flammenring** |
| 3 | Doppel-Dash: zweite Dash-Ladung | Zweites Herz: einmal je Run mit 2 HP wieder aufstehen (im Koop stattdessen doppelt so schnell wiederbelebt werden) | **Irrlichter** · **Heilfunke** · Stab-Meister 2×: +8 % Stab-Schaden |
| 4 (Schlussstein) | Windläufer: der Dash hinterlässt eine Lichtspur, die Gegner verlangsamt | Glutherz: unter 2 HP löst ein Treffer eine Glutwelle aus (10 s Abklingzeit) | Zweiter Zauberplatz |

### 6.2 Zauber

- **Ein Zauberplatz** (zwei mit dem Schlussstein), ausgerüstet am Altar im Zuhause. Neue Eingabe `cast_spell` (Vorschlag: Q, am Gamepad eine Schultertaste, Touch ein eigener Knopf; Belegung im Paket gegen die vorhandenen Aktionen prüfen). Die Abklingzeit steht im HUD neben den Waffen.
- **Flint wirkt den Zauber sichtbar** (die Flamme leuchtet auf, der Effekt geht von Flint aus); gerechnet wird am Spieler.
- Zauberschaden wächst mit denselben Run-Multiplikatoren wie Waffenschaden, damit Zauber tief im Dungeon nicht verfallen. Zauber sind eine neue Fähigkeitsart; das braucht nach D-026 eine Entscheidung (D-194).

| Zauber | Wirkung (TESTWERT) | Abklingzeit |
| --- | --- | ---: |
| Lichtblitz | Gegner im Umkreis von 3 Kacheln 1 s geblendet (kein Angriff) | 12 s |
| Seelenschild | +4 Schild | 15 s |
| Flammenring | 3 Schaden im Umkreis von 2,5 Kacheln, Rückstoß | 10 s |
| Irrlichter | 3 zielsuchende Lichter je 2 Schaden | 9 s |
| Heilfunke | heilt 2 HP bei dir und Mitspielern im Umkreis von 4 Kacheln | 25 s |

**Tränke** bleiben Proviant (§5.2) bzw. Heilung beim Händler; ein eigener Trank-Platz im Run ist nicht geplant (BACKLOG).

## 7. Flint – Begleiter, Licht und Erklärer

**VERBINDLICH (Projektmitglied 22.10.2026):** Flint ist unser Sidekick, immer dabei, fliegt vor und macht Licht. Er erklärt das Dorf, gibt beim ersten Dungeon eine kurze Übung und erklärt jede neue Raumart beim ersten Mal, auch im Koop für den, der sie noch nicht kennt.

### 7.1 Begleiter und Licht

- Flint schwebt dicht beim Spieler, wippt, zieht leicht nach und **fliegt in Laufrichtung ein Stück voraus** (bis 1,5 Kacheln, TESTWERT). Er weicht nie in den Weg und verdeckt keine Gegner.
- **Flint macht das Licht sichtbar** (D-212): Der Lichtkreis ist im Bild und für alle Regeln um die Figur zentriert; Flints Flamme gibt zusätzlich einen kleinen warmen Schein. Die Entscheidung „ist ein Punkt im Licht“ bleibt an einer Stelle (`LightQuery`, D-067).
- Reaktionen: Freude (Raum geschafft, Aufstieg), Angst (Boss, Dunkelheit), Neugier (Geheimnis in der Nähe, nur Optik), Trauer (am Boden), Licht-Puls (Lagerfeuer, Zauber).
- Kein eigener Angriff, fängt keine Treffer ab; seine Spielwirkung sind Licht und Zauber-Optik. Aktiv „Flint vorausschicken“ (zum Auskundschaften) ist eine Idee für später (BACKLOG).
- **Name:** Das Docht-Wesen heißt **Flint** (VERBINDLICH, Projektmitglied 22.10.2026, D-198), in beiden Sprachen; es ist zugleich das Maskottchen. Die Standard-Spielfigur (`characters/wick.tres`, Code-ID `wick`) heißt **Wick** in beiden Sprachen (bisher Deutsch „Docht“). Im Code heißt der Begleiter `flint` (`companions/`, `art/companions/flint/`).

### 7.2 Flint erklärt (ein Baukasten für alles)

**Ablauf einer Erklärung:** Flint wächst neben dem Spieler, fliegt aus der Welt **in die Ecke unten rechts ins UI** (Bild bleibt Flint, wird größer, bekommt einen Rahmen), daneben erscheint seine Sprechblase mit höchstens zwei Zeilen. Bei Bedarf fliegt die Kamera die Ziele ab (Gebäude, Weg, Ziel), Flint kommentiert jede Station. „Weiter“ mit Klick, Taste oder Antippen, „Überspringen“ jederzeit. Am Ende fliegt Flint zurück zum Spieler und wird wieder klein. Gebrabbel statt Sprache, wie beim Boss-Intro (D-098).

| Anlass | Wann | Was Flint tut |
| --- | --- | --- |
| **Dorf-Rundgang** | erster Start (je Konto) | Kamerafahrt über das Dorf: Dungeon-Eingang, Schmiede, Handelsposten, Zuhause, Chronik, Gilde, je ein Satz („Das ist die Schmiede. Hier machst du deine Waffen stärker – mit Gold aus dem Dungeon.“); ersetzt die Eröffnung durch den Chronisten (D-161) |
| **Erstes Betreten eines Gebäudes** | je Gebäude einmal | ein Satz zur Rolle wie heute (D-087), jetzt von Flint |
| **Übungsgang** | erster Gang in den Dungeon (je Konto, nur allein) | kurzer Gang aus 4 Stationen vor Raum 1: gezielt laufen und angreifen (Strohpuppen), gezielt dashen (Pfeilfalle oder Lücke), gezielt springen (kurzes Stück Seitenansicht), gezielt Rechtsklick (Puppe mit Schild); danach „Los geht's!“ und der normale Run beginnt. Überspringbar („Kenne ich schon“), +25 XP beim ersten Abschluss |
| **Neue Raumart** | erstes Mal je Raumart, Minispiel, Spezialraum (je Konto) | Flint fliegt mit der Kamera die Aufgabe ab und sagt sie in kurzen Sätzen: beim Geleit z. B. „Er muss hier entlang zum Ausgang. Er hat 5 Leben. Monster wollen ihn angreifen – beschützt ihn, damit er heil ankommt!“; ersetzt die Erklärkarte im Intro-Muster (D-133) |
| **Erstes Mal sonst** | Rang-Aufstieg, erster Talentpunkt, erstes Seelentor, erster Zauber | ein Satz in der Ecke, ohne Kamerafahrt |

- **Gesehen-Merker je Konto**, nicht mehr je Welt: Wer eine neue Welt anlegt, sieht Erklärungen nicht doppelt (heute `[seen]` im Spielstand). Mischregel: Vereinigung (§10).
- **Koop:** Nichts pausiert (D-085). Kennt ein Spieler die Raumart noch nicht, verlängert der Host den Countdown um die Dauer der Erklärung; der neue Spieler sieht Flints Kamerafahrt, die anderen sehen in der Zeit ein Banner „Flint erklärt Mia das Geleit …“ und die kurze Fassung. Wer erklärt bekommt, ist geschützt wie im Menü (D-123). Der Übungsgang läuft nur allein; wer zuerst im Koop einsteigt, bekommt in den ersten Räumen kurze Tipp-Blasen ohne Halt und den Übungsgang beim nächsten Solo-Start angeboten.
- Texte über Schlüssel `FLINT_*` (D-111), kurz, freundlich, du-Form; Englisch und Deutsch.

## 8. Kosmetik, Dorf-Deko, Zuhause einrichten, Pets, Huhn, Dorf besuchen

Verdichtet aus dem früheren Begleiter-Konzept; Regeln VERBINDLICH aus D-175, D-176, D-179, Rest VORGESCHLAGEN.

- **Kosmetik** für Spielfigur (Kopf, Rücken, Lichtfarbe), Flint (Hut, Flammenfarbe, Spur) und Dorf. Nur Optik, verdeckt keine Anzeigen, Licht- und Flammenfarben nur aus einer warmen Auswahl (nie Rot = Gefahr). Übertragung über das Konto-Profil (`PATCH /me`), nie über Spielpakete. Freispielen über Level (alle 5), Meilensteine, Erfolge; kaufen erst mit CP6, was man freispielt, kann man nicht kaufen und umgekehrt; keine Lootboxen.
- **Dorf-Deko** (Gold): kaufen, auf Rasterflächen setzen, drehen, wegräumen; je Welt gespeichert; Gäste im Koop sehen das Dorf des Hosts.
- **Zuhause einrichten** (VERBINDLICH als Wunsch: „später einrichten können“): Möbel wie die Deko im Innenraum (§6), Gold oder später kaufbare Kosmetik; **zum Release** nach der Dorf-Deko (D-202).
- **Pets** (VERBINDLICH als Wunsch: „dann soll die Idee mit den Pets dazukommen“): weitere Begleiter auf dem Gerüst von Flint, wohnen im Zuhause, laufen im Dorf und in der Lobby mit; reine Optik; nach dem Release. Im Dungeon nur Flint, damit vier Spieler nicht acht Begleiter vor den Gegnern haben (D-196); Kampf-Pets sind eine Idee für danach (§11).
- **Dorftiere** (zum Release, D-196): Huhn, Katze und weitere Tiere im Dorf reagieren, wenn man sie anspricht (streicheln, füttern, Herz, Gackern, Schnurren), Flint kommentiert beim ersten Mal; nur Optik, je Spieler lokal.
- **Huhn:** Neben-Maskottchen mit Gags (reitet Flint, pickt nach der Flamme, Nickerchen am Brunnen); im Dungeon selten und nie getötet gezeigt.
- **Dorf besuchen:** Schnappschuss des Dorfs (Gebäudestufen, Deko und Möbel mit Platz und Drehung, keine Freitexte, ≤ 16 KB) auf dem Server; Gildenmitglieder und wer den Besuchslink hat, schauen ihn an, nur ansehen; melden und ausblenden möglich; Löschen mit dem Konto.

## 9. Koop im Release: Solo-Charakter und Gilden-Charakter

**VERBINDLICH (Projektmitglied 22.10.2026):** „Im Quick Game bringt jeder seinen Charakter aus dem Solo-Game mit, und wenn man eine Gilde startet, ist man ja ein Longterm Squad und hat dort eigene Charaktere.“ Das ersetzt den Grundsatz von D-081 („Multiplayer startet ohne eigene Dorf-Boni“).

| Modus | Mit welchem Charakter | Fortschritt fließt in |
| --- | --- | --- |
| **Solo** | Solo-Charakter: Talentbaum und Zauber des Kontos, Schmiede, Handelsposten und Proviant der gewählten Welt | Welt (Gold, Kristalle) und Konto (XP, Talentpunkte, Rang) |
| **Schnelles Spiel** | **derselbe Solo-Charakter** wie allein (Talente, Zauber, Schmiede und Proviant der zuletzt gespielten Welt) | wie Solo: Auszahlung in die eigene Welt, XP ans Konto |
| **Gilden-Run** | **Gilden-Charakter**: je Spieler und Gilde ein eigener Charakter, der bei null beginnt und nur in Gilden-Runs dieser Gilde wächst | Gilden-Charakter (Gilden-Level, eigene Talentpunkte und eigener Talentbaum), Gildenkasse; XP zählen zusätzlich fürs Konto-Level |

**Gilden-Charakter (Ausgestaltung VORGESCHLAGEN):**

- **Gilden-Level** aus den XP der Gilden-Runs (gleiche Quellen und Kurve wie das Konto-Level, §4); je Gilden-Level ein Talentpunkt für den **eigenen Talentbaum des Gilden-Charakters** (gleicher Baum wie §6, eigene Verteilung, Umskillen im Gildenhaus).
- **Gilden-Schmiede:** Die Gildenkasse (gebaut, MP8) kauft Waffen- und Ausrüstungsstufen wie die Schmiede (§5.1), die **für alle Gilden-Charaktere dieser Gilde** gelten (das war schon der Vorschlag von D-081 und beantwortet D-161 OFFEN „was kauft die Gildenkasse“). Kein eigener Handelsposten, kein Proviant in Gilden-Runs (Vorschlag; später möglich, BACKLOG).
- **Gilden-Rang:** Die Gefahrenstufe eines Gilden-Runs kommt aus den Gilden-Leveln und den letzten 5 Gilden-Runs der Spieler im Raum (§3, §3.2); der Rang wird je Gilde angezeigt (Gildenseite, Gilden-Rangliste).
- **Gespeichert auf dem Server** am Mitglied der Gilde (Gilden-XP, Talente), wie die Gildenkasse; offline gibt es keine Gilden-Runs. Verlässt man eine Gilde, bleibt der Gilden-Charakter 30 Tage erhalten (Vorschlag), danach wird er gelöscht.
- Beim ersten Gilden-Run erklärt Flint in einem Satz: „In dieser Gilde fängst du neu an – zusammen werdet ihr stärker.“

**Für alle Koop-Modi:**

- Run-Gold bleibt eine **gemeinsame Kasse** (D-081). Schnelles Spiel: jeder bekommt wie gebaut den vollen Anteil nach der Auszahlungsregel (§2) in seine Welt (D-126); Gilden-Run: Auszahlung in die Gildenkasse (MP8). Weil die Kasse mit der Spielerzahl wächst, misst KE9, ob Koop zur Gold-Farm wird; dann Vorschlag: Gold je Gegner im Koop × 1/(1 + 0,3 · (n − 1)).
- Fair bleibt es über die **Gruppen-Gefahrenstufe** (§3.2); ein Spieler mit hoher Stufe kann einen Neuling mitnehmen, der Host kann senken.
- Leitplanken wie immer (D-088, [MULTIPLAYER.md](MULTIPLAYER.md)): Talente, Zauber, Schmiede-Stufen und Proviant sind Zustand am Spieler; der Host rechnet Wirkungen, Clients kennen die Werte aus der Lobby-Nachricht (Solo-Charakter) bzw. vom Server (Gilden-Charakter).

## 10. Konto, Anmeldung, Cloud (D-188 gilt weiter)

Verdichtet aus dem früheren Konto-Konzept (volle Fassung: `git show 6f6eab3:docs/KONZEPT_KONTO_FORTSCHRITT.md`). **VERBINDLICH (D-188)** bis auf Punkt 4, den §4 ersetzt.

- **Ein Konto je Mensch, viele Anmeldungen:** still als Gast (`device`), Steam (Ticket; im Browser Steam OpenID, dieselbe Identität), Play Games (Android, still), Game Center (iOS, still), Benutzername + Passwort, Magic Link, Google, Apple (auf iOS Pflicht, nativ), Discord. „Anmeldung hinzufügen“ stuft den Gast hoch, immer mit Nachweis; Verknüpfungscode bleibt; kein automatisches Verknüpfen über gleiche E-Mail; Benutzername ist privat, nicht der Anzeigename.
- **Web-Anmeldung aus dem Spiel:** Das Spiel startet eine Anfrage, öffnet `playsoulwick.com/login/<code>`, holt die Sitzung ab; so braucht kein Build eigene OAuth-Weiterleitungen.
- **Zusammenführen** (D-122): das ältere Konto bleibt; „leeres Konto“ geht ohne Rückfrage auf; XP zählen zusammen; Welten nach der Mischregel.
- **Cloud-Welten:** je Welt eine Cloud-Welt mit Welt-ID (Spielstand v5), offline zuerst, Abgleich beim Login, im Dorf, nach jedem Run-Ende, beim Schließen; nie im Run. ≤ 64 KB, 3 Welten, Sicherungen und Archiv 30 Tage. Steam Cloud und Play-Games-Speicher bleiben aus.
- **Konflikte ohne Dialog:** Monotones wird je Feld gemischt, der Rest kommt vom zuletzt gespielten Stand; der unterlegene Stand bleibt 30 Tage als Sicherung.
- **Am Konto statt in der Welt:** Profil, Kosmetik-Besitz, XP (Zuwächse je Run-ID genau einmal), **neu:** Talentbaum und ausgerüstete Zauber, Gesehen-Merker der Erklärungen, die letzten 5 Runs für den Rang.

**Mischregeln der neuen Felder** (ergänzt die Tabelle der früheren Fassung §4.3):

| Feld | Ort | Mischregel |
| --- | --- | --- |
| Schmiede: Waffen frei, Waffen-Stufen, Schildplatte, Laterne | Welt | Maximum je Stufe, Vereinigung bei Freischaltungen |
| Handelsstufen (Proviant-Plätze, Glück, Händlerfreund) | Welt | Maximum |
| Proviant im Gepäck | Welt | zuletzt gespielt |
| Talentbaum, Zauber | Konto | zuletzt geändert (Zeitstempel am Server gekappt) |
| Gilden-Charakter (Gilden-XP, Talente) | Server, am Gildenmitglied | nur auf dem Server, kein Abgleich nötig |
| Gesehen-Merker (Erklärungen, Übungsgang) | Konto | Vereinigung |
| letzte 5 Runs (Rang) | Konto | aus den XP-Einträgen je Run-ID, keine eigene Mischregel |
| Rückerstattung der Migration v5 | Welt | einmal je Welt (Merker), Maximum |

## 11. Danach: KI-Bosse und Party-Modus

Beide kommen zum Schluss (Projektmitglied 22.10.2026: „Party-Modus und KI-Boss hinten dran“). **Die KI-Bosse müssen trotzdem zum Release fertig sein** (Projektmitglied 22.10.2026, D-179 bleibt); der Party-Modus kommt nach dem Release.

**KI-Bosse „Traumweber“** (D-179; volle Fassung `git show 6f6eab3:docs/KONZEPT_KI_BOSS.md`):

- Nach einem Boss steht im Lagerfeuer-Raum der Schrein des Traumwebers. Der Spieler wünscht sich einen Boss aus **Bausteinen** (Gestalt, Material, Angriff, Laune, Farbe; Freitext nur nach eigener Entscheidung), der Server baut ihn in 1–3 Minuten, wenige Räume später ersetzt er den nächsten Miniboss.
- **Die KI wählt aus einem Baukasten, sie programmiert nicht:** Ausgabe ist ein `BossSpec`-JSON aus festen Modulen (Nahkampf, Fächer, Ring, Sturm, Sprung, Teleport, Eruption, Diener, Blenden, Tod mit Nachspiel; neu: zielsuchend, abprallend, umkreisend, Spur, Strahl). Spiel und Server prüfen Schema, Wertebereiche und **Punkte-Budget** je Schwierigkeit (Leicht 6, Normal 10, Schwer 14, Albtraum 18; TESTWERT). Fairness fest im Code: Vorwarnung ≥ 0,5 s, höchstens 40 Geschosse, keine Sofort-Tode.
- **Sprites im Spielstil:** Bildbeschreibung → fester Stilteil plus Stilreferenz → Bildgenerator → deterministische Nachbearbeitung (64×64, Palette, Kontur) → Bildprüfung; Ersatz-Sprite bei Fehlern.
- **Moderation:** Bausteine als Standard, Filter für Wunsch und Ergebnis, Melden nach dem Kampf, Admin-Ansicht. Echte Personen bleiben OFFEN (Team und Fachanwalt); bis dahin nur erfundene Beispiele. Kosten je Boss grob 0,05–0,20 $ plus Bild; Kontingent, Tagesobergrenze, Abschalter; wer zahlt, ist OFFEN.
- **Clip teilen** (KI9): nach jedem Bosskampf eine Bildkarte mit Bossname, Raum, Logo und Einladungslink; Kurzclip später.

**Kampf-Pets** (Idee nach dem Release, D-196): Pets, die im Dungeon mitkämpfen; braucht ein eigenes Konzept (Koop mit bis zu vier Spielern, Lesbarkeit, Balance).

**Party-Modus** (nach dem Release, D-179; volle Fassung `git show 6f6eab3:docs/KONZEPT_PARTY_MODUS.md`):

- 2–4 Spieler treten in 5 kurzen Runden (45–90 s) **gegeneinander** in den vorhandenen Minispielen an, gleiche Grafik und Steuerung, alle starten gleich (keine Talente, keine Schmiede), kein Schaden zwischen Spielern (schubsen, betäuben ≤ 0,5 s). Ausgeschiedene spielen als Geister weiter.
- Start mit Seelen sammeln, Einsturz und einem Prüfungs-Rennen; Punkte 3/2/1/0; Belohnung nur Statistik, Abzeichen und Kosmetik, nie Gold oder Kristalle.
- Lobby wie im Koop (Raumcode, Link), Host rechnet die Wertung, eigener `GameMode`.

## 12. Entscheidungen aus KE0 und was noch offen ist

**Beantwortet (Projektmitglied 22.10.2026, D-194 Ergänzung und D-196):**

| # | Frage | Antwort |
| --- | --- | --- |
| 1 | KI-Bosse vor dem Release? | **ja, sie müssen zum Release fertig sein** (D-179 bleibt); sie stehen trotzdem am Ende, weil sie Server, Konten und den neuen Kern brauchen |
| 2 | Eigener Charakter im Koop? | **Schnelles Spiel = Solo-Charakter, Gilde = eigener Gilden-Charakter je Gilde** (§9) |
| 3 | Rang-Namen | **Licht-Motiv:** Funke, Kerze, Flamme, Laterne, Leuchtfeuer, Seelenmeister (§3.1) |
| 4 | Name des Begleiters | **Das Docht-Wesen heißt Flint**, in beiden Sprachen; es ist auch das Maskottchen (D-198, ersetzt „Wick“ aus D-175/D-194) |
| 5 | Name der Standard-Spielfigur | **Wick** in beiden Sprachen (Deutsch bisher „Docht“); der Begleiter heißt Flint (D-198) |
| 6 | Tod-Auszahlung | **25 %**, mit Seelenanker 50 % (D-196) |
| 7 | Gefahrenstufe wählbar? | **nein**, sie kommt aus dem Rang; in der Gruppe aus den Stufen aller Spieler (D-196) |
| 8 | Umskillen | **kostet Kristalle:** 10 % der zurückgenommenen Punkte, aufgerundet, mindestens 1 (D-196) |
| 9 | Pets im Dungeon? | **nein**; Kampf-Pets als Idee nach dem Release (§11) |
| 10 | Zuhause einrichten und Pets | **nach dem Release**; zum Release: Zuhause betreten, Talentbaum, Dorf-Deko und **Dorftiere zum Anfassen** (WK12) |
| 11 | Mailversand für Magic Links | Mail-Adapter, Standard **Cloudflare Workers**, Alternative Nodemailer; endgültig in KF5 (D-196) |

**Noch offen:** SV0 (Seitenansicht 2.0, D-195: Namen, Häufigkeit 50/50, Medaillen, Krone im Koop).

**Delegiert und darum TESTWERT:** alle Zahlen in §2–§6, Formeln der Gefahrenstufe, Kristall- und Goldziele, Abklingzeiten, Flints Abstand.

**Weiterlesen:** [ROADMAP.md](ROADMAP.md) · [PRODUKT.md](PRODUKT.md) · [PRD.md](PRD.md) · [RAEUME.md](RAEUME.md) · [MULTIPLAYER.md](MULTIPLAYER.md) · [DECISIONS.md](DECISIONS.md) (D-081, D-087, D-175, D-176, D-179, D-188, D-193, D-194)
