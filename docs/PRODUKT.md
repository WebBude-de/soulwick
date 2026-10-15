# Soulwick – Produktüberblick

> **Stand:** 15.10.2026 · **Gilt für beide Repositories:** `soulwick` (Spiel) und `soulwick-platform` (Online-Teil). Diese Datei erklärt das Produkt an **einer** Stelle; Regeln und Zahlen stehen in den verlinkten Dokumenten und werden hier nicht wiederholt. Bei Widerspruch gelten [PRD.md](PRD.md) (Anforderungen ans Spiel), [`soulwick-platform/docs/PRD.md`](../../soulwick-platform/docs/PRD.md) (Online-Teil) und [DECISIONS.md](DECISIONS.md).
> **Leseregel:** `OFFEN` = noch nicht entschieden; nichts in dieser Datei legt eine offene Frage fest.

## 1. Was ist Soulwick

Soulwick ist ein 2D-Top-down-Dungeon-Roguelite mit direkter, mausgesteuerter Action, gebaut in Godot 4.7.2. Vom Dorf aus steigt man in einen endlosen, dunklen Dungeon mit Biomen und Bossen; was man im Run findet, geht verloren, ein Teil des Golds bleibt und baut das Dorf aus. Geplant sind Koop bis vier Spieler, Gilden, Ranglisten und ein Konto, das über Steam, Google Play und App Store hinweg gilt.

- **Name:** Soulwick (Docht + Seele: der Lichtkreis als letztes Licht im Dunkel, Seelenkristalle als Währung), D-094.
- **Tagline** (Untertitel im Hauptmenü): „Das letzte Licht im endlosen Dunkel“ (D-094). Englische Fassung: „The last light in the endless dark“ (aus dem Website-Handoff des Projektmitglieds, `copy.en.json`, 14.10.2026; im Spiel über UX3/D-111 übernehmen).
- **Herkunft:** Idee eines Kollegen des Projektmitglieds; kein Hochschulprojekt (Klarstellung Projektmitglied 14.10.2026). Nach außen erscheint nur „Made with ♥ by WebBude“ im Footer der Website. Marken- und Domainprüfung vor dem Steam-Start (MP10). Website: playsoulwick.com (D-111).

## 2. Für wen

- **Zielgruppe** (Projektmitglied 14.10.2026): Spieler, die kurze, knackige Runs mögen, allein oder mit Freunden, auf PC und Handy; internationales Publikum (Englisch als Standardsprache, D-111). Pixel-Kampf ohne Blut, deshalb voraussichtlich **ab 6** (USK/PEGI über den IARC-Fragebogen zu bestätigen, ROADMAP_CROSSPLAY CP0 Frage 6). Freunde-Koop und Gilden sind der soziale Kern.
- **Spielgefühl** (Designziele, PRD §2): direkte Steuerung, die sich präzise anfühlt; bedeutsame Run-Entscheidungen; nachvollziehbare Regeln; dunkel und warm: lila-schwarzer Grund, alles Wichtige leuchtt in Gold ([HANDOUT.md](HANDOUT.md)). Ton nach außen: ehrlich, nichts Geplantes als fertig ausgeben.

## 3. Die fünf Säulen

1. **Endloser Dungeon mit Biomen und Bossen.** Vorgefertigte, nahtlos verbundene Räume im Fünferzyklus; alle 15 Räume ein Boss, danach Lagerfeuer und ein neues Biom: Krypta, Schleimgrotte, Schattenreich, Glutkammer, dann stärker von vorn (D-073, [KONZEPT_ENDLOS.md](KONZEPT_ENDLOS.md)). Jeder Raum hat eine Aufgabe: Säubern, Arena oder eines von acht Minispielen ([KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md), D-120).
2. **Direkte Maussteuerung.** WASD, 360°-Zielen mit der Maus, Angriff halten, Spezialangriff rechts, Dash mit Leertaste, Q Waffenwechsel, E Interaktion (PRD §4.3). Touch-Steuerung für Mobil: OFFEN (CP0 Frage 5, Prototyp in CP2).
3. **Run-Entscheidungen.** Fünf Waffen (Schwert, Bogen, Magierstab, Dolche, Kriegshammer, D-090) in zwei Slots, 15 Upgrades mit Stack-Logik, Spezialräume Händler, Waffenauswahl, Brunnen, Upgrade-Altar, Prüfungsraum und Pakt-Altar, dazu Wagnis-Altar, Abzweigungen und Geheimnischen (PRD §4).
4. **Dorf und Meta-Progression.** Gold-Regel: 100 % am Portal, 50 % bei Tod oder Abbruch (PRD §4.6). Begehbare Gebäude Schmiede, Handelsposten (Seelenkristalle), Chronik, Zuhause, Gildenhaus; schrittweise Freischaltung, jedes Gebäude erklärt sich beim ersten Betreten (D-087, PRD §4.8).
5. **Zusammen spielen (in Arbeit).** Koop für 2 bis 4 Spieler: ein Spieler ist Host, die Pakete laufen über einen eigenen Relay mit Raumcode (D-119); Schnelles Spiel und Gilde; im Multiplayer gemeinsame Kasse und getrennter Fortschritt; Ranglisten; Crossplay Steam → Android → iOS (PRD §7, D-080 bis D-085, D-108, D-119).

