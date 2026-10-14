# Soulwick – Produktüberblick

> **Stand:** 14.10.2026 · **Gilt für beide Repositories:** `soulwick` (Spiel) und `soulwick-platform` (Online-Teil). Diese Datei erklärt das Produkt an **einer** Stelle; Regeln und Zahlen stehen in den verlinkten Dokumenten und werden hier nicht wiederholt. Bei Widerspruch gelten [PRD.md](PRD.md) (Spielregeln), [`soulwick-platform/docs/PRD.md`](../../soulwick-platform/docs/PRD.md) (Online-Teil) und [DECISIONS.md](DECISIONS.md).
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

1. **Endloser Dungeon mit Biomen und Bossen.** Vorgefertigte, nahtlos verbundene Räume im Fünferzyklus; alle 15 Räume ein Boss und danach ein neues Biom: Krypta, Schleimgrotte, Schattenreich, Glutkammer ([KONZEPT_ENDLOS.md](KONZEPT_ENDLOS.md)). Nach Raum 45 die Wahl: aussteigen oder Endlosmodus. Raumarten Arena, strukturiert, Abgrund ([KONZEPT_RAEUME.md](KONZEPT_RAEUME.md), D-086, D-100 bis D-105).
2. **Direkte Maussteuerung.** WASD, 360°-Zielen mit der Maus, Angriff halten, Dash mit Leertaste, Q Waffenwechsel, E Interaktion (PRD §4.3). Touch-Steuerung für Mobil: OFFEN (CP0 Frage 5, Prototyp in CP2).
3. **Run-Entscheidungen.** Drei Waffen (Schwert, Bogen, Magierstab) in zwei Slots, 15 Upgrades mit Stack-Logik, Spezialräume Shop, Waffenwahl, Brunnen, Extra-Upgrade (PRD §4.4 bis §4.6); seit Phase 2 zusätzlich Prüfungsräume und Pakt-Altar (D-112).
4. **Dorf und Meta-Progression.** Gold-Regel: 100 % am Portal, 50 % bei Tod oder Abbruch (PRD §4.6). Begehbare Gebäude Schmiede, Handelsposten (Seelenkristalle), Chronik, Gildenhaus; schrittweise Freischaltung, jedes Gebäude erklärt sich beim ersten Betreten (D-087, PRD §7.5).
5. **Zusammen spielen (geplant, nichts gebaut).** Koop für 2 bis 4 Spieler über einen Host-Spieler, ohne Gameserver; Schnelles Spiel und Gilde; im Multiplayer gemeinsame Kasse und getrennter Fortschritt; Ranglisten; Zielbild Crossplay (PRD §7.1 bis §7.3, D-080 bis D-085, D-108).

## 4. Der Loop in fünf Sätzen

1. Im Dorf startest du am Dungeon-Eingang einen Run: ohne Ausrüstung aus dem letzten Run, aber mit deinen dauerhaften Dorf-Verbesserungen.
2. Jeder Fünferzyklus bringt drei Kampfräume (im dritten eine Upgrade-Wahl), einen Spezialraum und einen Miniboss; auf Raum 15, 30 und 45 wartet stattdessen der Boss des Bioms.
3. Unterwegs kombinierst du Waffen und Upgrades, sammelst Gold und entscheidest freiwillig, ob du kaufst, tauschst oder ein Portal nimmst.
4. Nach jedem Boss folgt ein Lagerfeuer zwischen den Biomen; nach Raum 45 steht die Wahl zwischen Ausstieg mit 100 % des Golds und dem Endlosmodus.
5. Stirbst du oder brichst ab, bleibt die Hälfte des Run-Golds; damit und mit Seelenkristallen baust du im Dorf aus und kehrst stärker zurück.

## 5. Was online dazukommt

Alles davon ist **optional**: Das Spiel bleibt ohne Server spielbar, jeder Aufruf aus dem Spiel darf scheitern (D-083, D-093). Es gibt keinen Echtzeit-Spielverkehr über den Server; Koop läuft Host-zu-Client. Ob für Crossplay ein eigener Lobby-/Relay-Server dazukommt, ist OFFEN (CP0 Frage 3).

