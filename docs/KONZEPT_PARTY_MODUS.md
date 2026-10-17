# Konzept Party-Modus – Minispiele gegeneinander

> **Stand:** 17.10.2026 · **Status:** Konzept für **Phase 5** (D-179, VERBINDLICH: nach Koop und KI-Bossen). Nichts davon ist gebaut; alles außer der Reihenfolge ist Vorschlag. Offene Fragen: Abschnitt 8.
> **Grundlage:** D-173 (Koop ist der Kern, Clips, Einstieg in einer Minute), D-120 (Minispiele der Räume v2), D-084/D-085 (Koop-Regeln), D-176 (kein Pay-to-win). Pakete PA0–PA3: [ROADMAP.md](ROADMAP.md). Minispiele heute: [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) §3.

## 1. Die Idee in drei Sätzen

Ein zweiter Modus neben dem Abstieg, der nur aus kurzen Minispielen besteht: 2–4 Spieler treten in mehreren Runden **gegeneinander** an, mit derselben Grafik, Steuerung und denselben Räumen wie im Dungeon. Jede Runde dauert etwa eine Minute, danach gibt es Punkte, am Ende einen Sieger auf dem Podest. Er nutzt, was es schon gibt (die acht Minispiele aus D-120, Lobby mit Raumcode und Link), und liefert genau die lauten, lustigen Momente, die man teilt (D-173).

## 2. Regeln (Vorschlag)

- **Gleiche Grafik, gleiche Steuerung:** Maus, Touch, Gamepad wie im Abstieg; keine eigene Spielfigur-Ausrüstung. Alle starten gleich: keine Dorf-Boni, keine Upgrades aus Runs, keine gekaufte Stärke (D-176, es gibt keine).
- **Kurz:** eine Runde 45–90 s (TESTWERT), eine Party 5 Runden (TESTWERT), also unter 10 Minuten.
- **In einer Minute verstanden:** jede Runde mit dem Intro-Muster der Räume v2 (Kamera aufs Ziel, Banner mit einem Satz, 3-2-1, D-120); beim ersten Mal eine Erklärkarte.
- **Freundlich:** Spieler fügen sich **keinen Schaden** zu. Gegeneinander heißt schneller sammeln, stehen bleiben, schubsen, wegschnappen, betäuben (kurz). Dungeon-Gegner, Fallen und Abgründe dürfen mitspielen.
- **Wer rausfällt, schaut nicht nur zu:** Ausgeschiedene werden zu Geistern, die kleine Hilfen oder Störungen auslösen (z. B. eine Fackel anzünden, eine Seele verschieben) – Vorschlag, damit niemand eine Minute wartet.
- **Lobby wie im Koop:** Raum mit Raumcode und Einladen per Link (MP2b); der Host startet „Party“ statt „Abstieg“. Kein Matchmaking mit Fremden (wie im Koop).
- **Fair für alle Geräte:** Minispiele, die genaues Zielen verlangen, haben auf Touch keinen Nachteil (Zwei-Stick-Steuerung, D-155); im Zweifel Laufen und Timing statt Zielen.

## 3. Ablauf

1. Lobby (2–4 Spieler) → Host wählt „Party“ und ggf. die Rundenzahl.
2. Je Runde: Minispiel und Raum ziehen (nie zweimal hintereinander dasselbe), Intro, Runde, kurze Wertung mit Platzierungen.
3. Nach der letzten Runde: Podest mit Sieger, lustige Statistik („am häufigsten in den Abgrund gefallen“), Knopf „Clip teilen“ (ROADMAP_KI_BOSS KI9), „Noch eine Party“ oder zurück ins Dorf.

## 4. Welche Minispiele sich für „gegeneinander“ eignen

Gesichtet in `dungeon/modes/` (Regeln je Modus als eigene `*_rules.gd`, getrennt von der Optik). Heute sind alle Modi Koop gegen Dungeon-Gegner; für die Party braucht jeder eine eigene Wertung (eigene Party-Regeln, die Abstieg-Regeln bleiben unverändert).

