# Claude-Design-Antwort: Räume V2 (14.10.2026)

Antwort auf BRIEFING_RAEUME_V2 (14.10.2026). Gameplay aus KONZEPT_RAEUME_V2 übernommen; hier Look, Bau, Quellen, Türen, Intro-Muster, Wand-System, Dorf, UI. Mockups: docs/design/responses/mockups (2×, Beleuchtung als Vorschlag: Umgebung 45–55 % sichtbar statt schwarz, Lichtkreis 5 Kacheln, jede Quelle wirft Licht).

| Datei | Inhalt |
| --- | --- |
| 01_raumarten.md | Steckbriefe aller Raumarten (Fantasie, Bau, Quellen, Licht, Tür, Intro, Belohnung, Geleit-Figur) |
| 02_grundrisse.md + 02_grundrisse_uebersicht.png + sketches/ | 17 Grundrisse als ASCII mit Legende und Skizzen, Deko-Regeln |
| 03_gegner_auftritt.md | 6 Quellen mit Ablauf Warnung → Erscheinen → Angriff |
| 04_wandsystem.md | Autotile-Regel, Einbauten, Seitenwände, Abgrund |
| 05_tueren.md | Torbogen, Seitentür, Modusfarben, Gänge, Abzweigung |
| 06_dorf.md | Dorf und Dungeon-Eingang |
| 07_ui.md + 07_ui_*.png | Intro-Muster, Aufgabenleiste, HUD-Rework |
| 08_neue_raumkonzepte.md | 12 weitere Räume (Minispiele, Ruhe, Geheimnis) |
| 09_audio.md | Sound-Beschreibungen für die Code-Synthese |
| 10_makeover_organisch.md + 10_makeover_grundrisse.png | Makeover 2: organische Umrisse, Bodenzonen, Streu-Overlays, 8 neue Pläne (18–25) |
| 11_makeover3_komplett.md + 11_uebergang_seitenansicht.png | Makeover 3: Fels-Terrain (47 Kacheln), Höhlenmund, Emporen/Leitern, Seitenansicht-Gänge, Pakete P1–P7, SPRITES_V9-Liste |
| SPRITES_V8_vorschlag.md | geliefert / offen (offene Teile seit 22.10.2026 in `../sprites/SPRITES_V13.md` Teil D) |
| mockups/ | 17 Raum-Mockups im Spielstil (2×) |

Grundsätze:
- Jeder Raum hat eine Bühne: ein Objekt in der Mitte oder am Ziel, das die Aufgabe erklärt (Flamme, Altar, Pfad, Feuerschalen), bevor ein Wort fällt.
- Gegner kommen aus Quellen, die zum Grundriss gehören und meist hinter dem Spieler liegen; Quellen leuchten 1 s vor dem Erscheinen.
- Deko erzählt: Gruppen von 3–5 Teilen mit Geschichte (eingestürzte Säule + Geröll, Opferstelle + Kerzen, tropfende Decke + Pfütze), nie Einzelstreuung.
- Licht ist Information: Modusfarbe an der Tür, Quellenfarbe am Boden, warmes Licht = sicher, kaltes = Ziel, rot = Gefahr.
- Wände sind überall gleich: Krone + eine Reihe Vorderseite, Einbauten sitzen bündig in der Vorderseite (Nische, Riss, Tor, Tür).

Interaktive Fassung: Raumkonzept-V2.dc.html (Seite 1) und Raumkonzept-Neu.dc.html (Seite 2) im Design-Projekt. Generator: tools/roomgen (plans.json → mockups).

## Weitere Antworten

Neue Antworten von Claude Design kommen hierher, je eine Zeile. Für die Vollversion erwartet (SPRITES_V13 Teil A): `13_wick_erklaert.png`, `14_zuhause_talentbaum.png`, `15_dorf_drei_saeulen.png`, `16_rang_und_seelentor.png`, `17_uebungsgang.png`, `18_rang_abzeichen.png`.

| Datei | Inhalt | Datum |
| --- | --- | --- |
| `14_zuhause_talentbaum.png` (+ `_2x`) | A3: Zuhause innen mit Kerzen-Altar, daneben Talentbaum-Dialog (drei Pfade, Knoten) | 22.10.2026 |
| `14b_zuhause_cozy.png` (+ `_2x`) | Zuhause beim ersten Betreten fertig eingerichtet, Nacht, Licht-Konzept (siehe `20_antwort_zuhause_plattformen.md` §1) | 22.10.2026 |
| `15_dorf_drei_saeulen.png` (+ `_2x`) | A4: Dorf mit Schmiede, Handelsposten, Zuhause und ihren Schildern | 22.10.2026 |
| `16_rang_und_seelentor.png` (+ `_2x`) | A5: Rang-Anzeige am Eingang, Seelentor-Dialog, Run-Ende „Rang gestiegen!“ | 22.10.2026 |
| `17_uebungsgang.png` (+ `_2x`) | A6: Übungshof mit Strohpuppen, Pfeilfalle, Sprungstück, Stationsschildern | 22.10.2026 |
| `17b_uebungsgang_spielansicht.png` (+ `_2x`) | A6 als Spielansicht | 22.10.2026 |
| `18_rang_abzeichen.png` | A7: Entwurfsblatt der Rang-Abzeichen (32 und 16 px, Stufenmarken) | 22.10.2026 |
| `21_plattform_halbe_hoehe.png` | Plattformen und Emporen in halber Höhe (16 px) mit Treppe | 22.10.2026 |
| `19_antwort_flint_rang.md` | Flint ≈ 12 px im 16er-Frame, Kamera-Zoom 3,5, Rang des Squads steuert die Gefahr (Abzeichen mit Stufenmarken) | 22.10.2026 |
| `20_antwort_wick.md` | Stand 16.10.: Wick statt Flint als Begleiter, Erklären ohne Rahmen, zwei Jump'n'Run-Stile; in Name und Begleiter-Form **überholt** durch D-198 (Begleiter heißt Flint) | 22.10.2026 |
| `20_antwort_zuhause_plattformen.md` | Zuhause cozy (Licht, Startmöbel, Zusatzdateien), Plattformen halbe Höhe, Dorf auf zwei Ebenen | 22.10.2026 |
| `13_flint_erklaert.png` | Erklär-Ecke: Szene mit `guide_frame`, `flint_portrait_point` und Sprechblase (V13b); nur Vorlage, Flint darin noch mit violetter Flamme (gilt: orange, D-198) | 22.10.2026 |
| `19_sturmlauf.png` | A8 Sturmlauf ohne Uhr und Medaillen, Ergebnisbanner mit Münzen, Kombo und Gegnern, Krone über Spieler 2 (V13b) | 22.10.2026 |
| `20_flint_erklaert_ingame.png` | Flint erklärt im laufenden Spiel (V13b); nur Vorlage, Flamme noch violett (gilt: orange, D-198) | 22.10.2026 |
| `20_flint_massstab.png` | Flint 16 px im Maßstab zu Spieler und Raum (V13b); nur Vorlage, Flamme noch violett (gilt: orange, D-198) | 22.10.2026 |
