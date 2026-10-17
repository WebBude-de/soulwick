# ROADMAP KI-Boss „Traumweber“

> **Stand:** 17.10.2026 · **Phase 4, direkt nach Koop, zum Release** (D-179, VERBINDLICH): KI-Bosse („Wünsch dir einen Boss“) sind der stärkste Clip-Moment („jeder Boss ein Clip“, D-173) und beim Release im Spiel; Mindestumfang im Release-Tor von [ROADMAP.md](ROADMAP.md). Gebaut ist noch nichts; Inhalte und Zahlen im Konzept bleiben Vorschlag. Konzept: [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) · Übersicht: [ROADMAP.md](ROADMAP.md).
> **Voraussetzungen:** Server (`soulwick-platform`, `apps/api`, Bun und Hono) und Konten (MP7, CP1). **KI1, KI2 und KI9 brauchen keine KI und keinen Server** und dürfen jederzeit vorgezogen werden.
> **Abhaken** nur mit Nachweis (Tests, Datum). Jedes Paket ist für **einen** Agenten geschnitten.

## Überblick

| Paket | Ergebnis | Braucht Server/KI? | Agent (Vorschlag) |
| --- | --- | --- | --- |
| KI0 | Entscheidungen | – | Orchestrator mit dem Projektmitglied |
| KI1 | Bosse aus JSON + PNG zur Laufzeit laden | nein | `enemies-dev` |
| KI2 | Baukasten erweitern, Budget und Schwierigkeit | nein | `enemies-dev`, Zahlen `balance` |
| KI3 | Server: Wunsch, Chat und Boss-Beschreibung per Claude, Moderation | ja | `api-dev` |
| KI4 | Server: Sprite-Pipeline im Spielstil | ja | `api-dev` |
| KI5 | Im Spiel: Traumweber-Schrein, Wunsch, Wunschboss im Run | ja | `enemies-dev` (Boss), `player-dev` (Dialog, HUD) |
| KI6 | Arena der Albträume, Galerie, Teilen per Code | ja | `village-dev` |
| KI7 | Koop und Gilden | ja | Netzwerk wie MP3 (`player-dev`) |
| KI8 | Release: Steam-Angaben, Admin-Moderation, Kostenkontrolle | ja | `api-dev`, `admin-dev` |
| **KI9** | **Clip teilen: Boss-Moment als Bild oder kurzes Video teilen** | nein (Stufe 1) | `fx-audio-dev` (Aufnahme), `player-dev` (Teilen-Knopf) |

**Reihenfolge:** KI0 → KI1 → KI2 → KI3 ‖ KI4 → KI5 → KI7 (Koop ist Kern, D-173) → KI6 → KI8 vor dem Release (öffentlich geht es erst ab dem Release, D-179). KI9 darf jederzeit, gilt für alle Bosse (auch die festen) und für den Party-Modus.

**Zum Release (Vorschlag, Release-Tor in ROADMAP.md):** KI0–KI5, KI7, KI8 und KI9 Stufe 1; KI6 (Arena, Galerie) und KI9 Stufe 2 und 3 dürfen danach kommen.

## KI0 – Entscheidungen

