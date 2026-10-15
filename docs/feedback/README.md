# Dev-Feedback (F9)

Werkzeug für Entwickler: Während des Spiels eine Stelle markieren und aufschreiben, was an UI oder Grafik nicht gut ist. Claude wertet die Notizen danach für einen Grafik-Rework aus. Es läuft nur in Debug-Builds (Editor, lokaler Start), in Release-Exporten ist es aus.

## Bedienung

1. Im Spiel **F9** drücken (geht überall: Hauptmenü, Dorf, Dungeon, Seitenansicht, auch in Dialogen und im Pausenmenü). Das Spiel friert ein, das aktuelle Bild bleibt stehen.
2. **Markieren:** mit gedrückter linker Maustaste Rechtecke aufziehen (werden 1, 2, 3 … nummeriert). **Umschalt + Ziehen** zeichnet einen freien Strich. **Rechtsklick** auf ein Rechteck (oder einen Strich) entfernt es.
3. **Text:** unten links die gemeinsame Notiz (mehrzeilig), rechts daneben optional eine kurze Notiz je Rechteck. Oben die Kategorien anklicken (mehrere möglich): UI, Grafik, Licht, Raum/Layout, Gameplay, Bug, Text. Verdeckt die Leiste etwas, schiebt „Leiste nach oben“ sie nach oben.
4. **Speichern:** Strg+Enter oder „Speichern“. Oben links erscheint „Notiz gespeichert (#12)“, das Spiel läuft genau dort weiter.
5. **Verwerfen:** „Abbrechen“ oder Esc (steht schon etwas drin, Esc zweimal drücken).

## Wo die Dateien liegen

`%APPDATA%\Godot\app_userdata\Soulwick\dev_feedback\` – je Notiz ein Ordner `<Datum>_<Uhrzeit>_<Nr>` mit

- `screenshot.png` (Originalbild), `marked.png` (mit den Markierungen),
- `note.json` (Text, Kategorien, Rechtecke, Ort: Szene, Raum, Biom, Modus, Vorlage, Seed, Spielerposition sowie die UI- und Welt-Knoten unter jedem Rechteck),

dazu `index.md` mit einer Zeile je Notiz.

## Auswerten

```
python tools/collect_feedback.py                     # alle Notizen
python tools/collect_feedback.py --since 2026-10-15  # nur ab einem Tag
python tools/collect_feedback.py --group location    # nach Ort statt nach Kategorie
```

Das schreibt `docs/feedback/FEEDBACK_<Datum>.md` und kopiert die Bilder nach `docs/feedback/<Datum>/`. Diese Dateien bleiben lokal (gitignored, nur diese Anleitung ist versioniert). Danach Claude sagen: „Werte docs/feedback/FEEDBACK_<Datum>.md aus und mach den Grafik-Rework.“
