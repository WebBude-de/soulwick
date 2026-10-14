# Claude-Design-Antwort: Räume V2 (14.10.2026)

Antwort auf BRIEFING_RAEUME_V2 (14.10.2026). Gameplay aus KONZEPT_RAEUME_V2 übernommen; hier Look, Bau, Quellen, Türen, Intro-Muster, Wand-System, Dorf, UI. Mockups: docs/design/claude_design_antwort/mockups (2×, Beleuchtung als Vorschlag: Umgebung 45–55 % sichtbar statt schwarz, Lichtkreis 5 Kacheln, jede Quelle wirft Licht).

| Datei | Inhalt |
| --- | --- |
| 01_raumarten.md | Steckbriefe aller Raumarten (Fantasie, Bau, Quellen, Licht, Tür, Intro, Belohnung, Geleit-Figur) |
| 02_grundrisse.md + 02_grundrisse_uebersicht.png + skizzen/ | 17 Grundrisse als ASCII mit Legende und Skizzen, Deko-Regeln |
| 03_gegner_auftritt.md | 6 Quellen mit Ablauf Warnung → Erscheinen → Angriff |
| 04_wandsystem.md | Autotile-Regel, Einbauten, Seitenwände, Abgrund |
| 05_tueren.md | Torbogen, Seitentür, Modusfarben, Gänge, Abzweigung |
| 06_dorf.md | Dorf und Dungeon-Eingang |
| 07_ui.md + 07_ui_*.png | Intro-Muster, Aufgabenleiste, HUD-Rework |
| 08_neue_raumkonzepte.md | 12 weitere Räume (Minispiele, Ruhe, Geheimnis) |
| 09_audio.md | Sound-Beschreibungen für die Code-Synthese |
| SPRITES_V8_vorschlag.md | geliefert / offen |
| mockups/ | 17 Raum-Mockups im Spielstil (2×) |

Grundsätze:
- Jeder Raum hat eine Bühne: ein Objekt in der Mitte oder am Ziel, das die Aufgabe erklärt (Flamme, Altar, Pfad, Feuerschalen), bevor ein Wort fällt.
- Gegner kommen aus Quellen, die zum Grundriss gehören und meist hinter dem Spieler liegen; Quellen leuchten 1 s vor dem Erscheinen.
- Deko erzählt: Gruppen von 3–5 Teilen mit Geschichte (eingestürzte Säule + Geröll, Opferstelle + Kerzen, tropfende Decke + Pfütze), nie Einzelstreuung.
- Licht ist Information: Modusfarbe an der Tür, Quellenfarbe am Boden, warmes Licht = sicher, kaltes = Ziel, rot = Gefahr.
- Wände sind überall gleich: Krone + eine Reihe Vorderseite, Einbauten sitzen bündig in der Vorderseite (Nische, Riss, Tor, Tür).

Interaktive Fassung: Raumkonzept-V2.dc.html (Seite 1) und Raumkonzept-Neu.dc.html (Seite 2) im Design-Projekt. Generator: tools/roomgen (plans.json → mockups).
