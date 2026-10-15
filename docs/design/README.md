# Design – Mockups, Referenzen, Briefings

> Alles hier ist **Inspiration und Orientierung**, keine pixelgenaue Vorlage. Palette und Regeln: [HANDOUT.md](../HANDOUT.md). Übersicht der ganzen Doku: [docs/README.md](../README.md).

| Ordner / Datei | Inhalt |
| --- | --- |
| `screens/`, `ui_spec.json` | 13 UI-Mockups (unten beschrieben) mit Maßen, Farben und Schriftgrößen |
| `scenes/` | gerenderte Hintergründe (Hauptmenü, Dorf, Räume) aus den Spiel-Sprites |
| `szenen/` | Fotos aus dem echten Spiel als Vorlage für Claude Design ([INDEX.md](szenen/INDEX.md)); die PNGs sind nicht versioniert und werden mit `tools/scene_gallery.gd` neu erzeugt |
| [sprites/](sprites/README.md) | Grafik-Briefings `SPRITES*.md` mit Stand |
| [BRIEFING_RAEUME_V2.md](BRIEFING_RAEUME_V2.md) | Anfrage an Claude Design zu Räumen v2 (erledigt) |
| [claude_design_antwort/](claude_design_antwort/README.md) | Antworten von Claude Design; Dateinamen nicht ändern |
| `web/` | Website-Handoff und Landing-Mockups (Kopie; maßgeblich ist `soulwick-platform/docs/design/web/`) |

## Game-UI Screens – Referenz für die Umsetzung

13 Mockups der Spiel-Oberfläche, gerendert aus den echten Sprites in `art/`. Virtuelle Auflösung **480 × 270 px**: `1x/` = Originalgröße (pixelgenau), Hauptordner = 2× nearest-neighbor (960 × 540), `_overview.png` = alle zwölf auf einen Blick. Schrift: Pixelify Sans (SIL OFL) liegt als `art/fonts/PixelifySans-Variable.ttf` bei (Lizenz und Godot-Importeinstellungen daneben) und ist im Theme als `default_font` eingetragen.

**Für Claude Code / Godot:** Die PNGs sind Referenzbilder, keine Spiel-Assets. Die Bausteine liegen in `art/ui/` (Panels, Herzen, Icons), dazu `art/ui/theme.tres` (fertiges Godot-Theme mit StyleBoxTexture für alle Panels und Buttons, Varianten `PanelGold`, `PanelDark`, `LabelTitle`, `LabelMuted`) und `ui_spec.json` (alle Positionen, Größen, Farben und Schriftgrößen pro Screen, maschinenlesbar). Screens als Control-Szenen nachbauen, Viewport 480 × 270 mit Integer-Scaling.

## Gemeinsame Bausteine

- **Panels**: `art/ui/panel.png` (Standard), `panel_gold.png` (ausgewählt/fokussiert), `panel_dark.png` (HUD-Hintergrund), `button.png`, `button_hover.png`. Alle als 9-Slice mit **6 px Rand** (Godot: NinePatchRect, patch margins 6).
- **Farben**: Hintergrund `#15131f`, Text `#e9e4d2`, gedämpft `#b9b3c9`, ausgegraut `#7a7396`, Akzent/Gold `#f2cf4a`, Schaden rot `#e0463a`, Schild blau `#6cb2ec`, Attribut `#6cb2ec`, Mechanik `#5fcd62`, Effekt `#ff8a3c`, Waffe `#a98cf5`.
- **Menü-Overlay**: `rgba(21, 19, 31, 0.78)` über der pausierten Szene; Fußzeile nennt immer Tasten und „Spiel pausiert“.
- **Textgrößen (bei 480 × 270)**: Titel 13–14 px, Kartenname 9–10 px, Fließtext 7 px, Kategorie-Eyebrow 6 px Versalien mit Letterspacing.
- **Schattierung**: Text immer mit 1 px Schlagschatten `#1c1a2b` (unten rechts), damit er auf der Szene lesbar bleibt.

## Screens

