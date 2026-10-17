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
| [SPRITES_V6.md](SPRITES_V6.md) | abgelöst | Einheitliche Innenmauern; aufgegangen im Wand-Autotile aus [responses/04_wandsystem.md](../responses/04_wandsystem.md) |
| [SPRITES_V7.md](SPRITES_V7.md) | geliefert | Seitentüren und Abgrund-Nachträge (A4, A10) |
| [SPRITES_V8.md](SPRITES_V8.md) | **offen** (Deko-Gruppen geliefert) | Räume v2: Bosstor je Biom, Gänge, Dorf-Eingang v2, Aufgabenleiste, Minispiel-Objekte, Quellen |
| [SPRITES_V9.md](SPRITES_V9.md) | **teilweise offen** (§1 Nachlieferung, §6) | Makeover-Welle A: Fels-Innenecken, Tunnel-Tore, Wasser, Seitenansicht (Doppelsprung, Wandrutschen) |
| [SPRITES_V10.md](SPRITES_V10.md) | geliefert 17.10.2026, **14 Eingabe-Symbole offen** (§2: Gamepad-Buchstaben, Gesten, Esc, Select, Touch-Benutzen), **§9 niedrige Torbögen offen** (Bosstor und weicher Bogen 64×48), **§10 Hochkant-Controller offen** (Gehäuse, Steuerkreuz, A/B/kleine/flache Knöpfe; Platzhalter aus Code) | Touch-Steuerung, Eingabe-Symbole, Türme, Seitenansicht, Figuren und Lobby, App-Icons, niedrige Torbögen, Hochkant-Controller |
| [SPRITES_V11.md](SPRITES_V11.md) | geliefert 17.10.2026 | Store-Grafiken: App-Icon 1024, Android-Adaptive-Icon, Play-Feature-Grafik, Steam-Kapseln, Bibliothek |
| [SPRITES_V12.md](SPRITES_V12.md) | **offen** (17.10.2026; zuerst Konzeptblatt §0) | Maskottchen Wick als Begleiter und in groß für Menü und Stores, Huhn mit Wick, erste Kosmetik (drei Hüte für Figur und Wick); Website-Grafiken bekommen ein eigenes Briefing im Plattform-Repo |

Antworten und Lieferlisten von Claude Design liegen daneben in [responses/](../responses/README.md) (`SPRITES_V8_vorschlag.md`, `SPRITES_V9_lieferung.md`); diese Dateinamen nicht ändern, der Code und die Werkzeuge verweisen darauf.