## 4. Der Loop in fünf Sätzen

1. Im Dorf startest du am Dungeon-Eingang einen Run: ohne Ausrüstung aus dem letzten Run, aber mit deinen dauerhaften Dorf-Verbesserungen.
2. Jeder Fünferzyklus bringt drei Kampf- oder Minispielräume (nach dem dritten eine Upgrade-Wahl), einen Spezialraum und einen Miniboss; auf jedem 15. Raum wartet stattdessen der Boss des Bioms.
3. Unterwegs kombinierst du Waffen und Upgrades, sammelst Gold und entscheidest freiwillig, ob du kaufst, tauschst oder ein Portal nimmst.
4. Nach jedem Boss folgt ein Lagerfeuer zwischen den Biomen mit Portal: Ausstieg mit 100 % des Golds oder weiter, der Dungeon endet nie.
5. Stirbst du oder brichst ab, bleibt die Hälfte des Run-Golds; damit und mit Seelenkristallen baust du im Dorf aus und kehrst stärker zurück.

## 5. Was online dazukommt

Alles davon ist **optional**: Das Spiel bleibt ohne Server spielbar, jeder Aufruf aus dem Spiel darf scheitern (D-083, D-093). Koop bleibt im Host-Modell: Ein Spieler rechnet die Spielwelt; die Pakete laufen über den eigenen Relay `soulwick-relay` mit Raumcodes, der nur weiterleitet und keine Spiellogik kennt (entschieden in D-119, CP0 Frage 3; ENet im LAN nur optional, D-124).

| Baustein | Was | Wo |
| --- | --- | --- |
| **Konto / Identität** | Anmeldung aus dem Spiel: Testphase mit Geräte-ID, später Steam, Google Play, Game Center. Ein Soulwick-Konto mit beliebig vielen Plattform-Identitäten (`steam`, `device`, `google_play`, `game_center`), ohne E-Mail und Passwort; Geräte verknüpfen per Code, Zusammenführen zweier Konten nach festen Regeln (D-121, D-122, Plattform P-014). Konto löschen in-App und per Web-Formular. | `apps/api` |
| **Relay** | Räume mit Raumcode, leitet die Pakete zwischen Host und Clients weiter (D-119) | `apps/relay` (geplant) |
| **Gilden** | gründen, Beitritt per Einladungscode, jederzeit verlassen; höchstens eine Gilde je Spieler, höchstens 30 Mitglieder; Gildenkasse und Gilden-Schmiede auf dem Server (D-080, D-081 als Vorschlag) | `apps/api`, im Spiel das Gildenhaus |
| **Run-Berichte und Ranglisten** | der Host meldet das Run-Ende; Plausibilitätsprüfung **markiert statt löscht**; Tafeln Spieler Solo, Spieler Gruppe, Gilden, jeweils Allzeit und Saison (D-082) | `apps/api`, Website, später im Spiel |
| **Koop-Relay** | Räume mit Raumcode, leitet Pakete weiter, ohne sie zu lesen (D-119) | `apps/relay` |
| **Website** | playsoulwick.com, Englisch und Deutsch: Landingpage, Spielseite, Ranglisten, Gildenseiten, Rechtstexte aus eRecht24 | `apps/web` |
| **Admin-Panel** | Spieler sperren, Gilden verwalten, Runs prüfen, Rechtstexte, Protokoll jeder Aktion; Rollen `admin` und `moderator` | `apps/admin` |

Datenschutz: gespeichert werden nur Plattform-Identitäten (Nutzer-ID des Providers), Name, Gilde und Run-Berichte; keine E-Mail-Adressen von Spielern, keine Zahlungsdaten (Plattform-PRD §3.6).

