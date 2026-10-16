# Multiplayer – Architekturplan

> **Stand:** 14.10.2026 (Netzwerk nach D-119 und D-124) · **Status:** **MP1** (mehrere Spieler ohne Netzwerk, §3a), **MP1b** (API-Client), **MP2** (Raum mit Raumcode über den Relay, zusammen im Dorf, §3b) und **MP3** (gemeinsamer Dungeon-Run, §3c, D-126) sind gebaut; MP4 und alles danach ist Plan. Das **Online-Menü** (D-147, §3f) erreicht man aus dem Hauptmenü („Online spielen“) und im Dorf über das Gildengebäude: Schnelles Spiel (Raum erstellen, Raumcode) und Gilden (bis zu 5 je Spieler, Gilden-Raum nur für Mitglieder).
> Umfang beschlossen in D-080 … D-085, Netzwerk und Konto in D-119 und D-121 … D-124 ([DECISIONS.md](DECISIONS.md)). **Abweichend von Abschnitt 3:** Im Multiplayer bringt niemand seine Einzelspieler-Verbesserungen mit, und Gold ist eine gemeinsame Kasse (D-081).

## 1. Ziel

- **Koop für 2–4 Spieler** über das Internet per **Raumcode** und eigenem Relay (D-119, D-124); optional im LAN über ENet für Tests und Entwicklung; Steam nur als Zusatz für Anmeldung und Einladungen (MP6, Abschnitt 4a).
- Ein Spieler ist **Host** (rechnet die Spielwelt und spielt mit), die anderen sind **Clients**. Kein Gameserver: Der Relay `soulwick-relay` leitet die Pakete nur weiter (D-119). Für Internet-Spiele meldet sich jeder mit seinem Soulwick-Konto an (D-121); statt Matchmaking teilt der Host einen Raumcode. Der Einzelspieler braucht weder Konto noch Server.
- Gemeinsamer Dungeon-Run; jeder behält seinen **eigenen** permanenten Spielstand.

## 2. Technik

| Baustein | Wahl | Begründung |
| --- | --- | --- |
| Transport | austauschbarer `MultiplayerPeer` (Godot High-Level Multiplayer). **Hauptweg Relay** (D-119): `online/relay_peer.gd`, eine `MultiplayerPeerExtension` über `WebSocketPeer` (WSS). Optional `ENetMultiplayerPeer` für LAN und Entwicklung; später WebRTC oder dedizierter Server | Spiellogik kennt den Transport nicht; WebSocket ist auf allen Zielplattformen eingebaut, keine Portfreigaben, kein NAT-Problem (über WebSocket ist alles zuverlässig) |
| Autorität | **Host-Autorität** | Host simuliert Gegner, Schaden, Räume, Gold; Clients senden nur Eingaben |
| Replikation | `MultiplayerSpawner` (Spieler, Gegner, Projektile, Gold) und `MultiplayerSynchronizer` (Position, HP, Animation) | Standardweg in Godot 4 |
| Aufrufe | `@rpc` für Ereignisse (Treffer-Effekte, Dialoge, Run-Ende) | |
| Adresse | Relay-URL je Umgebung (beim Export gesetzt); nur ENet: Port z. B. 24565, einstellbar | |

Ablauf: Gilde → „Raum erstellen“ (Host meldet sich mit seinem Token beim Relay und bekommt einen Raumcode) oder „Raumcode eingeben“ (`online/lobby_client.gd`) → Spielerliste über `peer_connected`/`peer_disconnected` → Host startet den Run → alle laden `dungeon.tscn`, der Host verteilt den **RNG-Seed** (`DungeonManager.seed_value`). Im LAN-Testweg ersetzen `create_server` und `create_client(ip, port)` von ENet den Raumcode.

## 3. Was im aktuellen Code netzwerkfähig werden muss

| Bereich | Heute | Später |
| --- | --- | --- |
| `WorldController` | spawnt **einen** Spieler aus `player.tscn` | `MultiplayerSpawner` spawnt einen Spieler je Peer; Kamera, HUD und Sicht nur für den lokalen Spieler |
| `Player` | liest `Input` direkt | nur der Besitzer (`is_multiplayer_authority()`) liest Eingaben und sendet sie; Host bewegt/validiert, Synchronizer verteilt |
| Gegner-KI (`enemy_base.gd`), Goldmünzen (`gold_pickup.gd`) | `get_first_node_in_group(&"player")` | **nächster lebender** Spieler; nur auf dem Host |
| `DungeonManager`, `RoomController`, `EnemySpawner` | lokal | nur Host entscheidet (Raumfolge, Spawns, Raum geschafft); Clients bekommen Ergebnisse. Ein Raumwechsel erst, wenn alle lebenden Spieler im nächsten Raum stehen (kein Teleport) |
| `DamageProcessor`, Hitbox/Hurtbox | lokal | Treffer nur auf dem Host berechnen, Ergebnis (`DamageResult`) per RPC für Effekte/Schadenszahlen |
| `GameManager`-Pause, `Modal` | Dialoge **pausieren das ganze Spiel** (D-043) | im Multiplayer keine globale Pause: Dialoge (Upgrade-Wahl, Shop) nur lokal, Spieler währenddessen unverwundbar; Pausemenü pausiert nicht |
| `HitStop` | ändert `Engine.time_scale` global | nur lokal-visuell oder im Multiplayer abschalten |
| `RunManager` (Run-Gold, Kristalle, Boosts) | ein Run-Konto | Entscheidung nötig: **gemeinsame Kasse** oder Gold je Spieler; Run-Ende vom Host an alle, jeder Client bucht seine Auszahlung **selbst** in seinem `SaveManager` |
| `UpgradeManager`, `WeaponController` | ein Spieler | je Spieler eigene Upgrades/Waffen; Upgrade-Angebote je Spieler |
| `EventBus` | lokale Signale | bleibt lokal; der Host löst die Signale auf den Clients per RPC aus (z. B. `room_entered`, `run_ended`) |
| `SaveManager`, Meta-Progression | lokal | **bleibt lokal**: jeder bringt seine Dorf-Verbesserungen mit (`MetaProgression.apply_to_run` je Spieler auf dessen Rechner bzw. vom Host mit den gemeldeten Stufen) |
| `StatsTracker` (Chronik) | zählt lokale Signale | zählt weiter lokal; Kills ggf. nur die eigenen |
| Schwierigkeit | für einen Spieler | Gegner-HP/Anzahl mit Spielerzahl skalieren (z. B. HP ×(1 + 0,5 je weiterem Spieler)) |

## 3a. Stand MP1 (14.10.2026)

MP1 ist ohne Netzwerk umgesetzt ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP1). Mit einem Spieler verhält sich das Spiel wie vorher.

| Baustein | Datei | Was |
| --- | --- | --- |
| `GameMode` | `scenes/game_mode.gd` | Sitzung: `SOLO`, `QUICK`, `GUILD`, Spielerzahl 1–4, IDs der Spieler an diesem Rechner. Liegt am `WorldController` (kein Autoload, D-044); überall abrufbar mit `GameMode.of(node)`, ohne WorldController (Hauptmenü, Unit-Tests) gilt Solo. Entscheidet `pauses_for_menus()` und `allows_hit_stop()` (nur Solo, D-123), `get_meta_source()` (Solo: lokaler Spielstand, Schnelles Spiel: keine Boni, Gilde: später MP8) und `create_input(id)`. |
| `PlayerInput` | `player/input/player_input.gd` | Eingabe eines Spielers je Physik-Frame: `move`, `aim_point`/`aim_direction`, `is_pressed`/`is_just_pressed` für Angriff, Spezial, Dash, Waffenwechsel, Benutzen. |
| `LocalKeyboardMouseInput` | `player/input/local_keyboard_mouse_input.gd` | Die heutige Steuerung: InputMap und Maus über den Viewport des Spielers. |
| `RemoteInput` | `player/input/remote_input.gd` | Von außen gefüllt (später das Netz beim Host, jetzt Bots und Tests): `set_move`, `set_aim_point`/`set_aim_direction`, `press`/`release`/`tap`, `set_held_actions` (ganzer Tastenstand wie aus einem Paket). |
| `Player`, `WeaponController` | `player/` | Lesen nur noch ihr `input`. `player_id`, `is_local` (Kamera, „E …“-Hinweis, Bildschirmwackeln nur beim lokalen Spieler), `set_protected(grund, an)`/`is_protected()` für den Menüschutz. |
| `WorldController` | `scenes/world_controller.gd` | `game_mode`, `players`, `local_player`; spawnt je Sitzungsmitglied einen Spieler am `PlayerSpawn` (Versatz `SPAWN_OFFSETS`, TESTWERT), den primären (lokalen) zuerst. Kamera, HUD, Sicht und Run-Rückblick hängen am lokalen Spieler; ohne lokalen Spieler (Host ohne eigenen Spieler) wird keine Oberfläche gebunden. Ist im Gruppenspiel ein Menü offen, ist der lokale Spieler geschützt. |
| `GameManager`, `HitStop` | `autoload/`, `components/visual/` | Pausengründe wie bisher; der Baum pausiert nur, wenn der Modus es erlaubt, `pause_changed` meldet „Menü offen“. HitStop nur im Solo. |
| `DungeonManager` | `dungeon/dungeon_manager.gd` | Alle Spieler bekommen Upgrade-Werte und das Tod-Signal; Kontext, Upgrade-Dialoge, Upgrade-Effekte und Dorf-Boni am primären Spieler. Der Run endet erst, wenn keiner mehr steht; Heilung alle N Räume und Boss-Intro-Sperre für alle; Raumgröße nach Spielerzahl (`RoomSequence.room_sizes_for`, D-084: ab 3 Spielern L). `CombatVariant.get_player_count()` liest die Spielerzahl aus `GameMode`. |

**Bewusst gemeinsam oder noch offen:** Run-Gold ist die gemeinsame Kasse (D-081, `RunManager`), egal wer die Münze aufsammelt. Es gibt einen `UpgradeManager` je Dungeon: Er dient dem primären Spieler, die anderen teilen dessen Waffenwerte, Kill-Belohnungen gehen an den primären Spieler (je Spieler ab MP3). Proviant-Boosts nimmt `RunManager.start_run` seit MP2 nur noch im Solo (Schnelles Spiel ohne Boni, D-081). Den Raumwechsel löst der erste Spieler im Eingang aus (Nachzügler-Regel offen). Gegner ignorieren geschützte Spieler noch nicht (Haken `Player.is_protected()` für `EnemyTargeting`). Lichtkreis nur am lokalen Spieler; ohne Netzwerk tragen alle Figuren das Aussehen des lokalen Spielstands, im Raum jeder sein eigenes (MP2, `Player.appearance`). Wiederbeleben fehlt (MP5); bis dahin gilt ein gefallener Spieler als tot.

**Lokaler Mehrspieler-Test** (ohne Netzwerk, kein Fenster):

```text
godot --headless --fixed-fps 60 --path . -s tools/mp_local_sim.gd -- players=2 rooms=5
```

`players=1..4`, `rooms=1..14`. Startet ein Schnelles Spiel mit Spieler 0 als lokalem Spieler; die anderen sind Bots über `RemoteInput` (laufen zum nächsten Gegner, zielen, greifen an, nutzen den Spezialangriff). Die Gruppe geht durch die Räume, prüft unter anderem: Kamera und HUD nur beim lokalen Spieler, Gegner zielen auch auf Mitspieler, Menüs pausieren nicht und schützen den lokalen Spieler, `Engine.time_scale` bleibt 1, der Run läuft weiter, solange einer steht. Grundlage für die Balance-Tests mit mehreren Spielern (D-084, MP5).

## 3b. Stand MP1b und MP2 (14.10.2026)

MP1b (API-Client) und MP2 (Raum mit Raumcode, zusammen im Dorf) sind über den Relay gebaut ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP1b, MP2). Alles liegt in `online/`; der Einzelspieler braucht nichts davon und bleibt ohne Server spielbar.

