# Grafik-Briefings (SPRITES)

Briefings für Claude Design: welche Grafik fehlt, mit Dateiname, Größe, Frames, Beschreibung und Ablageort. Das Projektmitglied erzeugt die Bilder mit Claude Design und legt sie unter `art/` ab; der Code übernimmt Dateien mit dem vereinbarten Namen automatisch, bis dahin zeichnet er Platzhalter. Palette, Maßstab und Namensregeln: [HANDOUT.md](../../HANDOUT.md).

**Neue Grafiken:** in das neueste Briefing mit offenen Teilen schreiben oder ein neues `SPRITES_V<n>.md` anlegen und hier in die Tabelle eintragen. Nach dem Ablegen: `godot --headless --path . --import`.

| Briefing | Stand | Worum es geht |
| --- | --- | --- |
| [SPRITES.md](SPRITES.md) | geliefert | MVP: Spieler, Slime, Skelett, Bogenschütze, drei Waffen, Dungeon-Tileset, Dorf, UI-Grundteile; Stil- und Formatregeln |
| [SPRITES_V2.md](SPRITES_V2.md) | geliefert | Endlos-Ausbau: Biom-Tilesets, neue Gegner, vier Bosse, Elite-Kennzeichen, Dorfgebäude, Icons |
| [SPRITES_V3.md](SPRITES_V3.md) | geliefert | Dolche und Kriegshammer, Raumarten (Arena, Abgrund), Koop-Teile, Website-Grafiken (heute als WebP in `soulwick-platform/apps/web/public/brand/`) |
| [SPRITES_V4.md](SPRITES_V4.md) | geliefert | Dorf beleben (B3), Türen je Biom (D1), Lagerfeuer (A6) |
| [SPRITES_V5.md](SPRITES_V5.md) | geliefert, Kleinkram offen (§7) | Phase-2-Räume: Zutaten, Arena, Varianten, Prüfungen, Pakt, Geheimnisse; §8 Website-Chips |
| [SPRITES_V6.md](SPRITES_V6.md) | abgelöst | Einheitliche Innenmauern; aufgegangen im Wand-Autotile aus [claude_design_antwort/04_wandsystem.md](../claude_design_antwort/04_wandsystem.md) |
| [SPRITES_V7.md](SPRITES_V7.md) | geliefert | Seitentüren und Abgrund-Nachträge (A4, A10) |
| [SPRITES_V8.md](SPRITES_V8.md) | **offen** (Deko-Gruppen geliefert) | Räume v2: Bosstor je Biom, Gänge, Dorf-Eingang v2, Aufgabenleiste, Minispiel-Objekte, Quellen |
| [SPRITES_V9.md](SPRITES_V9.md) | **teilweise offen** (§1 Nachlieferung, §6) | Makeover-Welle A: Fels-Innenecken, Tunnel-Tore, Wasser, Seitenansicht (Doppelsprung, Wandrutschen) |
| [SPRITES_V10.md](SPRITES_V10.md) | **offen** (§8 App-Icons geliefert 16.10.2026) | Touch-Steuerung, Eingabe-Symbole, Türme, Seitenansicht, Figuren und Lobby, App-Icons |
| [SPRITES_V11.md](SPRITES_V11.md) | **offen** | Store-Grafiken: App-Icon 1024, Android-Adaptive-Icon, Play-Feature-Grafik, Steam-Kapseln, Bibliothek |

Antworten und Lieferlisten von Claude Design liegen daneben in [claude_design_antwort/](../claude_design_antwort/README.md) (`SPRITES_V8_vorschlag.md`, `SPRITES_V9_lieferung.md`); diese Dateinamen nicht ändern, der Code und die Werkzeuge verweisen darauf.