## 6. Plattformen und Sprachen

- **Zielbild** (D-108; Architektur D-119): Steam, Google Play und App Store, mit Crossplay über alle drei. Reihenfolge entschieden: **Steam → Android → iOS**, iOS später (kein Mac); Publisher WebBude (D-119). Vor Steam: Windows-Test-Build und Schnelles Spiel per Raumcode über den eigenen Relay (MP4, D-124).
- **Website** zeigt die Stores als „geplant“ mit Crossplay-Hinweis; keine Store-Badges oder Markenlogos, bis es echte Links gibt.
- **Sprachen** (D-111, VERBINDLICH): Englisch Standard, Deutsch zweite Sprache in Spiel und Website; Dokumentation bleibt Deutsch. Das Spiel erkennt die Systemsprache und lässt in den Optionen umschalten (UX3); die Website leitet `/` auf `/en`, deutsche Browser auf `/de` (Plattform P-012).
- **Domain:** playsoulwick.com (D-111).

## 7. Geschäftsmodell (OFFEN)

Nicht entschieden (D-108, CP0 Frage 1). Optionen: (a) mobil kostenlos und PC bezahlt (wie Among Us), (b) überall kostenlos mit Kosmetik später, (c) überall bezahlt. Entscheidet das Projektmitglied mit dem Team (Rechte am Spiel im Team klären, MP10). Ebenfalls OFFEN (PRD §7.6): Zeitpunkt, Lizenzen für den Verkauf, Preis; die Store-Konten führt WebBude als Publisher (D-119). Bis dahin gilt: keine Preise, keine Termine, keine Käufe; Tabellen für Käufe erst mit CP6.

## 8. Status (15.10.2026)

**Spiel** (`soulwick`, Branch `feature/phase2-rooms`, [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md)):

- Phase 1 „Spielbar für mich“ ist fertig: Hauptmenü, Spielstände, UX-Pass, Dorf.
- Phase 2 „Räume“ und die Umbauten 2b (Räume v2 mit Minispielen, D-120, D-130 bis D-139) und 2c (Fels-Makeover, Kamera, Seitenansicht, D-140 bis D-144) laufen; Stand und offene Pakete in [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md).
- Entscheidungen bis D-146 (D-121 bis D-129 Multiplayer, D-145 Dev-Feedback, D-146 GitHub).
- Grafik: offen sind vor allem [SPRITES_V8](design/sprites/SPRITES_V8.md) und Teile von [SPRITES_V9](design/sprites/SPRITES_V9.md); Übersicht in [design/sprites/](design/sprites/README.md).
- Phase 3 Multiplayer (MP1–MP4: Eingaben, Lobby, gemeinsamer Run über den eigenen Relay, Gast-Anmeldung, Test-Build) ist seit 15.10.2026 im selben Branch wie die Räume (kein eigener Worktree mehr); Test-Build mit `tools/export_build.ps1`. Crossplay und Phase 4 KI-Bosse: geplant.

**Plattform** (`soulwick-platform`, [ROADMAP](../../soulwick-platform/docs/ROADMAP.md)):

- Stack: Bun-Workspaces mit Turborepo, Prisma (PostgreSQL), Biome; Apps API, Relay, Website, Admin-Panel. Stand und Pakete: [Plattform-ROADMAP](../../soulwick-platform/docs/ROADMAP.md).

## 9. Zwei Repositories und ihre Doku

Warum zwei Repos: kein gemeinsamer Code, verschiedene Werkzeuge und Release-Zyklen, das Spiel-Repo bleibt schlank (D-093). Schnittstelle ist die HTTPS-API; Quelle der Wahrheit sind die Verträge in `soulwick-platform/packages/contracts`, der GDScript-Client im Spiel folgt ihnen.