- [x] Feature ja, Zeitpunkt direkt nach Koop, beim Release im Spiel (D-179, 17.10.2026).
- [ ] **Moderation für Jüngere** (D-173, D-179 OFFEN): Wünsche aus **vorgegebenen Bausteinen** (Gestalt, Material, Angriff, Laune, Farbe) statt Freitext. Vorschlag: Bausteine sind der Standard für alle; Freitext nur als Zusatz mit Filter und erst nach einer eigenen Entscheidung (wir fragen kein Alter ab, Konten haben keine E-Mail, D-121).
- [ ] **Kosten je Erzeugung und wer sie trägt** (D-179 OFFEN): Kontingent je Spieler, Tagesobergrenze, Abschalter. Bezahlte Erzeugungen wären ein neues Kaufprodukt außerhalb von D-176 (dort nur Kosmetik und Werbefrei) und brauchen eine eigene Entscheidung.
- [ ] **Echte Personen als KI-Boss** (D-179 OFFEN): Das Projektmitglied wünscht es sich für Clips (z. B. Politiker). Risiken: Persönlichkeitsrecht und Recht am eigenen Bild, Satire oder Schmähung, politische Inhalte, Store-Regeln für KI-Inhalte über reale Personen, Mobbing unter Jüngeren (Konzept §9). Mit Team und Fachanwalt klären. Bis dahin gilt die fiktive Hommage, und alle Beispiele (Doku, Website, Store) sind erfunden.
- [ ] Marken und fremde Figuren nur als freie Anlehnung, ohne Logo und Text im Bild (Empfehlung im Konzept §9).
- [ ] Anbieter für Bildgenerierung (Kriterien im Konzept §11).
- [ ] Platz im Run und Belohnungen (Vorschlag Konzept §3 und §5).
- [ ] Ob die Altersfreigabe durch KI-Inhalte steigt (D-173 OFFEN): IARC-Fragebogen mit „nutzergenerierte Inhalte“ vorab durchspielen.

## KI1 – Bosse aus Daten laden (ohne KI)

**Ziel:** Ein Boss lässt sich vollständig als JSON plus PNG-Dateien beschreiben und **ohne Neukompilieren** ins Spiel laden.

- [ ] JSON-Schema `BossSpec` (Version 1); Felder entsprechen den Modulen im Konzept §4 und den `EnemyData`-Feldern.
- [ ] `BossSpecLoader`: prüft das Schema, klemmt Werte auf erlaubte Bereiche, bereinigt Texte (kein BBCode), baut zur Laufzeit ein `EnemyData`, lädt Sprites aus PNG und prüft Größe und Format.
- [ ] Prozedurale Animation für Einzelbild-Sprites (Atmen, Laufwackeln, Ausholen, Auflösen).
- [ ] Beispiel: den Knochenkönig als JSON nachbauen; der Kampf verhält sich wie das Original (`boss_sim.gd`).
- [ ] Entwickler-Werkzeug: Boss aus `user://dreams/` direkt in einer Testarena starten.
- [ ] Tests: ungültige, zu große und böswillige JSONs werden abgelehnt oder geklemmt; nie ein Absturz.

## KI2 – Baukasten und Budget (ohne KI)

- [ ] Neue Module: zielsuchendes, abprallendes und umkreisendes Geschoss, Spur, Strahl mit langer Vorwarnung.
- [ ] Punktekosten je Modul und Parameter; Budget je Schwierigkeit; Faktoren für HP und Schaden; Belohnungen (TESTWERTE aus Konzept §5).
- [ ] Fairness-Regeln fest im Code (Vorwarnung ≥ 0,5 s, höchstens 40 Geschosse, Tempo-Grenze, Leuchtrand).
- [ ] **Fuzz-Test:** 500 zufällige gültige Bosse laden und vom Bot bekämpfen lassen: kein Absturz, kein Boss ohne Angriff, keiner, den der Bot auf Normal nie schafft.
- [ ] Die Bausteine für Wünsche (KI0) als Katalog: jeder Baustein zeigt auf Module und Bildbeschreibungs-Teile.

## KI3 – Server: Wunsch, Beschreibung, Moderation

