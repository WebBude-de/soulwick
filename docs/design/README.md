# Design – Briefings, Antworten, Mockups, Galerie

> **Stand:** 17.10.2026 · Alles hier ist **Inspiration und Orientierung**, keine pixelgenaue Vorlage. Palette, Maßstab und Namensregeln: [HANDOUT.md](../HANDOUT.md). Gesamte Doku: [docs/README.md](../README.md).
> Godot liest `docs/` nicht (`docs/.gdignore`): Bilder hier brauchen keine `.import`-Dateien und landen nie im Spiel. Was im Spiel benutzt wird, liegt unter `art/`.

## Ordner

| Ordner / Datei | Was | Wer schreibt |
| --- | --- | --- |
| [sprites/](sprites/README.md) | Grafik-Briefings `SPRITES_V*.md` mit Stand je Briefing | Agenten, wenn Grafik fehlt (AGENTS.md §8); die Bilder selbst kommen nach `art/` |
| [responses/](responses/README.md) | Antworten von Claude Design: Konzepte und Pläne (`*.md`, `content*.json`), Raum-Mockups (`mockups/`), Skizzen (`sketches/`), Lieferlisten | Claude Design über das Projektmitglied |
| `mockups/screens/` + [ui_spec.json](ui_spec.json) | 13 UI-Mockups der ersten Oberfläche (2×, `1x/` pixelgenau, `_overview.png`) mit Maßen, Farben, Schriftgrößen | Referenz, wird nicht nachgezogen |
| `mockups/backgrounds/` | gerenderte Hintergründe (Hauptmenü, Dorf, Räume) aus den Spiel-Sprites | Referenz |
| [gallery/](gallery/INDEX.md) | Fotos aus dem echten Spiel als Vorlage für Claude Design; `INDEX.md` beschreibt jedes Bild, `AUSWAHL.md` nennt die 30 wichtigsten | Werkzeug `tools/scene_gallery.gd`; nur die beiden `.md` sind versioniert |
| [BRIEFING_RAEUME_V2.md](BRIEFING_RAEUME_V2.md) | Anfrage an Claude Design zu Räumen v2 (erledigt, D-120) | – |

Das Website-Design liegt nur im Plattform-Repo (`soulwick-platform/docs/design/web/`).

## Regeln

- **Ordnernamen Englisch** (D-178). Dateinamen bleiben, wie sie geliefert wurden: Code und Werkzeuge verweisen auf `responses/*` (z. B. `02_grundrisse.md` als Legende der Raumpläne).
- **Neue Antwort von Claude Design** → nach `responses/` (Bilder in den passenden Unterordner), Zeile in `responses/README.md`; daraus macht Claude Briefings, D-Einträge und Roadmap-Pakete.
- **Neue Grafik nötig** → Briefing in `sprites/`, nicht hier ablegen.
- **Galerie neu erzeugen** (braucht ein Fenster, ca. 12 min): `SOULWICK_QUIET=1 godot --audio-driver Dummy --path . -s tools/scene_gallery.gd -- docs/design/gallery`. Die PNGs nicht committen (`.gitignore`), `INDEX.md` von Hand nachziehen.
- **Zahlen in Mockups** (Preise, Gold, Werte) sind Platzhalter; es gelten die TESTWERTE im Code.

## UI-Mockups (`mockups/screens/`)

Maße in Mockup-Pixeln 480 × 270; das Spiel läuft in 1280 × 720 und rechnet sie über `UiKit` um. Die heutige Oberfläche ist seit dem UI-Rework (D-139) weiterentwickelt; die Bilder zeigen den Ausgangsstil.

| Datei | Screen |
| --- | --- |
| `01_hud_kampfraum.png` | HUD im Kampf |
| `02_upgrade_auswahl.png` | Upgrade-Wahl (3 Karten) |
| `03_waffenauswahl.png` | Waffenauswahl mit Vergleich |
| `04_shop.png` | Händler (3 × 2 Angebote) |
| `05_tab_uebersicht.png` | Tab-Übersicht |
| `06_portal_bestaetigung.png` | Portal-Dialog |
| `07_run_ende_tod.png` | Run-Ende nach Tod |
| `08_pausemenue.png` | Pausemenü |
| `09_dorf.png`, `12_dorf_v2.png` | Dorf |
| `10_raum45_entscheidung.png` | Raum-45-Wahl (entfallen, D-073) |
| `11_bosskampf_grotte.png` | Bosskampf mit Boss-Leiste |
| `13_hauptmenue.png` | Hauptmenü |