| `soulwick/` (Spiel) | Wofür |
| --- | --- |
| [AGENTS.md](../AGENTS.md) | Arbeitsweise mit Agenten, gilt für beide Repos |
| [README.md](README.md) | Inhaltsverzeichnis der Spiel-Doku mit Lesereihenfolge |
| [PRD.md](PRD.md) | Anforderungen ans Spiel (Kern §4, Vision §7) |
| [ARCHITECTURE.md](ARCHITECTURE.md), [TECHSTACK.md](TECHSTACK.md) | Zielarchitektur, Szenen, Datenfluss; Godot, GUT, Branch-Modell, Commit-Format |
| [DECISIONS.md](DECISIONS.md) | Produkt-Entscheidungen, D-Nummern |
| [ROADMAP.md](ROADMAP.md), [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) | MVP und Endlos-Ausbau mit Prüfstand; Phasen 1, 2, 2b, 2c (jetzt) |
| [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md), [MULTIPLAYER.md](MULTIPLAYER.md) | Phase 3: MP0 bis MP10; Technik des Host-Modells |
| [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) | CP0 bis CP6: Konto, Mobil, Lobby/Relay, Stores, Cloud-Save, Käufe |
| [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md), [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) | Phase 4: KI-Wunschbosse „Traumweber“ |
| [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md), [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md), [KONZEPT_ENDLOS.md](KONZEPT_ENDLOS.md) | Räume v2 mit Minispielen (D-120, gültig); Raumkonzept v1 (teilweise abgelöst); Schwierigkeit, Biome (umgesetzt) |
| [GLOSSAR.md](GLOSSAR.md), [KONZEPT_SPRACHEN_EINSTELLUNGEN.md](KONZEPT_SPRACHEN_EINSTELLUNGEN.md), [AUDIO.md](AUDIO.md) | Begriffe Deutsch ↔ Englisch; Sprachen und Optionen; Musik und Übergänge |
| [HANDOUT.md](HANDOUT.md) | Palette, Maßstab, Namensregeln für Code und Grafik (Spiel und Web) |
| [design/sprites/](design/sprites/README.md) | Grafik-Briefings `SPRITES*.md` für Claude Design mit Stand; Ablage unter `art/` |
| [design/](design/README.md) | Mockups und Referenzen (`screens/`, `scenes/`, `szenen/`, `ui_spec.json`), Antworten von Claude Design; Inspiration, keine Vorlage |

| `soulwick-platform/` (Online-Teil) | Wofür |
| --- | --- |
| [README.md](../../soulwick-platform/README.md), [AGENTS.md](../../soulwick-platform/AGENTS.md) | Starten, Prüfen, Ordner; Ergänzungen zur Arbeitsweise (Verträge zuerst, Agenten `api-dev`, `web-dev`, `admin-dev`) |
| [docs/PRD.md](../../soulwick-platform/docs/PRD.md) | Anforderungen an API, Website und Admin-Panel |
| [docs/ARCHITECTURE.md](../../soulwick-platform/docs/ARCHITECTURE.md), [docs/TECHSTACK.md](../../soulwick-platform/docs/TECHSTACK.md) | Systemgrenzen, Datenmodell, Abläufe; Bun, Turborepo, Prisma, Befehle |
| [docs/ROADMAP.md](../../soulwick-platform/docs/ROADMAP.md) | Pakete P1 bis P17 |
| [docs/DECISIONS.md](../../soulwick-platform/docs/DECISIONS.md) | technische Entscheidungen, P-Nummern |
| [docs/design/README.md](../../soulwick-platform/docs/design/README.md) | Design-Index: Ordnerregeln, Dateien, wer was schreibt |
| [docs/design/TOKENS.md](../../soulwick-platform/docs/design/TOKENS.md) | Design-Tokens für Website und Admin-Panel |
| [docs/design/web/HANDOFF_WEB.md](../../soulwick-platform/docs/design/web/HANDOFF_WEB.md), Mockups | Übergabe aus Claude Design, verbindlich für die Landingpage |
| [docs/design/web/KONZEPT_WEB.md](../../soulwick-platform/docs/design/web/KONZEPT_WEB.md) | Website-Konzept: Seiten jenseits der Landingpage, Mockup-Liste, offene Fragen |
| [docs/design/admin/README.md](../../soulwick-platform/docs/design/admin/README.md) | Admin-Design (Platzhalter) |
| [infra/DOKPLOY.md](../../soulwick-platform/infra/DOKPLOY.md), [apps/web/public/brand/README.md](../../soulwick-platform/apps/web/public/brand/README.md) | Betrieb auf dem VPS; Ablage der Website-Grafiken |

## 10. Begriffe

Deutsch ist die Doku-Sprache, Englisch die Standardsprache von Spiel und Website (D-111). Englische Begriffe sind **verbindlich**, wo sie aus Verträgen oder Routen stammen (in Backticks); sonst Vorschlag für UI-Texte.