| Baustein | Was | Wo |
| --- | --- | --- |
| **Konto / Identität** | Anmeldung aus dem Spiel: Testphase mit Geräte-ID, später Steam-Ticket. Zielbild: ein Soulwick-Konto mit mehreren Plattform-Identitäten (`steam`, `device`, `google_play`, `game_center`), ohne E-Mail und Passwort (D-108, Plattform P-014). Konto löschen in-App. | `apps/api` |
| **Gilden** | gründen, Beitritt per Einladungscode, jederzeit verlassen; höchstens eine Gilde je Spieler, höchstens 30 Mitglieder; Gildenkasse und Gilden-Schmiede auf dem Server (D-080, D-081 als Vorschlag) | `apps/api`, im Spiel das Gildenhaus |
| **Run-Berichte und Ranglisten** | der Host meldet das Run-Ende; Plausibilitätsprüfung **markiert statt löscht**; Tafeln Spieler Solo, Spieler Gruppe, Gilden, jeweils Allzeit und Saison (D-082) | `apps/api`, Website, später im Spiel |
| **Website** | playsoulwick.com, Englisch und Deutsch: Landingpage, Spielseite, Ranglisten, Gildenseiten, Rechtstexte aus eRecht24 | `apps/web` |
| **Admin-Panel** | Spieler sperren, Gilden verwalten, Runs prüfen, Rechtstexte, Protokoll jeder Aktion; Rollen `admin` und `moderator` | `apps/admin` |

Datenschutz: gespeichert werden nur Plattform-Identitäten (Nutzer-ID des Providers), Name, Gilde und Run-Berichte; keine E-Mail-Adressen von Spielern, keine Zahlungsdaten (Plattform-PRD §3.6).

## 6. Plattformen und Sprachen

- **Zielbild** (D-108, VORGESCHLAGEN): Steam, Google Play und App Store, mit Crossplay über alle drei. Reihenfolge OFFEN (Empfehlung: Steam zuerst, Mobil nach dem Touch-Prototyp). Vor Steam: Windows-Build und Schnelles Spiel über direkte IP oder virtuelles LAN (PRD §7.6).
- **Website** zeigt die Stores als „geplant“ mit Crossplay-Hinweis; keine Store-Badges oder Markenlogos, bis es echte Links gibt.
- **Sprachen** (D-111, VERBINDLICH): Englisch Standard, Deutsch zweite Sprache in Spiel und Website; Dokumentation bleibt Deutsch. Das Spiel erkennt die Systemsprache und lässt in den Optionen umschalten (UX3); die Website leitet `/` auf `/en`, deutsche Browser auf `/de` (Plattform P-012).
- **Domain:** playsoulwick.com (D-111).

## 7. Geschäftsmodell (OFFEN)

Nicht entschieden (D-108, CP0 Frage 1). Optionen: (a) mobil kostenlos und PC bezahlt (wie Among Us), (b) überall kostenlos mit Kosmetik später, (c) überall bezahlt. Entscheidet das Projektmitglied mit dem Team (Rechte am Spiel im Team klären, MP10). Ebenfalls OFFEN (PRD §7.6): Zeitpunkt, wer das Steamworks-Konto führt, Lizenzen für den Verkauf, Preis. Bis dahin gilt: keine Preise, keine Termine, keine Käufe; Tabellen für Käufe erst mit CP6.

## 8. Status (14.10.2026)

**Spiel** (`soulwick`, Branch `feature/phase2-rooms`, [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md)):

- Phase 1 „Spielbar für mich“ ist fertig: Hauptmenü, Spielstände, UX-Pass, Dorf.
- Phase 2 „Räume“ läuft in Wellen: fertig A1 (Raumarten-Grundlage), A6 Lagerfeuer, D1 Türen, A8 Prüfungen und Pakt-Altar; in Arbeit A2 Wegfindung, A3 Formen und Zutaten, A5 Arena, UX2; als Nächstes A7 Kampf-Varianten, A4 Abgrund, A9 Licht-Varianten, A10 Wegführung.
- Entscheidungen bis D-112 (zuletzt D-108 Crossplay, D-109 Belohnungen der neuen Räume, D-110 Raum-Genres und Mauern, D-111 Sprachen, D-112 Prüfungen und Pakt).
- Grafik-Briefings SPRITES_V3 bis V6; V6 (einheitliches Mauer-Set) ist noch offen, V5 §8 beschreibt die Website-Grafiken.
- Phase 3 Multiplayer, Crossplay und Phase 4 KI-Bosse: geplant, nichts gebaut.

