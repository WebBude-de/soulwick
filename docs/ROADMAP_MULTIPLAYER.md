# ROADMAP Multiplayer – Schnelles Spiel, Gilden, Ranglisten und Steam

> **Stand:** 14.10.2026 (MP2–MP6 auf den Relay umgestellt, D-119) · **Status:** geplant, **noch nichts gebaut**. Beginnt **nach** [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) Phase 2 (alle Räume, D-088, D-106); das Plattform-Repo (MP7/MP7b) darf parallel laufen.  
> **Entscheidungen:** D-080 (Schnelles Spiel + Gilde), D-081 (getrennter Fortschritt, gemeinsame Kasse), D-082 (Ranglisten), D-083 (Server mit Dokploy), D-084 (Skalierung, Wiederbeleben), D-085 (Menüs/Pause, Abbruch, **Vorschlag**), D-119 (Host + eigener Relay) in [DECISIONS.md](DECISIONS.md).  
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

**Crossplay (D-108, Architektur D-119):** Das Zielbild Steam + Google Play + App Store steht in [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md). CP0 Fragen 3 (eigener Relay) und 4 (Steam → Android → iOS) sind entschieden; die übrigen CP0-Fragen (Geschäftsmodell, Konto-Modell, Touch …) fallen **vor MP2**. Der Relay selbst ist Paket CP3 (Plattform P13, P17) und muss vor MP2 laufen, lokal reicht `bun dev` im Plattform-Repo.

**Warum ein austauschbarer Peer:** Die Spiellogik nutzt die allgemeine Godot-`multiplayer`-API. Die Verbindungsart steckt hinter `MultiplayerPeer` und ist austauschbar: **Relay** (Hauptweg für Internet und Crossplay), ENet (optional für LAN und Entwicklung ohne laufenden Relay), später WebRTC-Direktverbindung oder ein dedizierter Server. Mit Relay und ENet laufen mehrere Spielinstanzen auf **einem** Rechner; mit Steam ginge das nicht (ein Konto pro Rechner), deshalb ist Steam kein Transport, sondern nur Anmeldung und Einladung.

## MP0 – Entscheidungen

- [x] Gruppenmodi: Schnelles Spiel **und** dauerhafte Gilde (D-080).
- [x] Multiplayer getrennt vom Einzelspieler, gemeinsame Goldkasse (D-081).
- [x] Ranglisten für Spieler und Gilden (D-082).
- [x] Server: VPS mit Dokploy (D-083).
- [x] Skalierung und Wiederbeleben als TESTWERTE (D-084).
- [ ] **Menüs/Pause im Multiplayer und Verbindungsabbruch** bestätigen (Vorschlag D-085).
- [ ] Details bestätigen: Gilden-Fortschritt (Vorschlag D-081), Ranglisten-Wertung (Vorschlag D-082).
- [ ] Wo die Netzwerk-Sitzung lebt: Node in `game.tscn` (bevorzugt, D-044 erlaubt nur vier Autoloads) oder neuer Autoload per neuer Entscheidung.
- [ ] D-001 („lokales“ Roguelite) und ARCHITECTURE („kein Backend“) für die Zeit nach dem MVP anpassen.

## MP1 – Code für mehrere Spieler vorbereiten (ohne Netzwerk)

**Ziel:** Nichts setzt mehr „genau einen Spieler“ voraus. Der Einzelspieler bleibt unverändert.

