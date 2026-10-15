# ROADMAP KI-Boss „Traumweber“

> **Stand:** 13.10.2026 · **Status:** Idee für später, **nichts beschlossen oder gebaut.** Konzept: [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md).  
> **Einordnung:** Phase 4, nach [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) und [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) (D-088, D-106). Braucht den Server aus MP7 (heute `apps/api` im Repo `soulwick-platform`, Bun und Hono). **KI1 und KI2 brauchen keine KI und keinen Server** und können jederzeit vorgezogen werden.  
> **Abhaken** nur mit Nachweis (Tests, Datum).

## Überblick

| Phase | Ergebnis | Braucht Server/KI? |
| --- | --- | --- |
| KI0 | Entscheidungen | – |
| KI1 | Bosse aus JSON + PNG zur Laufzeit laden | nein |
| KI2 | Baukasten erweitern, Budget und Schwierigkeit | nein |
| KI3 | Server: Chat und Boss-Beschreibung per Claude | ja |
| KI4 | Server: Sprite-Pipeline im Spielstil | ja |
| KI5 | Im Spiel: Traumweber-Schrein, Chat, Wunschboss im Run | ja |
| KI6 | Arena der Albträume, Galerie, Teilen | ja |
| KI7 | Multiplayer und Gilden | ja |
| KI8 | Release: Steam-Angaben, Moderation, Kostenkontrolle | ja |

## KI0 – Entscheidungen

- [ ] Feature ja; Zeitpunkt (Empfehlung: nach MP, KI1/KI2 früher möglich).
- [ ] Echte Personen und Marken nur als fiktive Hommage (Empfehlung).
- [ ] Anbieter für Bildgenerierung (Kriterien siehe Konzept §11).
- [ ] Kontingent je Spieler, Tagesobergrenze für Kosten, eventuell Preis im Spiel.
- [ ] Platz im Run und Belohnungen (Vorschlag Konzept §3 und §5).

## KI1 – Bosse aus Daten laden (ohne KI)

**Ziel:** Ein Boss lässt sich vollständig als JSON plus PNG-Dateien beschreiben und **ohne Neukompilieren** ins Spiel laden.

- [ ] JSON-Schema `BossSpec` (Version 1) festlegen; Felder entsprechen den Modulen im Konzept §4 und bestehenden `EnemyData`-Feldern.
- [ ] `BossSpecLoader`:
  - prüft das Schema, klemmt Werte auf erlaubte Bereiche und bereinigt Texte,
  - baut zur Laufzeit ein `EnemyData`,
  - lädt Sprites aus PNG (`Image.load_png_from_buffer` → `ImageTexture`),
  - prüft Größe und Format.
- [ ] Prozedurale Animation für Einzelbild-Sprites (Atmen, Laufwackeln, Ausholen, Auflösen).
- [ ] Beispiel: den Knochenkönig als JSON nachbauen; Kampf muss sich wie das Original verhalten.
- [ ] Entwickler-Werkzeug: Boss aus `user://dreams/` oder einem Ordner direkt in einer Testarena starten.
- [ ] Tests: ungültige, zu große und böswillige JSONs werden abgelehnt oder geklemmt; nie ein Absturz.

## KI2 – Baukasten und Budget (ohne KI)

- [ ] Neue Module: zielsuchendes, abprallendes und umkreisendes Geschoss, Spur, Strahl mit langer Vorwarnung.
- [ ] Punktekosten je Modul und Parameter; Budget je Schwierigkeit; Faktoren für HP und Schaden; Belohnungen (TESTWERTE aus Konzept §5).
- [ ] Fairness-Regeln fest im Code (Vorwarnung ≥ 0,5 s, max. 40 Geschosse, Tempo-Grenze, Leuchtrand).
- [ ] **Fuzz-Test:** 500 zufällige gültige Bosse laden, kämpfen lassen (Bot wie in `boss_sim.gd`): kein Absturz, kein Boss ohne Angriff, kein Boss, den der Bot auf Normal nie schaffen kann.

## KI3 – Server: Chat und Boss-Beschreibung