| Minispiel (heute) | Gegeneinander (Vorschlag) | Eignung |
| --- | --- | --- |
| Seelen sammeln (`souls`): 12 Seelen nacheinander an festen Plätzen, 45 s | Wer sammelt die meisten Seelen? Mehrere Seelen gleichzeitig, Schubsen erlaubt | **sehr gut**: sofort klar, zählbar, schon als „Wettstreit“ vorgemerkt (KONZEPT_RAEUME_V2 §3.11) |
| Einsturz (`collapse`): Boden bricht in Feldern von außen nach innen, 30 s überleben | Wer steht am längsten? Wer fällt, scheidet aus (wird Geist) | **sehr gut**: klarer Sieger, lustige Stürze, Clip-Moment |
| Prüfungen (Spießrutenlauf, Lichtlauf, Bröckelboden) und Seitenwege (Seitenansicht, M5) | Rennen durch denselben Parcours, Zeit zählt | **sehr gut**: Können zählt, Fehler kosten Zeit statt Leben |
| Reliquie holen (`relic`): Träger ist langsamer und kann nicht angreifen | Capture the Flag: Reliquie zum eigenen Altar; andere können sie abnehmen | **gut**, am besten 2 gegen 2 |
| Lichtfeuer (`lightfire`): Fackeln im dunklen Raum entzünden | Fackeln in der eigenen Farbe entzünden oder umfärben; wer am Ende die meisten hat, gewinnt | **gut**, braucht eine Regel fürs Umfärben |
| Jagd (`hunt`): der Gekrönte flieht und springt in ein Loch | Wer fängt den Gekrönten? Oder: ein Spieler trägt die Krone, die anderen jagen ihn (Fangen) | **mittel**: ein Treffer entscheidet, viel Zufall; die Fangen-Variante ist stärker |
| Risse schließen (`rifts`): Risse bekämpfen, bis sie zu sind | Wer schließt die meisten Risse (letzter Treffer zählt)? | **mittel**: „letzter Treffer“ ist frustig |
| Geleit (`escort`): verirrter Dorfbewohner (selten Huhn) zum Ausgang bringen | Jeder führt sein eigenes Huhn ins Ziel; Variante „Hühner einfangen“ als neues Minispiel | **mittel** in Reinform (langsam); als Hühner-Gag gut (Neben-Maskottchen, D-175) |
| Flamme hüten (`flame`): Flamme 40 s gegen Gegner verteidigen | Jeder hütet seine Flamme, Gegner kommen zu allen; wessen Flamme brennt am längsten? | **schwach** allein; als 2 gegen 2 denkbar |

**Vorschlag für den Start (PA2):** Seelen sammeln, Einsturz und ein Prüfungs-Rennen – drei Minispiele, die sich sofort erklären und klare Sieger haben.

## 5. Wertung und Belohnung

- **Punkte je Runde (Vorschlag):** Platz 1 = 3, Platz 2 = 2, Platz 3 = 1, Platz 4 = 0; Gleichstand teilt sich die Punkte. Die letzte Runde zählt doppelt (Vorschlag, hält es bis zum Ende spannend; OFFEN).
- **Belohnung im Dorf (OFFEN):** Vorschlag **keine** Spielwerte (kein Gold, keine Kristalle), damit der Party-Modus kein Farm-Modus wird und die Abstieg-Balance unberührt bleibt; stattdessen Statistik in der Chronik, Abzeichen und freispielbare Kosmetik für Meilensteine (Konzept Begleiter und Kosmetik).
- **Ranglisten:** Vorschlag zum Start keine; Siege zählen nur in der eigenen Statistik.

## 6. Koop-Check und Technik-Leitplanken

- Host rechnet alles, auch die Wertung (D-119); Clients zeigen sie. Der Punktestand ist ein gespiegeltes Objekt wie die Aufgabenleiste (`RoomObjective`), Zustand je Spieler am Spieler.
- Zufall (Minispiel-Ziehung, Raum, Seelen-Plätze) nur über den Dungeon-RNG mit Party-Seed; `randf()` nur für Optik.
- Keine globale Pause, kein `Engine.time_scale` (D-085); Menüs schützen den einzelnen Spieler.
- Party-Regeln je Minispiel als eigene Klassen neben den vorhandenen Regeln; Entscheidungen (wer hat gewonnen, wer ist raus) an **einer** Stelle, Effekte über Signale.
- Kein neuer Autoload: der Modus ist ein weiterer Wert im `GameMode` (heute `SOLO`, `QUICK`, `GUILD`).
- Räume aus Plänen (D-120): Party-Räume sind eigene Pläne in Arena-Größe, damit die Kamera alle Spieler zeigt.

## 7. Was es nicht ist

- Kein Kampfmodus Spieler gegen Spieler mit Schaden und Waffen-Balance.
- Kein Matchmaking mit Fremden, keine öffentlichen Räume (wie im Koop, Plattform-PRD §4).
- Kein eigener Grafikstil, keine eigenen Figuren.

## 8. Offene Fragen (für PA0)

| Frage | Vorschlag |
| --- | --- |
| Wie viele Runden, wie lang? | 5 Runden zu 45–90 s, Host kann 3/5/7 wählen |
| Wertung | 3/2/1/0 Punkte, letzte Runde doppelt |
| Belohnung im Dorf ja/nein | nein bei Spielwerten; ja bei Statistik, Abzeichen und freispielbarer Kosmetik |
| Teams | jeder gegen jeden als Standard; 2 gegen 2 als Option bei 4 Spielern (Reliquie, Flamme) |
| Online oder lokal | online über Relay, Raumcode und Link zuerst; lokal an einem Gerät mit mehreren Gamepads später (die Eingabe-Objekte je Spieler aus MP1 erlauben es) |
| Weniger als 2 Spieler | Bots auffüllen (wie in `tools/mp_local_sim.gd`) oder Party erst ab 2 Spielern – OFFEN |
| Schubsen und Betäuben | ja, kurz und ohne Schaden; Betäubung höchstens 0,5 s (TESTWERT) |
| Ausgeschiedene als Geister | ja, mit kleinen Aktionen ohne Ausschlag auf den Sieg |
| Name des Modus | „Party“ (Arbeitstitel, Glossar) |

**Weiterlesen:** [ROADMAP.md](ROADMAP.md) · [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [PRODUKT.md](PRODUKT.md) · [DECISIONS.md](DECISIONS.md)