- [ ] Gegner-KI, Goldmünzen und alle weiteren Stellen nutzen den **nächsten lebenden** Spieler statt `get_first_node_in_group(&"player")` (zentrale Hilfsfunktion).
- [ ] Kamera, HUD, Lichtkreis und Blendung hängen am **lokalen** Spieler.
- [ ] Eingaben gekapselt (ein Eingabe-Objekt je Spieler, lokal aus `Input`, später aus dem Netz).
- [ ] Spielmodus-Objekt (`SOLO`, `QUICK`, `GUILD`) mit Spielerzahl; `n = 1` verhält sich exakt wie heute.
- [ ] Pause (D-043) und HitStop abhängig vom Modus (D-085).
- [ ] `MetaProgression` liest aus einer austauschbaren Quelle (lokal, „keine Boni“, Gilde) (D-081).
- [ ] Raumwechsel erst, wenn **alle** lebenden Spieler den Ausgang erreicht haben.
- [ ] Abgründe (A4): Fallprüfung und sichere Stelle je Spieler.
- [ ] Server-Regel: Die Spielwelt setzt **keinen eigenen Spieler** beim Host voraus.
- [ ] Test: zwei lokal gesteuerte Spieler ohne Netzwerk spielen einige Räume (Bot-Steuerung wie `smoke_test.gd`); alle bestehenden Tests grün.

## MP2 – Schnelles Spiel: Lobby und Dorf (Relay)

**Braucht:** MP1 und den Relay (ROADMAP_CROSSPLAY CP3 Teil A, Plattform P13; lokal über `bun dev` im Plattform-Repo). Der HTTP-Client und die Sitzung aus MP7 (`online/api_client.gd`, `online/session.gd`) werden dafür vorgezogen.

- [ ] Gildengebäude zeigt zwei Wege: **„Schnelles Spiel“** und **„Gilde“** (Gilde bis MP8 als „in Vorbereitung“).
- [ ] Schnelles Spiel: **„Raum erstellen“** (Host bekommt vom Relay einen Raumcode zum Weitergeben, z. B. über Discord) und **„Raumcode eingeben“**; Spielerliste mit Namen; Host startet den Run.
- [ ] Verbindung über `online/relay_peer.gd` (`MultiplayerPeerExtension` über `WebSocketPeer`, D-119) und `online/lobby_client.gd`; ENet (`create_server`, `create_client(ip, port)`) bleibt nur als optionaler LAN- und Entwicklungsweg hinter derselben Schnittstelle.
- [ ] Anmeldung für Internet-Spiele: Spieler-Token aus `/auth/dev` (Testphase) bzw. später `/auth/steam`; ohne Anmeldung kein Raum, der Einzelspieler bleibt offline spielbar.
- [ ] `MultiplayerSpawner` erzeugt einen Spieler je Verbindung, `MultiplayerSynchronizer` für Position und Animation.
- [ ] Verständliche Fehlermeldungen (Raumcode unbekannt, Raum voll, Run läuft schon, andere Spielversion, Relay nicht erreichbar, gesperrt).
- [ ] Entwickler-Test: Godot *Debug → Ausführungsinstanzen anpassen* mit zwei bis vier Instanzen (`--player=1..4`, je eigene Geräte-ID) gegen den lokalen Relay ([ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) „Lokal testen“).

**Fertig, wenn:** Zwei Instanzen auf einem Rechner und zwei Rechner in **verschiedenen** Netzen per Raumcode über den Relay zusammen durchs Dorf laufen.

## MP3 – Gemeinsamer Dungeon-Run

- [ ] Host startet; alle laden den Dungeon mit demselben Seed; Modus `QUICK` (keine Meta-Boni, D-081).
- [ ] Nur der Host entscheidet: Raumfolge, Raumart, Spawns, Schaden, Raum geschafft, Abstürze, Gold.
- [ ] Gegner, Geschosse (nur als Ereignis: Start, Richtung, Tempo), Münzen und Raumzustand werden repliziert.
- [ ] **Gemeinsame Goldkasse**; Shop-Käufe aus der Kasse, atomar beim Host (D-081).
- [ ] Upgrade-Angebote, Waffen und Upgrades **je Spieler**.
- [ ] Menüs nach D-085 (keine globale Pause, Spieler im Menü geschützt).
- [ ] Run-Ende vom Host an alle; Schnelles Spiel ohne dauerhafte Auszahlung.
- [ ] Verbindungsabbruch nach D-085; verliert der Host die Verbindung zum Relay, gilt das als Host-Abbruch (Raum wird geschlossen).
- [ ] Automatischer Test: Headless-Host und Headless-Client spielen über den lokalen Relay einige Räume (`tools/net_smoke.gd`).