| Baustein | Datei | Was |
| --- | --- | --- |
| `OnlineConfig` | `online/online_config.gd` | API- und Relay-Adresse je Umgebung: Standard `http://localhost:8787` und `ws://localhost:8790/v1`, darüber Projekteinstellungen `soulwick/online/api_url`/`relay_url` (später je Export-Vorlage), `[settings]` in `user://online.cfg`, zuletzt die Kommandozeile `-- api=… relay=… dev_key=… name=… instance=N`. Den Relay meldet sonst die API (`GET /public/config`). `PROTOCOL_VERSION = 1` (gleich wie im Vertrag), Spielversion aus `application/config/version` (`0.9.0`). Speichert Geräte-ID (UUID, einmal je Installation) und Token mit Ablauf in `user://online.cfg` bzw. `online_<n>.cfg` je Instanz, nie im Spielstand. |
| `ApiClient`, `ApiResult`, `HttpTransport` | `online/api_client.gd` … | HTTP mit JSON, Bearer-Token, 5 s Zeitlimit (TESTWERT). Jeder Aufruf ist eine Koroutine und liefert ein `ApiResult` (nie eine Ausnahme): `unreachable`, `timeout`, `banned` (mit Grund und Ende), `unauthorized`, `no_dev_key` oder der Fehlercode der API. `login_dev` (mit Dev-Schlüssel), `login_device` (Gast-Anmeldung `POST /auth/device` ohne Schlüssel, P-028), `get_me`, `get_relay_token` (`GET /auth/token`), `get_public_config`, `get_health`, `post_run`. Ein 401 auf einem Aufruf mit Token meldet das Signal `unauthorized`. Keine E-Mail, kein Passwort (D-121). |
| `OnlineSession` | `online/session.gd` | Anmeldestand des Spiels: nutzt ein gespeichertes Session-Token weiter (prüft es mit `GET /me`), sonst `POST /auth/dev` bzw. `/auth/device` mit Name und Aussehen des Spielerprofils (D-152, §3g) und der Geräte-ID; liest danach `GET /public/config`. `ensure_relay_token()` liefert das kurzlebige Relay-JWT (siehe unten). Node unter der Spielszene, wird bei Bedarf angelegt (`OnlineSession.of(node)`), kein Autoload (D-044). |
| `RelayProtocol` | `online/relay_protocol.gd` | Konstanten und Rahmenformat des Relay-Vertrags (`lobby.ts`): 10-Byte-Kopf, Raumcode-Alphabet, Close-Codes, Fehlercodes. |
| `RelayPeer` | `online/relay_peer.gd` | `MultiplayerPeerExtension` über `WebSocketPeer`: `hello` → `welcome` → `create`/`join` → `created`/`joined` (Peer-ID: Host 1, Clients ab 2). Host: `peer_joined`/`peer_left` werden zu `peer_connected`/`peer_disconnected`; Client: nur der Host (Peer 1), alle Pakete gehen an ihn (`CLIENT_ROUTING=host_only`, SceneMultiplayer leitet mit `server_relay` weiter). `room_closed` oder eine geschlossene Verbindung beenden die Sitzung (D-123). |
| `LobbyClient` | `online/lobby_client.gd` | Schnittstelle für die Oberfläche: `create_room(mode, guild_id)` (`guild` braucht die Gilden-ID, sonst `no_guild`), `join_room(code)` (vor jeder Verbindung Anmeldung und Relay-JWT, das JWT geht in `hello.token`), `leave()`, `kick()`, `start_run()` (Haken für MP3); Signale `state_changed`, `room_changed`, `error(code)`, `session_ended(reason)`. Im Raum: `multiplayer.multiplayer_peer = RelayPeer`, Sitzung `GameMode.QUICK` (Gilden-Raum: `GameMode.GUILD` mit `guild_id`, `create_session_mode()`) mit `network = LobbyClient`, Dorf neu laden. Wunsch aus dem Hauptmenü: `request_launch()` (statisch) → das Dorf des neuen Spiels ruft `take_launch()`/`run_launch()`. Ende (Host weg, rausgeworfen, Relay-Neustart, Verbindung weg): zurück ins Solo-Dorf mit Hinweis. |
| `NetPlayers`, `NetPlayerState` | `online/net_players.gd`, `online/net_player_state.gd` | `MultiplayerSpawner` mit eigener Spawn-Funktion: Der Host erzeugt seinen Spieler sofort und den eines Clients, sobald dessen Profil (Name und Aussehen aus dem Spielerprofil, D-152) da ist. `MultiplayerSynchronizer` je Spieler (Position, Bewegung, Zielrichtung, gehaltene Tasten, 30/s). Der eigene Spieler eines Clients läuft lokal sofort los (leichte Vorhersage), schickt seine Eingabe an den Host und gleitet zur Host-Position zurück, sobald beide stehen; die anderen Spieler spielen die übertragene Eingabe nach (Lauf- und Dash-Animationen) und werden sanft zur Host-Position gezogen. „Benutzen“ (E) wird nie übertragen. Namensschilder in den Koop-Farben P1–P4 (HANDOUT). |
| `WorldController`, `GameMode` | `scenes/` | `register_player`/`unregister_player` für Spieler aus dem Netz, `GameMode.network`/`is_networked()`; im Raum spawnt der WorldController keine Spieler selbst und der Dungeon-Eingang zeigt „Noch nicht gemeinsam“ (gemeinsamer Run = MP3). `set_game_mode` wendet die Pausen-Regel sofort an. |
| Gildengebäude | `ui/menus/village_ui.gd` | Zeigt das Online-Menü (`OnlineMenu`, §3f): „Schnelles Spiel“ mit **Raum erstellen** (Raumcode groß, Spielerliste mit Name, Host, Plattform, Koop-Farbe; „Starten“, „Raum schließen“) und **Raumcode** (6 Zeichen, nur das eindeutige Alphabet, Großbuchstaben) + **Raum beitreten**; „Gilden“ mit der Gildenverwaltung. Texte `LOBBY_*`, `GUILD_*` (EN/DE). |

**Anmeldung mit Better Auth (Plattform P19, P-027; Spiel angepasst 15.10.2026).** Zwei Tokens:

1. **Session-Token** aus `POST /auth/dev` (später `/auth/steam`, `/auth/google-play`; Bodies unverändert `{name, deviceId}` + `x-dev-auth-key`): Better-Auth-Session `<token>.<signatur>`, 30 Tage fest ab Anmeldung, steht mit Ablauf in `user://online.cfg` und geht als `Authorization: Bearer` an alle Spieler-Routen (`/me`, `/runs` …). Der Relay nimmt es **nicht** mehr an.
2. **Relay-JWT** aus `GET /auth/token` (mit dem Session-Token): EdDSA, `aud` `soulwick-relay`, `sub` = Spieler-ID, 15 min. `LobbyClient` holt es vor jedem Verbinden zum Relay (Raum erstellen, beitreten, erneut beitreten) über `OnlineSession.ensure_relay_token()` und schickt es in `hello.token`. Es bleibt nur im Speicher und wird wiederverwendet, solange es noch mindestens 60 s gilt (TESTWERT `RELAY_TOKEN_MARGIN_SECONDS`; die Laufzeit wird zusätzlich auf 900 s ab Abruf begrenzt, falls die lokale Uhr nachgeht). Eine laufende Verbindung ist vom Ablauf nicht betroffen.

Fehler: **401** auf irgendeinem Aufruf mit Token (Session abgelaufen, widerrufen, Konto gelöscht) löscht das Session-Token samt `online.cfg`-Eintrag; `ensure_relay_token()` meldet sich dann **einmal** neu an (Dev-Login mit Dev-Schlüssel, sonst Gast-Anmeldung) und fragt erneut. Ist die Gast-Anmeldung auf dem Server aus (`403 guest_auth_disabled`), zeigt die Lobby den allgemeinen Anmeldefehler; ein zweites 401 zeigt `LOBBY_ERR_UNAUTHORIZED`. **403 `banned`** zeigt `LOBBY_ERR_BANNED` (kein erneuter Login). Lehnt der Relay das JWT ab (`unauthorized`, Close 4001), wird nur das zwischengespeicherte JWT verworfen, das Session-Token bleibt; der nächste Versuch holt ein neues. Alte Tokens aus der Zeit vor P19 lehnt die API mit 401 ab, das Spiel meldet sich dabei von selbst neu an.

Außerdem: `RunManager.start_run` nimmt Proviant-Boosts nur noch bei lokalem Fortschritt (Solo); im Schnellen Spiel bleiben sie für den nächsten Solo-Run liegen (D-081). `Player.appearance` färbt Mitspieler mit ihrem eigenen Profil.

**TESTWERTE (MP2):** Zeitlimit API 5 s; Verbindungsaufbau bis zum Raum 10 s, Bestätigung von „Verlassen“ 2 s; Synchronisation 30/s; Eingabe bei Änderung, sonst alle 10 Physik-Frames; Sprung zur Host-Position ab 96 px Abweichung, sonst Korrektur 10/s (Mitspieler) bzw. 8/s (eigener Spieler im Stand); WebSocket-Puffer 1 MiB.

**Zwei Spieler auf einem PC testen:**

1. Plattform-Repo: `bun dev` (API 8787, Relay 8790; Datenbank-Container `soulwick-postgres` vorher mit `bun run services:up`; nach P19 einmal `bun run db:deploy` und `bun run db:seed:dev`). Der Relay braucht die laufende API (`API_INTERNAL_URL`), weil er die JWTs gegen `GET /auth/jwks` prüft. Den Wert `DEV_AUTH_KEY` aus `soulwick-platform/apps/api/.env` einmal in `%APPDATA%/Godot/app_userdata/Soulwick/online.cfg` eintragen:
   ```ini
   [settings]
   dev_key="<DEV_AUTH_KEY>"
   ```
2. Godot-Editor: *Debug → Ausführungsinstanzen anpassen …* (englisch *Customize Run Instances …*): „Mehrere Instanzen aktivieren“, Anzahl 2; Instanz 1 Argumente `-- instance=1`, Instanz 2 `-- instance=2`. Jede Instanz hat damit eine eigene Geräte-ID und ein eigenes Konto (Name mit „ 2“), beide nutzen denselben Spielstand. F5 startet beide.
3. Instanz 1: Spielstand laden, ins Gildengebäude, **Raum erstellen**, Raumcode ablesen. Instanz 2: Gildengebäude, Raumcode eingeben, **Raum beitreten**. Beide laufen danach zusammen durchs Dorf; „Raum schließen“ beim Host beendet den Raum für alle.
4. Ohne Editor: zwei Terminals mit `godot --path . -- instance=1` und `godot --path . -- instance=2` (optional `api=… relay=… dev_key=…`).

**Automatisch** (zwei Headless-Prozesse, der Host startet den Client selbst):

```text
godot --headless --path . -s tools/net_smoke.gd -- api=http://localhost:8787 relay=ws://localhost:8790/v1 dev_key=<DEV_AUTH_KEY>
```

Prüft Anmeldung, Relay-JWT in `hello` (nicht das Session-Token; `aud`, `sub`), Raum erstellen und beitreten, Wiederverwendung des JWT beim erneuten Beitreten, zwei Spieler auf beiden Seiten, Eingabe des Clients kommt beim Host an und die Position zurück, sauberes Verlassen und erneutes Beitreten, „Host geht“ schließt den Raum für den Client. Schlechtes Netz: Relay mit `RELAY_SIM_LATENCY_MS=120` starten.

## 3f. Online-Menü und Gilden (D-147, 15.10.2026)

Ein Menü an zwei Orten: im Hauptmenü **Online spielen** (`ui/main_menu/online_panel.gd`; Name und Aussehen kommen aus dem Spielerprofil, D-152; braucht eine Welt zum Starten und lädt die von „Weiterspielen“) und im Dorf das **Gildengebäude** (`VillageUI.open_guild`). Beide nutzen `OnlineMenu` (`ui/menus/online/online_menu.gd`); die Daten holt `GuildDirectory` (`ui/menus/online/guild_directory.gd`).