**Plattform** (`soulwick-platform`, [ROADMAP](../../soulwick-platform/docs/ROADMAP.md)):

- Grundgerüst P1 steht (13.10.2026): API, Website v1, Admin-Panel, Compose, Tests grün.
- Umstellung auf Bun, Turborepo und Prisma: P7 Code fertig (14.10.2026), P8 geplant.
- Website v2 (P9) in Arbeit: Design aus Claude Design liegt vor (`soulwick-platform/docs/design/web/HANDOFF_WEB.md` und Mockups); P10 Rechtstexte, P11 Konten, P12 Grafiken geplant.
- Noch nicht online (P2); Domain in Dokploy noch festzulegen.

## 9. Zwei Repositories und ihre Doku

Warum zwei Repos: kein gemeinsamer Code, verschiedene Werkzeuge und Release-Zyklen, das Spiel-Repo bleibt schlank (D-093). Schnittstelle ist die HTTPS-API; Quelle der Wahrheit sind die Verträge in `soulwick-platform/packages/contracts`, der GDScript-Client im Spiel folgt ihnen.

| `soulwick/` (Spiel) | Wofür |
| --- | --- |
| [AGENTS.md](../AGENTS.md) | Arbeitsweise mit Agenten, gilt für beide Repos |
| [PRD.md](PRD.md) | verbindliche Spielregeln (MVP §4, Vision §7, Begriffe §8) |
| [ARCHITECTURE.md](ARCHITECTURE.md), [TECHSTACK.md](TECHSTACK.md) | Zielarchitektur, Szenen, Datenfluss; Godot, GUT, Branch-Modell, Commit-Format |
| [DECISIONS.md](DECISIONS.md) | Produkt-Entscheidungen, D-Nummern |
| [ROADMAP.md](ROADMAP.md), [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) | MVP und Endlos-Ausbau mit Prüfstand; Phasen 1 und 2 (jetzt) |
| [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md), [MULTIPLAYER.md](MULTIPLAYER.md) | Phase 3: MP0 bis MP10; Technik des Host-Modells |
| [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) | CP0 bis CP6: Konto, Mobil, Lobby/Relay, Stores, Cloud-Save, Käufe |
| [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md), [KONZEPT_KI_BOSS.md](KONZEPT_KI_BOSS.md) | Phase 4: KI-Wunschbosse „Traumweber“ |
| [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md), [KONZEPT_ENDLOS.md](KONZEPT_ENDLOS.md) | Raumkonzept (D-100 bis D-105); Schwierigkeit, Biome, Meta-Progression |
| [HANDOUT.md](HANDOUT.md) | Palette, Maßstab, Namensregeln für Code und Grafik (Spiel und Web) |
| [SPRITES.md](SPRITES.md) bis [SPRITES_V6.md](SPRITES_V6.md) | Grafik-Briefings für Claude Design; Ablage unter `art/` |
| [design/](design/README.md) | Referenz-Screens der Spiel-Oberfläche (`screens/`, `scenes/`, `ui_spec.json`), Inspiration, keine Vorlage |

