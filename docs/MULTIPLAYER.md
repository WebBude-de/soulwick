# Multiplayer – Host-Modell und Regeln

> **Stand:** 17.10.2026 · **Gebaut:** MP1 bis MP4 (lokale Basis, Anmeldung, Raum mit Raumcode, gemeinsamer Run, Testversion), Online-Menü mit Gilden und Profil; Plan und Abnahme in [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md). Hier stehen **Absicht und Regeln**: wer was rechnet, was gespiegelt wird, was für neuen Code gilt und wie man testet. Wie es gebaut ist, steht im Code unter `online/` (D-178).
> **Entscheidungen:** D-080 bis D-085 (Umfang), D-119 und D-121 bis D-128 (Netz, Konto, Lobby, Run, Tore), D-147 (Online-Menü), D-152 (Profil), D-158, D-159 (Raumwechsel, Synchronisierung). Im Koop bringt niemand seine Dorf-Boni mit, und Run-Gold ist eine gemeinsame Kasse (D-081).

## 1. Ziel

- **Koop für 2–4 Spieler** über das Internet per **Raumcode** über den eigenen Relay (D-119, D-124); optional im LAN über ENet für Tests; Steam nur als Zusatz für Anmeldung und Einladungen (§4a).
- Ein Spieler ist **Host** (rechnet die Spielwelt und spielt mit), die anderen sind **Clients**. Kein Gameserver: Der Relay leitet Pakete nur weiter. Für Internet-Spiele meldet sich jeder mit seinem Soulwick-Konto an (D-121); der Einzelspieler braucht weder Konto noch Server.
- Gemeinsamer Dungeon-Run; jeder behält seinen **eigenen** dauerhaften Spielstand.

## 2. Technik

| Baustein | Wahl | Grund |
| --- | --- | --- |
| Transport | austauschbarer `MultiplayerPeer`; Hauptweg `online/relay_peer.gd` über WebSocket (WSS) zum Relay, ENet nur für LAN und Entwicklung | Spiellogik kennt den Transport nicht; WebSocket läuft auf allen Plattformen ohne Portfreigabe |
| Autorität | **Host-Autorität** | Host simuliert Gegner, Schaden, Räume, Gold; Clients senden Eingaben |
| Replikation | `MultiplayerSpawner`/`MultiplayerSynchronizer` für Spieler; Gegner als Schnappschüsse plus Ereignisse | Standardweg in Godot 4, wenig Last |
| Ereignisse | `@rpc` (Treffer-Effekte, Dialoge, Run-Ende) | |

Ablauf: Host erstellt einen Raum und bekommt einen Raumcode → Clients treten mit dem Code bei → Host startet den Run → alle laden den Dungeon, der Host verteilt den **Seed** und den RNG-Zustand je Raum.

## 3. Wer rechnet was

| Bereich | Host (und Einzelspieler) | Client |
| --- | --- | --- |
| Räume, Raumfolge, Abzweigungen | entscheidet aus Seed und RNG-Zustand je Slot | baut dieselben Räume nach, vergleicht Raum-Signaturen, startet nie selbst einen Kampf (`remote_encounter`) |
| Gegner, Treffer, Schaden, Tod | rechnet | zeigt Puppen ohne KI (Schnappschüsse 15/s, Ereignisse) |
| Spieler | übernimmt Eingaben, korrigiert Lagen, Werte 10/s | eigene Eingabe mit leichter Vorhersage, gleitet zur Host-Lage |
| Gold, Kristalle | gemeinsame Kasse | gleicht nach jedem Raum mit dem Host ab |
| Waffen, Upgrades, Shop | je Spieler; Käufe laufen über den Host | wählt selbst, der Host bestätigt |
| Minispiele | Logik, Uhr, Schübe, Bonus | Zustand gespiegelt in `RoomObjective`; Aktionen mit E sind Anfragen an den Host |
| Raumwechsel, Tore | Raum startet, wenn alle Lebenden drin sind oder nach 10 s Countdown (D-158); Tor schließt erst, wenn alle drin sind (D-128) | folgt |
| Pause, HitStop | keine globale Pause, wer ein Menü offen hat, ist geschützt; HitStop nur im Solo (D-123) | gleich |
| Auszahlung, Spielstand | Run-Ende an alle | jeder bucht seine Auszahlung im eigenen Spielstand |
| Licht, Fels, Deko, Kamera | jeder Rechner selbst aus denselben Plänen | gleich |

