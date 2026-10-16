# Doku – Inhaltsverzeichnis

> **Stand:** 15.10.2026 · Die Doku ist Deutsch, Code und Kommentare sind Englisch. Arbeitsweise mit KI-Agenten: [AGENTS.md](../AGENTS.md).
> **Leseregel in allen Dokumenten:** `VERBINDLICH` = beschlossen · `TESTWERT` = vorläufige Zahl, darf sich ändern · `VORGESCHLAGEN` / „Vorschlag“ = braucht noch eine Bestätigung · `OFFEN` = nicht entschieden, nicht still festlegen.

## Zuerst lesen

| # | Dokument | Wofür |
| --- | --- | --- |
| 1 | [PRODUKT.md](PRODUKT.md) | Überblick für **beide** Repositories: Pitch, Säulen, Loop, Online-Teil, Plattformen, Status |
| 2 | [PRD.md](PRD.md) | Anforderungen an das Spiel: was es ist und was es leisten muss |
| 3 | [ARCHITECTURE.md](ARCHITECTURE.md) | Szenen, Zuständigkeiten, Datenfluss, Ordner |
| 4 | [TECHSTACK.md](TECHSTACK.md) | Godot-Version, Konventionen, Git-Workflow, Tests |
| 5 | [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) | **was jetzt dran ist** (Phasen 1 bis 2c) |
| 6 | [DECISIONS.md](DECISIONS.md) | alle Produkt-Entscheidungen (D-Nummern), bei Widerspruch maßgeblich |

Nachschlagen: [GLOSSAR.md](GLOSSAR.md) (Begriffe Deutsch ↔ Englisch), [HANDOUT.md](HANDOUT.md) (Palette, Maßstab, Namensregeln für Grafik und Code), [RELEASE.md](RELEASE.md) (Releases über GitHub Actions: Windows, Linux, macOS, Android; Secrets, development/production).

## Roadmaps

Jede Roadmap ist in Pakete für je **einen Agenten** geschnitten; abgehakt wird nur mit Nachweis (Tests grün, Datum).

| Roadmap | Rolle | Stand |
| --- | --- | --- |
| [ROADMAP.md](ROADMAP.md) | MVP (M0–M6) und Endlos-Ausbau (M7–M15) mit Prüfstand | fast fertig; offen sind Team-Punkte (Branch-Schutz, manuelle Abnahme, Release) |
| [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) | Phase 1 „spielbar machen“, Phase 2 „Räume“, 2b Raum-Rework, 2c Makeover | **aktuell** (Branch `feature/phase2-rooms`) |
| [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) | Phase 3: Koop, Steam, Gilden, Ranglisten (MP0–MP10); Technik in [MULTIPLAYER.md](MULTIPLAYER.md) | im Worktree `../soulwick-mp` (Branch `feature/multiplayer`) in Arbeit |
| [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) | nach dem Multiplayer: Steam, Google Play, App Store (CP0–CP7); Entscheidungen CP0 vor MP2 | geplant |
| [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) | Phase 4: KI-Wunschbosse „Traumweber“ | Idee, nichts beschlossen |

Server, Website und Admin-Panel haben eine eigene Roadmap im Repo `soulwick-platform` (`docs/ROADMAP.md`).

## Konzepte

| Konzept | Status |
| --- | --- |
| [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) | **gültig** für Raumarten und Minispiele (D-120) |
| [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md) | teilweise abgelöst durch V2; weiter gültig für Wagnis-Altar, Prüfungen, Pakt, Lagerfeuer, Wegführung |
| [KONZEPT_ENDLOS.md](KONZEPT_ENDLOS.md) | umgesetzt (M11); Zahlen stehen in DECISIONS |
| [KONZEPT_SPRACHEN_EINSTELLUNGEN.md](KONZEPT_SPRACHEN_EINSTELLUNGEN.md) | umgesetzt (UX3, D-111); Anleitung für neue Texte |
| [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) | Idee für Phase 4 |

## Ordner

| Ordner | Inhalt |
| --- | --- |
| [design/](design/README.md) | Mockups und Referenzbilder (Inspiration, keine exakte Vorlage): `screens/` (UI-Screens mit `ui_spec.json`), `scenes/` (gerenderte Hintergründe), `szenen/` (Fotos aus dem Spiel, neu erzeugbar), `web/` (Website-Handoff), Briefing an Claude Design |
| [design/sprites/](design/sprites/README.md) | Grafik-Briefings `SPRITES*.md` mit Stand je Briefing |
| [design/claude_design_antwort/](design/claude_design_antwort/README.md) | Antworten von Claude Design (Raumarten, Grundrisse, Wand-System, Türen, Dorf, UI, Audio, Makeover); Dateinamen nicht ändern, Code und Werkzeuge verweisen darauf |
| [feedback/](feedback/README.md) | Dev-Feedback-Modus (F9) im Spiel: Anleitung; die Auswertungen bleiben lokal |