| `soulwick-platform/` (Online-Teil) | Wofür |
| --- | --- |
| [README.md](../../soulwick-platform/README.md), [AGENTS.md](../../soulwick-platform/AGENTS.md) | Starten, Prüfen, Ordner; Ergänzungen zur Arbeitsweise (Verträge zuerst, Agenten `api-dev`, `web-dev`, `admin-dev`) |
| [docs/PRD.md](../../soulwick-platform/docs/PRD.md) | Anforderungen an API, Website und Admin-Panel |
| [docs/ARCHITECTURE.md](../../soulwick-platform/docs/ARCHITECTURE.md), [docs/TECHSTACK.md](../../soulwick-platform/docs/TECHSTACK.md) | Systemgrenzen, Datenmodell, Abläufe; Bun, Turborepo, Prisma, Befehle |
| [docs/ROADMAP.md](../../soulwick-platform/docs/ROADMAP.md) | Pakete P1 bis P12 |
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
| Fünferzyklus | five-room cycle | drei Kampfräume (der dritte mit Upgrade-Wahl), ein Spezialraum, ein Miniboss; alle 15 Räume stattdessen der Boss |
| Spezialraum | special room | Raum 4 im Zyklus: Shop, Waffenwahl, Brunnen, Extra-Upgrade, seit Phase 2 auch Prüfungsraum und Pakt-Altar; Angebote freiwillig, in 30 % ein Ausstiegsportal |
| Raumart | room kind | Aufbau eines Kampfraums (Arena, strukturiert, Abgrund), unabhängig vom Biom |
| Biom | biome | Optik, Gegner und Boss eines 15-Raum-Abschnitts: Krypta, Schleimgrotte, Schattenreich, Glutkammer |
| Boss, Miniboss | boss, miniboss | Boss auf Raum 15, 30, 45 (einer je Biom); Miniboss auf Raum 5 jedes Zyklus |
| Lagerfeuer | campfire | Rast zwischen den Biomen nach einem Boss |
| Dorf | village | Start- und Rückkehrpunkt mit Schmiede, Handelsposten, Chronik und Gildenhaus |
| Seelenkristall | soul crystal | zweite Währung für den Handelsposten (Proviant für den nächsten Run); in der Lore Reste verloschener Seelen |
| Gold-Regel | gold rule | 100 % des Run-Golds am Portal, 50 % bei Tod oder Abbruch; ab Raum 45 bleibt Gold im Run |
| Host, Client | host, client | im Koop rechnet der Host die Spielwelt, die anderen sind Clients; kein Gameserver |
| Schnelles Spiel | quick play (`quick`) | Koop ohne Bindung, ohne Meta-Boni und Auszahlung |
| Gilde | guild (`guild`, `guilds`) | dauerhafte Gruppe mit Einladungscode, höchstens 30 Mitglieder, eine je Spieler |
| Gildenkasse, Gilden-Schmiede | guild treasury, guild forge | gemeinsamer Gilden-Fortschritt auf dem Server, abgesichert über eine Versionsnummer (Vorschlag D-081) |
| Rangliste | leaderboard (`leaderboards`, `solo`, `group`, `guild`) | Wertung nach höchstem Raum, bei Gleichstand kürzere Zeit; markierte Runs und gesperrte Spieler zählen nicht |
| Saison | season (`season=YYYY-MM`) | Kalendermonat als Ranglisten-Zeitraum, neben Allzeit (`all`) |
| Konto, Identität | account, identity (`player_identities`) | Konto = Spieler auf dem Server; Identität = ein Plattform-Login daran (`steam`, `device`, `google_play`, `game_center`) |
| Crossplay | crossplay | zusammen spielen über Steam, Google Play und App Store hinweg (Zielbild D-108) |

## 11. Wo Entscheidungen stehen

- **Produkt:** D-Nummern in [DECISIONS.md](DECISIONS.md) (Spiel-Repo), aktuell bis D-112. Vor einem neuen Eintrag die höchste Nummer suchen (`grep -n "^### D-" docs/DECISIONS.md | tail`); nichts als OFFEN Markiertes still festlegen (AGENTS.md §6).
- **Technik der Plattform:** P-Nummern in [`soulwick-platform/docs/DECISIONS.md`](../../soulwick-platform/docs/DECISIONS.md): P-001 bis P-015 (Stack, i18n, eRecht24, Identitäten, WebP) und P-101 bis P-109 (Annahmen, VORGESCHLAGEN, vom Team zu bestätigen).
- **Offene Produktfragen gesammelt:** CP0 Fragen 1 bis 8 in [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md), MP0 in [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md), Website in [`KONZEPT_WEB.md`](../../soulwick-platform/docs/design/web/KONZEPT_WEB.md) §12.
- **Bei Widerspruch** zwischen den Repos gilt für Produktfragen das Spiel-Repo; Verträge (`packages/contracts`) gelten für die API.
