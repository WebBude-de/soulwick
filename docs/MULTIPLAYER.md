# Multiplayer – Architekturplan (in Vorbereitung)

> **Stand:** 13.10.2026 · **Status:** Planung, **nichts davon ist gebaut.** Im Dorf zeigt die **Gilde** bereits eine Lobby-Oberfläche („Lobby erstellen“, „Lobby beitreten (IP)“, Spielerliste), alle Knöpfe sind deaktiviert und als „in Vorbereitung“ markiert (D-078).
> Umfang beschlossen in D-080 … D-085 ([DECISIONS.md](DECISIONS.md)). **Abweichend von Abschnitt 3:** Im Multiplayer bringt niemand seine Einzelspieler-Verbesserungen mit, und Gold ist eine gemeinsame Kasse (D-081).

## 1. Ziel

- **Koop für 2–4 Spieler** im lokalen Netzwerk (LAN) oder per direkter IP; später über das Internet und Steam (Abschnitt 4a).
- Ein Spieler ist **Host** (Server + Spieler), die anderen sind **Clients**. Kein eigener Server-Dienst, keine Anmeldung, kein Matchmaking (passt zu ARCHITECTURE „keine Web-App, kein Backend“).
- Gemeinsamer Dungeon-Run; jeder behält seinen **eigenen** permanenten Spielstand.

## 2. Technik

| Baustein | Wahl | Begründung |
| --- | --- | --- |
| Transport | `ENetMultiplayerPeer` (Godot High-Level Multiplayer) | in Godot eingebaut, UDP, zuverlässige + unzuverlässige Kanäle |
| Autorität | **Host-Autorität** | Host simuliert Gegner, Schaden, Räume, Gold; Clients senden nur Eingaben |
| Replikation | `MultiplayerSpawner` (Spieler, Gegner, Projektile, Gold) und `MultiplayerSynchronizer` (Position, HP, Animation) | Standardweg in Godot 4 |
| Aufrufe | `@rpc` für Ereignisse (Treffer-Effekte, Dialoge, Run-Ende) | |
| Port | z. B. 24565, einstellbar | |

Ablauf: Gilde → „Lobby erstellen“ (`create_server`) oder „Lobby beitreten“ (`create_client(ip, port)`) → Spielerliste über `peer_connected`/`peer_disconnected` → Host startet den Run → alle laden `dungeon.tscn`, der Host verteilt den **RNG-Seed** (`DungeonManager.seed_value`).

## 3. Was im aktuellen Code netzwerkfähig werden muss

| Bereich | Heute | Später |
| --- | --- | --- |
| `WorldController` | spawnt **einen** Spieler aus `player.tscn` | `MultiplayerSpawner` spawnt einen Spieler je Peer; Kamera, HUD und Sicht nur für den lokalen Spieler |
| `Player` | liest `Input` direkt | nur der Besitzer (`is_multiplayer_authority()`) liest Eingaben und sendet sie; Host bewegt/validiert, Synchronizer verteilt |
| Gegner-KI (`enemy_base.gd`), Goldmünzen (`gold_pickup.gd`) | `get_first_node_in_group(&"player")` | **nächster lebender** Spieler; nur auf dem Host |
| `DungeonManager`, `RoomController`, `EnemySpawner` | lokal | nur Host entscheidet (Raumfolge, Spawns, Raum geschafft); Clients bekommen Ergebnisse. Ein Raumwechsel erst, wenn alle Spieler am Ausgang sind (oder Nachzügler teleportieren) |
| `DamageProcessor`, Hitbox/Hurtbox | lokal | Treffer nur auf dem Host berechnen, Ergebnis (`DamageResult`) per RPC für Effekte/Schadenszahlen |
| `GameManager`-Pause, `Modal` | Dialoge **pausieren das ganze Spiel** (D-043) | im Multiplayer keine globale Pause: Dialoge (Upgrade-Wahl, Shop) nur lokal, Spieler währenddessen unverwundbar; Pausemenü pausiert nicht |
| `HitStop` | ändert `Engine.time_scale` global | nur lokal-visuell oder im Multiplayer abschalten |
| `RunManager` (Run-Gold, Kristalle, Boosts) | ein Run-Konto | Entscheidung nötig: **gemeinsame Kasse** oder Gold je Spieler; Run-Ende vom Host an alle, jeder Client bucht seine Auszahlung **selbst** in seinem `SaveManager` |
| `UpgradeManager`, `WeaponController` | ein Spieler | je Spieler eigene Upgrades/Waffen; Upgrade-Angebote je Spieler |
| `EventBus` | lokale Signale | bleibt lokal; der Host löst die Signale auf den Clients per RPC aus (z. B. `room_entered`, `run_ended`) |
| `SaveManager`, Meta-Progression | lokal | **bleibt lokal**: jeder bringt seine Dorf-Verbesserungen mit (`MetaProgression.apply_to_run` je Spieler auf dessen Rechner bzw. vom Host mit den gemeldeten Stufen) |
| `StatsTracker` (Chronik) | zählt lokale Signale | zählt weiter lokal; Kills ggf. nur die eigenen |
| Schwierigkeit | für einen Spieler | Gegner-HP/Anzahl mit Spielerzahl skalieren (z. B. HP ×(1 + 0,5 je weiterem Spieler)) |

## 4. Schritte

Phasenplan mit Abnahmekriterien: [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md). Anforderungen: [PRD.md](PRD.md) Abschnitt 7.

## 4a. Erweiterung: Internet, Steam und Gilden (Plan, 13.10.2026)

Zwei getrennte Systeme:

| | Echtzeit-Spiel | Gilden- und Ranglisten-Daten |
| --- | --- | --- |
| Inhalt | Bewegung, Gegner, Schaden | Gilden, Gildenfortschritt, Run-Berichte, Ranglisten |
| Server | Ein Spieler ist Host, kein eigener Gameserver | eigene HTTPS-API mit Datenbank auf dem VPS mit Dokploy (D-083) |
| Technik | Godot `multiplayer`-API | REST, Anmeldung per Steam-Sitzungsticket |

Verbindungsart in Stufen, die Spiellogik bleibt gleich:

1. **ENet direkt / LAN**: Entwicklung, zwei Instanzen auf einem Rechner.
2. **ENet über virtuelles LAN** (z. B. Tailscale oder ZeroTier): Tests mit Freunden über das Internet ohne Portfreigabe und ohne Server.
3. **Steam** (Plugin GodotSteam, `SteamMultiplayerPeer`): Lobbys, Einladen über die Freundesliste, Steam-Relay. Entwicklung mit der Test-AppID 480.

**Regel:** Der Server-Code setzt keinen eigenen Spieler voraus. Dann ist später auch ein Headless-Server möglich.

## 5. Risiken

- Die **globale Pause** (D-043) und **HitStop** sind tief im Spielgefühl verankert und passen nicht zu Echtzeit-Koop.
- Viele Projektile/Gegner erzeugen Netzlast → Projektile nur als Spawn-Ereignis (Start, Richtung, Tempo) senden, nicht jede Position.
- Testaufwand: automatisierte Tests mit zwei Instanzen (`--headless`, Host + Client) einplanen.
