# Fehler melden und Ideen einreichen (Taste #, F9, Käfer-Knopf)

Werkzeug für alle Spieler, solange Beta-/Test-/Entwicklungsphase ist: Während des Spiels eine Stelle markieren und aufschreiben, was nicht stimmt (Reiter **Fehler melden**, Standard) oder was man sich wünscht (Reiter **Idee einreichen**). Eine Kategorie wählt der Spieler nicht (seit 17.10.2026): Das Spiel schreibt selbst dazu, wo die Meldung entstand (Raum, Biom, Bosskampf, offenes Menü oder Dialog, Koop, Gerät, siehe „Was automatisch mitkommt“). Jede Meldung wird lokal gespeichert und zusätzlich an die Plattform-API geschickt. Claude wertet die Meldungen danach aus.

## Wann ist es an?

Schalter in dieser Reihenfolge (das Erste, was gesetzt ist, gilt):

1. Kommandozeile nach `--`: `bug_reports=1` oder `bug_reports=0`.
2. Projekteinstellung `soulwick/beta/bug_reports` (true/false). Steht noch nicht in `project.godot`; ohne sie entscheidet Punkt 3.
3. Umgebung des Builds (`OnlineConfig`): im Editor (`local`) und in `development`-Exporten **an**, in `production`-Exporten **aus**.

Ist es aus, entsteht kein Knoten, keine Taste und kein Knopf.

## Bedienung

### PC

1. Im Spiel **#** drücken (deutsche Tastatur; auf anderen Layouts die Taste an derselben Stelle neben Enter, z. B. `\`) oder **F9**. Geht überall: Hauptmenü, Dorf, Dungeon, Seitenansicht, Dialoge, Pausenmenü. In einem Textfeld (z. B. Gildenname) bleibt # ein Zeichen, F9 geht trotzdem. Das Spiel friert ein, das aktuelle Bild bleibt stehen.
2. **Markieren:** mit gedrückter linker Maustaste Rechtecke aufziehen (werden 1, 2, 3 … nummeriert). **Umschalt + Ziehen** zeichnet einen freien Strich. **Rechtsklick** auf ein Rechteck (oder einen Strich) entfernt es.
3. **Reiter:** oben in der Leiste „Fehler melden“ (immer vorausgewählt) oder „Idee einreichen“. Beide funktionieren gleich, nur Überschrift und Platzhalter wechseln („Was ist kaputt?“ / „Was wünschst du dir?“). Wechseln per Klick oder **Strg+Tab**; Text und Markierungen bleiben beim Wechsel erhalten.
4. **Text:** unten links die gemeinsame Notiz (mehrzeilig), rechts daneben optional eine kurze Notiz je Rechteck. Verdeckt die Leiste etwas, schiebt „Leiste nach oben“ sie nach oben.
5. **Senden:** Strg+Enter oder „Senden“. Oben links erscheint „Danke! Meldung gespeichert“ (bei Ideen „Danke! Idee gespeichert“), das Spiel läuft genau dort weiter; sobald die Meldung beim Server ist, kurz „Meldung gesendet“.
6. **Verwerfen:** „Abbrechen“ oder Esc (steht schon etwas drin, Esc zweimal drücken).

### Gamepad

Im offenen Dialog: **LB/RB** wechselt den Reiter, **Start** sendet (bestätigt auch den Datenschutz-Hinweis), **B** bricht ab (mit Inhalt zweimal). Sobald eine Pad-Taste kommt, zeigt die Leiste diese Tasten statt der Tastenkürzel. Öffnen geht per Pad noch nicht (offen: eigene Tastenkombination).

### Handy (temporär, nur Beta)

- Oben rechts unter der Raumzeile sitzt ein kleiner, halbtransparenter **Käfer-Knopf** (nur sichtbar, wenn Touch benutzt wird). Antippen öffnet die Meldung.
- Die beiden Reiter sind auf dem Handy daumengroß; antippen wechselt.
- **Ziehen** mit dem Finger = Rechteck, **lange drücken** auf ein Rechteck = entfernen.
- Notiz-Feld antippen öffnet die Bildschirmtastatur, die Leiste rutscht darüber. „Senden“ und „Abbrechen“ statt Tastenkürzel.