### 3a. Lokale Basis (MP1)

`GameMode` (am `WorldController`, kein Autoload) kennt Sitzung (Solo, Schnelles Spiel, Gilde), Spielerzahl und entscheidet `pauses_for_menus()` und `allows_hit_stop()`. Spieler lesen nie `Input` direkt, sondern ihr `PlayerInput` (Tastatur und Maus, Gamepad, Touch, `RemoteInput` für Netz und Bots). Kamera, HUD und Sicht hängen am lokalen Spieler.

### 3b. Anmeldung und Raum (MP1b, MP2)

- Alles Online liegt in `online/`; der Einzelspieler braucht nichts davon. Jeder Aufruf liefert ein Ergebnis statt einer Ausnahme und darf scheitern.
- **Zwei Tokens:** Session-Token der API (30 Tage, in `user://online.cfg`, nie im Spielstand) und ein kurzlebiges Relay-JWT (nur im Speicher, vor jedem Verbinden neu geholt). Ein 401 meldet einmal neu an, ein Bann zeigt den Hinweis. Keine E-Mail, kein Passwort (D-121).
- Im Relay ist der Host Peer 1; Clients schicken alles an den Host. Endet der Raum (Host weg, Verbindung weg, Neustart des Relays), geht es zurück ins Solo-Dorf mit Hinweis (D-123).
- **Host steht still** (Browser-Tab im Hintergrund, Hänger; D-183): Clients merken die Stille von Peer 1 (Spiel-Frames und Lebenszeichen des Hosts alle 80 ms auf Kanal 254, auch beim Weltwechsel; `HostStall`: ab 750 ms, nach angekündigtem Laden des Hosts bis 8 s Schonfrist), sperren den eigenen Spieler je Spieler (`host_stall`), lassen ihn einmal zur Host-Lage gleiten und senden die Eingabe nur noch 1×/s; ab 1 s „Warte auf den Host …“, ab 15 s „Raum verlassen“. Der Host lässt einen Client, von dem 500 ms nichts kam, stehen. Im Browser läuft das Spiel in einem Raum auch im versteckten Tab weiter (`WebKeepAlive`, `deploy/web/shell.html`); Safari/iOS und Handy-Browser im Hintergrund nicht.

### 3c. Gemeinsamer Run (MP3, D-126)

Der Host startet im Gildengebäude oder am Dungeon-Eingang; Upgrade-Wahl je Spieler (höchstens 30 s), Wiederbeleben durch Danebenstehen, Ende per Portal (100 %), wenn alle am Boden sind (50 %) oder wenn der Host geht (50 % mit Hinweis). Der Host meldet den Run an die API (`POST /runs`). Zahlen: `online/coop_rules.gd` (TESTWERT).

**Noch nicht repliziert / bekannte Lücken** (im Code unter `online/` und `dungeon/modes/` geprüft, 17.10.2026):