| Deutsch | Englisch | Erklärung |
| --- | --- | --- |
| Run | run (`runs`) | ein zusammenhängender Dungeon-Durchlauf mit temporären Waffen, Upgrades und Gold |
| Raum | room | kleinste Einheit des Dungeons, vorgefertigte Vorlage, nahtlos mit der nächsten verbunden; gezählt ab 1 |
| Fünferzyklus | cycle of five | drei Kampf- oder Minispielräume (nach dem dritten eine Upgrade-Wahl), ein Spezialraum, ein Miniboss; alle 15 Räume stattdessen der Boss |
| Spezialraum | special room | Raum 4 im Zyklus: Händler, Waffenauswahl, Brunnen, Upgrade-Altar (manchmal Pakt-Altar), Prüfungsraum; Angebote freiwillig, in 30 % ein Ausgangsportal |
| Raumart | room kind | Aufgabe eines Kampfraums (Säubern, Arena, Minispiele, D-120), unabhängig vom Biom |
| Biom | biome | Optik, Gegner und Boss eines 15-Raum-Abschnitts: Krypta, Schleimgrotte, Schattenreich, Glutkammer |
| Boss, Miniboss | boss, miniboss | Boss auf Raum 15, 30, 45 (einer je Biom); Miniboss auf Raum 5 jedes Zyklus |
| Lagerfeuer | campfire | Rast zwischen den Biomen nach einem Boss |
| Dorf | village | Start- und Rückkehrpunkt mit Schmiede, Handelsposten, Chronik und Gildenhaus |
| Seelenkristall | soul crystal | zweite Währung für den Handelsposten (Proviant für den nächsten Run); in der Lore Reste verloschener Seelen |
| Gold-Regel | gold rule | 100 % des Run-Golds am Portal, 50 % (aufgerundet) bei Tod oder Abbruch |
| Host, Client | host, client | im Koop rechnet der Host die Spielwelt, die anderen sind Clients; der Relay leitet nur weiter |
| Schnelles Spiel | quick play (`quick`) | Koop ohne Bindung, ohne Meta-Boni und Auszahlung |
| Gilde | guild (`guild`, `guilds`) | dauerhafte Gruppe mit Einladungscode, höchstens 30 Mitglieder, eine je Spieler |
| Gildenkasse, Gilden-Schmiede | guild treasury, guild forge | gemeinsamer Gilden-Fortschritt auf dem Server, abgesichert über eine Versionsnummer (Vorschlag D-081) |
| Rangliste | leaderboard (`leaderboards`, `solo`, `group`, `guild`) | Wertung nach höchstem Raum, bei Gleichstand kürzere Zeit; markierte Runs und gesperrte Spieler zählen nicht |
| Saison | season (`season=YYYY-MM`) | Kalendermonat als Ranglisten-Zeitraum, neben Allzeit (`all`) |
| Konto, Identität | account, identity (`player_identities`) | Konto = Spieler auf dem Server; Identität = ein Plattform-Login daran (`steam`, `device`, `google_play`, `game_center`); verknüpft per Code (D-121, D-122) |
| Relay, Raumcode | relay, room code | eigener Server, der Koop-Pakete nur weiterleitet; der Host teilt einen Raumcode, die anderen treten damit bei (D-119) |
| Crossplay | crossplay | zusammen spielen über Steam, Google Play und App Store hinweg (Zielbild D-108) |

## 11. Wo Entscheidungen stehen

- **Produkt:** D-Nummern in [DECISIONS.md](DECISIONS.md) (Spiel-Repo), aktuell bis D-146. Vor einem neuen Eintrag die höchste Nummer suchen (`grep -n "^### D-" docs/DECISIONS.md | tail`); nichts als OFFEN Markiertes still festlegen (AGENTS.md §6).
- **Technik der Plattform:** P-Nummern in [`soulwick-platform/docs/DECISIONS.md`](../../soulwick-platform/docs/DECISIONS.md): P-001 bis P-029 (Stack, i18n, eRecht24, Identitäten, WebP) und P-101 bis P-109 (Annahmen, VORGESCHLAGEN, vom Team zu bestätigen).
- **Offene Produktfragen gesammelt:** CP0 Fragen 1 bis 8 in [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md), MP0 in [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md), Website in [`KONZEPT_WEB.md`](../../soulwick-platform/docs/design/web/KONZEPT_WEB.md) §12.
- **Bei Widerspruch** zwischen den Repos gilt für Produktfragen das Spiel-Repo; Verträge (`packages/contracts`) gelten für die API.
