# ROADMAP Multiplayer – Schnelles Spiel, Gilden, Ranglisten und Steam

> **Stand:** 14.10.2026 (MP2–MP6 auf den Relay umgestellt, D-119) · **Status:** **MP1, MP1b, MP2 und MP3 gebaut** (14.10.2026; Stand und Bausteine: [MULTIPLAYER.md](MULTIPLAYER.md) §3a–§3c, MP3-Regeln D-126), **MP4 teilweise** (Umgebung je Build, Versionsprüfung im Hauptmenü, Export-Vorlagen und Build-Skripte, 14.10.2026, §3d; erster Build offen, Export-Vorlagen von Godot fehlen), MP5–MP10 geplant. Beginnt **nach** [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) Phase 2 (alle Räume, D-088, D-106); das Plattform-Repo (MP7/MP7b) darf parallel laufen.
> **Entscheidungen:** D-080 (Schnelles Spiel + Gilde), D-081 (getrennter Fortschritt, gemeinsame Kasse), D-082 (Ranglisten), D-083 (Server mit Dokploy), D-084 (Skalierung, Wiederbeleben), D-085 (Menüs/Pause, Abbruch, verbindlich seit D-123), D-119 (Host + eigener Relay), D-121 (Konto-Modell), D-122 (Konten zusammenführen), D-124 (Netzwerk-Reihenfolge) in [DECISIONS.md](DECISIONS.md).
> **Anforderungen:** [PRD.md](PRD.md) Abschnitt 7 · **Technik:** [MULTIPLAYER.md](MULTIPLAYER.md) · **Abhaken** nur mit Nachweis (Tests, Datum).

## Überblick

```text
Spiel (Godot)                    Server (VPS, Dokploy)                 Spiel (Godot)
┌──────────────┐  WSS, Raumcode  ┌──────────────────┐  WSS, Raumcode  ┌──────────────┐
│ Host-Spieler │◄───────────────►│  soulwick-relay  │◄───────────────►│  Client(s)   │
└──────┬───────┘                 │ leitet nur weiter│                 └──────┬───────┘
       │                         └──────────────────┘                        │
       │ HTTPS: Anmeldung, Gilden, Run-Bericht, Ranglisten                   │
       ▼                                                                     ▼
┌────────────────────────────────────────────────────────────────────────────────────┐
│ soulwick-api (TypeScript) ──► soulwick-postgres (PostgreSQL)                       │
└────────────────────────────────────────────────────────────────────────────────────┘
   Der Host rechnet, der Relay versteht die Pakete nicht (D-119). ENet direkt nur optional (LAN, Entwicklung).
```

| Phase | Ergebnis | Server? | Steam? |
| --- | --- | --- | --- |
| MP0 | Restliche Entscheidungen | – | – |
| MP1 | Code verträgt mehrere Spieler (noch ohne Netzwerk) | nein | nein |
| MP1b | API-Client im Spiel: Dev-Anmeldung, Token, offline-sicher (D-124) | API (lokal reicht) | nein |
| MP2 | Schnelles Spiel: Raum mit Raumcode in der Gilde, zusammen im Dorf (Relay) | Relay | nein |
| MP3 | Gemeinsamer Dungeon-Run, gemeinsame Kasse | Relay | nein |
| **MP4** | **Testversion für Freunde** (Windows-Build über den Relay) | Relay | nein |
| MP5 | Koop-Gefühl: Skalierung, Wiederbeleben, Raumgröße L | Relay | nein |
| MP6 | Steam als Zusatz: Anmeldung, Einladung mit Raumcode (Test-AppID 480) | Relay | ja |
| MP7 | Server-Grundlage auf Dokploy | **ja** | Anmeldung |
| MP8 | Dauerhafte Gilden mit Gilden-Fortschritt | ja | ja |
| MP9 | Ranglisten für Spieler und Gilden | ja | ja |
| MP10 | Eigene Steam-App, Playtest, Release-Vorbereitung | ja | ja |

**Parallel möglich:** MP7 (`apps/api` im Repo `soulwick-platform`, D-093) und MP7b (Website und Admin-Panel, `apps/web`, `apps/admin`) können von eigenen Agenten **gleichzeitig** zu MP1–MP5 gebaut werden, weil sie keinen Spielcode berühren. Das Grundgerüst steht bereits (siehe unten).

