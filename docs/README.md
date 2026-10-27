# Doku – Inhaltsverzeichnis

> **Stand:** 22.10.2026 · Die Doku ist Deutsch, Code und Kommentare sind Englisch. Arbeitsweise mit KI-Agenten: [AGENTS.md](../AGENTS.md).
> **Grundsatz (D-178):** Die Doku beschreibt Absicht, Gründe, Regeln, Begriffe und was kommt. **Was gebaut ist, steht im Code** (Kopfkommentare, `*.tres`, Konstanten mit `TESTWERT`). Ist etwas gebaut, wird sein Konzept auf Entscheidung und Glossar eingedampft; Roadmaps behalten Offenes und eine kurze Erledigt-Liste. Kein Archiv: Git hat die Historie.
> **Leseregel:** `VERBINDLICH` = beschlossen · `TESTWERT` = vorläufige Zahl · `VORGESCHLAGEN` = braucht Bestätigung · `OFFEN` = nicht entschieden, nicht still festlegen.

## Lesereihenfolge

| # | Dokument | Wofür |
| --- | --- | --- |
| 1 | [PRODUKT.md](PRODUKT.md) | Was Soulwick ist, für wen, Ton, Geschäftsmodell; gilt für beide Repositories |
| 2 | [GLOSSAR.md](GLOSSAR.md) | Begriffe Deutsch ↔ Englisch für Spiel, Website und Plattform |
| 3 | [ROADMAP.md](ROADMAP.md) und [KONZEPT.md](KONZEPT.md) | was jetzt dran ist und wie es werden soll |
| 4 | [PRD.md](PRD.md) | Designziele, Spielregeln mit Grund, Nicht-Ziele |
| 5 | [ARCHITECTURE.md](ARCHITECTURE.md) | Landkarte: Szenen, Zuständigkeiten, Ordner, Datenfluss |
| 6 | [TECHSTACK.md](TECHSTACK.md) | Godot-Version, Konventionen, Git-Workflow, Tests |
| 7 | [DECISIONS.md](DECISIONS.md) | alle Entscheidungen (D-Nummern), bei Widerspruch maßgeblich |
| 8 | [BACKLOG.md](BACKLOG.md) | Ideen für „nicht jetzt“, eine Zeile je Idee, keine Zusagen |

## Was jetzt dran ist

| Dokument | Wofür |
| --- | --- |
| [ROADMAP.md](ROADMAP.md) | **die einzige Roadmap** für die Vollversion (Release 1.0): vier Bereiche A Kern-Umbau, B Online und Release-Technik, C Inhalt und Feinschliff, D KI-Bosse und Party-Modus; Startaufstellung für die Agenten, Release-Tor (D-193) |
| [KONZEPT.md](KONZEPT.md) | **das Konzept** für alles Ungebaute: Extraktion, Gefahrenstufe und Rang, Level mit Talentpunkten, Schmiede, Handelsposten, Zuhause mit Talentbaum und Zaubern, Flint als Begleiter und Erklärer, Kosmetik, Koop, Konto und Cloud, KI-Bosse, Party-Modus (D-194) |
| [design/sprites/SPRITES_V13.md](design/sprites/SPRITES_V13.md) | **das offene Grafik-Briefing** für Claude Design; Agenten tragen fehlende Grafik jederzeit in Teil C ein |

Server, Website und Admin-Panel haben eine eigene Roadmap im Repo `soulwick-platform` (`docs/ROADMAP.md`).

## Regeln und Anleitungen

| Dokument | Wofür |
| --- | --- |
| [RAEUME.md](RAEUME.md) | Regeln für Raumarten und Minispiele (Räume v2, D-120); Abschnittsnummern sind Code-Verweise |
| [SPRACHEN.md](SPRACHEN.md) | Regeln für Texte, Übersetzungen und Optionen (D-111) |
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
| [design/sprites/](design/sprites/README.md) | offenes Briefing [SPRITES_V13.md](design/sprites/SPRITES_V13.md), gelieferte in `delivered/` |
| [design/responses/](design/responses/README.md) | Antworten von Claude Design; Dateinamen nicht ändern, Code und Werkzeuge verweisen darauf |
| [feedback/](feedback/README.md) | Dev-Feedback-Modus (F9): Anleitung; die Auswertungen bleiben lokal |