- [ ] `POST /dreams` (Bausteine bzw. Wunsch, Schwierigkeit, Chatverlauf) startet einen Job; `GET /dreams/{id}` liefert Status, Nachfrage oder Ergebnis. Verträge zuerst in `packages/contracts`.
- [ ] Claude (TypeScript-SDK) mit **strukturierter Ausgabe** gegen das `BossSpec`-Schema; Antwort: Nachfrage (höchstens zwei) **oder** fertige Beschreibung plus Bildbeschreibung.
- [ ] Fester Systemprompt mit Rolle, Modulkatalog, Budgetregeln und Inhaltsgrenzen; Prompt-Caching.
- [ ] **Moderation in drei Stufen:** (1) Bausteine statt Freitext als Standard; (2) Filter für Wunsch **und** Ergebnis (Text und Bild, Konzept §9); (3) **Melden** im Spiel nach dem Kampf und in der Galerie, gemeldete Bosse sofort für andere ausgeblendet. Ablehnungen als „Der Traum zerfiel“.
- [ ] Der Server prüft Schema und Budget selbst noch einmal (nie dem Modell vertrauen).
- [ ] Kontingent je Spieler, Tagesobergrenze, **Kosten je Job protokollieren** (Grundlage für die Kostenfrage aus KI0).
- [ ] **Testsammlung** mit rund 50 Wünschen (normale, verrückte, echte Personen, Marken, Unsinn, Beleidigungen, Regel-Umgehungen) und allen Baustein-Kombinationen, die sich ungünstig ergänzen; vor jeder Prompt-Änderung erneut prüfen.

## KI4 – Server: Sprite-Pipeline

- [ ] Bildgenerator mit fester Stilvorgabe und vorhandenen Boss-Sprites als Stilreferenz; Stil nach D-174 (moderne Pixel-Art).
- [ ] Spielpalette als Datei (`art/palette.png`), falls noch nicht vorhanden.
- [ ] Nachbearbeitung: Hintergrund entfernen, 64×64 bzw. 16×16, Palette, Kontur, Ausrichtung.
- [ ] Bildprüfung mit Claude (Bildeingabe): passt es, ist es lesbar, kein Text, kein Logo, kein echtes Gesicht; bis zu zwei neue Versuche, sonst Ersatz-Sprite.
- [ ] Ziel: fertiger Boss in **unter 3 Minuten**.

## KI5 – Im Spiel: Traumweber und Wunschboss im Run

- [ ] Schrein des Traumwebers im Lagerfeuer-Raum nach jedem Boss (nur online und angemeldet).
- [ ] Wunsch-Dialog im Spielstil: Bausteine als Karten zum Antippen (Touch und Gamepad), Antworten des Traumwebers, Zusammenfassungskarte, Schwierigkeitswahl; Freitext nur, wenn KI0 ihn erlaubt (höchstens 300 Zeichen).
- [ ] HUD-Anzeige „Der Traumweber webt …“, Job-Status im Hintergrund.
- [ ] Wunschboss ersetzt den nächsten Miniboss-Raum, frühestens 3 Räume später; Titel-Banner mit Name und Spruch – der Moment, den KI9 festhält.
- [ ] Fallbacks: nicht fertig → nächster Slot; Fehler oder Ablehnung → normaler Miniboss mit Meldung.
- [ ] Belohnung nach Schwierigkeit; Eintrag in die Albtraum-Galerie; Melden-Knopf nach dem Kampf.

## KI6 – Arena der Albträume, Galerie, Teilen

- [ ] Ort im Dorf: Boss wünschen und direkt in einer Arena bekämpfen (feste Ausrüstung je Schwierigkeit).
- [ ] Galerie eigener Bosse, erneut spielen.
- [ ] Teilen per Code mit Freunden; Community-Galerie und „Albtraum der Woche“ erst mit Melde- und Moderationswerkzeugen (KI8).

## KI7 – Koop und Gilden

- [ ] Der Host erzeugt bzw. lädt den Wunschboss und verteilt JSON und PNGs an alle Clients.
- [ ] Wer im Koop wünscht: Vorschlag reihum, der Host bestätigt; OFFEN.
- [ ] Skalierung nach Spielerzahl (D-084) gilt auch für Wunschbosse.
- [ ] Gilden-Galerie; die Gilde stimmt über den nächsten Albtraum ab.

## KI8 – Release

- [ ] Steam: KI-Inhalte angeben und die Schutzmaßnahmen für live erzeugte Inhalte beschreiben (Konzept §9).
- [ ] Admin-Ansicht: gemeldete Bosse prüfen, löschen, Spieler sperren (Plattform, `admin-dev`).
- [ ] Datenschutzerklärung ergänzen (Wünsche, Speicherdauer, Löschung mit dem Konto).
- [ ] Kostenüberwachung mit Warnung, Abschalter für das Feature.
- [ ] Altersfreigabe mit KI-Inhalten erneut prüfen (KI0).