**Transport: Entscheidung D-119** (VERBINDLICH, Projektmitglied 14.10.2026): Host-Modell plus eigener Relay `soulwick-relay`; im Spiel `online/relay_peer.gd` (`MultiplayerPeerExtension` über `WebSocketPeer`), ENet nur optional für LAN und Entwicklung, Steam nur Zusatz.

**Crossplay (D-108, Architektur D-119):** Das Zielbild Steam + Google Play + App Store steht in [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md). Entschieden sind CP0 Frage 3 (eigener Relay mit Raumcodes, D-119), Frage 4 (Steam → Android → iOS, D-119) sowie Konto-Modell und Zusammenführen (Frage 2, D-121, D-122); die übrigen CP0-Fragen (Geschäftsmodell, Touch …) fallen **vor MP2**, soweit sie MP2, MP6 und MP7 verändern können. Der Relay selbst ist Paket CP3 (Plattform P13, P17) und muss vor MP2 laufen, lokal reicht `bun dev` im Plattform-Repo.

**Reihenfolge (D-124):** MP1 → **MP1b** (API-Client im Spiel) → **MP2 über den Relay** (D-119) → MP3. ENet nur optional für LAN-Tests und Entwicklung, Steam erst in MP6 und nur als Zusatz (Anmeldung, Einladung mit Raumcode).

**Warum ein austauschbarer Peer:** Die Spiellogik nutzt die allgemeine Godot-`multiplayer`-API. Die Verbindungsart steckt hinter `MultiplayerPeer` und ist austauschbar ([MULTIPLAYER.md](MULTIPLAYER.md) §2): **Relay** (Hauptweg für Internet und Crossplay), ENet (optional für LAN und Entwicklung ohne laufenden Relay), später WebRTC-Direktverbindung oder ein dedizierter Server. Mit Relay und ENet laufen mehrere Spielinstanzen auf **einem** Rechner; mit Steam ginge das nicht (ein Konto pro Rechner), deshalb ist Steam kein Transport, sondern nur Anmeldung und Einladung.

## MP0 – Entscheidungen

- [x] Gruppenmodi: Schnelles Spiel **und** dauerhafte Gilde (D-080).
- [x] Multiplayer getrennt vom Einzelspieler, gemeinsame Goldkasse (D-081).
- [x] Ranglisten für Spieler und Gilden (D-082).
- [x] Server: VPS mit Dokploy (D-083).
- [x] Skalierung und Wiederbeleben als TESTWERTE (D-084).
- [x] **Menüs/Pause im Multiplayer und Verbindungsabbruch** bestätigt: D-085 ist verbindlich (D-123, 14.10.2026).
- [ ] Details bestätigen: Gilden-Fortschritt (Vorschlag D-081), Ranglisten-Wertung (Vorschlag D-082).
- [ ] Wo die Netzwerk-Sitzung lebt: Node in `game.tscn` (bevorzugt, D-044 erlaubt nur vier Autoloads) oder neuer Autoload per neuer Entscheidung.
- [ ] D-001 („lokales“ Roguelite) und ARCHITECTURE („kein Backend“) für die Zeit nach dem MVP anpassen. ARCHITECTURE §1 und §8 angepasst am 14.10.2026 (Online-Teile optional, D-119, D-121); D-001 offen.

## MP1 – Code für mehrere Spieler vorbereiten (ohne Netzwerk)

**Ziel:** Nichts setzt mehr „genau einen Spieler“ voraus. Der Einzelspieler bleibt unverändert.

Stand und Klassen: [MULTIPLAYER.md](MULTIPLAYER.md) §3a.