Unten in der Leiste steht der Hinweis: Screenshot, Notiz und Spielinfos werden an das Entwicklerteam geschickt. Vor der allerersten Meldung kommt einmal ein kurzer Datenschutz-Hinweis („Einverstanden, senden“ / „Zurück“); die Bestätigung merkt sich das Spiel in `user://bug_report_consent.cfg` (nicht im Spielstand).

## Wo die Dateien liegen

`%APPDATA%\Godot\app_userdata\Soulwick\dev_feedback\` – je Meldung ein Ordner `<Datum>_<Uhrzeit>_<Nr>` mit

- `screenshot.png` (Originalbild), `marked.png` (mit den Markierungen),
- `note.json` (Text, Art `kind`: `bug` oder `idea`, Rechtecke, lesbarer Ort `location`, Kontext wie unten sowie die UI- und Welt-Knoten unter jedem Rechteck; ältere Meldungen haben statt `kind` noch `categories` und zählen als Fehler),
- `upload.json` (nach dem Upload: `sent` mit Server-ID oder `rejected` mit Fehler),

dazu `index.md` mit einer Zeile je Meldung (Spalte „Art“: Fehler oder Idee).

## Was automatisch mitkommt (`context`)

Alles wird defensiv gelesen (fehlt etwas, bleibt es weg); höchstens 16 KiB, keine Raumcodes, keine Namen außer dem eigenen.

- `location`: eine lesbare Zeile auf Deutsch, z. B. `Dungeon · Raum 23 · Schleimgrotte · Kampf (Upgrade)`, `Dungeon · Raum 30 · Krypta · Bossraum · Bosskampf: <Name> (Phase 2)`, `Hauptmenü · Online · Gilden · Gildenseite` oder `Dorf · Schmiede`. Offene Dialoge hängen hinten an (`… · Pausemenü`).
- `screen`: offener Bildschirm bzw. Dialog (`label` wie oben, `parts` als Liste, `nodes` die gefundenen Knoten).
- `boss`: im Bosskampf Name, Kennung, Phase, Lebenspunkte (`hp`, `hp_max`) und Anzahl.
- `coop`: Spieleranzahl, Rolle (`solo`, `host`, `client`), online ja/nein, `ping_ms` (aus `network`).
- `device`: Plattform (`windows`, `web`, `android` …), Handy-UI ja/nein, Eingabegerät (`mouse`, `touch`, `gamepad`), Bildschirmgröße, UI-Zoom.
- Dazu wie bisher Szene, Phase, Fenster, Kamera, Pausegründe, Dungeon (Raum, Biom, Art, Vorlage, Seed …), Spielerpositionen und `network` (Bildrate, Hänger, online Ping und Datenmenge, ohne Raumcode).

## Upload

- Beim Senden landet die fertige Anfrage zusätzlich in `dev_feedback/outbox/<ordner>.json` und geht im Hintergrund an `POST /bug-reports` (Spieler-Token der `OnlineSession`, bei Bedarf Gast-Login). Nichts blockiert, nichts pausiert.
- Inhalt (Vertrag `soulwick-platform/packages/contracts/src/bug-report.ts`): Notiz, Art (`kind`: `bug`/`idea`, zusätzlich unter `context.kind`, falls der Server das Feld noch nicht kennt), `categories: []` (leer), Rechtecke und Striche relativ (0..1), Kontext (höchstens 16 KiB, sonst gekürzt, Liste in `truncated`), Spielversion, Plattform, Screenshot als WebP (verlustbehaftet, höchstens 1280×720 und 1,5 MiB).
- Kein Server, 404 (Route fehlt noch) oder 5xx: bleibt in der Outbox und wird beim nächsten Start (nach 8 s) bzw. alle 3 Minuten erneut versucht. 429 (`rate_limited`, 10 je Spieler und Stunde): 10 Minuten Pause. 401: neue Anmeldung, einmal erneut.
- 400 `invalid_image`: einmal als JPEG neu kodiert und erneut gesendet; 413 `payload_too_large`: einmal kleiner (960×540, niedrigere Qualität) erneut. Beides aus `screenshot.png` der Meldung.
- Endgültig (kein weiterer Versuch): 400 `validation_error`, 403 `banned`, ein zweites `invalid_image`/413. Die Datei wandert nach `outbox/rejected/`, Vermerk in `upload.json` und `outbox/index.md`.
- Der Server löscht Meldungen nach 90 Tagen und mit dem Konto.

## Auswerten (lokal)

```bat
python tools/collect_feedback.py                     # alle lokalen Meldungen
python tools/collect_feedback.py --since 2026-10-15  # nur ab einem Tag
python tools/collect_feedback.py --group location    # nach Ort statt nach Art
```

Das schreibt `docs/feedback/FEEDBACK_<Datum>.md` (Abschnitte **Fehler** und **Ideen**; Meldungen ohne `kind` sind Fehler, alte Kategorien stehen als „Kategorien (alt)“ dabei; die Kontextzeile nennt Bildschirm, Bosskampf, Koop, Gerät und Eingabe) und kopiert die Bilder nach `docs/feedback/<Datum>/`. Diese Dateien bleiben lokal (gitignored, nur diese Anleitung ist versioniert). Danach Claude sagen: „Werte `docs/feedback/FEEDBACK_<Datum>.md` aus und mach den Grafik-Rework.“

## Run-Protokolle auswerten (D-165)

Jeder Run schreibt ein Protokoll nach `user://runs/` (JSONL, die letzten 50 Runs; nur Spieldaten): Kopf mit Version, Modus, Waffe und Seed, je Raum Art, Biom, Dauer, Schaden und Gold, am Ende Grund, Ursache und Upgrades. Fehlt die `end`-Zeile, ist das Spiel abgestürzt.