- Fallen-Takt und Abgrund-Stürze rechnet nur der Host; Flüche des Pakt-Altars und der Händler der Geheimnische bleiben beim jeweiligen Rechner (die Geheimnische selbst bricht bei allen auf); Prüfungsräume sind im gemeinsamen Run aus; kein Beitreten mitten im Run (nur zwischen zwei Runs im Dorf).
- Gegner-Quellen: Mehrere Gegner aus derselben Quelle zeigen beim Client nur ein Öffnen; lädt bei zwei oder mehr Clients einer mitten im Raum fertig, bekommt er die Quellen-Phasen davor nicht nach (die Gegner schon).
- Slimes: Sprung- und Landetöne und `ability_used` fehlen beim Client.
- Intro: Überspringen mit E gilt nur am eigenen Rechner (überspringt der Host, beginnt der Kampf für alle).
- Jagd: Die Krone über der Puppe des Gekrönten fehlt (der Client entfernt seine eigene Kopie samt `BountyFlight`); Entkommen sieht beim Client wie ein Tod aus (der Host meldet es als `enemy_died`).
- Reliquie: wippt beim Client nicht (ihre Physik ist dort aus); getragen liegt sie im Gang über dem Fels (`z_index` 2 über `DoorView.LINTEL_Z`, auch im Einzelspieler).
- Einsturz: Der eigene Spieler landet beim Client zuerst am letzten sicheren Platz, die Lage des Hosts korrigiert ihn (den Landeplatz wählt der Modus nur beim Host).
- Licht rechnet jeder Rechner selbst aus dem Raum: gleich, aber nicht in der Raum-Signatur geprüft. Schwarzblende und Banner „Abstieg“ vor einem Segment kommen beim Client um die Latenz später.
- Testlücken: Das Aufstehen hinter einem geschlossenen Tor (D-128) ist nur in Unit-Tests geprüft, nicht in `net_run_smoke`; dort werden die Spieler in den nächsten Raum gesetzt und laufen kaum durch den Gang (das Verdecken im Tunnel prüfen nur Unit-Tests).

### 3d. Testversion für Freunde (MP4)

Builds gibt es je Server-Umgebung (`development` gegen `api-dev`/`play-dev`, `production`), festgelegt in `online/environment.cfg` beim Export. Das Hauptmenü prüft die Version; zu alte Builds sind online gesperrt, der Einzelspieler geht immer. Ohne Dev-Schlüssel meldet sich jede Installation als Gast an; der Dev-Schlüssel kommt **nie** in einen Build. Bauen, Android und Verteilen: [RELEASE.md](RELEASE.md).

### 3e. Räume, Minispiele und Makeover im gemeinsamen Run

- Der Host hält den RNG-Zustand vor jedem Slot und jedem Abzweigungsweg fest und schickt ihn; der Client baut damit dieselben Räume, Modi und Seitenwege und vergleicht Signaturen (0 Abweichungen ist Pflicht).
- Minispiele laufen nur beim Host; Banner, Bonus, Truhen-Stellen und der Zustand (`RoomObjective`) kommen beim Client an. Das Intro läuft auf jedem Rechner selbst.
- Tore schließt nur der Host; wer hinter einem geschlossenen Tor aufsteht, erscheint beim nächsten stehenden Mitspieler (D-128).
- Seitenwege geht die Gruppe gemeinsam; ob sie ausgelassen werden, entscheidet die Option des Hosts. Die Kamera zeigt im Koop die Mitte aus lokalem Spieler und nahen Mitspielern, der lokale bleibt immer im Bild.
- OFFEN: Eine Rettung im Geleit landet nur im Spielstand des Hosts.

### 3f. Online-Menü und Gilden (D-147)

Ein Menü an zwei Orten: Hauptmenü „Online spielen“ und Gildengebäude im Dorf (`ui/menus/online/`). Ist der Server weg, sagt es das und der Einzelspieler läuft weiter. Gilden-Räume nur für Mitglieder; der Run zahlt 100 % bzw. 50 % in die Gildenkasse, zu schnelle Runs zählt der Server nicht. Gilden-Fehler stehen am Feld, nicht als Fenster.

### 3g. Profil und Welten (D-152)

Name und Aussehen gehören dem Spieler (`profile.cfg`), nicht dem Spielstand; Spielstände sind Welten. Lokal geändert und noch nicht gesendet → `PATCH /me`, sonst gewinnt der Server. Im Raum gehen Änderungen über den Host an alle.

## 4. Schritte

Phasenplan mit Abnahmekriterien: [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md); Stores und Crossplay: [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md).

## 4a. Verbindungsarten

1. **Relay** (Hauptweg, D-119): Raumcode, WebSocket; in der Entwicklung gegen den lokalen Relay aus `soulwick-platform`.
2. **ENet direkt / LAN** (optional): Tests ohne Relay.
3. **Steam** (MP6, GodotSteam) nur als Zusatz: Anmeldung, Freunde einladen mit dem Raumcode; die Verbindung läuft weiter über den Relay. Entwicklung mit der Test-AppID 480.
4. **Später**, ohne Umbau der Spiellogik: WebRTC-Direktverbindung, dedizierter Godot-Server. Deshalb setzt Host-Code keinen eigenen Spieler voraus.