- [x] Gegner-KI, Goldmünzen und alle weiteren Stellen nutzen den **nächsten lebenden** Spieler statt `get_first_node_in_group(&"player")` (zentrale Hilfsfunktion `EnemyTargeting`; nur `tests/manual/combat_sandbox.gd` nutzt es noch). Geprüft 14.10.2026: Gegner wählen in `mp_local_sim.gd` auch die Mitspieler als Ziel.
- [x] Kamera, HUD, Lichtkreis und Blendung hängen am **lokalen** Spieler (`WorldController.local_player`); Mitspieler ohne Kamera, Hinweis und Bildschirmwackeln. 14.10.2026, `test_player_multi_spawn.gd`.
- [x] Eingaben gekapselt: `PlayerInput` je Spieler, `LocalKeyboardMouseInput` (Tastatur/Maus) und `RemoteInput` (später Netz, jetzt Bots/Tests); `player.gd` und `weapon_controller.gd` lesen kein `Input` mehr. 14.10.2026, `test_player_input.gd`.
- [x] Spielmodus-Objekt `GameMode` (`SOLO`, `QUICK`, `GUILD`) mit Spielerzahl und lokalen Spielern, am `WorldController` (kein Autoload); `n = 1` verhält sich wie heute (smoke_test 47 Räume, combat_sim, boss_sim bestanden). 14.10.2026, `test_game_mode.gd`.
- [x] Pause (D-043) und HitStop abhängig vom Modus (D-085, verbindlich D-123): Solo wie bisher; im Gruppenspiel pausieren Menüs nicht, der lokale Spieler ist im Menü geschützt (keine Eingabe, unverwundbar), kein HitStop. 14.10.2026, `test_player_multi_spawn.gd`, `mp_local_sim.gd`.
- [ ] `MetaProgression` liest aus einer austauschbaren Quelle (lokal, „keine Boni“, Gilde) (D-081). **Teilweise (14.10.2026):** `GameMode.get_meta_source()` wählt die Quelle, der Dungeon wendet Dorf-Boni nur bei `LOCAL` an (Schnelles Spiel ohne Boni); Gilden-Quelle fehlt (MP8). Proviant-Boosts nimmt `RunManager.start_run` seit 14.10.2026 nur noch bei lokalem Fortschritt (Solo), im Schnellen Spiel bleiben sie liegen (MP2).
- [x] Raumwechsel erst, wenn **alle** lebenden Spieler den Ausgang erreicht haben: im gemeinsamen Run über den Relay nach D-126 (alle im Raum oder 10 s Countdown), 14.10.2026 mit MP3. Ohne Netzwerk (lokaler Test-Modus) löst weiter der erste Spieler aus.
- [x] Abgründe (A4): Fallprüfung und sichere Stelle je Spieler (`PlayerFall` am Spieler, D-088). 14.10.2026, `test_player_input.gd` (zwei Spieler fallen unabhängig).
- [x] Server-Regel: Die Spielwelt setzt **keinen eigenen Spieler** beim Host voraus (`GameMode` ohne lokale Spieler: alle Spieler mit `RemoteInput`, keine Kamera, keine Oberfläche gebunden). 14.10.2026, `test_player_multi_spawn.gd`.
- [x] Test: lokal gesteuerte Mitspieler ohne Netzwerk spielen einige Räume: `tools/mp_local_sim.gd -- players=2 rooms=5` (Bots über `RemoteInput`), bestanden mit 2 und 4 Spielern (Räume 1–5) sowie 2 und 3 Spielern (Räume 1–14); alle bestehenden Tests grün. 14.10.2026: GUT 850/850 grün, `mp_local_sim.gd` mit 2, 3 und 4 Spielern bestanden.

## MP1b – API-Client im Spiel (D-124)

**Ziel:** Das Spiel kann sich beim Server anmelden und hält ein Spieler-Token, das MP2 (Relay) und später MP8/MP9 brauchen. Vorgezogen aus MP7; kleiner Schritt ohne Netzwerk-Spiellogik.

**Dateien:** `online/online_config.gd`, `online/api_client.gd`, `online/api_result.gd`, `online/http_transport.gd`, `online/session.gd` (Node unter der Spielszene, wird bei Bedarf angelegt, kein neuer Autoload, D-044; als Haken kann der Integrator ihn fest in `scenes/game.tscn` einhängen), Tests `tests/unit/test_online_config.gd`, `test_api_client.gd`, `test_api_integration.gd`.

