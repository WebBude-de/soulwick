# Doku – Inhaltsverzeichnis

> **Stand:** 17.10.2026 · Die Doku ist Deutsch, Code und Kommentare sind Englisch. Arbeitsweise mit KI-Agenten: [AGENTS.md](../AGENTS.md).
> **Grundsatz (D-178):** Die Doku beschreibt Absicht, Gründe, Regeln, Begriffe und was kommt. **Was gebaut ist, steht im Code** (Kopfkommentare, `*.tres`, Konstanten mit `TESTWERT`). Ist etwas gebaut, wird sein Konzept auf Entscheidung und Glossar eingedampft; Roadmaps behalten Offenes und eine kurze Erledigt-Liste. Kein Archiv: Git hat die Historie.
> **Leseregel:** `VERBINDLICH` = beschlossen · `TESTWERT` = vorläufige Zahl · `VORGESCHLAGEN` = braucht Bestätigung · `OFFEN` = nicht entschieden, nicht still festlegen.

## Lesereihenfolge

| # | Dokument | Wofür |
| --- | --- | --- |
| 1 | [PRODUKT.md](PRODUKT.md) | Was Soulwick ist, für wen, Ton, Geschäftsmodell; gilt für beide Repositories |
| 2 | [GLOSSAR.md](GLOSSAR.md) | Begriffe Deutsch ↔ Englisch für Spiel, Website und Plattform |
| 3 | [ROADMAP.md](ROADMAP.md) | Übersicht aller Phasen und was jetzt dran ist |
| 4 | [PRD.md](PRD.md) | Designziele, Spielregeln mit Grund, Nicht-Ziele |
| 5 | [ARCHITECTURE.md](ARCHITECTURE.md) | Landkarte: Szenen, Zuständigkeiten, Ordner, Datenfluss |
| 6 | [TECHSTACK.md](TECHSTACK.md) | Godot-Version, Konventionen, Git-Workflow, Tests |
| 7 | [DECISIONS.md](DECISIONS.md) | alle Entscheidungen (D-Nummern), bei Widerspruch maßgeblich |

## Roadmaps

Jede Roadmap ist in Pakete für je **einen Agenten** geschnitten; abgehakt wird nur mit Nachweis (Tests grün, Datum).

| Roadmap | Inhalt |
| --- | --- |
| [ROADMAP.md](ROADMAP.md) | Übersicht über alle Phasen (D-179) |
| [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) | Phase 1 und 2: spielbar machen, Räume (2, 2b, 2c) |
| [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) | Phase 3: Koop, Steam, Gilden, Ranglisten (MP0–MP10) |
| [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) | Stores und Crossplay (CP0–CP7) |
| [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) | Phase 4: KI-Bosse „Traumweber“ |

Server, Website und Admin-Panel haben eine eigene Roadmap im Repo `soulwick-platform` (`docs/ROADMAP.md`).

## Konzepte

| Konzept | Wofür |
| --- | --- |
| [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) | Raumarten und Minispiele: Leitlinien, Regeln, Offenes (D-120) |
| [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) | KI-Bosse aus einem Wunsch (Phase 4) |
| [KONZEPT_PARTY_MODUS.md](KONZEPT_PARTY_MODUS.md) | Party-Modus: nur Minispiele, Spieler gegeneinander (Phase 5) |
| [KONZEPT_BEGLEITER_KOSMETIK.md](KONZEPT_BEGLEITER_KOSMETIK.md) | Wick als Begleiter, Kosmetik und Dorf-Deko |
| [KONZEPT_SPRACHEN_EINSTELLUNGEN.md](KONZEPT_SPRACHEN_EINSTELLUNGEN.md) | Regeln für Texte, Übersetzungen und Optionen (D-111) |

## Regeln und Anleitungen

| Dokument | Wofür |
| --- | --- |
| [MULTIPLAYER.md](MULTIPLAYER.md) | Host-Modell: wer was rechnet, Regeln für neuen Code, Koop testen |
| [HANDOUT.md](HANDOUT.md) | Ton, Maßstab, Palette, Namensregeln für Grafik und Code |
| [AUDIO.md](AUDIO.md) | Musik, Geräuschkulissen, Übergänge, eigene Dateien |
| [RELEASE.md](RELEASE.md) | Releases über GitHub Actions, Secrets, lokal bauen, Android einrichten |
| [GITHUB.md](GITHUB.md) | GitHub-Einstellungen für beide Repos: Beschreibung, Labels, Sicherheit, Branch-Schutz, Actions, Checkliste (klickt das Projektmitglied) |
| [WEB_BUILD.md](WEB_BUILD.md) | Browser-Version: Docker, Dokploy, App-Installation, Messwerte |
| [LAUNCH.md](LAUNCH.md) | Launch-Checkliste für Produktion |
| [STORES.md](STORES.md) | Google Play, App Store, Steam, Signaturen, Altersfreigabe, Datenschutz-Angaben |
| [../LICENSE-ASSETS.md](../LICENSE-ASSETS.md) | Lizenz der Inhalte: Code GPL-3.0, Grafik, Musik, Klang, Logo, Name und Figuren alle Rechte vorbehalten (D-177) |

## Ordner

| Ordner | Inhalt |
| --- | --- |
| [design/](design/README.md) | Briefings, Antworten von Claude Design, Mockups, Szenen-Galerie (Inspiration, keine exakte Vorlage); Godot liest `docs/` nicht |
| [design/sprites/](design/sprites/README.md) | Grafik-Briefings `SPRITES_V*.md` mit Stand, neuestes: [SPRITES_V12.md](design/sprites/SPRITES_V12.md) |
| [design/responses/](design/responses/README.md) | Antworten von Claude Design; Dateinamen nicht ändern, Code und Werkzeuge verweisen darauf |
| [feedback/](feedback/README.md) | Dev-Feedback-Modus (F9): Anleitung; die Auswertungen bleiben lokal |