Gilden, Ranglisten und Run-Berichte laufen getrennt davon über die HTTPS-API (`soulwick-platform`, D-083, D-093).

## 5. Risiken

- Die **globale Pause** (D-043) und **HitStop** gehören zum Spielgefühl im Solo und passen nicht zu Echtzeit-Koop: im Koop aus (D-123).
- Viele Geschosse und Gegner erzeugen Netzlast: Geschosse nur als Ereignis (Start, Richtung, Tempo, Aussehen) senden, nicht jede Position.
- Testaufwand: Jeder Netz-Umbau braucht den Zwei-Prozess-Test (§7).

## 6. Regeln für neuen Code (Multiplayer-Vertrag)

- Den Koop-Check aus [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) erfüllen (kein `get_first_node_in_group(&"player")`, Zufall nur über den Dungeon-RNG, Zustand am Spieler, keine globale Pause).
- Nichts hält das Spiel im Koop bei Fokus- oder Sichtbarkeitsverlust an oder drosselt es (auch nicht im Browser): Der Host rechnet für alle. Warten gehört je Spieler an den Spieler (`set_input_locked` mit eigenem Grund), nie in eine Pause (D-183).
- Raum- und Modus-Logik nur, wenn `room.remote_encounter == false` (Host oder Einzelspieler).
- Raumziele in ein `RoomObjective` schreiben (wird gespiegelt); Banner nur über `CombatVariant.show_banner`, Truhen über `spawn_bonus_chests`, Bonus über `set_bonus`.
- Gegner nur über Encounter, Quellen oder `track_enemy` erzeugen; dann kommen sie beim Client als Puppen an.
- Der Aufbau eines Modus (`_on_attach`) ist deterministisch: nur benannte Kinder, kein Dungeon-RNG außer dem Seed, keine Spielerpositionen. Intros über `player_entered`, damit sie auf jedem Rechner laufen.
- Raumgrößen über `DungeonManager.get_room_sizes()`, nie feste Größen; Haken des `DungeonManager` (`before_prepare_slot`, `after_prepare_slot`, `slot_rng_captured`, `prepare_slot`, `prepare_branch_ways`, `enter_room`, `plan_side_way`, `start_side_transit`) bleiben öffentlich.
- **Namen nicht umbenennen**, die `online/` benutzt (Methoden, Signale, Knotennamen in `dungeon/`, `enemies/`, `player/`): vorher `grep -rn "<name>" online/ tests/unit/test_net_*.gd`; wer umbenennt, zieht `online/` im selben Paket mit.
- Testskripte warten auf `room.state == CLEARED`, nicht auf „keine Gegner“.
- **Reihenfolge und Laufzeit (bricht kein grep):**
  - `DungeonManager._prepare_slot`: erst `net.before_prepare_slot(slot, option, way)`, dann den RNG-Zustand festhalten und `slot_rng_captured` senden (für jeden Slot und jeden Weg), zuletzt `net.after_prepare_slot(room, way)`.
  - `_prepare_branch_ways` baut die Wege in Index-Reihenfolge aus demselben Kettenzustand (gestaffelt ein Weg je Frame, gleiche Reihenfolge); der Client baut sie erst, wenn beide Zustände da sind.
  - An `room.completed` hängen in dieser Reihenfolge: die Variante (`CombatVariant`, beim Anhängen in `_prepare_slot`), dann `DungeonManager`, dann `NetDungeon` (`after_prepare_slot`). Darum geht `mode_bonus` immer vor `room_completed_net` hinaus, und `finish()` stellt beim Client dieselbe Truhe.
  - `RoomController.start_encounter` prüft `remote_encounter` vor `_encounter_started = true`, `check_completion` ebenso; beim Client schließt nur `complete_remotely()` den Raum ab.
  - `Enemy.emerge_started` kommt am Ende von `begin_emerge`; der Host verbindet sich schon beim Einhängen des Gegners (`node_added`).
  - Kennungen über Namen und Bau-Reihenfolge: `SpawnSource` heißt nach Art und Kachel bzw. Lage, Bonus-Truhen sind direkte Kinder der Variante mit dem Namen `BonusChest%d` und ihrer Lage vor `add_child`; im Segment zählen Gegner, Bröckelkanten, Geschütze und Stachelfallen nach Bau-Reihenfolge, Münzen nach ihrer Lage. Wer Namen oder Aufbau-Reihenfolge ändert, ändert die Kennungen auf allen Rechnern.
  - Vor `_ready` gesetzt: `SummoningRift.rift_color` und `in_wall` (der Client setzt sie in `node_added`).
  - Der Client schaltet Logik zur Laufzeit ab, deshalb gehört sie an diese Stellen: Logik von Segment und Segment-Gegnern nur in `_physics_process`, die der Reliquie in `Relic._physics_process`; der Totengräber hängt an `room.enemy_container.child_entered_tree` (der Client trennt genau diese Verbindung).
  - Bei `net != null` ruft `enter_room` `net.close_gate_behind(previous, room)` statt `GateCloser.close_behind`, `_plan_side_way` danach `net.after_plan_side_way`, und `_on_side_gate_passed` fragt vorher `net.allow_side_transit(gate)`.
  - Zeichenreihenfolge: `DoorView.LINTEL_Z` liegt über dem `z_index` jedes `Player` (Spieler im Gang verdeckt, Namensschild aus).