- [x] `online/api_client.gd`: kleiner HTTP-Client (`HTTPRequest`) mit Token im Header, JSON, Zeitlimit 5 s; Ergebnis-Objekt statt Ausnahmen für „Server nicht erreichbar“, Zeitüberschreitung, „gesperrt“ (mit Grund und Ende) und abgelaufenes Token. API- und Relay-Adresse je Umgebung (`OnlineConfig`: Standard, Projekteinstellung, `user://online.cfg`, Kommandozeile `-- api=… relay=…`; Relay sonst aus `GET /public/config`). 14.10.2026, `test_api_client.gd` (9 Tests, simuliert).
- [x] Dev-Anmeldung: `POST /auth/dev` mit Spielername und zufälliger Geräte-ID (UUID je Installation, je Instanz `-- instance=N` eine eigene); Token mit Ablauf in `user://online.cfg`, Konto in `online/session.gd`; gespeichertes Token wird mit `GET /me` weiterverwendet. 14.10.2026, `test_api_integration.gd` gegen die lokale API bestanden.
- [x] Offline zuerst: Kein Aufruf blockiert den Einzelspieler; scheitert die Anmeldung, zeigt das Gildengebäude nur einen Status. 14.10.2026.
- [x] Tests ohne laufenden Server (Antworten simuliert); fassen den echten Spielstand nie an (eigene `online`-Testdateien). Gegen die lokale Plattform geprüft (eigene Datenbank, API und Relay). 14.10.2026.

**Fertig, wenn:** sich zwei Instanzen auf einem Rechner gegen die lokale Plattform mit verschiedenen Geräte-IDs anmelden, ohne Server alles wie heute läuft und alle Tests grün sind.

**Koop-Check:** Konto und Token am lokalen Client (`online/session.gd`), nicht in einem Autoload; keine Spiellogik betroffen.

## MP2 – Schnelles Spiel: Lobby und Dorf (Relay)

**Braucht:** MP1 und den Relay (ROADMAP_CROSSPLAY CP3 Teil A, Plattform P13; lokal über `bun dev` im Plattform-Repo). Der HTTP-Client und die Sitzung aus MP7 (`online/api_client.gd`, `online/session.gd`) werden dafür vorgezogen.

- [x] Gildengebäude zeigt zwei Wege: **„Schnelles Spiel“** und **„Gilde“** (Gilde bis MP8 als „in Vorbereitung“). 14.10.2026.
- [x] Schnelles Spiel: **„Raum erstellen“** (Host bekommt vom Relay einen Raumcode, groß angezeigt) und **Raumcode** (6 Zeichen, nur das eindeutige Alphabet, Großbuchstaben) + **„Raum beitreten“**; Spielerliste mit Name, Host, Plattform und Koop-Farbe. „Starten“ ist bis MP3 deaktiviert (`LobbyClient.start_run()` als Haken). 14.10.2026.
- [x] Verbindung über `online/relay_peer.gd` (`MultiplayerPeerExtension` über `WebSocketPeer`, D-119) und `online/lobby_client.gd`. ENet als optionaler LAN-Weg ist **nicht** gebaut (bleibt optional hinter derselben Schnittstelle). 14.10.2026, `test_relay_peer.gd` (Rahmen gegen `RELAY_FRAME_TEST_VECTORS`).
- [x] Anmeldung für Internet-Spiele: Spieler-Token aus `/auth/dev` (Testphase); ohne Anmeldung kein Raum, der Einzelspieler bleibt offline spielbar. 14.10.2026.
- [x] `MultiplayerSpawner` erzeugt einen Spieler je Verbindung (Host-Autorität, Aussehen aus dem Profil des Spielers), `MultiplayerSynchronizer` für Position und Eingabe (daraus Lauf-/Dash-Animation); der Client sagt seine eigene Bewegung leicht voraus. Im Raum gilt `GameMode.QUICK` (keine Dorf-Boni, keine Proviant-Boosts, D-081). 14.10.2026, `tools/net_smoke.gd`.
- [x] Verständliche Fehlermeldungen (Raumcode unbekannt, Raum voll, Run läuft schon, andere Spielversion, Relay/Server nicht erreichbar, gesperrt, Host gegangen; Texte `LOBBY_ERR_*`). 14.10.2026.
- [ ] Entwickler-Test von Hand: Godot *Debug → Ausführungsinstanzen anpassen* mit zwei bis vier Instanzen (`-- instance=1..4`, je eigene Geräte-ID) gegen den lokalen Relay; Anleitung in [MULTIPLAYER.md](MULTIPLAYER.md) §3b. Automatisch bestanden 14.10.2026: `tools/net_smoke.gd` (Headless-Host und -Client, 3 von 3 Läufen, dazu 1 Lauf mit `RELAY_SIM_LATENCY_MS=120`); von Hand mit Fenstern offen.

