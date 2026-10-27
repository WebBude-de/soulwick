# Grafik-Briefings (SPRITES)

Briefings für Claude Design: welche Grafik fehlt, mit Dateiname, Größe, Frames, Beschreibung und Ablageort. Das Projektmitglied erzeugt die Bilder mit Claude Design und legt sie unter `art/` ab; der Code übernimmt Dateien mit dem vereinbarten Namen automatisch, bis dahin zeichnet er Platzhalter. Palette, Maßstab und Namensregeln: [HANDOUT.md](../../HANDOUT.md). Nach dem Ablegen: `godot --headless --path . --import`.

## Offen: ein Briefing für alles

**[SPRITES_V13.md](SPRITES_V13.md)** (22.10.2026, D-193) ist das **einzige offene Briefing**: Teil A Konzeptblätter und Mockups (Flint, „Flint erklärt“, Zuhause mit Talentbaum, Dorf mit drei Säulen, Rang und Seelentor, Übungsgang, Rang-Abzeichen), Teil B Sprites für den Kern-Umbau, **Teil C Nachträge der Agenten**, Teil D alles, was aus älteren Briefings noch fehlt.

**Agenten tragen fehlende Grafik jederzeit in Teil C ein** (eine Zeile: Paket, Datei, Größe und Frames, Beschreibung, Datum) und bauen bis zur Lieferung einen Platzhalter aus Code ([AGENTS.md](../../../AGENTS.md) §8). Ist SPRITES_V13 komplett geliefert, kommt das nächste Briefing als `SPRITES_V14.md`, und V13 wandert nach `delivered/`.

## Geliefert: Namensregeln in `delivered/`

Die gelieferten Briefings bleiben als Nachschlagewerk für Dateinamen, Maße, Pivots und JSON, weil Code und Werkzeuge darauf verweisen. Offene Reste daraus stehen in SPRITES_V13 Teil D.

| Briefing | Worum es ging |
| --- | --- |
| [SPRITES.md](delivered/SPRITES.md) | MVP: Spieler, Slime, Skelett, Bogenschütze, drei Waffen, Dungeon-Tileset, Dorf, UI-Grundteile; Stil- und Formatregeln |
| [SPRITES_V2.md](delivered/SPRITES_V2.md) | Endlos-Ausbau: Biom-Tilesets, neue Gegner, vier Bosse, Elite-Kennzeichen, Dorfgebäude, Icons |
| [SPRITES_V3.md](delivered/SPRITES_V3.md) | Dolche und Kriegshammer, Raumarten, Koop-Teile, Website-Grafiken |
| [SPRITES_V4.md](delivered/SPRITES_V4.md) | Dorf beleben, Türen je Biom, Lagerfeuer |
| [SPRITES_V5.md](delivered/SPRITES_V5.md) | Räume der Phase 2: Zutaten, Arena, Varianten, Prüfungen, Pakt, Geheimnisse; Website-Chips |
| [SPRITES_V6.md](delivered/SPRITES_V6.md) | Innenmauern (abgelöst durch das Wand-Autotile) |
| [SPRITES_V7.md](delivered/SPRITES_V7.md) | Seitentüren und Abgrund-Nachträge |
| [SPRITES_V9.md](delivered/SPRITES_V9.md) | Makeover: Fels, Tunnel-Tore, Wasser, Seitenansicht, Höhe |
| [SPRITES_V10.md](delivered/SPRITES_V10.md) | Touch-Steuerung, Eingabe-Symbole, Türme, Figuren und Lobby, App-Icons, niedrige Torbögen, Hochkant-Controller |
| [SPRITES_V11.md](delivered/SPRITES_V11.md) | Store-Grafiken: App-Icon, Android-Adaptive-Icon, Play-Feature-Grafik, Steam-Kapseln |

SPRITES_V8 (Räume v2) und SPRITES_V12 (Flint, Huhn, erste Hüte) sind vollständig in SPRITES_V13 aufgegangen. Antworten und Lieferlisten von Claude Design liegen in [responses/](../responses/README.md); deren Dateinamen nicht ändern. Website-Grafiken haben ein eigenes Briefing im Plattform-Repo.
