# ROADMAP Crossplay – Steam, Google Play und App Store

> **Stand:** 14.10.2026 · **Status:** Zielbild D-108; **Architektur entschieden** (D-119, VERBINDLICH, Projektmitglied 14.10.2026): Host-Modell plus **eigener Relay**, Reihenfolge **Steam → Android → iOS** (iOS später), Publisher **WebBude**; entschieden sind außerdem das Konto-Modell (D-121) und das Zusammenführen von Konten (D-122). Im Spiel gebaut: Mehrspieler-Vorbereitung (MP1), API-Client (MP1b) und Relay-Peer mit Raumcodes (MP2, `online/`). OFFEN bleiben Geschäftsmodell, Touch-Schema und Relay-Regionen. Kommt als eigene Phase **nach** [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) (Phase 3, D-106); die restlichen Entscheidungen **CP0** fallen **vor MP2**, soweit sie Lobby (MP2), Steam (MP6) und Anmeldung (MP7) verändern können. Der Relay (CP3) wird schon für MP2–MP4 gebraucht. Plattform-Repo: Datenbank fertig (P11, P-014), geplant P13–P17 (`soulwick-platform/docs/ROADMAP.md`), Konzept für Entwickler: `soulwick-platform/docs/KONZEPT_ONLINE.md`.
> **Entscheidungen:** D-080 (Gruppenmodi), D-081 (getrennter Fortschritt), D-082 (Ranglisten), D-083 (Server, Host-Modell), D-084/D-085 (Koop-Regeln), D-093 (zwei Repos), **D-108** (Zielbild Crossplay), **D-119** (Crossplay-Architektur), **D-121** (Konto-Modell), **D-122** (Konten zusammenführen) in [DECISIONS.md](DECISIONS.md). Plattform: `soulwick-platform/docs/PRD.md` §3.8, `ARCHITECTURE.md` §1, §3, §5 und §7, `DECISIONS.md` P-014, P-016 bis P-018.
> **Anforderungen:** [PRD.md](PRD.md) Abschnitt 7.1 und 7.6 · **Technik:** [MULTIPLAYER.md](MULTIPLAYER.md) · **Abhaken** nur mit Nachweis (Tests, Datum). Jedes Paket ist für **einen Agenten** geschnitten; Spiel- und Plattform-Teile werden getrennt vergeben.

## Überblick

```text
Steam (PC)              Google Play (Android)        App Store (iOS, später)
   │ Steam-Ticket           │ Play Games Services         │ Game Center
   ▼                        ▼                             ▼
┌───────────────────────────────────────────────────────────────────┐
│ Soulwick-Konto (players) ──── player_identities (1..n je Spieler) │  soulwick-api (HTTPS)
├───────────────────────────────────────────────────────────────────┤
│ Relay: Räume mit Raumcode, Pakete weiterleiten (CP3, D-119)       │  soulwick-relay (WSS, Bun)
└───────────────────────────────────────────────────────────────────┘
   Das Spiel bleibt im Host-Modell: ein Spieler rechnet, der Relay leitet nur Pakete weiter.
```

| Paket | Ergebnis | Spiel? | Plattform? | Stores? |
| --- | --- | --- | --- | --- |
| **CP0** | **Entscheidungen** (vor MP2): Geschäftsmodell, Konto-Modell, Lobby/Relay, Reihenfolge, Touch, Altersfreigabe; Fragen 3, 4 und Publisher entschieden (D-119) | – | – | – |
| CP1 | Soulwick-Konto und Identitäten (Steam, Google Play Games, Game Center, Geräte-ID), Verknüpfungscode, Konto löschen in-App | Konto-UI | ja | – |
| CP2 | Mobile-Build und Touch (Android/iOS-Export, virtueller Stick, Auto-Aim, UI-Skalierung, Leistung) | ja | – | Test-Builds |
| CP3 | Relay `soulwick-relay` (Bun, WebSocket) mit Raumcodes; im Spiel `online/relay_peer.gd` | ja | ja (P13, P16, P17) | – |
| CP4 | Stores (Steamworks, Google Play Console, App Store Connect; IARC/USK; Datenschutz-Labels; Screenshots/Trailer) | Export | Website-Badges | ja |
| CP5 | Cross-Progression (Cloud-Save über die API, Konfliktregeln) | ja | ja | – |
| CP6 | Geschäftsmodell und Käufe (OFFEN; Tabellen `purchases`/`entitlements` erst dann) | ja | ja | ja |
| CP7 | Build-CI und Stores: GitLab-CI-Exporte, Upload zu Steam und Google Play, Signaturschlüssel, Store-Konten und -Pflichten | CI | Löschantrag-Seite (P15) | ja |

**Reihenfolge:** CP0 vor MP2. **CP3 ist mit D-119 gesetzt:** Der Plattform-Teil (P13 Relay, P17 Relay auf Dokploy) darf jederzeit parallel laufen; der Spiel-Teil (`relay_peer.gd`) kommt nach MP1 und vor MP2, weil Schnelles Spiel und der Test-Build für Freunde (MP4) über den Relay laufen. CP1 braucht den Server (MP7) und kommt vor jedem Store-Release. CP2 darf als **Prototyp nach MP1** vorgezogen werden, weil die Frage „Touch ja/nein“ nur mit echtem Spielgefühl zu beantworten ist (Vorschlag). CP4 nach MP10 (Steam) und CP2 (Mobil). CP5 nach CP1. CP6 nach CP0 und frühestens mit CP4. CP7 beginnt mit dem Windows-Export für MP4 und wächst mit CP2 (Android) und CP4 (Stores). **Stores in der Reihenfolge Steam → Google Play → App Store** (D-119); iOS erst, wenn ein Cloud-Mac eingerichtet ist.