**Fertig, wenn:** Zwei Instanzen auf einem Rechner und zwei Rechner in **verschiedenen** Netzen per Raumcode über den Relay zusammen durchs Dorf laufen.

## MP3 – Gemeinsamer Dungeon-Run

Regeln: **D-126**; Stand und Bausteine: [MULTIPLAYER.md](MULTIPLAYER.md) §3c.

- [x] Host startet („Starten“ im Gildengebäude oder am Dungeon-Eingang); alle laden den Dungeon mit demselben Seed; Modus `QUICK` (keine Meta-Boni, D-081). 14.10.2026, `tools/net_run_smoke.gd` (gleicher Seed, 0 abweichende Räume).
- [x] Nur der Host entscheidet: Raumfolge (RNG-Zustand je Slot an die Clients), Raumart, Spawns, Schaden, Raum geschafft, Gold; Raumwechsel nach D-126 (alle im Raum oder 10 s Countdown, Nachzügler werden geholt). Abstürze in Abgründe rechnet nur der Host (Client-Darstellung MP5). 14.10.2026.
- [x] Gegner (Ereignis + Schnappschüsse), Gegnergeschosse und -explosionen (nur als Ereignis), Münzen, Kisten, Geheimnischen und Raumzustand werden repliziert. 14.10.2026, Gegner und Tode auf beiden Seiten gleich (z. B. 79/79 bis Raum 16).
- [x] **Gemeinsame Goldkasse**; Shop-Käufe aus der Kasse, atomar beim Host (D-081), wer zuerst kauft, bekommt das Einzelstück. 14.10.2026 (Seed 1: Kauf des Clients über den Host).
- [x] Upgrade-Angebote, Waffen und Upgrades **je Spieler**; Upgrade-Wahl nach Raum 3 für jeden, Ausgang erst wenn alle gewählt haben (30 s). 14.10.2026 (Stapel des Clients beim Host gleich; Seed 7: Waffenwahl des Clients beim Host).
- [x] Menüs nach D-085 (keine globale Pause, Spieler im Menü geschützt, auch beim Host; Gegner ignorieren geschützte und gefallene Spieler). 14.10.2026.
- [x] Am Boden und Wiederbeleben (D-084, eigentlich MP5): 2 s daneben stehen, 2 HP; geschaffter Raum holt alle zurück; alle am Boden = Run-Ende. 14.10.2026.
- [x] Run-Ende vom Host an alle; Portal 100 %, Tod/Aufgeben/Host weg 50 % ins eigene Dorf (D-126 ersetzt den Vorschlag „ohne dauerhafte Auszahlung“); Run-Bericht `POST /runs` vom Host. 14.10.2026.
- [x] Verbindungsabbruch nach D-085/D-123: Client geht → Run läuft weiter, ab dem nächsten Raum für weniger Spieler; Host geht oder verliert den Relay → Run endet für alle mit 50 %. 14.10.2026 (`end=client_leaves`, `end=host_leaves`).
- [x] Automatischer Test: Headless-Host und Headless-Client spielen über den lokalen Relay Räume 1–5 bzw. 1–16 (`tools/net_run_smoke.gd`; `tools/net_smoke.gd` für MP2 weiter grün). 14.10.2026, Zahlen im Bericht des Pakets.
- [ ] Von Hand mit zwei Fenstern (Anleitung MULTIPLAYER.md §3c).

**Fertig, wenn:** Zwei Spieler zusammen den ersten Boss erreichen.

## MP4 – Testversion für Freunde

**Braucht:** Relay und API online in der Umgebung `development` (Plattform P2, P17).