```bat
python tools/collect_feedback.py --runs                      # -> docs/feedback/RUNS_<Datum>.md
python tools/collect_feedback.py --runs --since 2026-10-17   # nur neuere Runs
python tools/collect_feedback.py --runs --src <ordner>       # Protokolle eines Mitspielers
```

Die Übersicht zeigt Endgründe und End-Raum, die häufigsten Todesursachen, Zeit, Schaden und Gold je Biom und Raumart und den End-Raum je Startwaffe. Für einen Dev-Test: Mitspieler schicken ihren Ordner `%APPDATA%/Godot/app_userdata/Soulwick/runs/`.

Bug-Meldungen (F9) enthalten seit D-159 unter `context.network` Bildrate, längsten Hänger des Hauptthreads und online Ping, Datenmenge und den letzten Trennungsgrund.

## Meldungen auswerten (alle Spieler, Server)

Eine Admin-Oberfläche dafür gibt es nicht: Claude holt die Meldungen aller Spieler über die Admin-API und wertet sie aus (labeln, verbessern).

```bat
set SOULWICK_ADMIN_EMAIL=<admin-konto>
set SOULWICK_ADMIN_PASSWORD=<passwort>
python tools/collect_feedback.py --api https://api-dev.playsoulwick.com              # neue Meldungen
python tools/collect_feedback.py --api https://api-dev.playsoulwick.com --status all --limit 200
python tools/collect_feedback.py --api https://api-dev.playsoulwick.com --mark-seen  # danach auf "seen" setzen
```

Das meldet sich wie das Admin-Panel an (`POST /admin/auth/login`), liest `GET /admin/bug-reports`, die Details und das Bild, zeichnet die Markierungen lokal ins Bild (`marked.png`, mit Pillow; ohne Pillow nur Originalbild und Liste) und schreibt dieselbe Übersicht wie lokal. Fehlen die Admin-Routen noch (404), die Zugangsdaten oder der Server, kommt ein Hinweis, kein Absturz.

**Regel für den auswertenden Agenten:** Unplausible oder offensichtlich falsche Meldungen (Spaß, Spam, widersprüchlich, Markierung passt nicht zur Notiz, beschreibt gewolltes Verhalten) **nicht still umsetzen und nicht still verwerfen**. In der Übersicht die Spalte **prüfen?** (Tabelle „Alle Meldungen“ und die Zeile je Meldung) auf `ja: <Grund>` setzen und dem Projektmitglied kurz zeigen: Bild, Notiz, Begründung. Das Projektmitglied entscheidet „hatte recht“ oder „Unsinn“. Plausible Meldungen bleiben leer und werden umgesetzt.