**Warum eigenes Konto und eigener Relay (Relay entschieden in D-119, Konto-Modell weiter CP0 Frage 2):** Steam-Lobbys und Steam-Relay (MP6) funktionieren nur zwischen Steam-Konten. Ein Android- oder iOS-Spieler hat kein Steam, Google Play Games und Game Center kennen sich gegenseitig nicht. Crossplay braucht deshalb eine **plattformneutrale** Stelle, die alle kennen: ein Soulwick-Konto, an dem die Plattform-Identitäten hängen, und eine Lobby mit Raumcode, die über den eigenen Server läuft. Among Us macht es genauso (Raumcode + verknüpftes Konto). ENet bleibt nur optional für LAN und Entwicklung; Steam (MP6) ist Zusatz für Anmeldung und Einladungen, die Verbindung läuft auch für Steam-Spieler über den Relay. Die Verbindungsart ist hinter `MultiplayerPeer` austauschbar ([MULTIPLAYER.md](MULTIPLAYER.md) §2), später auch gegen WebRTC oder einen dedizierten Server.

## CP0 – Entscheidungen (vor MP2)

Fragen 2, 3 und 4 sowie der Publisher sind seit dem 14.10.2026 entschieden (Projektmitglied; 3, 4 und Publisher in D-119, 2 in D-121, Zusammenführen D-122); alles andere ist OFFEN. Die Spalte „Empfehlung“ ist ein Vorschlag von Claude und ersetzt keine Entscheidung.

| # | Frage | Optionen | Empfehlung (Vorschlag) | Wer entscheidet | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | **Geschäftsmodell** | (a) mobil kostenlos, PC bezahlt (wie Among Us) · (b) überall kostenlos, Kosmetik später · (c) überall bezahlt | Keine ohne Zahlen. (a) ist am einfachsten (keine Käufe im Spiel), wirft aber die Fairness-Frage Käufer/Gratis-Spieler auf; (b) braucht Kosmetik-Content und Kaufabwicklung (CP6) | Projektmitglied mit dem Team (Rechte am Spiel, MP10) | **OFFEN** |
| 2 | **Konto-Modell** | (a) eigenes Soulwick-Konto, Plattform-Identitäten verknüpft · (b) nur Plattform-Konten, keine Verknüpfung (kein Cross-Progression) · (c) E-Mail/Passwort-Konto | (a): ohne E-Mail, ohne Passwort; Identitäten reichen, Verknüpfung per Code | Projektmitglied | **ENTSCHIEDEN** 14.10.2026 (Projektmitglied, an Claude delegiert, D-121): (a); Verknüpfungscode 6 Zeichen, 10 Minuten gültig; Konto löschen in der App und per Web-Formular. Zusammenführen zweier Konten: D-122 |
| 3 | **Lobby/Relay** | (a) eigener Lobby-/Relay-Server `soulwick-relay` mit Raumcodes · (b) Steam-Relay für PC plus eigener Relay nur für Mobil · (c) nur Steam (kein Crossplay) | (a): ein Weg für alle, Steam bleibt Zusatz für Einladungen; ändert D-083 | Projektmitglied (Betrieb, Kosten) mit dem Team | **ENTSCHIEDEN** 14.10.2026 (Projektmitglied, D-119): (a) Host-Modell + eigener Relay; Transport in Phase 1 WebSocket-Relay (`online/relay_peer.gd`), WebRTC und dedizierter Server später |
| 4 | **Plattform-Reihenfolge** | (a) Steam zuerst, Mobil später · (b) alle gleichzeitig | (a): MP10 ist ohnehin zuerst; Mobil erst nach dem CP2-Prototyp | Projektmitglied | **ENTSCHIEDEN** 14.10.2026 (Projektmitglied, D-119): Steam → Android → iOS; iOS später (kein Mac) |
| 5 | **Touch-Steuerung** für ein maus-gezieltes Spiel | (a) virtueller Stick + Auto-Aim/Zielhilfe + Angriffsknopf · (b) zwei Sticks (Bewegen, Zielen) · (c) kein Mobil, nur Controller/PC | Prototyp in CP2 entscheidet; (a) als Startpunkt, Zielhilfe nur auf Mobil als TESTWERT | Projektmitglied nach dem Prototyp | **OFFEN** |
| 6 | **Altersfreigabe** | IARC-Fragebogen (Google Play, App Store → USK/PEGI), Steam-Fragebogen | Pixel-Kampf ohne Blut: voraussichtlich ab 6 (USK 6 / PEGI 7, Schätzung, mit dem Fragebogen prüfen) | Team | **OFFEN** |
| 7 | **Ranglisten** (D-082) je Plattform oder gemeinsam | (a) gemeinsam mit Plattform-Kennzeichen am Eintrag · (b) je Plattform getrennt | (a), passt zum Crossplay-Gedanken; Zielhilfe auf Mobil muss dann sichtbar sein | Team | **OFFEN** |
| 8 | **Sign in with Apple** | nur Pflicht, wenn die iOS-App einen anderen Social-Login (z. B. Google) anbietet (App-Store-Regel 4.8) | Nur Game Center und Play Games als Plattform-Login, keinen Social-Login → kein Sign in with Apple nötig; mit dem Fragebogen in CP4 prüfen | Team (CP4) | **OFFEN** |
| 9 | **Publisher** (wer veröffentlicht und führt die Store-Konten) | (a) WebBude · (b) Privatperson · (c) eigene Firma für Soulwick | – | Projektmitglied | **ENTSCHIEDEN** 14.10.2026 (Projektmitglied, D-119): WebBude, Firmenkonten bei Steam, Google, später Apple |
| 10 | **Relay-Regionen** | (a) eine Instanz (EU) · (b) je Region eine Instanz, Raumcode mit Regions-Präfix | (a) zuerst, (b) erst bei messbarer Latenz außerhalb Europas | Projektmitglied (Kosten) | **OFFEN** |