- [ ] Windows-Export einrichten, Build als ZIP, gebaut gegen `development` (API `api.dev.…`, Relay `play.dev.…`, Domains nach Plattform P-018); später automatisch über die CI (ROADMAP_CROSSPLAY CP7). **Teilweise 14.10.2026:** Export-Vorlagen (`export_presets.cfg`: Windows, Linux, Linux Dedicated Server) und Build-Skripte (`tools/export_build.ps1`/`.sh` → `builds/<env>/<version>/`, ZIP, Start-Prüfung) stehen, `test_online_build.gd` prüft die Vorlagen; **15.10.2026:** Export-Vorlagen installiert, erster Windows-Build `Soulwick-0.9.0-development-windows.zip` erzeugt, Starttest bestanden (Skript wartet jetzt auf Godot, verträgt Godot-Warnungen und kurz gesperrte Dateien); **offen:** online gegen die Dev-Instanz spielen.
- [x] Umgebung je Build: `online/environment.cfg` bzw. Feature-Tag `env_*` → API/Relay/Website nach P-018, Editor bleibt auf localhost, `online.cfg` und Kommandozeile gewinnen weiter, Relay aus `GET /public/config`; Dev-Schlüssel nie im Build (nur `online.cfg` oder `-- dev_key=…`). 14.10.2026, `test_online_build.gd` (12 Tests), [MULTIPLAYER.md](MULTIPLAYER.md) §3d.
- [x] README-Abschnitt „Mit Freunden testen“: entpacken, starten; der Host erstellt im Gildengebäude einen Raum und teilt den **Raumcode**, die anderen geben ihn ein. Keine Portfreigabe, kein VPN, keine Zusatzsoftware. 14.10.2026: [README.md](../README.md), ausführlich [MULTIPLAYER.md](MULTIPLAYER.md) §3d, `LIESMICH.txt` in jedem ZIP.
- [ ] Nur noch als Notlösung ohne erreichbaren Relay: ENet über LAN oder ein virtuelles LAN (z. B. Tailscale); früher als Hauptweg geplant, durch D-119 ersetzt.
- [x] Spielversion im Hauptmenü anzeigen; der Relay lässt nur gleiche `protocolVersion` in einen Raum, `/health` meldet `minGameVersion` (Plattform P16). 14.10.2026: Fußzeile „v0.9.0 dev“ + Online-Status, `OnlineVersionCheck` liest `GET /public/config` (Rückfall `/health`) ohne zu blockieren; zu alt → Online gesperrt mit „Bitte aktualisiere das Spiel“ und Link, API weg → Offline-Hinweis. `test_online_build.gd`, live gegen die lokale API geprüft.
- [ ] Rückmeldungen sammeln (Lag, Abbrüche, Schwierigkeit, Spaß) und dazu die Relay-Metriken (Bytes/s je Raum) ansehen.

**Fertig, wenn:** 2–4 Personen an verschiedenen Orten einen Run zusammen gespielt haben.

## MP5 – Koop-Gefühl (D-084)

- [ ] Skalierung nach Spielerzahl laut D-084, zentral als TESTWERT.
- [ ] Raumgröße L für 3–4 Spieler (L-Vorlagen je Raumart, siehe ROADMAP_AUSBAU A3–A5).
- [ ] Wiederbeleben: zu Boden gehen, 2 s neben dem Gefallenen stehen, Aufstehen mit 2 HP; Raum geschafft → alle stehen auf; alle am Boden → Run-Ende.
- [ ] Eigener Lichtkreis je Spieler, Namen über den Figuren, Pfeil zu Mitspielern außerhalb des Bildes.
- [ ] `balance_sim.gd` mit 1–4 Bots; Werte anpassen.

## MP6 – Steam als Zusatz (Test-AppID 480)

Steam ist **kein Transport** (D-119, Plattform P-017): Auch Steam-Spieler verbinden sich über den Relay, damit PC und Handy im selben Raum landen.

- [ ] **GodotSteam** (GDExtension) einbinden, Kompatibilität mit Godot 4.7.2 prüfen; nur über die Schnittstelle `PlatformServices` mit Null-Implementierung für Editor, Headless und Mobil.
- [ ] Kein `SteamMultiplayerPeer` und kein Steam-Relay als Hauptweg; die Verbindung bleibt `relay_peer.gd`.
- [ ] **Freunde einladen** (Steam-Overlay) und „Spiel beitreten“ aus der Freundesliste über Rich Presence; die Einladung trägt nur den **Raumcode**, der Beitritt läuft über `lobby_client.gd`.
- [ ] Anmeldung mit Steam-Sitzungsticket an `/auth/steam` vorbereiten; echt prüfbar erst mit eigener AppID (MP10, Plattform P14).
- [ ] Testen mit zwei Rechnern und zwei Steam-Konten.