| Datei | Screen | Was er zeigt |
| --- | --- | --- |
| `01_hud_kampfraum.png` | HUD im Kampf | Herzen (Viertelschritte, 16 px, 18 px Abstand) + Schild + Run-Gold oben links in `panel_dark`; Raum/Zyklus oben rechts; Waffenslots unten links (aktiv = `panel_gold`, 28 × 28), daneben effektive Werte. Schadenszahlen gelb, Schildschaden blau, Gegner mit 20 × 4 HP-Leiste. |
| `02_upgrade_auswahl.png` | Upgrade-Auswahl | 3 Karten 124 × 158, Gap 8, fokussierte Karte 4 px angehoben + `panel_gold`. Karte: Kategorie-Eyebrow, 32-px-Icon, Name, Effekt, Stack-Zeile („1 / 3 → 2 / 3“ bei Limit, „Stufe 1 → 2 · unbegrenzt“ sonst), Tastenhinweis `[1]`. |
| `03_waffenauswahl.png` | Waffenraum | Vergleichspanel 308 px breit, 3 Spalten: Angebot (`panel_gold`) / Slot 1 / Slot 2, jeweils Icon, Rolle, Schaden/Rate/Reichweite/Extra mit **effektiven** Werten inkl. Upgrades, Hinweis `[1] ersetzen`. Leeres zweites Podest wird nicht aufgefüllt. |
| `04_shop.png` | Händler | 3 × 2 Raster, Karte 64 px hoch: Icon 24 px, Eyebrow, Name, Effekt, Preis mit Münz-Icon rechts. Zu teuer = Opacity 0,55 + roter Preis + „zu wenig Gold“. Nicht kaufbare Angebote werden weggelassen (Platzhalter „kein 6. Angebot“ gestrichelt). Gold oben rechts. |
| `05_tab_uebersicht.png` | Tab-Übersicht | Ein großes Panel 440 × 242, zwei Spalten: links Upgrade-Liste (Icon, Name, Kategorie, Stack), rechts beide Waffen mit Rechenweg („14,4 Schaden (12 × 1,2)“), HP/Schild/Dash und nächste Heilung. |
| `06_portal_bestaetigung.png` | Portal-Dialog | Zentrierter Dialog 220 px: Titel, Konsequenz-Text, Zeilen „Run-Gold“ / „Gutschrift (100 %)“, zwei Buttons (`button_hover` = Default). |
| `07_run_ende_tod.png` | Tod / Run-Ende | Gleiche Dialogmaske, Titel rot, Statistikzeile, Gold-Zeilen (50 %), ein Button. Hintergrund: Death-Frame des Spielers. |
| `08_pausemenue.png` | Pause | 170 px Panel, 4 Einträge als Buttons mit rechtsbündigem Hinweis („50 % Gold · 73“), Fokus = `button_hover`. |
| `09_dorf.png` | Dorf (MVP) | Dorfgold oben rechts, Interaktionsprompt „E Dungeon betreten“ als `panel` direkt über dem Objekt. |
| `10_raum45_entscheidung.png` | Raum 45 | Dialog mit zwei gleichwertigen Buttons: Aussteigen (100 % Gold) vs. Endlos (Gold bleibt im Run). |
| `11_bosskampf_grotte.png` | Bosskampf (V2) | Boss-Leiste oben Mitte in `panel_dark`: 48-px-Porträt, Name, Raum, 180 × 7 HP-Balken in Boss-Farbe, HP-Text. Elite-Badges (12 px) 4 px über der Gegner-HP-Leiste; Elite-Name als 6-px-Label daneben. |
| `12_dorf_v2.png` | Dorf (V2) | Gold + Seelenkristalle oben rechts, Chronik-Werte (Trophäe/Schädel/Uhr) unten links, `E <Gebäude>`-Prompts über den Türen. |
| `13_hauptmenue.png` | Hauptmenü | Nachtszene vor dem Eingang aus `art/ui/menu/menu_bg_far.png` + `menu_bg_near.png` (Parallaxe möglich), Laterne/Spieler/Nebel als Sprites (`menu.json`). Logo 160 × 48 oben links, Tagline 7 px, Menüliste links (aktiv = `button_hover` + Gold-Cursor `>`, gesperrt = `#7a7396` mit Hinweis), Dorfgold/Kristalle unten links, Rekord + Version unten rechts. Linker Rand abgedunkelt (Gradient), damit Text lesbar bleibt. |

## Verhaltensregeln, die die Screens voraussetzen

1. Jedes Menü pausiert die Simulation; mehrere Pausengründe können gleichzeitig aktiv sein.
2. Gold-Konsequenz steht an jeder Entscheidung: 100 % Portal, 50 % Tod/Abbruch, „bleibt im Run“ beim Weiterspielen.
3. Angebote, die nicht gelten (Waffe im Besitz, Upgrade am Limit), werden weggelassen statt ersetzt.
4. Alle angezeigten Waffenwerte sind effektive Werte inklusive aktiver Upgrades.
5. Preise und Gold-Drops in den Mockups sind Platzhalter (im PRD offen).