- [ ] Fragen 1–10 beantworten; jede Antwort als D-Eintrag (VERBINDLICH oder bewusst „später“) in [DECISIONS.md](DECISIONS.md). Stand 14.10.2026: 3, 4 und 9 in D-119, 2 in D-121 (Zusammenführen D-122); 1, 5–8 und 10 offen.
- [ ] D-108 auf VERBINDLICH setzen oder anpassen (teilweise entschieden durch D-119, D-121); D-083 („kein Echtzeit-Spielverkehr über den Server“) wird laut D-119 zu „Weiterleitung ja, Spiellogik nein“, Verweis in D-083 selbst nachtragen.
- [ ] [PRD.md](PRD.md) §7.6 (Steam) um die anderen Stores ergänzen, neuer Abschnitt §7.8 „Crossplay“; [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP2–MP6 auf den Relay umstellen (Doku umgestellt 14.10.2026: Raumcode statt IP, MP4 über den Relay, Steam als Zusatz).
- [ ] Plattform: `soulwick-platform/docs/PRD.md` §3.8 von OFFEN auf die getroffenen Antworten bringen (für Fragen 3, 4 und 9 am 14.10.2026 geschehen; die übrigen folgen mit ihren Antworten).

**Dateien:** `docs/DECISIONS.md`, `docs/PRD.md`, `docs/ROADMAP_MULTIPLAYER.md`, `docs/MULTIPLAYER.md`, `docs/ROADMAP_CROSSPLAY.md`; Plattform `docs/PRD.md`.

**Fertig, wenn:** alle zehn Fragen einen D-Eintrag haben. Für MP2 ist geklärt: Lobbys laufen über Raumcodes auf dem eigenen Relay (D-119).

## CP1 – Soulwick-Konto und Identitäten

> **Bezeichnungen festgelegt (15.10.2026, Website `/delete-account`, P-026):** Bereich im Spiel „Konto“ / „Account“, Knöpfe „Konto löschen“ / „Delete account“ und „Löschcode für die Website“ (EN wie in `soulwick-platform/apps/web/messages/en/deletion.json`). Der Löschcode ist ein Einmal-Code: `POST /me/deletion-code`, 15 Minuten gültig (TESTWERT). Die Website verweist auf genau diese Namen.

**Ziel:** Ein Spieler hat ein Soulwick-Konto mit beliebig vielen Identitäten (`steam`, `device`, `google_play`, `game_center`) und kann Geräte verknüpfen, ohne E-Mail oder Passwort. Grundlage ist `player_identities` aus P11 (Plattform); hier kommen die Routen und die Spiel-Oberfläche dazu.

**Plattform (`api-dev`, Pakete P14 und P15):** `packages/contracts/src/identity.ts` (neu: `POST /auth/google-play`, später `POST /auth/game-center`, `POST /me/link-code`, `POST /me/link`, `GET /me/identities`, `DELETE /me/identities/:provider`), `apps/api/src/services/identities.ts`, `apps/api/src/routes/auth.ts`, `routes/me.ts`, `routes/admin/players.ts` (Identitäten anzeigen), Tests. **Spiel (`village-dev` oder `player-dev`, nach MP7):** `online/api_client.gd` (HTTP-Client aus MP1b, D-124), `online/session.gd` (Konto und Token am lokalen Client, kein neuer Autoload, D-044), `ui/options/account_panel.gd` (neu).

- [ ] Anmeldung je Provider: Steam-Ticket (MP7/MP10), Google Play Games Services v2 (Server-Auth-Code → serverseitig prüfen), Game Center (signierte Prüfung mit `publicKeyUrl`, `signature`, `salt`, `timestamp`), Geräte-ID nur in der Testphase. Jede Anmeldung findet oder erzeugt eine Identität; eine neue Identität ohne Konto erzeugt ein Konto.
- [ ] **Verknüpfungscode wie Among Us:** Gerät A fordert `POST /me/link-code` an (6 Zeichen, 10 Minuten gültig, TESTWERT, D-121), Gerät B löst ihn angemeldet mit seiner Identität über `POST /me/link` ein; die Identität von B hängt danach am Konto von A. Hat B schon ein leeres Konto, wird es ohne Rückfrage ersetzt. Hängt die Identität von B an einem Konto mit Fortschritt, zeigt das Spiel, welches Konto bleibt, und führt erst nach Bestätigung zusammen, nie still. **Regel für das Zusammenführen: D-122** (das ältere Konto bleibt und erhält alle Identitäten; Name und Gilde des bleibenden Kontos, ist es gildenlos, die Gilde des anderen; Run-Teilnahmen werden umgehängt; das andere Konto wird gelöscht; ist eines gesperrt, kein Zusammenführen, manuelle Prüfung).
- [ ] Identität entkoppeln (`DELETE /me/identities/:provider`), die letzte Identität darf nicht entkoppelt werden.
- [ ] **Konto löschen in-App** (Store-Pflicht, App Store 5.1.1 (v), Google Play „Datenlöschung“): Knopf im Konto-Panel → Bestätigung → `DELETE /me`; löscht Konto, Identitäten, Mitgliedschaft; Run-Teilnahmen werden anonymisiert (bestehende Regel). Gesperrte Spieler weiter nach P-108. Zusätzlich eine **Web-Seite für den Löschantrag** (Google-Play-Pflicht, D-121, Plattform P15).
- [ ] Spiel: Konto-Panel zeigt verknüpfte Plattformen, Verknüpfungscode (anzeigen/eingeben) und „Konto löschen“; Offline-Betrieb bleibt unverändert möglich.
- [ ] Datenschutz: nur Provider-Nutzer-IDs speichern; Datenschutzerklärung im eRecht24-Projekt um Google Play Games und Game Center ergänzen (P-013, Push).

**Fertig, wenn:** sich eine Person auf dem PC (Steam) und einem Handy (Play Games oder Game Center) anmeldet, beide per Code verknüpft und auf beiden dieselbe Gilde sieht; „Konto löschen“ im Spiel entfernt alles; API-Tests für Verknüpfen, Konflikt, Entkoppeln und Löschen grün.

**Koop-Check:** Konto, Token und Identitäten liegen am lokalen Client (`online/session.gd`), nicht in einem Autoload; keine Spiellogik betroffen.

## CP2 – Mobile-Build und Touch

**Ziel:** Soulwick läuft auf Android und iOS mit Touch-Steuerung, lesbarer UI und stabiler Bildrate. Darf als Prototyp nach MP1 vorgezogen werden (siehe Überblick).

**Agent:** `player-dev` (Eingabe, HUD) mit Haken für den Integrator in `project.godot`. **Dateien:** `export_presets.cfg` (neu: Android, iOS), `player/player_input.gd` (Eingabe-Objekt aus MP1: neue Implementierung `TouchInput`), `ui/touch/` (neu: virtueller Stick, Knöpfe für Angriff, Dash, Waffe wechseln, Interaktion, Menü), `ui/hud/*` (Skalierung, sichere Bereiche), `tools/perf_check.gd` (neu, misst Bildrate und Zeichenaufrufe über N Räume); Haken: `project.godot` (Eingabe-Aktionen für Touch, `display/window/handheld`, Stretch-Modus), `player/player.gd` (Zielhilfe als Parameter).

- [ ] Android-Export (SDK, Debug-Keystore, später Upload-Key) als `.apk`/`.aab`; Renderer **Mobile** statt Forward+ für Android prüfen. iOS-Export (`.ipa`, Xcode nötig) erst **später** über einen Cloud-Mac (D-119, CP7).
- [ ] Touch-Schema nach CP0 Frage 5: linker virtueller Stick bewegt; Angriff per Knopf oder Halten mit **Zielhilfe** (nächster Gegner im Lichtkreis, TESTWERT Winkel/Reichweite, nur auf Mobil aktiv); Dash-, Waffenwechsel-, Interaktions- und Menü-Knopf; Tab-Übersicht als Knopf. Optional zweiter Stick zum Zielen.
- [ ] UI auf 480×270 bleibt; auf Handys (16:9 bis 20:9) ganzzahlig skaliert, Ränder mit Hintergrund gefüllt, HUD und Knöpfe außerhalb der Aussparungen (Safe Area), Berührungsflächen mindestens 48 px auf dem Gerät.
- [ ] Leistung: Sicht-Shader, Nachbearbeitung und Partikel auf einem Mittelklasse-Android messen (`perf_check.gd`); Zielwert 60 fps, mindestens 50 fps (TESTWERT); Stufe „Mobil“ in den Optionen (weniger Partikel, einfachere Schatten); Bildrate auf 60 begrenzen (Akku).
- [ ] Automatischer Test: `smoke_test.gd` steuert den Bot über das Eingabe-Objekt (nicht über `Input`), damit Touch und Maus denselben Weg nehmen.

**Fertig, wenn:** ein Run über 10 Räume auf einem Android-Gerät mit Touch spielbar ist (≥ 50 fps), das Projektmitglied das Spielgefühl als „gut genug“ einstuft und CP0 Frage 5 damit beantwortet ist.

**Koop-Check:** Eingaben nur über das Eingabe-Objekt (MP1); Zielhilfe als Eigenschaft des Spielers; keine neuen `get_first_node_in_group(&"player")`; kein `Engine.time_scale`.

## CP3 – Relay-Server (`soulwick-relay`) und Raumcodes

**Ziel:** Spieler auf PC, Android und später iOS treffen sich über einen **Raumcode**; der eigene Relay leitet die Pakete weiter, niemand muss Ports freigeben. Das Spiel bleibt im **Host-Modell**: Der Host rechnet, der Relay versteht die Spielpakete nicht (D-119; D-083 gilt damit als „Weiterleitung ja, Spiellogik nein“). Protokoll, Abläufe und Betrieb im Detail: `soulwick-platform/docs/KONZEPT_ONLINE.md`.

**Transport (D-119, entschieden):** eigene `MultiplayerPeerExtension` in GDScript (`online/relay_peer.gd`) über Godots eingebautes `WebSocketPeer`, verschlüsselt (WSS) über Traefik. Läuft ohne GDExtension auf Windows, Linux, macOS, Android und iOS; kein NAT-Problem, keine Portfreigaben. Später austauschbar, ohne die Spiellogik umzubauen: WebRTC-Direktverbindung (Relay bzw. TURN als Rückfall) und ein dedizierter Godot-Server (Abschnitt „Dedizierter Server (später)“).

**Plattform (Repo `soulwick-platform`):** P13 Relay (`api-dev` für den Vertrag, dann `relay-dev` oder `api-dev`), P16 Versionen und Umgebungen, P17 Relay auf Dokploy (Integrator). Dateien: `packages/contracts/src/lobby.ts` (neu, zuerst), `apps/relay/` (neu: Bun + WebSocket, Biome, `bun test`, Dockerfile auf `oven/bun`), interner API-Endpunkt für Gilden- und Sperrstatus. **Spiel (Netzwerk-Agent, z. B. `player-dev` nach MP1):** `online/relay_peer.gd` (Peer), `online/lobby_client.gd` (Raum erstellen, beitreten, Spielerliste, Steuer-Nachrichten), `online/api_client.gd` (HTTP-Client aus MP7, dafür vorgezogen), `online/session.gd` (Konto und Token am lokalen Client, Node in `game.tscn`, kein Autoload, D-044); Gildengebäude: „Raum erstellen“ und „Raumcode eingeben“.

**Teil A (vor MP2/MP4):** Relay läuft, zwei PCs spielen über einen Raumcode. **Teil B (mit CP2):** Android-Client im selben Raum.

- [ ] **Räume:** Code aus 6 Zeichen ohne verwechselbare Zeichen (kein `0`/`O`, `1`/`I`/`L`), Modus `quick` oder `guild`, ein Host, höchstens 4 Spieler (D-084). Läuft nach 10 Minuten ohne Start ab (TESTWERT), wird geschlossen, wenn der Host geht (D-085); kein Beitritt nach dem Start (D-085). Räume liegen nur im Speicher des Relays.
- [ ] **Beitritt:** Spieler-JWT ist Pflicht, der Relay prüft es selbst (gemeinsames `TOKEN_SECRET` mit der API); bei `guild` fragt er die API nach Mitgliedschaft und Sperre. Nur gleiche `protocolVersion` kommt in einen Raum (Plattform P16).
- [ ] **Protokoll:** Steuer-Nachrichten als JSON-Textrahmen (`hello`, `create`, `join`, `start`, `leave`, Spielerliste, Fehler); Spielpakete als **binärer Rahmen** `{from, to, channel, mode, data}`. `from` setzt der Relay (nie vom Absender übernommen), `to` = Peer-ID, 0 = alle, negativ = alle außer; `mode` = Godot-Übertragungsart (über WebSocket ist alles zuverlässig, das Feld bleibt für spätere WebRTC-Peers); `data` = Godot-Paket unverändert. Host hat Peer-ID 1, Clients bekommen vom Relay eindeutige IDs ≥ 2. Vertrag in `packages/contracts/src/lobby.ts`, Testvektoren für TypeScript und GDScript.
- [ ] **Schutz:** Rate-Limit je IP und Spieler, Paketgröße und Bytes/s je Verbindung begrenzt (TESTWERTE), Herzschlag mit Zeitlimit; JSON-Logs ohne Paketinhalte; Metriken (Räume, Spieler, Bytes/s) und `/health`.
- [ ] **Spiel:** Raumcode statt IP für Internet-Spiele. ENet über IP bleibt nur **optional** für LAN und Entwicklung hinter derselben Schnittstelle; eine Steam-Einladung (MP6) trägt nur den Raumcode. Fehlermeldungen: Code unbekannt, Raum voll, Run läuft schon, andere Version, gesperrt, kein Gildenmitglied, Relay nicht erreichbar.
- [ ] **Tests:** `bun test` für Protokoll und Raum-Lebenszyklus im Relay; `tools/net_smoke.gd` (neu): Headless-Host und Headless-Client spielen über den lokalen Relay einige Räume; Relay-Optionen `--sim-latency` und `--sim-loss` für schlechtes Netz.
- [ ] **Betrieb:** eigene Dokploy-Application, Domain `play.playsoulwick.com`, in `development` `play.dev.playsoulwick.com` (Vorschlag P-018); WebSocket über Traefik; eine Instanz zuerst, Regionen später (CP0 Frage 10, OFFEN); Datenvolumen beobachten (P17).

**Fertig, wenn:** Teil A: zwei Windows-PCs an verschiedenen Orten per Raumcode fünf Räume zusammen spielen und `net_smoke.gd` sowie die Relay-Tests grün sind. Teil B: ein PC-Host (Steam-Build) und ein Android-Client über mobile Daten (nicht dasselbe WLAN) per Raumcode fünf Räume zusammen spielen. Ein Neustart des Relay-Containers verliert keine dauerhaften Daten (Räume sind flüchtig, laufende Runs enden wie bei einem Host-Abbruch).

**Koop-Check:** Verbindungsart hinter `MultiplayerPeer` austauschbar (Relay, optional ENet, später WebRTC oder dedizierter Server), keine Spiellogik kennt den Transport; Raumzustand liegt im Relay und beim Host, Konto und Token in `online/session.gd`, nicht in Autoloads; die Spielwelt setzt keinen eigenen Spieler beim Host voraus ([MULTIPLAYER.md](MULTIPLAYER.md) §4a).

## CP4 – Stores

**Ziel:** Soulwick in allen drei Stores als Testversion, später als Release. Steam ist in [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP10 beschrieben; hier kommen Google Play und App Store dazu und die gemeinsamen Pflichten.

**Wer:** Publisher ist **WebBude** (D-119): Firmenkonten, Gebühren und Rechte führt das Projektmitglied für WebBude mit dem Team (MP10: Rechte am Spiel, Lizenzen für den Verkauf). Konten, Kosten, Upload und Store-Pflichten im Einzelnen: CP7. **Dateien:** `export_presets.cfg`, `art/store/` (neu, Briefing in einer späteren `SPRITES_V*.md`: Play-Icon 512×512, Feature-Grafik 1024×500, App-Store-Icon 1024×1024, Screenshots je Gerätegröße), Plattform `apps/web` (echte Store-Badges statt der Pixel-Chips, nur `web-dev`), eRecht24-Projekt (Datenschutzerklärung).

- [ ] **Steamworks:** siehe MP10 (Konto, Steam Direct, AppID, SteamPipe, Playtest, Store-Seite).
- [ ] **Google Play Console:** Entwicklerkonto (einmalige Gebühr), App-Signatur, Testspuren intern → geschlossen → offen → Produktion; Formular „Datensicherheit“, IARC-Fragebogen, Ziel-API-Level, Anforderungen für neue persönliche Konten (Testerzahl und -dauer vor dem Release prüfen).
- [ ] **App Store Connect:** Apple Developer Program (jährliche Gebühr), Zertifikate und Profile, TestFlight, „App-Datenschutz“-Labels, Altersfreigabe, Prüfregeln: Konto löschen in-App (5.1.1 (v)), Sign in with Apple nur bei Social-Login (4.8, CP0 Frage 8), keine externen Kauf-Links ohne Erlaubnis.
- [ ] Gemeinsam: Datenschutzerklärung und Impressum aus eRecht24 (Website `/de/datenschutz`, `/en/privacy`) als Store-Links; Support-Adresse; Screenshots und Trailer je Store in DE und EN; Store-Texte aus den Website-Texten (P9).
- [ ] Website: Plattform-Abschnitt bekommt die echten Badges und Links, sobald die Store-Seiten existieren (vorher nur die Pixel-Chips, SPRITES_V5 §8).

**Fertig, wenn:** je Store ein Test-Build (Steam Playtest, interne Play-Testspur, TestFlight) von drei Testpersonen installiert wurde und die Store-Einträge in DE und EN als Entwurf stehen.

## CP5 – Cross-Progression (Cloud-Save)

**Ziel:** Der Einzelspieler-Spielstand folgt dem Soulwick-Konto von PC zu Handy und zurück. Braucht CP1. Gilden-Fortschritt bleibt getrennt auf dem Server (D-081); hier geht es um den lokalen Spielstand (`savegame.cfg`).

**Plattform (`api-dev`):** `packages/contracts/src/save.ts` (neu: `GET /me/save`, `PUT /me/save`), Tabelle `player_saves` (Spieler, `version`, Daten ≤ 64 KB, Spielversion, `updated_at`, Gerätebezeichnung), Tests. **Spiel (`village-dev`, Haken im Hotspot `autoload/save_manager.gd`):** `online/cloud_save.gd` (neu), Haken `SaveManager.export_blob()` / `import_blob()` (Integrator), Dialog bei Konflikt in `ui/menus/`.

- [ ] Offline zuerst: der lokale Stand ist die Wahrheit, die Cloud ist ein Spiegel; Abgleich beim Betreten und Verlassen des Dorfs und nach jedem Run-Ende (nicht im Dungeon).
- [ ] Konfliktregel: `PUT` schickt die gelesene `version`; stimmt sie nicht (anderes Gerät hat gespeichert), antwortet die API `409` mit dem Server-Stand, und das Spiel fragt: „Auf einem anderen Gerät gibt es einen neueren Stand: diesen laden oder meinen behalten?“ Nie stilles Zusammenführen, nie Verlust ohne Rückfrage. Speichern mit **neuerer** Spielversion wird auf älteren Clients nur gelesen, wenn das Format kompatibel ist (Save-Migration wie heute).
- [ ] Eine Wahrheit: Wenn Soulwick-Cloud-Save kommt, bleibt Steam Cloud (MP10, optional) **aus**, damit es nicht zwei Spiegel gibt (Vorschlag; Entscheidung in CP0 nachtragen).
- [ ] Tests fassen den echten Spielstand nie an (AGENTS.md Regel 4); API-Tests für Versionskonflikt, Größenlimit, Löschung mit dem Konto.

**Fertig, wenn:** ein auf dem PC gespeicherter Stand nach der Anmeldung auf dem Handy erscheint und umgekehrt, ein erzeugter Konflikt den Dialog zeigt und die Tests grün sind.

**Koop-Check:** nur Einzelspieler-Zustand; Multiplayer-Fortschritt bleibt nach D-081 getrennt; keine Spiellogik betroffen.

## CP6 – Geschäftsmodell und Käufe (OFFEN)

**Ziel:** Erst nach CP0 Frage 1. Bis dahin **keine** Tabellen `purchases`/`entitlements`, keine Kauf-Routen, kein Shop-Code.

| Option | Was gebaut werden müsste | Folgen |
| --- | --- | --- |
| (a) mobil kostenlos, PC bezahlt | nichts im Spiel; Steam-Preis, Mobil ohne Käufe | einfachster Weg; Fairness-Frage PC-Käufer vs. Gratis-Mobil (gleicher Inhalt, keine Vorteile) |
| (b) überall kostenlos, Kosmetik | Kaufabwicklung Play Billing, StoreKit, Steam-Mikrotransaktionen; serverseitige Belegprüfung (Google Play Developer API, App Store Server API, Steam); Tabellen `purchases` (Provider, Bestell-ID, Produkt, Status, Beleg) und `entitlements` (Spieler, Gegenstand, Quelle); Kosmetik im Spiel (Spielerfarben über `player_tint_mask`, Laternen-Skins); Rückerstattungen, Steuern | am meisten Arbeit und Betrieb; **kein Pay-to-win** (Geist von D-081) |
| (c) überall bezahlt | Preise je Store; nichts im Spiel | mobil schwer verkäuflich; einfach zu bauen |

- [ ] Entscheidung aus CP0 als D-Eintrag; danach Paket neu schneiden (Plattform `contracts/shop.ts`, API-Belegprüfung, Spiel-Kosmetik).
- [ ] Bei (b): je Store ein Testkauf in der Sandbox, serverseitig geprüft und als Entitlement sichtbar.

**Fertig, wenn:** ein D-Eintrag VERBINDLICH ist; bei (b) ein Sandbox-Kauf je Store serverseitig bestätigt wurde.

## CP7 – Build-CI und Stores

**Ziel:** Jeder Build entsteht reproduzierbar in der CI und landet ohne Handarbeit im passenden Testkanal (Steam-Beta-Branch, Play „Interner Test“); Konten, Kosten und Pflichten der Stores sind für den Publisher **WebBude** (D-119) geklärt. Reihenfolge wie D-119: Steam → Android → iOS (später).

**Wer:** Integrator (CI und `export_presets.cfg` sind gemeinsame Dateien, CP2 baut die Mobil-Presets mit); Konten und Gebühren: Projektmitglied für WebBude. **Dateien:** `.gitlab-ci.yml` (neu), `export_presets.cfg` (Windows, Linux, Android, Dedicated Server; iOS später), `tools/ci/` (neu: Export-Skript, `steamcmd`-Build-Skripte, Play-Upload-Konfiguration), `online/build_config.gd` (neu, Vorschlag: API- und Relay-URL, Umgebung, `protocolVersion`, beim Export gesetzt).

- [ ] **GitLab-CI:** Godot 4.7.2 headless mit Export-Vorlagen im Container; vorher `validate_project.gd` und GUT; Exporte für Windows, Linux, Android (`.aab` für den Store, `.apk` zum Testen) und **Dedicated Server** (Linux, headless; nur gebaut und aufbewahrt, nicht verteilt).
- [ ] **Umgebungen:** Builds für `development` (Domains `api.dev.…`/`play.dev.…`, Steam-Beta-Branch, Play „Interner Test“) und `production`; API- und Relay-URL je Umgebung beim Export, Spielversion und `protocolVersion` im Build (passt zu Plattform P16).
- [ ] **Steam:** Upload per `steamcmd` (SteamPipe) auf einen Beta-Branch; braucht die eigene AppID (MP10). Den Standard-Branch schaltet ein Mensch frei.
- [ ] **Google Play:** Upload per Gradle Play Publisher oder fastlane in die Spur „Interner Test“; Play App Signing, eigener Upload-Schlüssel.
- [ ] **Signaturschlüssel** (Android-Upload-Keystore, Steam-Build-Konto, Play-Dienstkonto) nur als geschützte, maskierte CI-Variablen; nie im Repo.
- [ ] **iOS später:** Cloud-Mac (Codemagic oder GitHub-Actions-macOS), Apple-Zertifikate und Profile; erst nach Android.
- [ ] **Konten und Kosten (WebBude):** Steam Direct 100 USD je App (30 Tage Wartezeit nach der Zahlung, Store-Seite mindestens 2 Wochen „Demnächst“ vor dem Release), Steuer- und Bankdaten bei Steam; Google Play 25 USD einmalig als **Organisationskonto** (D-U-N-S-Nummer nötig; erspart die Testpflicht neuer Privatkonten mit 12 Testern über 14 Tage); Apple Developer Program 99 USD/Jahr (später).
- [ ] **Store-Pflichten** (zusammen mit CP4): Konto löschen in der App **und** als Web-Seite (Google; Plattform P15); Datenschutz-Angaben (Google „Datensicherheit“, Apple „App-Datenschutz“); IARC-Altersfreigabe; Melden und Filtern von Spieler- und Gildennamen (nutzergenerierte Inhalte); Zielgruppe in der Play Console **ab 13** angeben, sonst greifen die Familien-Richtlinien (USK 6 ist nur die Freigabe, nicht die Zielgruppe); Datenschutzerklärung (eRecht24) um Steam-, Google- und Apple-IDs und Relay-Verbindungsdaten ergänzen.

**Fertig, wenn:** ein CI-Lauf auf `dev` ohne Handarbeit einen Windows-Build im Steam-Beta-Branch und einen Android-Build in der Play-Spur „Interner Test“ ablegt, keine Schlüsseldatei im Repo liegt, der Dedicated-Server-Export als Artefakt entsteht und das Projektmitglied die Konten- und Kostenliste für WebBude bestätigt hat.

**Koop-Check:** keine Spiellogik betroffen; alle Plattform-Builds einer Version tragen dieselbe `protocolVersion`, sonst finden sie sich im Relay nicht.

## Lokal testen (ohne Stores)

Alles Folgende läuft auf einem Entwickler-PC; die Dienste kommen aus dem Plattform-Repo (`soulwick-platform/docs/KONZEPT_ONLINE.md` §5).

| Was | Wie |
| --- | --- |
| Dienste | im Plattform-Repo `bun run services:up`, dann `bun dev` (API 8787, Relay 8790 als Vorschlag, Web, Admin) |
| Vier Spieler auf einem PC | Godot-Editor *Debug → Ausführungsinstanzen anpassen*, vier Instanzen mit Argument `-- instance=1..4`; jede Instanz meldet sich per `/auth/dev` mit eigener Geräte-ID an und tritt per Raumcode bei (Schritt für Schritt: [MULTIPLAYER.md](MULTIPLAYER.md) §3b) |
| Gilden | Testdaten aus `bun run db:seed:dev` (Gilde „Dochtwächter“), Dev-Anmeldung als Seed-Spieler |
| Handy (Android) | Ein-Klick-Export per USB, `adb reverse tcp:8787 tcp:8787` und `adb reverse tcp:8790 tcp:8790`; das Handy erreicht `localhost` des PCs ohne HTTPS-Umweg (unverschlüsseltes HTTP/WS im Debug-Export erlauben, prüfen) |
| Steam | Test-AppID 480 mit `steam_appid.txt`, Steam-Client offen; zwei Steam-Konten brauchen zwei Rechner |
| Schlechtes Netz | Relay-Optionen `--sim-latency` und `--sim-loss`, unter Windows zusätzlich „clumsy“ |
| Automatisch | `tools/net_smoke.gd`: Headless-Host und Headless-Client gegen den lokalen Relay (Smoke-Test); `bun test` für das Relay-Protokoll |
| Echte Konten (Steam, Google) | nur in der Umgebung `development` mit Steam-Beta-Branch und Play „Interner Test“ |

## Dedizierter Server (später)

Godot exportiert einen **„Dedicated Server“**: Linux, headless, ohne Grafik und Audio, eine Binärdatei. Ein Docker-Image dafür schreibt man selbst (`debian:bookworm-slim` + Binärdatei). In Phase 1 ist er **nicht nötig**, weil der Host ein Spieler ist (D-119). Er wird ein eigenes Paket, sobald eines davon stört: Handy-Hosts (App im Hintergrund = Host weg = Run-Ende nach D-085), Cheats in Ranglisten oder häufige Host-Abbrüche. Hosting dann zuerst als Container-Pool auf dem eigenen VPS (Dokploy), bei Bedarf über einen Anbieter mit Regionen (Edgegap o. ä.). Voraussetzung im Code ist schon heute die Regel aus [MULTIPLAYER.md](MULTIPLAYER.md) §4a: Die Spielwelt setzt keinen eigenen Spieler beim Host voraus. Der Dedicated-Server-Export läuft ab CP7 in der CI mit, damit er nicht unbemerkt kaputtgeht.

## Koop-Check für Crossplay-Pakete

Zusätzlich zu den fünf Fragen aus [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) („Koop-Check für jedes Paket“) beantwortet jeder Bericht mit „ja“:

- [ ] Eingabequelle (Maus, Touch, Controller, Netz) ist eine Implementierung des Eingabe-Objekts aus MP1; Spiellogik fragt nie `Input` direkt.
- [ ] Verbindungsart (Relay als Hauptweg, ENet optional für LAN, später WebRTC oder dedizierter Server) ist hinter `MultiplayerPeer` austauschbar; keine Spiellogik kennt die Plattform.
- [ ] Konto, Token und Identitäten liegen am lokalen Client (`online/session.gd` in `game.tscn`), nicht in einem neuen Autoload (D-044); Zustand je Spieler am Spieler.
- [ ] Plattform-SDKs (GodotSteam, Play Games, Game Center) nur über eine gemeinsame Schnittstelle `PlatformServices` mit Null-Implementierung für Editor und Headless, damit alle Tests ohne SDK laufen.

## Risiken

- **iOS braucht einen Mac:** Godot exportiert für iOS nur mit Xcode (Signatur). Das Projektmitglied hat keinen Mac; deshalb kommt iOS **später** (D-119), über einen Cloud-Mac in der CI (CP7). Dazu die jährliche Apple-Gebühr.
- **Touch für ein maus-gezieltes Spiel:** Zielhilfe verändert die Balance und kann Crossplay unfair wirken lassen (PC zielt frei, Mobil mit Hilfe); Zielhilfe nur auf Mobil, eigene TESTWERTE, Plattform-Kennzeichen in Ranglisten (CP0 Frage 7).
- **Leistung auf Handys:** Sicht-Shader, Nachbearbeitung und ×2,8 Gegner bei vier Spielern (D-084) auf schwachen Geräten.
- **Eigener Relay = Betrieb:** Kosten, Datenvolumen (Inklusivtraffic des VPS beobachten), Latenz (EU-Server für Spieler in Übersee, Regionen OFFEN), Angriffsfläche; Monitoring und eine Status-Anzeige im Spiel bei Server-Ausfall (Einzelspieler bleibt offline spielbar). D-083 ist durch D-119 geändert.
- **Handy als Host:** Geht die App in den Hintergrund, ist der Host weg und der Run endet für alle (D-085). Handy-Spieler möglichst nicht hosten lassen oder vorher warnen; der dedizierte Server (später) löst das grundsätzlich.
- **Versionsversatz zwischen Stores:** Steam, Google und Apple geben Updates zeitversetzt frei; Crossplay braucht dieselbe `protocolVersion`. Der Relay lässt nur gleiche Protokollversionen in einen Raum, das Hauptmenü sperrt Online-Funktionen mit Update-Hinweis, wenn `/health` eine höhere `minGameVersion` meldet (Plattform P16).
- **Store-Prüfungen:** Konto löschen in-App **und** eine Web-URL für den Löschantrag (Google, Plattform P15), Datenschutz-Labels, Altersfreigabe, Testpflichten für neue Google-Play-Privatkonten (entfallen mit dem Organisationskonto, CP7); Ablehnungen verschieben Releases.
- **Zielgruppe in der Play Console:** Wer „unter 13“ ankreuzt, unterliegt den Familien-Richtlinien (Werbung, Datenerhebung, Login); deshalb Zielgruppe **ab 13** angeben, unabhängig von der Altersfreigabe USK 6.
- **Rechte und Lizenzen** (MP10) gelten für alle Stores: schriftlicher Vertrag mit dem Kollegen (Idee) und allen Mitwirkenden, dass WebBude Soulwick veröffentlichen und verkaufen darf; Lizenzen aller Grafiken, Schriften, Audio-Dateien und Addons prüfen. Klären, bevor Geld fließt oder eine Store-Seite öffentlich ist.
- **Zwei Spielstand-Wahrheiten** (Steam Cloud und Soulwick-Cloud) führen zu Konflikten; nur eine wählen (CP5).
- **Offenes Geschäftsmodell** blockiert Store-Einträge (Preis) und CP6; Entscheidung früh treffen, auch wenn „später“.
- **Betrug:** Der Host rechnet (D-082 nimmt fälschbare Ranglisten in Kauf); Crossplay vergrößert den Kreis. Plausibilitätsprüfung und Markieren bleiben der Weg.
- **Umfang:** Die ganze Phase kommt nach Phase 3. Nur CP0 (und optional der CP2-Prototyp) dürfen vorgezogen werden, damit MP2–MP7 nicht zweimal gebaut werden.

**Weiterlesen:** [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [MULTIPLAYER.md](MULTIPLAYER.md) · [PRD.md](PRD.md) · [DECISIONS.md](DECISIONS.md) · `soulwick-platform/docs/KONZEPT_ONLINE.md` · `soulwick-platform/docs/ROADMAP.md` (P11, P13–P17) · `soulwick-platform/docs/PRD.md` §3.8