**Fertig, wenn:** Ein Freund über eine Steam-Einladung einem Run beitritt (Raumcode über Rich Presence, Verbindung über den Relay).

## MP7 – Server-Grundlage auf Dokploy (D-083, parallel möglich)

**Ziel:** Ein lauffähiger, gesicherter Server, den Gilden (MP8) und Ranglisten (MP9) nutzen.

- [x] Grundgerüst im Repo `../soulwick-platform` (D-093, 13.10.2026): `apps/api` (Hono, damals Drizzle und PGlite), `packages/contracts`, `infra/docker-compose.yml`, Migrationen. Seit 14.10.2026 Umstellung auf **Bun, Turborepo und Prisma** (Plattform P7, P8), Datenbank-Container `soulwick-postgres`, Tests mit `bun test`. Stand und Befehle: `soulwick-platform/README.md` und `soulwick-platform/docs/TECHSTACK.md`.
- [ ] In Dokploy deployen; Domain (z. B. `api.<domain>`) mit HTTPS; Umgebungsvariablen (Datenbank, Steam-Web-API-Schlüssel, Token-Geheimnis) nur in Dokploy.
- [ ] **Anmeldung:**
  - **Testphase:** `POST /auth/dev`: Spielername plus zufällige Geräte-ID, nur mit Test-Schlüssel aktiv.
  - **Gastkonto (P-028, 15.10.2026):** `POST /auth/device` ohne Schlüssel, Geräte-ID je Installation; Test-Builds für Freunde melden sich so an, später Verknüpfung per Link-Code.
  - **Mit eigener AppID (MP10):** `POST /auth/steam`: Das Spiel schickt ein Steam-Sitzungsticket, der Server prüft es bei Steam (`AuthenticateUserTicket`). Mit der Test-AppID 480 geht das nicht, weil dafür der Publisher-Schlüssel der eigenen App nötig ist.
  - Antwort: Sitzungs-Token für weitere Aufrufe.
- [ ] `GET /health`, Fehlerprotokoll, Begrenzung der Anfragen pro Minute.
- [ ] Tägliches Datenbank-Backup.
- [ ] Datenschutz: gespeichert werden nur Plattform-Identitäten (Nutzer-ID des Providers: Steam, Geräte-ID, Google Play Games, Game Center; D-121), Name, Gilde, Run-Berichte. Löschung auf Wunsch (`DELETE /me`, zusätzlich Web-Formular, Plattform P15), kurze Datenschutzerklärung.
- [ ] Godot-Seite: HTTP-Client mit Token → vorgezogen als **MP1b** (D-124). **Das Spiel funktioniert weiter, wenn der Server nicht erreichbar ist** (der Einzelspieler braucht ihn nicht; Internet-Koop braucht Anmeldung und Relay, LAN über ENet optional nicht).
- [ ] API-Tests im Repo `soulwick-platform` mit `bun test` gegen den lokalen Docker-Postgres (`soulwick-postgres`, Wegwerf-Datenbank je Lauf).

**Datenmodell (Vorschlag, Stand Plattform):** `players` (id, name), `player_identities` (spieler, provider, provider-nutzer-id; P-014, D-121), `guilds` (id, name, kürzel, einladungscode, gründer), `guild_members` (gilde, spieler, rolle, beigetreten), `guild_progress` (gilde, kasse, schmiede-stufen, version), `runs` (id, modus, gilde, raum, dauer, seed, spielversion, zeitpunkt), `run_players` (run, spieler).

## MP7b – Website und Admin-Panel (D-093, parallel möglich)