| Bereich | Inhalt |
| --- | --- |
| Öffnen | Meldet sofort an (`OnlineSession.ensure_login` über das erste `GET /me/guilds`; Gast-Konto oder mit Dev-Schlüssel das Dev-Konto). Server weg → roter Satz „Der Server ist nicht erreichbar. Der Einzelspieler funktioniert weiter.“ + **Erneut versuchen**; das Menü bleibt bedienbar (Zurück, Esc). Mit `-- offline` sendet es nichts. |
| Reiter **Schnelles Spiel** | **Raum erstellen** (Relay `mode: quick`), Raumcode + **Raum beitreten**; im Raum (nur im Dorf) Raumcode groß mit **Kopieren**, Hinweis + Ping (`last_rtt_msec`, jede Sekunde nachgezogen), Spielerliste mit Koop-Farben, Host: **Starten** / **Raum schließen**. Ein Gilden-Raum heißt „Gilden-Raum · Name“ und zeigt nach einem Run „Letzter Run: +X Gold für die Gildenkasse (jetzt Y)“. |
| Reiter **Gilden** ohne Gilde | nur zwei große Knöpfe **Gilde erstellen** / **Gilde beitreten** |
| Reiter **Gilden** mit Gilden | „Deine Gilden (n/5)“, oben rechts **Gilde erstellen** / **Gilde beitreten** (gesperrt mit Hinweis bei `items.length >= maxGuilds`), darunter je Gilde eine Karte: [Kürzel], Name, eigene Rolle · Mitglieder n/30, Gildenkasse |
| Gilde gründen | Name (3–32 Zeichen), Kürzel (2–5, nur A–Z/0–9, wird groß geschrieben). Fehler stehen am Feld: `guild_name_taken` unter dem Namen, `guild_tag_taken` unter dem Kürzel, `guild_limit_reached` unter dem Formular |
| Gilde beitreten | Einladungscode (6–16 Zeichen, Groß/Klein egal; Leerzeichen und Bindestriche aus Discord werden entfernt). Fehler am Feld: `invalid_invite_code`, `already_member`, `guild_full`, `guild_limit_reached` |
| Eine Gilde (`GET /guilds/:id`) | Kopf: **Zurück**, [Kürzel] Name, eigene Rolle. Kasten: Einladungscode mit **Kopieren** und **Neuer Code** (nur wenn die API einen `inviteCode` liefert, also Gründer/Offizier; sonst „nur Gründer und Offiziere“), Gildenkasse und **Gilde verlassen** (Bestätigung; Gründer: „Die Leitung geht an den Offizier, der am längsten dabei ist (ohne Offiziere an das älteste Mitglied).“, wie die API nach P-102, letztes Mitglied: „Die Gilde wird aufgelöst.“). Darunter **Gilden-Raum erstellen** (Relay `create {mode: "guild", guildId}`) und Raumcode + **Beitreten** (Gilden-Raum beitreten; Nicht-Mitglieder bekommen `not_guild_member`). Zuletzt die Mitglieder (zweizeilig: Name, darunter Rolle und Beitrittsdatum) mit **Ernennen**/**Absetzen** (nur der Gründer, `PATCH /guilds/:id/members/:playerId {role}`) und **Entfernen** (Gründer: alle außer sich, Offiziere: nur Mitglieder; Bestätigung). |

- **Routen** (`contracts/guild.ts`, API 1.1.0) über `OnlineSession.call_api()` (vorher Anmeldung, nach einem 401 genau einmal neu anmelden und wiederholen; zu alte Spielversion sendet nichts): `GET /me/guilds`, `POST /guilds`, `POST /guilds/join`, `GET /guilds/:id`, `POST /guilds/:id/leave` (`disbanded` → „Die Gilde ist aufgelöst.“), `DELETE /guilds/:id/members/:playerId`, `PATCH /guilds/:id/members/:playerId`, `POST /guilds/:id/invite-code`, `GET /guilds/:id/progress` (nur für ältere Antworten ohne `progress`). Fehler als Satz: `GUILD_ERR_*`, sonst `LOBBY_ERR_*`.
- **Aus dem Hauptmenü:** Raum erstellen, Raum beitreten, Gilden-Raum erstellen oder beitreten lädt den Spielstand von „Weiterspielen“ und startet das Spiel; das Dorf führt den Wunsch aus (`LobbyClient.request_launch` → `VillageUI._resume_lobby` → `run_launch`) und öffnet das Gildengebäude ohne Erklärung, damit Verbinden und Fehler sichtbar sind.
- **Gilden-Raum und Run-Meldung:** Im Raum gilt `GameMode.GUILD` mit `guild_id` (keine Dorf-Boni, keine Proviant-Boosts, keine globale Pause; Gilden-Schmiede = MP8). Am Run-Ende meldet der Host `POST /runs` mit `mode: guild`, `guildId`, `participants`, `roomReached`, `durationSeconds`, `seed`, `gameVersion`, `endReason` (`portal|wiped|abandoned`), `remainingGold` und `reportId` (eine UUID je Run, bei der einen Wiederholung nach Netz-/Serverfehler dieselbe) – alles in `NetRun` (`report_body`), ausgelöst über `EventBus.run_ended`, also ohne Änderung an `net_dungeon.gd`. Die API zahlt 100 % (Portal) bzw. 50 % in die Gildenkasse; Runs unter `MIN_SECONDS_PER_ROOM` (8 s je Raum) markiert sie als „too_fast“ und zahlt 0. Die Antwort (`guildPayout`, `guildProgress`) schickt der Host an alle im Raum (`NetRun.share_guild_payout`); im Dorf erscheint oben kurz „Gildenkasse · +21 Gold für [DOCHT] · Kasse jetzt: 1271 Gold“ (`VillageUI._on_guild_payout`, auch wenn die Antwort erst nach dem Laden des Dorfs kommt).
- **Raum-Ende:** Schließt die Verbindung im Raum, nennt `LobbyClient` den Grund aus `RelayPeer.end_reason` bzw. `RelayProtocol.end_reason_for_close(code)` (`timeout`, `slow_consumer`, `host_left`, `rate_limited`, `banned`, `shutdown`, `disconnected`; Texte `LOBBY_ERR_*`).
- **Bedienung:** Jeder Knopf nimmt den Fokus (Pfeile/Steuerkreuz, Enter/A, goldener Rahmen), W/A/S/D bewegen ihn auch, Esc geht einen Schritt zurück (Formular/Gilde → Liste, Bestätigung → Gilde), oben schließt Esc das Menü. Touch: alle Knöpfe sind Tippflächen (Maus-Emulation). Im Dorf bleibt der Dialog auf dem Bildschirm (`OnlineMenu.VILLAGE_CONTENT_HEIGHT`, längere Ansichten scrollen); kein Menü pausiert selbst, im Dorf pausiert der Dialog nur im Einzelspieler (`GameMode.pauses_for_menus`).
- **Geprüft (16.10.2026):** `tests/unit/test_online_menu.gd` (35 Tests, Fake-Transport, kein Netz). Live gegen lokale API (1.1.0) und Relay mit bis zu drei Spielprozessen: Anmeldung beim Öffnen, Liste (Lumen: DOCHT Gründer, ASCHE Offizier), Gilde als Gründer/Offizier/Mitglied, gründen, `guild_name_taken`/`guild_tag_taken` am Feld, `invalid_invite_code`, beitreten per Code in Kleinbuchstaben, Code erneuern, Ernennen/Absetzen (PATCH), Entfernen (DELETE, `cannot_target_self`), verlassen (letztes Mitglied löst auf); Gilden-Raum aus dem Hauptmenü (Sitzung `GUILD`), Mitglied tritt bei, Nicht-Mitglied bekommt `not_guild_member`, Run mit 42 Gold aufgegeben → `guildPayout` 21, Kasse 1250 → 1271, Meldung „+21 Gold für [DOCHT]“ bei Host und Mitglied; Offline-Hinweis bei nicht erreichbarer API.

### Testanleitung für das Projektmitglied (Gilden, 15.10.2026)

**Vorbereitung lokal** (Plattform-Repo): `bun dev` startet API (8787) und Relay (8790); Datenbank mit `bun run services:up`, einmal `bun run db:deploy` und `bun run db:seed:dev`. Zwei Spiel-Instanzen wie in §3b (Editor: *Debug → Ausführungsinstanzen anpassen*, Argumente `-- instance=1` und `-- instance=2`, oder zwei Terminals mit `godot --path . -- instance=1` / `-- instance=2`). Ohne Dev-Schlüssel meldet sich jede Instanz als Gast an; mit `dev_key=…` und `name=Lumen` ist Instanz 1 der Seed-Spieler Lumen (nur, wenn ihre Geräte-ID `dev-device-00000001` ist), sonst ein neues Dev-Konto.

1. **Instanz 1:** Hauptmenü → **Online spielen** → Reiter **Gilden**. Ohne Gilde: **Gilde erstellen**, Name und Kürzel eintragen, **Gründen**. Die Gilde öffnet sich; **Kopieren** legt den Einladungscode in die Zwischenablage.
2. **Instanz 2:** **Online spielen** → **Gilden** → **Gilde beitreten**, Code einfügen (Groß/Klein egal), **Beitreten**. Prüfen: „Willkommen in …“, als Mitglied kein Einladungscode, keine Entfernen-Knöpfe.
3. **Instanz 1:** In der Gilde steht Instanz 2 als Mitglied; einmal **Ernennen** und **Absetzen** probieren. Dann **Gilden-Raum erstellen** → das Spiel startet, im Dorf öffnet sich der Gilden-Raum mit Raumcode.
4. **Instanz 2:** Hauptmenü → Gilde öffnen → Raumcode ins Feld neben **Gilden-Raum erstellen** → **Beitreten** (oder im Dorf über das Gildengebäude). Beide stehen im Dorf; der Raum-Dialog zeigt „Gilden-Raum · Name“, beide Spieler und den Ping.
5. Optional dritte Instanz (`-- instance=3`, nicht in der Gilde): denselben Code im Reiter **Schnelles Spiel** eingeben → „Nur Mitglieder dieser Gilde dürfen beitreten.“
6. **Instanz 1:** **Starten**, ein paar Räume spielen (mindestens 8 s je Raum, sonst zählt der Server den Run als zu schnell und zahlt nichts), Gold sammeln, dann per Portal raus oder aufgeben.
7. Zurück im Dorf erscheint bei beiden oben „Gildenkasse · +X Gold für [KÜRZEL]“ (Portal 100 %, sonst 50 % des Run-Golds). Im Online-Menü zeigt die Gilde die neue Gildenkasse.
8. Aufräumen: **Gilde verlassen** (als letztes Mitglied wird sie aufgelöst).

**Gegen die Dev-Instanz:** Ein Build mit `-Env development` (§3d) verbindet sich ohne weitere Einstellungen mit `api-dev`/`play-dev`; zwei PCs (oder zwei Instanzen mit `-- instance=1/2`) melden sich als Gäste an. Schritte 1–8 wie oben. Fällt der Server aus, zeigt das Online-Menü den Offline-Hinweis, der Einzelspieler läuft weiter.

## 3g. Profil, Figuren und Lobby-Plätze (D-152, 16.10.2026)

Ein Charakter je Konto: Name und Aussehen gehören dem Spieler, nicht dem Spielstand. Spielstände sind nur noch **Welten** („Welt 1“ oder ein eigener Name, wie Maps in Minecraft).

| Baustein | Datei | Was |
| --- | --- | --- |
| `PlayerLook` | `characters/player_look.gd` | Aussehen im API-Format von `PlayerAppearance` (contracts `common.ts`, P-034): `{character: wick\|ember\|moss\|frost, colors: {hair, outfit, skin, accent}}`, Indizes 0–7 (TESTWERT-Paletten, Index 0 = Farbe der Grafik). Färbt die Bögen einer Figur je Aussehen einmal auf der CPU um (Schlüsselfarben der Grafik, auch Seitenansicht) und hält sie im Speicher; keine Tint-Maske mehr nötig. Neue Figuren ohne Grafik = Grundfigur mit Kopf-Merkmal (Flammenschopf, Spitzhut, Bommelmütze). |
| `PlayerProfile` | `characters/player_profile.gd` | Name + Aussehen in `user://profile.cfg` (Instanz N: `profile_<n>.cfg`; Läufe mit `-s` im echten Ordner: `script_profile*.cfg`; `SaveManager.set_storage_root` verlegt es mit). Kein Autoload: `PlayerProfile.current()`. Änderungen melden `SaveManager.profile_changed`. |
| `ProfileEditor` | `ui/menus/profile/profile_editor.gd` | Ein Editor für Erststart („Wie heißt du?“), Hauptmenü („Figur“), Lobby (eigener Platz: „Aussehen ändern“) und Dorf (Spiegel neben dem Zuhause, Zuhause). Zeilen Name · Figur · Haare · Kleidung · Haut · Akzent; ↑/↓, ←/→, 1–8, Enter, Esc; Maus/Touch über Pfeile und Farbfelder. |
| `LobbySlot` | `ui/menus/online/lobby_slot.gd` | Ein Platz je Spieler im Raum-Dialog: Rahmen (eigener gold), Figur (idle), Name, Host-Krone, „Bereit“/„Kommt …“/„Im Run“, Ping-Balken; leere Plätze „Wartet auf Spieler …“ mit „Code teilen“. |

- **Anmeldung:** `POST /auth/device|dev {deviceId, name?, appearance?}` (nur beim Anlegen des Kontos wirksam; das Aussehen nur, wenn der Spieler schon eines gewählt hat). Danach `OnlineSession.sync_profile()`: kein lokales Profil → das des Servers übernehmen; lokal geändert und noch nicht gesendet (`name_dirty`/`look_dirty`) oder das Profil kennt dieses Konto noch nicht → `PATCH /me`; sonst **gewinnt der Server** (auf einem anderen Gerät geändert). Einfach gehalten: kein Zusammenführen einzelner Felder.
- **Ändern:** Speichern im Editor schreibt sofort lokal; ist eine Sitzung angemeldet, geht die Änderung mit `PATCH /me {name?, appearance?}` hinaus (nur was sich geändert hat). `429 name_change_limited` (höchstens 3 Namensänderungen in 24 h, contracts TESTWERT): Der Name bleibt der des Servers, der Editor zeigt „Namen kannst du in X h wieder ändern.“, das Aussehen geht in einer zweiten Anfrage allein hinaus. `400 validation_error` am Namen: Servername bleibt. Ohne Netz: „Gespeichert. Online kommt es bei der nächsten Anmeldung an.“
- **Im Raum:** Das Profil der Mitspieler trägt `look` (dazu wie bisher `character`/`color`). Ändert jemand sein Aussehen oder seinen Namen, schickt `NetPlayers` es an den Host (`request_look`), der es an alle in dieser Welt weitergibt (`apply_look`); wer die Welt später lädt, bekommt alle aktuellen Looks. Die Relay-Laufzeit jedes Rechners geht alle 2 s (TESTWERT) über den Host an alle (Ping-Balken).
- **Spielstand v4:** `[world] name` statt Spielername; Name/Figur/Farbe alter Stände wandern nach `[legacy_profile]` und werden beim ersten Start einmal als Vorschlag genutzt (Ablauf in `autoload/save_manager.gd`).
- **Geprüft (16.10.2026):** GUT `test_player_profile`, `test_player_look`, `test_profile_sync` (Fake-Transport) und die angepassten Menü-, Dorf- und Spielstand-Tests; live gegen die lokale API (Stand mit `PATCH /me`) und den Relay mit zwei Prozessen: Konto entsteht mit Name und Aussehen, drei Namensänderungen, die vierte → 429 mit `Retry-After` und Hinweis, Aussehen allein nachgeschickt; Raum mit zwei Spielern, Aussehens- und Namenswechsel kommen beim jeweils anderen an.

## 3c. Stand MP3: gemeinsamer Dungeon-Run (14.10.2026)

MP3 ist über den Relay gebaut ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP3, Regeln in **D-126**). Der Host rechnet alles, was im Dungeon passiert; Clients schicken ihre Eingabe und zeigen, was der Host schickt. Im Einzelspieler ist keine der neuen Klassen aktiv (alle Haken prüfen `net != null`).

| Baustein | Datei | Was |
| --- | --- | --- |
| `NetRun` | `online/net_run.gd` | Kind „NetRun“ des `LobbyClient` (gleicher Pfad auf allen Rechnern, überlebt Weltwechsel). Host: `start()` („Starten“ im Gildengebäude oder Dungeon-Eingang) schließt den Raum beim Relay (`start`), versteckt die Dorf-Spieler vor den Clients, schickt `begin_run(seed, spielerzahl, run-nummer)` und lädt den Dungeon. Zurück im Dorf schickt der Host `end_run` (Portal → `portal`, alle am Boden → `wiped`, sonst `abandoned`); der Relay meldet allen `run_ended`, der Raum ist wieder in der Lobby (Beitritte und „Starten“ gehen wieder). Client: hält die Pakete an (`set_delivering(false)`), bis der Dungeon geladen ist. `configure_world` gibt jedem Dungeon den Seed und ein `NetDungeon`. Nimmt die Profile der Clients an (Welt + Epoche = begonnene Runs; wer zwischen zwei Runs beitritt, bekommt die Run-Nummer per `sync_runs` und schickt sein Profil neu) und die Eingabe (`submit_input`), damit nichts an einem Knoten einer alten Welt verloren geht. Run-Bericht `POST /runs` (Modus `quick`; im Gilden-Raum `guild` mit `guildId`, `endReason`, `remainingGold`, D-147). |
| `NetDungeon` | `online/net_dungeon.gd` | Kind „NetDungeon“ des `DungeonManager`. Räume: RNG-Zustand je Slot und je gebautem Abzweigungsweg aus `DungeonManager.slot_rng_captured` (`prepare_slot_net`, seit Welle B, §3e), gewählter Weg (`branch_chosen_net`), Raum-Signatur (mit Modus-Aufbau), Raum starten (`activate_slot`, erst wenn alle lebenden Spieler drin sind), geschafft, Ausgang offen, Warte-Hinweise; Spieler: Werte 10/s, Treffer, am Boden/Wiederbeleben, Loadout (Waffen, Upgrade-Stapel; die aktive Waffe als Zustand im Spielerzustand), Menüschutz; Shop-Angebote und Käufe, Upgrade-Wahl je Spieler, Run-Ende (`run_over`). Prüfungsräume sind im gemeinsamen Run aus. |
| `NetEnemies` | `online/net_enemies.gd` | Gegner als Ereignis + Schnappschüsse (15/s), Treffer/Tod/Phase als Ereignis, Gegnergeschosse, Gegner-Explosionen, Münzen/Herzen, Kisten. Clients zeigen „Puppen“ (echte Gegner-Szene ohne KI) und spielen das Boss-Intro selbst. |
| `CoopRules` | `online/coop_rules.gd` | Zahlen und reine Regeln (D-084, D-126): Skalierung, Raumstart-Regel, Wiederbeleben, Auszahlung. |
| `NetPlayers`, `NetPlayerState` | `online/` | Der Synchronizer hängt jetzt am Spieler selbst, seine Sichtbarkeit bestimmt Spawn und Despawn je Client; Profil und Eingabe gehen über `NetRun`. |

**Raumwechsel (seit dem Online-Test 15.10.2026):** Der nächste Raum beginnt erst, wenn alle lebenden Spieler in ihm stehen; kein Countdown, kein Teleport. Wer drin ist, sieht „Warte auf <Name> …“, der Nachzügler „<Name> wartet im nächsten Raum – beeil dich!“ mit Pfeil. Gefallene werden beim Start hineingeholt (D-128). Die aktive Waffe reist als Zustand im Spielerzustand, nicht als Tastendruck.

**Haken in gemeinsamen Dateien (für den Merge):** `dungeon/dungeon_manager.gd` (`net`, `enter_room()`/`prepare_slot()` öffentlich, Prüfungen vor/nach `_prepare_slot`, beim Betreten, Ausgang öffnen, Upgrade-Wahl, `end_run`, lokaler Spieler wird `context.player`), `dungeon/rooms/room_controller.gd` (`remote_encounter`, `complete_remotely()`, seit den Plan-Räumen auch `apply_remote_progress()` und die `remote_encounter`-Abfrage in `start_encounter`/`check_completion`, §3e), `enemies/enemy_base.gd` (Schadenszahl nur über `DamageNumber.shows_hit_by`, Signal `emerge_started`, §3e), `player/player.gd` (`revive()`, `is_downed()`, Signal `revived`), `enemies/enemy_targeting.gd` (geschützte Spieler sind kein Ziel), `autoload/run_manager.gd` (`sync_from_host`, `sync_room`, `get_run_gold_earned`), `scenes/world_controller.gd` (`configure_world` vor `add_child`, nach dem Run ins Dorf), `ui/menus/village_ui.gd` („Starten“ aktiv). Kleinere: `HealthComponent.set_current`, `ShieldComponent.set_current`, `UpgradeManager.get_all_stacks/set_all_stacks/find_upgrade`, `UpgradeEffects.only_own_hits`, `EconomySystem.purchase_hook/purchase`, `GoldPickup.visual_only`, `DamageNumber.shows_hit_by`, `PostProcess` (Farbe kommt nach dem Wiederbeleben zurück), `ApiClient.post_run`.

**Zwei Spieler auf einem PC testen (MP3):** wie §3b Schritte 1–3 (Plattform starten, `dev_key` eintragen, zwei Instanzen mit `-- instance=1` und `-- instance=2`). Danach:

1. Instanz 1 (Host): im Gildengebäude **Starten** drücken (oder in den Dungeon-Eingang laufen). Beide landen in Raum 1; der Raum beginnt, sobald der zweite geladen hat.
2. Kämpfen: Beide sehen dieselben Gegner, Münzen landen in der gemeinsamen Kasse (HUD bei beiden gleich).
3. Raumwechsel: Einer läuft durch die offene Tür in den nächsten Raum → er sieht „Warte auf <Name> …“, der andere „<Name> wartet im nächsten Raum – beeil dich!“ mit Pfeil. Der Raum beginnt erst, wenn beide drin sind (kein Countdown, kein Teleport).
4. Nach Raum 3 wählt jeder sein Upgrade; die Tür öffnet erst, wenn beide gewählt haben (spätestens nach 30 s).
5. Am Boden: Fällt einer auf 0 HP, liegt er am Boden („Am Boden“); der andere stellt sich 2 s daneben → er steht mit 2 HP auf.
6. Ende: Portal (100 %) oder alle am Boden (50 %); beide sehen den Run-Rückblick und landen wieder im gemeinsamen Dorf. Schließt der Host den Raum mitten im Run, endet der Run beim Client mit 50 % und dem Hinweis „Der Host hat das Spiel verlassen“.
7. Mehrere Runs je Raum: Ist der Host zurück im Dorf, kann eine dritte Instanz (`-- instance=3`) mit demselben Raumcode beitreten und erscheint im Dorf; der nächste „Starten“ nimmt alle mit (Skalierung nach der neuen Spielerzahl). Während eines Runs lehnt der Relay Beitritte ab („Der Run läuft gerade …“).

**Automatisch** (zwei Headless-Prozesse über den Relay):

```text
godot --headless --path . -s tools/net_run_smoke.gd -- api=http://localhost:8787 relay=ws://localhost:8790/v1 dev_key=<DEV_AUTH_KEY> [rooms=5|16] [seed=N] [end=portal|host_leaves|client_leaves|two_runs]
```

Prüft auf beiden Seiten: gleicher Seed und gleiche Räume (Signaturen), Gegner nur beim Host und als Puppen beim Client (gleiche Anzahl, gleiche Tode), der Bot des Clients trifft über den Host, gemeinsame Kasse gleich, Raumstart-Regel (allein im nächsten Raum: kein Start, Warte-Hinweise), Upgrade-Wahl je Spieler (Stapel beim Host gleich), Shop-Kauf über den Host bzw. Waffenwahl (je nach Seed: 1 = Shop, 7 = Waffen bei 2 Spielern), am Boden und Wiederbeleben, Portal (100 %) bzw. Host/Client geht (50 %), Run-Bericht, zurück ins gemeinsame Dorf. `rooms=16` spielt bis nach dem ersten Boss und dem Lagerfeuer. `end=two_runs` (drei Prozesse): Run 1 wie `portal`, danach `end_run` (`run_ended` „portal“ bei allen, Raum wieder offen), ein dritter Prozess tritt im Dorf bei (Name und Kleidungsfarbe bei allen richtig, Run-Nummer übernommen), Run 2 mit drei Spielern (Skalierung 3, gleicher Seed), Räume 1–2, Portal, wieder `end_run`, Run-Bericht mit drei Teilnehmern.

**TESTWERTE (MP3, D-126):** Upgrade-Wahl 30 s, Warten auf Clients 30 s, Wiederbeleben 2 s / 56 px / 2 HP / 1,5 s I-Frames, Gegner-Schnappschüsse 15/s, Spielerwerte 10/s.

**Noch nicht repliziert (MP5):** die Minispiele (R4) sind seit Welle B repliziert (§3e, Tabelle „Raum-Modi“); Fallen-Takt und Abgrund-Stürze rechnet nur der Host; Flüche des Pakt-Altars und der Händler in der Geheimnische bleiben beim jeweiligen Rechner; kein Beitreten mitten im Run (nur zwischen zwei Runs im Dorf).

## 3d. Testversion für Freunde (MP4, 14.10.2026)

Ein Windows-Build (und Linux) als ZIP, der über den Relay der Umgebung `development` spielt ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP4, D-119, D-124). Voraussetzung auf der Serverseite: API und Relay laufen unter `api-dev.playsoulwick.com` und `play-dev.playsoulwick.com` (Plattform P2, P17, Domains P-018 und P-029). **Stand 14.10.2026:** beide Domains antworten noch nicht; der Build startet dann offline (Hinweis im Hauptmenü), Einzelspieler geht.

| Baustein | Datei | Was |
| --- | --- | --- |
| Export-Vorlagen | `export_presets.cfg` | „Windows Desktop“ (x86_64, PCK eingebettet, Produktname Soulwick, Version aus `application/config/version`, Symbol vorerst `art/ui/logo_square.png`), „Linux“ (x86_64) und „Linux Dedicated Server“ (für später, D-119; noch ohne Server-Code). Ausgeschlossen: `tests/`, `tools/`, `addons/gut/`, `docs/`, `.userdata/`, `builds/`, `*.md`; zusätzlich gepackt: `online/environment.cfg` und `*.json` (Animationsdaten der Gegner-Grafiken). |
| Umgebung je Build | `online/environment.cfg`, `OnlineConfig` | `env="development"` oder `"production"` → API, Relay und Website nach P-018 (`https://api-dev.playsoulwick.com`, `wss://play-dev.playsoulwick.com/v1`, `https://dev.playsoulwick.com`; Produktion ohne `-dev`, flache Namen wegen Cloudflare, Plattform P-029). Reihenfolge: Editor (und jeder Start mit der Editor-EXE) immer `local` = localhost; exportiert zuerst ein Feature-Tag `env_development`/`env_production` der Export-Vorlage, dann die Datei, sonst `development`. Darüber gelten wie bisher Projekteinstellungen, `user://online.cfg` und die Kommandozeile (`-- env=development` schaltet auch im Editor auf den Dev-Server). Den Relay ersetzt `relayUrl` aus `GET /public/config`, solange er nicht ausdrücklich gesetzt ist. |
| Versionsprüfung | `online/version_check.gd`, `ui/main_menu/main_menu.gd` | Beim Öffnen des Hauptmenüs liest `OnlineVersionCheck` im Hintergrund `GET /public/config` (ältere APIs: `GET /health`). Fußzeile unten rechts: Version und Umgebung („v0.9.0 dev“, in Produktion nur die Version), darunter „Online bereit“, „Offline · Einzelspieler geht“ oder „Bitte aktualisiere das Spiel (online ab vX)“ mit Link zur Website der Umgebung. Ist das Spiel zu alt, sind die Online-Funktionen gesperrt: „Online / Gilde“ zeigt „Update nötig“, `LobbyClient` lehnt Räume mit `update_required` ab (auch wenn die Sperre erst bei der Anmeldung bekannt wird). `-- offline` überspringt die Prüfung. Texte `ONLINE_*`, `LOBBY_ERR_UPDATE_REQUIRED`. |
| Build-Skripte | `tools/export_build.ps1`, `tools/export_build.sh`, `tools/build_readme.txt` | Exportieren nach `builds/<env>/<version>/<plattform>/` (gitignored), legen `LIESMICH.txt` dazu, starten den Windows-Build einmal headless (`--headless --quit-after 300 -- offline`, eigener Benutzerordner) und packen `Soulwick-<version>-<env>-<plattform>.zip`. Die Version muss `application/config/version` entsprechen. Ohne Export-Vorlagen brechen sie vor dem Export ab. |

**Bauen** (im Repo-Root):

```text
powershell -ExecutionPolicy Bypass -File tools/export_build.ps1                       # development, Version aus project.godot, Windows + Linux
powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Env production -Platforms windows
GODOT=/pfad/zu/godot tools/export_build.sh development 0.9.0 "windows linux"
```

Einmalig vorher: **Export-Vorlagen** für Godot 4.7.2 installieren (Editor → *Editor → Export-Vorlagen verwalten* / *Manage Export Templates* → *Herunterladen und installieren*, oder *Aus Datei installieren* mit `Godot_v4.7.2-stable_export_templates.tpz`). Sie liegen danach in `%APPDATA%/Godot/export_templates/4.7.2.stable/`. Ohne Skript: `godot --headless --path . --export-release "Windows Desktop" builds/development/0.9.0/windows/Soulwick.exe` (dann gilt das `env` aus `online/environment.cfg`).

**Anmeldung im Build (Gastkonto, Plattform P-028):** Ohne Dev-Schlüssel meldet sich der Build über `POST /auth/device` an: Name aus dem Spielstand, Geräte-ID (zufällige UUID, einmal je Installation in `user://online.cfg`). Jede Installation ist damit ein eigenes Gastkonto; später wird es per Link-Code mit Steam oder Google Play verknüpft. Ohne Verknüpfung geht das Gastkonto mit der Installation verloren. Der `DEV_AUTH_KEY` wird weiterhin **nie** in den Build gepackt (Tests prüfen `export_presets.cfg` und `environment.cfg`); mit `online.cfg` `[settings] dev_key=…` oder `-- dev_key=…` nutzt ein Build stattdessen den Dev-Login (z. B. um sich als Seed-Spieler anzumelden). Schaltet der Server die Gast-Anmeldung ab (`GUEST_AUTH_ENABLED=false`), geht online nur noch mit Dev-Schlüssel.

**So starten Freunde:** ZIP entpacken, `Soulwick.exe` starten (SmartScreen: *Weitere Informationen → Trotzdem ausführen*, der Build ist nicht signiert), Spielstand anlegen; der Name wird der Online-Name. Im Dorf ins Gildengebäude: Der Host wählt **Raum erstellen** und schickt den **Raumcode**, die anderen geben ihn ein und wählen **Raum beitreten**; der Host drückt **Starten**. Keine Portfreigabe, kein VPN, keine Zusatzsoftware.

**Was testen:**

1. Hauptmenü: unten rechts Version „v0.9.0 dev“ und „Online bereit“ (oder der Offline-Hinweis, wenn die API nicht erreichbar ist).
2. Raum erstellen und beitreten mit 2–4 Personen an verschiedenen Orten; Raumcode-Fehler (falscher Code, voller Raum).
3. Einen ganzen Run zusammen: Raumwechsel (der Raum beginnt, wenn alle drin sind), Upgrade-Wahl, Shop, Wiederbeleben, Boss nach Raum 15, Portal bzw. alle am Boden; danach gemeinsam zurück ins Dorf.
4. Abbrüche: Host schließt das Spiel, ein Client verliert das WLAN; was sieht der Rest?
5. Rückmeldung je Abend: Lag (spürbar? wann?), Abbrüche mit Uhrzeit, Fehler, Schwierigkeit, Spaß; dazu `godot.log` aus `%APPDATA%/Godot/app_userdata/Soulwick/logs/`. Auf der Serverseite die Relay-Metriken (Bytes/s je Raum) ansehen.

**Bekannte Grenzen (aus MP3, §3c, und den Plan-Räumen, §3e):** Minispiele (R4) laufen beim Host und werden gespiegelt, mit den kleinen Lücken aus §3e (Tabelle „Raum-Modi“); ab 3 Spielern vorerst S/M-Räume (keine L-Pläne); Quellen, die mehrere Gegner nacheinander bringen, öffnen beim Client sichtbar nur einmal; Slime-Sprungtöne fehlen beim Client; Fallen-Takt und Abgrund-Stürze rechnet nur der Host; Flüche des Pakt-Altars und der Händler der Geheimnische bleiben beim jeweiligen Rechner; Prüfungsräume sind im gemeinsamen Run aus; kein Wiederbeitreten mitten im Run (zwischen zwei Runs im Dorf geht es wieder); Balance der Skalierung und Lichtkreis je Spieler folgen in MP5. Außerdem: Build nicht signiert (SmartScreen-Warnung), Symbol ist ein 64×64-Platzhalter, keine automatische Aktualisierung (neue ZIPs von Hand verteilen; `minGameVersion` der API sperrt alte Builds online).

### Android-Testversion (CP2-Prototyp, 15.10.2026)

Eine APK für Freunde mit Android-Handy, die über denselben Relay mitspielen (gleiche Version = gleiche `protocolVersion`, also Koop mit PC-Spielern). Touch-Steuerung als Minimum aus [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) CP2.

| Baustein | Datei | Was |
| --- | --- | --- |
| Export-Vorlage | `export_presets.cfg` „Android“ | `com.webbude.soulwick`, Name Soulwick, `version/name` leer = `application/config/version`, `version/code` setzt das Skript (0.9.0 → 900), nur `arm64-v8a`, Berechtigungen `INTERNET` und `ACCESS_NETWORK_STATE`, Vollbild (immersive), kein Gradle-Build, Symbol `art/ui/logo_square.png` (Platzhalter). Gleiche Filter wie Windows, kein Feature-Tag: die Umgebung kommt wie bei Windows aus `online/environment.cfg`. Kein Schlüssel in der Vorlage. |
| Projekteinstellungen | `project.godot` | `rendering/renderer/rendering_method.mobile="gl_compatibility"` (OpenGL ES 3, läuft auch auf billigen Handys mit wackligem Vulkan; der PC bleibt Forward+), `rendering/textures/vram_compression/import_etc2_astc=true` (Pflicht für den Android-Export), `display/window/handheld/orientation=4` (Querformat, dreht mit dem Sensor). Alle Shader laden unter `gl_compatibility` ohne Fehler (Fensterlauf mit `--rendering-method gl_compatibility`, 15.10.2026). |
| Build-Skript | `tools/export_build.ps1`, `tools/export_build.sh`, `tools/build_readme_android.txt` | `-Platforms android` → `builds/<env>/<version>/Soulwick-<version>-<env>.apk` und `LIESMICH-android.txt` (Installation aus unbekannten Quellen, Steuerung, Online). Kein Boot-Test. Signatur: `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`, sonst für `development` der lokale Debug-Schlüssel; `production` bricht ohne echten Schlüssel ab. |
| Touch | `player/input/touch_state.gd`, `player/input/touch_input.gd`, `ui/touch/touch_overlay.gd` | siehe unten |

**Einmalig auf dem Build-PC** (Stand dieses PCs, 15.10.2026):

1. JDK 17 (`C:\Program Files\Java\jdk-17.0.5`), Godot-Export-Vorlagen 4.7.2 (enthalten `android_release.apk`).
2. Android-SDK nach `%LOCALAPPDATA%\Android\Sdk`: Command-line Tools von developer.android.com nach `cmdline-tools\latest`, dann
   `sdkmanager --sdk_root=%LOCALAPPDATA%\Android\Sdk --licenses` und
   `sdkmanager --sdk_root=… "platform-tools" "build-tools;35.0.1" "platforms;android-35"` (Godot-Doku 4.7) sowie `"build-tools;36.1.0" "platforms;android-36"` (die Vorlage zielt auf SDK 36; ohne 36 nimmt Godot 35.0.1 mit Hinweis). NDK und CMake braucht nur ein Gradle-Build (nicht genutzt).
3. Godot-Editor-Einstellungen (`%APPDATA%\Godot\editor_settings-4.7.tres`): `export/android/java_sdk_path` und `export/android/android_sdk_path` (Editor → Editoreinstellungen → Export → Android).
4. Debug-Schlüssel `%APPDATA%\Godot\keystores\debug.keystore` (Alias `androiddebugkey`, Passwort `android`; das Skript legt ihn mit `keytool` an, falls er fehlt). **Er gehört zu diesem PC:** Baut ein anderer PC die APK, müssen Freunde die alte App erst deinstallieren (Spielstand weg). Für den Store kommt ein eigener Upload-Schlüssel (CP7), nie ins Repo.

**Bauen:** `powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Env development -Platforms android` (≈ 1 Minute, APK ≈ 46 MB). Prüfen: `aapt dump badging <apk>` (Paket, `versionCode`, Berechtigungen, `native-code: 'arm64-v8a'`), `apksigner verify --print-certs <apk>`.

**Freunde installieren:** APK aufs Handy schicken, antippen, „Installation aus unbekannten Quellen“ für die öffnende App erlauben, Play-Protect-Warnung mit „Trotzdem installieren“ bestätigen. Android 7 oder neuer, 64-Bit. Updates: neue APK drüber installieren (Spielstand bleibt, solange derselbe Schlüssel signiert). Am PC mit USB-Debugging: `adb install -r <apk>`.

**Touch-Steuerung (CP2-Minimum):**

| Teil | Wie |
| --- | --- |
| Auswahl | `Player.input` (eine Stelle in `player/player.gd`): `TouchInput.adapt()` macht aus der lokalen Tastatur/Maus-Eingabe ein `TouchInput`, wenn das Gerät einen Touchscreen hat (`DisplayServer.is_touchscreen_available()`) oder `-- touch=1` gesetzt ist. Greift für Einzelspieler (`GameMode.create_input`), Dorf und Online (`NetPlayers`), ohne deren Code zu ändern. `RemoteInput` bleibt unverändert. |
| `TouchInput` | erbt von `LocalKeyboardMouseInput`: solange kein Finger benutzt wurde, genau die Desktop-Steuerung (Laptop mit Touchscreen). Nach der ersten Berührung **zwei Sticks (D-155)**: links laufen, rechts zielen; ab der Auto-Angriffs-Schwelle greift die Figur in Stick-Richtung automatisch an. Spezial-Knopf links, Dash, Benutzen, Waffe wechseln (Seitenansicht: Springen, Seiten-Dash) rechts; ein Tippen kürzer als ein Frame zählt trotzdem. Ohne rechten Stick gilt die Laufrichtung als Blickrichtung; die frühere Zielhilfe (200 px) ist entfernt. Tastatur oder echte Maus schalten zurück. |
| `TouchOverlay` | CanvasLayer 25 unter dem Root-Fenster (überlebt Szenenwechsel), nur sichtbar, wenn Touch aktiv ist und ein lokaler Spieler, der handeln kann, in den letzten 250 ms abgefragt wurde. Jedes offene Menü (`GameManager.is_game_paused()`, auch im Gruppenspiel ohne Pause), gesperrter Spieler (Intro, Spielerschutz), Hauptmenü, Tod: Overlay weg, gehaltene Knöpfe losgelassen, jedes Tippen geht an die Menüs (Godot `emulate_mouse_from_touch`, Standard an). Sichere Bereiche: auf Mobilgeräten auf `DisplayServer.get_display_safe_area()` beschränkt. |
| Belegung | Linke Hälfte (unter der oberen Leiste): schwebender Stick (Radius 90 px, Totzone 18 %). Rechts unten: **Schwert** = Angriff (halten = weiter angreifen), **Doppelpfeil** = Dash (Seitenansicht: **Pfeil hoch** = Springen, zusätzlicher Knopf **Doppelpfeil mit Strich** = Seit-Dash), **Stern** = Spezial, **Kreis mit Punkt** = Benutzen (E), **Kreispfeile** = Waffe wechseln. Oben Mitte: **Liste** = Upgrade-Übersicht (Tab), **Pause**. Nur Symbole, keine neuen Übersetzungsschlüssel. Knöpfe spiegeln ihre Aktion zusätzlich als `InputEventAction` (Intro überspringen, Menü-Tasten). |
| Testen am PC | `godot --path . -- touch=1` erzwingt das Overlay, die Maus wirkt dann als ein Finger (`emulate_touch_from_mouse`). Unit-Tests: `tests/unit/test_touch_input.gd` (simulierte `InputEventScreenTouch/Drag`, auch durch die Engine). |

**Noch nicht am Gerät geprüft (15.10.2026):** Bildrate (Sicht-Shader, Nachbearbeitung, Partikel unter OpenGL ES), Lage und Größe der Knöpfe auf echten Handys (Viewport 1280×720 mit schwarzen Rändern bei 20:9), Notch, Gefühl der zwei Sticks, Akku/Wärme, Verhalten beim Wechsel in den Hintergrund (Host am Handy = Raum weg nach D-085). Die HUD blendet im Touch-Modus die Tastaturhinweise aus und zeigt Symbole (GlyphText).

## 3e. Räume aus Plänen im gemeinsamen Run (14.10.2026)

Die Räume-Welle A (D-131–D-134: Räume aus Plänen, Gegner-Quellen, Intro und Aufgabenleiste, Licht) kam nach MP3 dazu. Was sich für den gemeinsamen Run geändert hat (Regeln weiter nach D-126: der Host rechnet, Clients zeigen):

| Was | Host | Client |
| --- | --- | --- |
| Raumwahl (Kampf-, Boss-, Miniboss-, Ruhe-Pläne je Biom) | wie im Einzelspieler | gleich, weil Boss/Miniboss/Ruhe ohne Zufallszug gewählt werden und der RNG-Zustand je Slot weiter mitkommt; die Raum-Signatur prüft es (0 Abweichungen in `net_run_smoke rooms=16`). |
| Gegner-Quellen (R2) | `SpawnSources` wählt Quellen und schickt die Gegner hindurch | baut dieselben Quellen (gleiche Pläne, eigener RNG aus Seed + Raumnummer), spawnt aber nie (`RoomController.remote_encounter`). `NetEnemies` meldet jeden Phasenwechsel einer Quelle des aktiven Raums (Warnung, Öffnen, Ruhe) → der Client spielt Licht, Ring, Ton und Tor-Animation an seiner gleichnamigen Quelle; die eigene Quelle eines Champions wird beim Client nachgebaut. |
| Erscheinen der Gegner | `Enemy.begin_emerge` (versteckt, passiv, unverwundbar) | Signal `Enemy.emerge_started` → `enemy_emerge` mit der Restzeit → die Puppe erscheint genauso (Aufsteigen, Hüpfen, aus der Wand); Schnappschüsse ändern ihr Bild erst danach. Puppen bleiben ohne Trefferzone (`PUPPET_INVULNERABLE`, Trefferzone nach dem Erscheinen wieder aus). |
| Slime-Sprünge (D-130) | `EnemyPack`, Landering | Landering kommt im Schnappschuss mit (`FLAG_HOP`), Höhe über die Sprite-Position. |
| Raum-Intro (R3) | `RoomIntro` hält den Kampf zurück | spielt das Intro selbst (Banner, 3-2-1), startet aber nichts; der erste Wellenstand des Hosts (`room_progress`) beendet ein noch laufendes Intro. Jeder Rechner sperrt beim langen Intro nur den eigenen Spieler (`NetDungeon._release_remote_players`). |
| Wellen und Aufgabenleiste | `RoomController`, `ArenaObjective` | `room_progress` (Welle, Wellen gesamt, lebende Gegner, Gegner der Welle) → `RoomController.apply_remote_progress`: Aufgabenleiste „Welle n/N · x Gegner“, „Welle n/N kommt …“ mit Gong, Wackeln bei neuer Welle. Abgeschlossen wird der Raum nur über `room_completed_net`; `check_completion` ist beim Client aus (auch für Varianten, die es sonst aufrufen). |
| Andere Raumziele (R4, noch keine) | `RoomObjective` mit `changed` | `objective_state` spiegelt Text, Fortschritt, Zeit, Gefahr und Ende in ein eigenes `RoomObjective` des Raums (wird angelegt, wenn es fehlt); das Arena-Ziel folgt stattdessen `room_progress`. |
| Raumgröße (D-084) | `DungeonManager.get_room_sizes()` | gleich. Die Plan-Räume haben noch **keine L-Vorlagen**: ab 3 Spielern gibt es deshalb vorerst S/M wie im Einzelspieler (vorher L). |
| Skalierung (D-084) | Gegnerzahl über die Encounter-Gruppe, HP beim Registrieren | – (mehr Gegner als Quellen-Plätze werden wie D-086 zu einer weiteren Welle) |

**Für neue Raum-Modi (R4) gilt im gemeinsamen Run:** Logik nur, wenn `room.remote_encounter` falsch ist (Host oder Einzelspieler); den Stand in ein `RoomObjective` schreiben (der Client bekommt ihn gespiegelt); Gegner nur über die Encounter-/Quellen-Wege oder `track_enemy` (dann kommen sie als Puppen an); Intro mit `RoomIntro.start` bitte so starten, dass es auch beim Client läuft (der Modus-Code läuft dort nicht, also z. B. aus dem Raum-Genre wie die Arena in `DungeonUI.show_room_genre`). Sonst laufen Modi beim Client nur lokal wie heute die Varianten.

**Noch nicht repliziert (Plan-Räume):** mehrere Gegner nacheinander aus derselben Quelle zeigen beim Client nur das erste Öffnen der Quelle (die Puppen erscheinen trotzdem einzeln); Sprung- und Landetöne der Slimes und `ability_used` fehlen beim Client; das Überspringen des Intros mit E gilt nur am eigenen Rechner (überspringt der Host, beginnt der Kampf für alle); Licht (R6) rechnet jeder Rechner selbst aus dem Raum (gleich, aber nicht geprüft); kein Nachholen von Quellen-Phasen für einen Client, der mitten im Raum fertig lädt.

**Geprüft (14.10.2026):** `net_run_smoke` zeigt zusätzlich „Wellenstand vom Host angekommen“, „Puppen aus Quellen erschienen“, „Quellen haben gewarnt und geöffnet“ und vergleicht die Zahl der Erscheinen auf beiden Rechnern; neue Unit-Tests `tests/unit/test_net_rooms.gd`.

### Welle B: Minispiele und Abzweigung ohne Aufploppen (14.10.2026)

Die Räume-Welle B (D-135–D-137: Minispiele `dungeon/modes/*` mit `RoomMode`/`ModeRegistry`, Türen zeigen den nächsten Raum, beide Wege einer Abzweigung stehen gebaut, `RoomVeil`) kam nach §3e dazu. Stand im gemeinsamen Run:

| Was | Host | Client |
| --- | --- | --- |
| RNG je Slot | `DungeonManager` hält den Zustand vor jedem Slot und jedem Abzweigungsweg fest (`slot_rng_captured(slot, way, state)`, `get_slot_rng_state`); `NetDungeon` schickt ihn mit Spielerzahl und gewähltem Weg (`prepare_slot_net(slot, way, state, option, count)`). Die eigene Zustandsübertragung von MP3 ist ersetzt. | setzt den Zustand im Haken `before_prepare_slot` direkt vor dem Festhalten; Slots baut er sofort, die beiden Wege einer Abzweigung, sobald beide Zustände da sind (`DungeonManager.prepare_branch_ways`, gleiche Reihenfolge und Kettenzustände wie beim Host). Prüft danach, ob sein festgehaltener Zustand dem des Hosts entspricht (`rng_mismatches`). |
| Abzweigung (R5) | beim Betreten des Abzweigungsraums baut der Host beide Wege (bis 4 lebende Räume); die Gruppe wählt an der Tür (D-105) → `branch_chosen_net(slot, index)`, danach Signatur des gewählten Wegs als Raum n+1 | baut dieselben Wege dunkel hinter den Türen (`RoomVeil`), wählt nie selbst (`BranchChoice` aus), übernimmt die Wahl des Hosts; der andere Weg blendet aus wie beim Host. |
| Raum-Signatur | Datei, Typ, Spezialtyp, Lage, Türen, Modus und **Modus-Aufbau** (`NetModes.layout_of`: benannte Objekte des Modus mit Lage, Seelen-Plätze, Einsturz-Felder, Geleit-Weg, Risse, Wächter-Plätze, Fluchtloch) – für jeden Slot, **jeden gebauten Weg** und den gewählten Weg | vergleicht alle (`signatures_checked`, `way_signatures_checked`, 0 Abweichungen in allen Läufen unten). |
| Vorgebaute Räume, Schleier, Türschilder | wie im Einzelspieler | gleich gebaut; jeder vorbereitete Raum (auch ein Weg) ist `remote_encounter`, startet also nie selbst einen Kampf; Schleier und Türschilder sind reine Optik. |
| Minispiele (R4) | Logik, Uhr, Schübe, Entscheidungen und Bonus nur hier; `NetModes` (`online/net_modes.gd`) schickt Banner (`CombatVariant.banner_shown`), Bonus (`mode_bonus`, immer vor `room_completed_net`), Start, Ereignisse und einen Zustand (10/s, nur bei Änderung) | baut den Modus beim Vorbereiten genauso (gleicher Seed), startet ihn nie (`CombatVariant.start()` bricht bei `room.remote_encounter` ab); eigene Entscheidungen sind abgeschnitten (Reliquien-Signale, E an Reliquie/Fackel → `request_action` an den Host, Totengräber-Eigenschaft aus), eigene Banner stumm (`banners_muted`), die des Hosts kommen. Intro: startet wie beim Host beim Betreten (`player_entered` feuert auf jedem Rechner); die Aufgabenleiste ist der gespiegelte `RoomObjective` (jetzt auch Titel-, Ziel- und Regel-Schlüssel, z. B. das Huhn beim Geleit; Gefahr kommt vom Host). |
| Bonus-Truhen | `spawn_bonus_chests` | stellt die Truhe an dieselbe Stelle, sobald der Bonus feststeht (beim Raumende bzw. bei Rettung/Überstanden); jeder Spieler öffnet seine eigene (Upgrade je Spieler wie D-126). Kristalle bucht nur der Host; ein Client gleicht seine Kasse nach jedem Raumende wieder mit dem Host ab. |

**Raum-Modi im gemeinsamen Run:**

| Modus | Repliziert (Client zeigt) | Nur Host | Lücken / ausgeschlossen |
| --- | --- | --- | --- |
| Flamme hüten (`flame`) | Flamme aus dem Aufbau; HP (Zustand) → Balken, Lichtradius, Erlöschen mit Verdunkeln; Banner, Bonus, Truhe | Schübe, welche Gegner die Flamme angreifen, Raidzeit, Kristall | – |
| Reliquie holen (`relic`) | Altar und Reliquien; je Reliquie liegt/getragen (von welchem Spieler)/auf dem Altar und Lage; der Träger ist auf jedem Rechner langsamer und greift nicht an (`LanternCarry`); E beim Client fragt den Host | Aufheben, Ablegen, Fallenlassen bei Treffer, Heimflug, Gräber brechen auf | Reliquie wippt beim Client nicht; Host nimmt E nur bis 140 px Abstand an (TESTWERT) |
| Risse schließen (`rifts`) | Risse sind Gegner → Puppen (Biomfarbe und Wandlage aus dem Plan nachgestellt); Leiste | Schübe durch die Wandtore, Zusatzrisse | – |
| Jagd (`hunt`) | Gekrönter und Wachen als Puppen; Fluchtloch (Ort, Öffnungsgrad, Schließen); Fangort für die Truhe | Flucht, Entkommen | Krone über der Puppe fehlt; Entkommen sieht beim Client wie ein Tod aus |
| Lichtfeuer (`lightfire`) | Ständer aus dem Aufbau; Entzünden als Ereignis (Treffer über die Host-Kopie, E fragt den Host); Dunkelheit und Lichtkreis je Rechner | Steinwächter (Puppen), Zusatzwächter | – |
| Geleit (`escort`) | Dorfbewohner und Weg; Weganteil (geglättet), Herzen, Stehen/Gehen mit Hilferuf, Rettung (Truhe, Dank) oder Fallen | Weg-Entscheidungen, Schübe, Köder | Rettung landet nur im Spielstand des Hosts (`RescueRecord`) – **offene Frage** |
| Seelen sammeln (`souls`) | Seelen erscheinen/genommen/verblassen als Ereignisse, Ringe laufen lokal, Rundenende mit Kristallen am Ausgang (beim Client nur Anzeige) | Aufnahme über die Füße der Spieler beim Host, Schübe, Buchung | – |
| Einsturz (`collapse`) | Platten; Felder gewarnt/gebrochen (Abgrund, Requisiten und Quellen sinken), überstanden → Truhe | Gegner fallen (Puppen über `enemy_died`), Landeplatz der Spieler | der eigene Spieler landet beim Client zuerst am letzten sicheren Platz, die Lage des Hosts korrigiert ihn |
| Elite-Nest (Abzweigung) | Gegner als Puppen, Banner, Truhe | Kristalle | – |
| Totengräber (Krypta-Eigenschaft) | Haufen und Aufstehen kommen als Puppen | alles | beim Client abgeschaltet |
| Wagnis-Altar | wie bisher je Rechner | – | Flüche bleiben beim jeweiligen Rechner (MP5) |

Ausgeschlossen ist kein Modus. Für Tests gibt es `NetDungeon.test_mode_table` (auf jedem Rechner vor dem ersten Slot) und in `net_run_smoke` die Optionen `modes=all|<ids>`, `mode_from=<raum>` (Standard 2) und `branch=1`.

**Geprüft (14.10.2026):** GUT inkl. neuer `tests/unit/test_net_modes.gd` (Aufbau gleich bei gleichem Seed, Client-Modus startet nie, Flamme, Seelen, Einsturz, Geleit, Reliquie/Fackel, Ziel-Schlüssel); `net_run_smoke` mit `modes=all branch=1 seed=4711` (Jagd, Lichtfeuer, Einsturz, Flamme; Abzweigung in Raum 8: beide Wege und der gewählte Weg verglichen, Wahl übernommen) und `modes=relic,rifts,escort,souls seed=1234` (alle vier Modi, gleicher Bonus auf beiden Rechnern), dazu die bisherigen Szenarien; Zahlen im Bericht der Integration.

### Makeover-Welle A: ein Tor, Kamera, Seitenansicht (15.10.2026)

Die Makeover-Welle A (D-138–D-144: Fels-Terrain und kleinere organische Räume, ein Tor pro Übergang mit 1-Kachel-Gang, Kamera 1,25×, Licht, Gang-Segmente in Seitenansicht, Dorf- und UI-Rework) kam nach Welle B dazu. Fels, Licht, Dorf und UI rechnet jeder Rechner selbst aus denselben Plänen; geändert hat sich der gemeinsame Run hier:

| Was | Host | Client |
| --- | --- | --- |
| Tor hinter dem Raum (M2, D-143) | `GateCloser` nur beim Host (`NetDungeon.close_gate_behind`, Haken in `DungeonManager.enter_room`): das Tor des verlassenen Raums schließt, sobald alle lebenden Spieler mindestens 8 px im Boden des neuen Raums stehen; danach `gate_closed(slot)`. Zähler `gates_closed_early` (Tor zu, obwohl jemand draußen stand) muss 0 bleiben. | baut keinen eigenen `GateCloser` (`RoomController.activate` schließt seit M2 nichts mehr) und schließt sein Tor, wenn der Host es meldet. |
| Raumwechsel mit 1-Kachel-Gang (`ExitRules.JOIN_OVERLAP`) | Regel D-126 unverändert (alle lebenden Spieler im Raum oder 10 s). Nachzügler landen hinter dem Tor: `NetDungeon.gather_point` nimmt Startplatz + Versatz nur, wenn der Punkt begehbarer Boden mindestens 8 px innen ist, sonst den Startplatz; wer innerhalb des 8-px-Rands steht, wird mitgeholt. Das Tor schließt im nächsten Physikschritt. | folgt `activate_slot` wie bisher. |
| Aufstehen hinter geschlossenem Tor (D-143, offener Koop-Punkt; Vorschlag „erscheint beim Team“ umgesetzt) | steht ein Spieler außerhalb des aktiven Raums auf (Wiederbeleben oder geschaffter Raum) und ist das Tor dahinter zu oder der Raum schon entladen, steht er beim nächsten stehenden Mitspieler (`CoopRules.rejoin_point`, Zähler `rejoins`). Ist das Tor noch offen, läuft er selbst. | Lage kommt über die Synchronisation (Sprung über 96 px). |
| Kamera (M4, D-140) | `CameraRig.set_targets_provider` am lokalen Spieler jedes Rechners (`NetDungeon.camera_targets_of`): Mitte aus dem lokalen Spieler (auch am Boden) und den stehenden Mitspielern höchstens 380×200 Welt-px entfernt (`CoopRules.CAMERA_KEEP`, TESTWERT). So bleibt der lokale Spieler mit Totzone und Vorlauf bei 1,25× im Bild; wer weiter weg ist, fällt aus der Mitte, bis er zurückkommt. Zoom, Überblick beim Betreten und Wackeln bleiben je Rechner. | gleich |
| Seitenansicht-Segmente: Planung (M5, D-144) | plant den Weg mit seiner Option „Seitenwege auslassen“ (`SideWays.plan(…, skip)`) und kündigt ihn an (`side_way_net(raum-slot, signatur)`; Signatur = Plan, Spiegelung, Biom, Grund, Segment-Seed, Slots, Münzzahl, `NetSide.signature_of`). | plant nur angekündigte Wege (`DungeonManager.plan_side_way`, eigene Option egal): gleicher Run-Seed + Slot geben über `SideRules.make_rng` denselben Plan und Seed; vergleicht die Signatur (`side.signature_mismatches`). |
| Seitenansicht-Segmente: Ablauf | sein Tor (`SideGate`, irgendein Spieler) nimmt **alle Spieler der Sitzung** mit (`DungeonManager.start_side_transit`) und meldet `side_transit_net`. Münzen und goldene Münze (Kasse über `pot`), Tür, Ende (der erste an der Tür beendet für alle), Rückholen nach 3 s außerhalb des Bilds (SideSegment-Catch-up) und die Segment-Gegner rechnet nur er; Schnappschüsse der Gegner 10/s, Tode als Ereignis (`online/net_side.gd`). Die Segmentkamera folgt der Mitte aller Spieler im Segment. | sein eigenes Tor wartet auf den Host; das Segment ist ein Bild: Physik von Segment und Gegnern aus, Münzen, Tür, Gegnerlage, Tode und Ende kommen vom Host (ein Ende vor dem eigenen Aufbau wird nachgeholt). Danach setzt der Übergang alle an den Startplatz des nächsten Raums wie beim Host. |
| Spieler in der Seitenansicht | `PlayerSideMotion` liest jetzt `player.input` (Sprung = Dash-Taste, Seiten-Dash = neue Aktion `side_dash`/Umschalt in `project.godot` und `PlayerInput.ACTIONS`, Bit 5); `NetPlayerState` sendet zusätzlich `vel` und `side` (aktiv, Leiter, Boden, Sprung, Grube, Blick nach links). | Mitspieler: Eingabe nachspielen, Geschwindigkeit vom Host, Leiter/Grube/Blickrichtung über `PlayerSideMotion.apply_remote_state`, Zug zur Host-Lage. Eigener Spieler: Korrektur nur, wenn beide Kopien stehen (nie im Sprung, auf der Leiter, in der Grube). Ist eine Kopie schon im Segment und die andere noch im Raum (oder umgekehrt), wird die Lage bis zu 2 s nicht übernommen (`VIEW_MISMATCH_GRACE`, TESTWERT). |

**Haken für den Multiplayer-Vertrag (Phase 2b/2c, nicht brechen):** `DungeonManager`: `enter_room` ruft bei `net != null` `net.close_gate_behind(previous, room)` statt `GateCloser.close_behind`; `_plan_side_way(room, next, ladder_way, forced) -> SideGate` ruft `net.after_plan_side_way(room, next, gate)`; `plan_side_way(room, next)` und `start_side_transit(gate)` öffentlich; `_on_side_gate_passed` fragt `net.allow_side_transit(gate)`; `get_session_players()`. `SideWays.plan(…, skip := is_skipped())` und Test-Hilfe `SideWays.force_for_tests`. `PlayerSideMotion._read_input` liest `player.input` (ein `input_source` hat Vorrang), `is_jumping()`, `apply_remote_state(climbing, in_pit, facing)`. `SideSegment`: Signale `finished`, `coin_collected`, `golden_coin_collected`, Kinder `Exit` (`SideExit.is_open`/`open()`), Münzen als `SideCoin`-Kinder (Lage = Kennung), Gegner in Bau-Reihenfolge (`SideEnemy.died`, `get_facing()`, `_facing`, Kind `Sprite`), `get_players()`, `camera_targets()`, `finish()`; Segment-Logik nur in `_physics_process` (der Client schaltet sie ab). `SideTransit`: macht nur aktivierte Spieler-Kameras wieder aktuell. `GateCloser.close_behind`/`gate_between`/`INSIDE_MARGIN`/`closed`.

**Noch nicht repliziert (Makeover):** Stacheln im Segment laufen je Rechner nach eigener Uhr (Schaden nur beim Host, beim Client um die Latenz versetzt); Gruben erkennt jeder Rechner für seine Kopien selbst (der Schaden kommt über die Werte vom Host, der Client zeigt kurz seinen eigenen); die Truhe im Segment öffnet jeder für sich (Upgrade je Spieler wie bei den Bonus-Truhen); Schwarzblende und Banner „Abstieg“ beim Client um die Latenz später; die Option „Seitenwege auslassen“ eines Clients gilt im Gruppenspiel nicht (der Host entscheidet); der Leiter-Weg einer Abzweigung ist noch nicht angeschlossen (M5 offen); das Aufstehen hinter einem geschlossenen Tor ist nur in Unit-Tests geprüft, nicht im Zwei-Prozess-Test.

**Tests:** `net_run_smoke` mit `side=1` (Test-Hilfe auf allen Rechnern: jeder Weg, der ein Segment sein darf, ist eins; bei `rooms=5` Raum 1→2 und 3→4): die Gruppe läuft ins Tor, der Host-Spieler und der Client-Bot laufen mit dem Autopiloten `SideBot` (der Client über `RemoteInput` und das Netz), beide kommen im nächsten Raum an. Geprüft: gleiche Seitenweg-Signaturen, beide Spieler im Segment und in seiner Kamera, Übergänge und Enden kommen an. In **jedem** Szenario zusätzlich: kein Tor schließt, solange ein lebender Spieler draußen steht, der Client schließt dieselben Tore, die Gruppenkamera hält beide Spieler. Unit-Tests `tests/unit/test_net_makeover.gd`.

**Geprüft (15.10.2026):** validate 0 Fehler; GUT mit `test_net_makeover` (9 Tests) grün; `smoke_test 47` 2× PASS, `combat_sim` PASS, `boss_sim` PASS (ein Lauf fiel zufallsabhängig an der Quellenprüfung „mehrere Quellen“ in einem kleinen Makeover-Raum, ohne Bezug zum Netzcode; 3 Wiederholungen PASS), `mp_local_sim` 2×5 und 3×14 PASS, `net_smoke` PASS; `net_run_smoke` `side=1` 4× (2–3 Segmente je Lauf, 0 Signatur-Abweichungen), `portal` 2×, `rooms=16` 4× (Lagerfeuer → Segment → Raum 16), `host_leaves` 2×, `client_leaves` 3×, `two_runs` 2×, `modes=all branch=1 seed=4711 rooms=16` 2× PASS; Tore: Host und Client je Lauf gleich viele (z. B. 16/16 bei `rooms=16`), nie eines zu früh.

### Makeover: Tunnel, Risse, Bonus-Truhen (15.10.2026)

Mit 7188dfa (M2 Tunnel, Risse ohne zweites Loch, Truhen nie auf Spielern) kam im gemeinsamen Run dazu:

| Was | Host | Client |
| --- | --- | --- |
| Gang als Tunnel (`PassageCover`, `DoorSigns.show_way` → `DoorView.build_lintel`) | Jeder Rechner baut den Fels über dem Gang selbst (gleicher Weg über `DungeonManager._dress_way`). Der Fels liegt über allen Figuren (`DoorView.LINTEL_Z` > `z_index` jedes `Player`), also ist **jeder** Spieler im Gang auf **jedem** Rechner verdeckt, eigene wie fremde. Nur Optik. | gleich |
| Namensschild im Tunnel | `NetDungeon._update_tunnel_tags` (jeder Physikschritt, Host und Clients): steht ein Spieler in einem Gang (`CoopRules.in_passage` mit `DoorView.get_passage_rects`, Ausgänge des aktiven und des vorigen Raums mit Fels), verschwindet sein Namensschild (`NetPlayers.set_tag_hidden`, Schild z 30 läge sonst über dem Fels). Das Wiederbelebungs-Schild bleibt (ein Gestürzter muss zu finden sein). Kamera und HUD unverändert. | gleich |
| Risse-Modus: kein zweites Loch | `RiftsMode._open_rift` blendet die Wandquelle aus (`SpawnSource.hide_opening`). | Die Riss-Puppe kommt über NetEnemies; `NetModes._on_node_added` markiert sie als Wandriss und ruft (verzögert, die Quellen werden evtl. erst gebaut) `NetModes.hide_rift_opening(mode, tile)`. Die Phasen vom Host (`warn`, `open(first)`, `settle`) ändern nur das Innere der Öffnung, die ausgeblendet bleibt. |
| Bonus-Truhen nie auf Spielern (`CombatVariant._tiles_around_players`) | nimmt alle lebenden Spieler der Sitzung (`EnemyTargeting.living_players`, auch entfernte). Jede Truhe meldet ihre Stelle (`mode_chest(slot, name, spot)`, `child_entered_tree` der Variante, vor `SortLift`). | stellt die Truhe selbst auf (wie bisher über `finish()` bzw. NetModes bei Escort/Einsturz), aber an die Stelle des Hosts: kam die Meldung vorher, beim Einhängen (`_on_client_chest`), sonst wird die stehende Truhe verschoben (`apply_chest`). Grund: die Spielerlagen weichen je Rechner um die Latenz ab, die eigene Rechnung gäbe eine andere Kachel. |

**Haken für den Multiplayer-Vertrag (nicht brechen):** `DoorView.get_passage_rects()`, `get_lintel()`, `LINTEL_Z` (Fels über allen Figuren); `Door.view`; `RoomController.get_exit_doors()`; `SpawnSource.hide_opening()`/`is_opening_hidden()`, `RiftsMode.get_wall_rift_tiles()`, `RoomMode.get_sources()`, Wandquelle `kind == RIFT_WALL` mit `floor_tile` = Risskachel; Bonus-Truhen als direkte Kinder der Variante mit festem Namen `BonusChest%d`, Lage vor `_ready` gesetzt.

**Tests:** `test_net_modes` (Truhe an der Stelle des Hosts, Wandriss ohne zweites Loch auch nach den Host-Phasen), `test_net_makeover` (Tunnel-Test und Namensschild). `net_run_smoke`: Client zählt Räume mit Fels über dem Gang (`STAT tunnels`, Pflicht ≥ 1 bei `portal` ab 3 Räumen) und prüft, dass ein Spieler im Gang kein Namensschild zeigt; bei `modes=…` stehen die Bonus-Truhen auf beiden Rechnern an derselben Stelle (`mode_chest_hash`).

**Noch offen:** Im Zwei-Prozess-Test werden die Spieler in den nächsten Raum gesetzt, laufen also nicht durch den Gang (`tunnel_frames` meist 0); das Verdecken selbst ist Zeichenreihenfolge und in Unit-Tests geprüft. Eine getragene Reliquie (`z_index` 2) läge im Gang über dem Fels (auch im Einzelspieler).

**Geprüft (15.10.2026, nach 7188dfa):** validate 0 Fehler; GUT 1242/1243 grün (1 ausstehend: API-Test ohne Umgebung); `smoke_test 47` 2× PASS, `combat_sim` PASS, `boss_sim` 3× PASS, `mp_local_sim` 2×5 PASS, `net_smoke` PASS; `net_run_smoke` je 2× PASS: `portal`, `rooms=16`, `two_runs`, `side=1`, `modes=all branch=1 seed=4711 rooms=16` (6/6 Truhen gleich, Fels in 16 Räumen beim Client), `modes=rifts,relic rooms=10` (2/2 Truhen gleich).

## 4. Schritte

Phasenplan mit Abnahmekriterien: [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md). Anforderungen: [PRD.md](PRD.md) Abschnitt 7.

## 4a. Erweiterung: Internet, Steam und Gilden (Plan, 13.10.2026; Netzwerk seit 14.10.2026 nach D-119 und D-124)

Zwei getrennte Systeme:

| | Echtzeit-Spiel | Gilden- und Ranglisten-Daten |
| --- | --- | --- |
| Inhalt | Bewegung, Gegner, Schaden | Gilden, Gildenfortschritt, Run-Berichte, Ranglisten |
| Server | Ein Spieler ist Host, kein eigener Gameserver; der eigene Relay `soulwick-relay` leitet die Pakete nur weiter (D-119) | eigene HTTPS-API mit Datenbank auf dem VPS mit Dokploy (D-083, Repo `soulwick-platform`, D-093) |
| Technik | Godot `multiplayer`-API über WebSocket (WSS) zum Relay | REST mit Spieler-Token; Anmeldung in der Testphase per Geräte-ID (`/auth/dev`), später Steam, Google Play, Game Center (D-121) |

Verbindungsart (D-119, D-124), die Spiellogik bleibt gleich:

1. **Relay** (Hauptweg): Raumcode, WebSocket über `online/relay_peer.gd`; in der Entwicklung gegen den lokalen Relay aus dem Plattform-Repo, auch mit mehreren Instanzen auf einem Rechner.
2. **ENet direkt / LAN** (optional): LAN-Tests und Entwicklung ohne laufenden Relay. Ein virtuelles LAN (früher als Weg für Freunde-Tests geplant) ist durch D-119 ersetzt.
3. **Steam** (MP6, Plugin GodotSteam) nur als Zusatz: Anmeldung, Freunde einladen und Beitreten über die Freundesliste mit dem Raumcode; die Verbindung läuft auch für Steam-Spieler über den Relay. Entwicklung mit der Test-AppID 480.
4. **Später**, ohne Umbau der Spiellogik: WebRTC-Direktverbindung, dedizierter Godot-Server.

**Regel:** Der Server-Code setzt keinen eigenen Spieler voraus. Dann ist später auch ein Headless-Server möglich.

## 5. Risiken

- Die **globale Pause** (D-043) und **HitStop** sind tief im Spielgefühl verankert und passen nicht zu Echtzeit-Koop.
- Viele Projektile/Gegner erzeugen Netzlast → Projektile nur als Spawn-Ereignis (Start, Richtung, Tempo) senden, nicht jede Position.
- Testaufwand: automatisierte Tests mit zwei Instanzen (`--headless`, Host + Client) einplanen.