- [ ] `POST /dreams` (Wunsch, Schwierigkeit, Chatverlauf) startet einen Job; `GET /dreams/{id}` liefert Status, Nachfrage oder Ergebnis.
- [ ] Claude (`claude-opus-5-5`, TypeScript-SDK) mit **strukturierter Ausgabe** gegen das `BossSpec`-Schema. Antwort enthält: Nachfrage des Traumwebers (höchstens zwei) **oder** fertige Beschreibung plus Bildbeschreibung.
- [ ] Fester Systemprompt mit Rolle, Modulkatalog, Budgetregeln und Inhaltsgrenzen; Prompt-Caching.
- [ ] Moderation des Wunschs und des Ergebnisses; Ablehnungen als „Der Traum zerfiel“.
- [ ] Der Server prüft Schema und Budget **noch einmal selbst** (nie dem Modell vertrauen).
- [ ] Kontingent je Spieler, Tagesobergrenze, Kosten je Job protokollieren.
- [ ] **Testsammlung** mit ca. 50 Wünschen: normale, verrückte, echte Personen, Marken, Unsinn, Beleidigungen, Versuche, die Regeln auszuhebeln. Ergebnisse vor jeder Prompt-Änderung erneut prüfen.

## KI4 – Server: Sprite-Pipeline

- [ ] Anbindung des Bildgenerators mit fester Stilvorgabe und vorhandenen Boss-Sprites als Stilreferenz.
- [ ] Spielpalette als Datei festlegen (`art/palette.png`), falls noch nicht vorhanden.
- [ ] Nachbearbeitung: Hintergrund entfernen, 64×64 bzw. 16×16, Palette, Kontur, Ausrichtung.
- [ ] Bildprüfung mit Claude (Bildeingabe): Passt es, ist es lesbar, kein Text, kein Logo, kein echtes Gesicht. Bis zu zwei neue Versuche, sonst Ersatz-Sprite.
- [ ] Ziel: fertiger Boss in **unter 3 Minuten**.

## KI5 – Im Spiel: Traumweber und Wunschboss im Run

- [ ] Schrein des Traumwebers im Checkpoint-Raum nach jedem Boss (nur online und angemeldet).
- [ ] Chat-Dialog im Spielstil (Eingabefeld max. 300 Zeichen, Antworten des Traumwebers, Zusammenfassungskarte, Schwierigkeitswahl).
- [ ] HUD-Anzeige „Der Traumweber webt …“; Abfrage des Job-Status im Hintergrund.
- [ ] Wunschboss ersetzt den nächsten Miniboss-Raum, frühestens 3 Räume später; Titel-Banner mit Name und Spruch.
- [ ] Fallbacks: nicht fertig → nächster Slot; Fehler oder Ablehnung → normaler Miniboss mit Meldung.
- [ ] Belohnung nach Schwierigkeit; Eintrag in die Albtraum-Galerie.
- [ ] Melden-Knopf nach dem Kampf.

## KI6 – Arena der Albträume, Galerie, Teilen

- [ ] Ort im Dorf: Boss beschreiben und direkt in einer Arena bekämpfen (feste Ausrüstung je Schwierigkeit).
- [ ] Galerie eigener Bosse, erneut spielen.
- [ ] Teilen per Code mit Freunden; später Community-Galerie, „Albtraum der Woche“ mit Rangliste.

## KI7 – Multiplayer und Gilden

- [ ] Der Host erzeugt bzw. lädt den Wunschboss und verteilt JSON und PNGs an alle Clients.
- [ ] Skalierung nach Spielerzahl (D-084) gilt auch für Wunschbosse.
- [ ] Gilden-Galerie; Gilde stimmt über den nächsten Albtraum ab.

## KI8 – Release

- [ ] Steam: KI-Inhalte angeben, Schutzmaßnahmen für live erzeugte Inhalte beschreiben.
- [ ] Admin-Ansicht: gemeldete Bosse prüfen, löschen, Spieler sperren.
- [ ] Datenschutzerklärung ergänzen (Wünsche, Speicherdauer, Löschung).
- [ ] Kostenüberwachung mit Warnung; Abschalter für das Feature.
- [ ] Altersfreigabe prüfen.

## Risiken

- **Kosten** pro Boss (Sprachmodell + Bildgenerierung); ohne Kontingent und Obergrenze schwer planbar.
- **Bildqualität:** Generatoren treffen Pixel-Art und feste Perspektive nicht immer; die Nachbearbeitung ist deshalb Pflicht.
- **Inhalte und Recht:** Spieler testen Grenzen aus; Moderation muss vor dem öffentlichen Start stehen.
- **Balance:** Das Budget-System muss verhindern, dass Wunschbosse trivial oder unfair werden.

**Weiterlesen:** [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) · [ROADMAP.md](ROADMAP.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [DECISIONS.md](DECISIONS.md)