## 7. Testen

Godot immer leise starten (`--audio-driver Dummy`, AGENTS.md §7).

- **Ohne Netz:** `godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tools/mp_local_sim.gd -- players=2 rooms=5` (1–4 Spieler, Bots über `RemoteInput`).
- **Zwei Spieler auf einem PC:** Im Plattform-Repo `bun run services:up`, einmal `bun run db:deploy` und `bun run db:seed:dev`, dann `bun dev` (API 3101, Relay 3103). `DEV_AUTH_KEY` aus `soulwick-platform/apps/api/.env` einmal in `%APPDATA%/Godot/app_userdata/Soulwick/online.cfg` unter `[settings] dev_key="…"` eintragen (ohne Schlüssel meldet sich jede Instanz als Gast an). Im Editor *Debug → Ausführungsinstanzen anpassen*: zwei Instanzen mit `-- instance=1` und `-- instance=2` (eigene Geräte-ID und eigenes Konto je Instanz); ohne Editor zwei Terminals mit `godot --path . -- instance=1` bzw. `instance=2`. Instanz 1: Online spielen → Raum erstellen, Code ablesen; Instanz 2: Code eingeben → beitreten; Host drückt Starten.
- **Gilden von Hand:** Instanz 1 gründet eine Gilde und kopiert den Einladungscode, Instanz 2 tritt bei; Instanz 1 erstellt einen Gilden-Raum, Instanz 2 tritt mit dem Raumcode bei; ein paar Räume spielen (mindestens 8 s je Raum), Portal oder aufgeben → beide sehen „Gildenkasse · +X Gold“. Eine dritte Instanz außerhalb der Gilde wird abgewiesen.
- **Automatisch** (zwei Headless-Prozesse über den Relay):
  - `godot --headless --audio-driver Dummy --path . -s tools/net_smoke.gd -- api=http://localhost:3101 relay=ws://localhost:3103/v1 dev_key=<DEV_AUTH_KEY>`: Anmeldung, Raum, Beitritt, Eingaben, Verlassen.
  - `tools/net_run_smoke.gd` mit denselben Argumenten und `rooms=5|16`, `seed=N`, `end=portal|host_leaves|client_leaves|two_runs`, `modes=all|<ids>`, `branch=1`, `side=1`: ganzer gemeinsamer Run mit Signaturvergleich auf beiden Rechnern. Schlechtes Netz: Relay mit `RELAY_SIM_LATENCY_MS=120` starten.
- **Gegen den Dev-Server:** ein `development`-Build verbindet sich ohne Einstellungen mit `api-dev`/`play-dev`.