**Fertig, wenn:** Zwei Spieler zusammen den ersten Boss erreichen.

## MP4 – Testversion für Freunde

**Braucht:** Relay und API online in der Umgebung `development` (Plattform P2, P17).

- [ ] Windows-Export einrichten, Build als ZIP, gebaut gegen `development` (API `api.dev.…`, Relay `play.dev.…`, Domains nach Plattform P-018); später automatisch über die CI (ROADMAP_CROSSPLAY CP7).
- [ ] README-Abschnitt „Mit Freunden testen“: entpacken, starten; der Host erstellt im Gildengebäude einen Raum und teilt den **Raumcode**, die anderen geben ihn ein. Keine Portfreigabe, kein VPN, keine Zusatzsoftware.
- [ ] Nur noch als Notlösung ohne erreichbaren Relay: ENet über LAN oder ein virtuelles LAN (z. B. Tailscale); früher als Hauptweg geplant, durch D-119 ersetzt.
- [ ] Spielversion im Hauptmenü anzeigen; der Relay lässt nur gleiche `protocolVersion` in einen Raum, `/health` meldet `minGameVersion` (Plattform P16).
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

- [x] Grundgerüst im Repo `../soulwick-platform` (D-093, 13.10.2026): `apps/api` (Hono, Drizzle, PostgreSQL, Tests mit PGlite), `packages/contracts`, `infra/docker-compose.yml`, Migrationen. Stand und Befehle: `apps/api/README.md`.
- [ ] In Dokploy deployen; Domain (z. B. `api.<domain>`) mit HTTPS; Umgebungsvariablen (Datenbank, Steam-Web-API-Schlüssel, Token-Geheimnis) nur in Dokploy.
- [ ] **Anmeldung:**
  - **Testphase:** `POST /auth/dev`: Spielername plus zufällige Geräte-ID, nur mit Test-Schlüssel aktiv.
  - **Mit eigener AppID (MP10):** `POST /auth/steam`: Das Spiel schickt ein Steam-Sitzungsticket, der Server prüft es bei Steam (`AuthenticateUserTicket`). Mit der Test-AppID 480 geht das nicht, weil dafür der Publisher-Schlüssel der eigenen App nötig ist.
  - Antwort: Sitzungs-Token für weitere Aufrufe.
- [ ] `GET /health`, Fehlerprotokoll, Begrenzung der Anfragen pro Minute.
- [ ] Tägliches Datenbank-Backup.
- [ ] Datenschutz: gespeichert werden nur Steam-ID bzw. Geräte-ID, Name, Gilde, Run-Berichte. Löschung auf Wunsch (`DELETE /me`), kurze Datenschutzerklärung.
- [ ] Godot-Seite: kleiner HTTP-Client (`HTTPRequest`) mit Token (für MP2 vorgezogen); **das Spiel funktioniert weiter, wenn der Server nicht erreichbar ist** (der Einzelspieler braucht ihn nicht; Internet-Koop braucht Anmeldung und Relay, LAN über ENet optional nicht).
- [ ] API-Tests im Ordner `server/` (z. B. Vitest) gegen eine Test-Datenbank.

**Datenmodell (Vorschlag):** `players` (id, steam_id/geräte_id, name), `guilds` (id, name, kürzel, einladungscode, gründer), `guild_members` (gilde, spieler, rolle, beigetreten), `guild_progress` (gilde, kasse, schmiede-stufen, version), `runs` (id, modus, gilde, raum, dauer, seed, spielversion, zeitpunkt), `run_players` (run, spieler).

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