## KI9 – Clip teilen

**Ziel:** Der Boss-Auftritt und der Sieg sind die Momente, die Spieler zeigen wollen (D-173). Ein Knopf „Teilen“ nach dem Kampf macht daraus ein Bild oder einen kurzen Clip, der zum Spiel einlädt. Gilt für alle Bosse, KI-Bosse und den Party-Modus.

- [ ] **Stufe 1 – Bildkarte:** Schnappschuss von Banner und Kampf (Viewport-Bild), mit Bossname, Raum, Logo und Link zum Spiel (Einladen per Link, MP2b); speichern bzw. teilen.
- [ ] **Stufe 2 – Kurzclip:** die letzten Sekunden als kurzes Video oder animiertes Bild (Ringpuffer kleiner Bilder in 480×270).
- [ ] **Stufe 3 – Plattform-Werkzeuge nutzen** statt selbst aufnehmen, wo es sie gibt (z. B. Markierungen für die Spielaufnahme von Steam, Bildschirmaufnahme des Handys).
- [ ] Mitspieler-Namen im Bild: Vorschlag nur der eigene Name, andere ausgeblendet; OFFEN.

**Machbarkeit OFFEN** (vor dem Bau als kleiner Prototyp prüfen):

| Plattform | Bild (Stufe 1) | Kurzclip (Stufe 2) |
| --- | --- | --- |
| Godot allgemein | Viewport-Bild als PNG ist einfach | Godots Movie Maker ist für Offline-Aufnahmen gedacht, nicht fürs laufende Spiel; eigener Ringpuffer kostet Speicher und Kodierzeit (GIF/WebP in GDScript langsam) |
| Browser | Teilen über das Teilen-Menü des Browsers bzw. Download | Aufnahme der Spielfläche über den Browser (Canvas-Stream) wahrscheinlich machbar; Formate je Browser verschieden |
| Android, iOS | Teilen-Menü des Systems braucht ein Plugin | Bildschirmaufnahme des Systems über ein Plugin oder dem Spieler überlassen |
| Steam (Windows, Linux, macOS) | Ordner öffnen bzw. Steam-Screenshot | Spielaufnahme von Steam mit Markierungen aus dem Spiel (prüfen, ob GodotSteam die Schnittstelle anbietet) |

**Fertig, wenn (Stufe 1):** nach einem Bosskampf auf PC, Browser und Android ein Bild mit Link entsteht und geteilt bzw. gespeichert werden kann; GUT für die Bildkarte; keine Ruckler im Kampf (Aufnahme erst nach dem Sieg).

**Koop-Check:** Aufnahme und Teilen nur lokal im eigenen Bild; keine Pause, kein Netzpaket; die Bildkarte zeigt nur, was der eigene Rechner sieht.

## Risiken

- **Kosten** je Boss (Sprachmodell + Bildgenerierung); ohne Kontingent und Obergrenze schwer planbar, wer sie trägt ist OFFEN.
- **Inhalte und Jüngere:** Spieler testen Grenzen aus, auch Jüngere spielen mit (D-173). Bausteine, Filter und Melden müssen vor dem Release stehen.
- **Echte Personen:** Rechtliche und Store-Risiken, solange die Frage offen ist (KI0, Konzept §9).
- **Bildqualität:** Generatoren treffen Pixel-Art und feste Perspektive nicht immer; die Nachbearbeitung ist Pflicht.
- **Balance:** Das Budget-System muss verhindern, dass Wunschbosse trivial oder unfair werden.
- **Clips:** Aufnahme kann auf Handys Leistung kosten; deshalb erst nach dem Kampf und als Stufe 1 nur ein Bild.

**Weiterlesen:** [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) · [ROADMAP.md](ROADMAP.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [DECISIONS.md](DECISIONS.md)