- [x] Grundgerüst: `apps/web` (Startseite, Ranglisten, Gildenseiten, Datenschutz/Impressum als Platzhalter) und `apps/admin` (Anmeldung, Spieler sperren/entsperren, Gilden verwalten, Runs prüfen, Protokoll, Admins) – 13.10.2026.
- [ ] Texte für Datenschutz und Impressum (verantwortliche Person, Betreiber WebBude).
- [ ] Logo, Keyart und Screenshots einbauen ([SPRITES_V3.md](design/sprites/SPRITES_V3.md) §6).
- [ ] Deployment auf Dokploy: Domains `<domain>`, `api.<domain>`, `admin.<domain>`; Admin-Panel zusätzlich schützen (z. B. Basic Auth oder IP-Liste in Dokploy).
- [ ] Ersten Admin anlegen, Moderatoren einladen.
- [ ] Optional: Discord-Webhook bei gemeldeten Runs.

## MP8 – Dauerhafte Gilden (D-080, D-081)

- [ ] API: Gilde gründen (Name, Kürzel), beitreten per **Einladungscode**, verlassen, Mitglieder ansehen, Gründer kann Mitglieder entfernen und den Code erneuern. Höchstens eine Gilde je Spieler, max. 30 Mitglieder.
- [ ] Gildengebäude: Tab „Gilde“ mit Mitgliederliste, Einladungscode zum Kopieren (für Discord), Gilden-Schmiede, Gildenkasse.
- [ ] **Gilden-Run:** Host startet im Modus `GUILD`; nur Mitglieder dürfen beitreten (Prüfung über den Server); Meta-Boni aus der Gilden-Schmiede.
- [ ] Run-Ende: Auszahlung in die Gildenkasse nach 50-/100-%-Regel; Gilden-Schmiede kauft aus der Kasse. Gleichzeitige Käufe mit Versionsprüfung (kein doppeltes Abbuchen).
- [ ] Später mit Steam: Mitglieder direkt aus der Freundesliste einladen.

**Fertig, wenn:** Drei Personen eine Gilde gründen bzw. beitreten, einen Gilden-Run spielen und die Gildenkasse danach für alle gleich ist.

## MP9 – Ranglisten (D-082)

- [ ] `POST /runs`: Der Host meldet am Run-Ende Modus, Teilnehmer, erreichten Raum, Dauer, Seed und Spielversion. Auch Einzelspieler-Runs werden gemeldet (wenn angemeldet und online).
- [ ] Plausibilitätsprüfung auf dem Server (z. B. Mindestdauer je Raum, bekannte Spielversion); verdächtige Einträge markieren statt löschen.
- [ ] Ranglisten: **Spieler Solo**, **Spieler Gruppe**, **Gilden**; jeweils **Allzeit** und **Saison** (monatlich).
- [ ] Anzeige im Spiel (Chronik oder Gildengebäude): Top 50 und die eigene Position.
- [ ] Optional: Ranglisten als Webseite.
- [ ] Testphasen-Ranglisten zum Steam-Start zurücksetzen.

## MP10 – Eigene Steam-App und Release-Vorbereitung

- [ ] Rechte am Spiel im Team klären; Lizenzen aller Grafiken, Musik und Addons für den kommerziellen Verkauf prüfen.
- [ ] Steamworks-Konto (wer führt es, Steuer- und Bankdaten), Steam Direct bezahlen, eigene AppID.
- [ ] Steam-Anmeldung am Server auf die eigene AppID umstellen (MP7).
- [ ] Builds per SteamPipe hochladen, Beta-Branch mit Passwort, **Steam Playtest** für Freunde und Testspieler.
- [ ] Store-Seite, Screenshots, Trailer; optional Achievements und Steam-Cloud für Spielstände.

## Risiken

- Globale Pause und HitStop prägen das Einzelspieler-Gefühl; im Multiplayer fallen sie weg (D-085).
- Netzlast durch viele Gegner und Geschosse (×2,8 Gegner bei 4 Spielern); über den Relay zählt jedes Byte doppelt (Host → Relay → Clients) und kostet Server-Traffic.
- Abgründe im Multiplayer: Nur der Host entscheidet über Abstürze, sonst entstehen „unfaire“ Stürze durch Verzögerung.
- Ranglisten sind fälschbar, solange der Host rechnet; für den Anfang akzeptiert.
- Der Server braucht Betrieb: Updates, Backups, Datenschutz.

**Weiterlesen:** [PRD.md](PRD.md) · [MULTIPLAYER.md](MULTIPLAYER.md) · [ROADMAP.md](ROADMAP.md) · [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) · [DECISIONS.md](DECISIONS.md)
