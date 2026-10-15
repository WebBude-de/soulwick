# ARCHITECTURE – Systemgrenzen, Szenen und Datenfluss

> **Stand:** 15.10.2026 · **Status:** Verbindliche Architektur, im Spiel umgesetzt (ROADMAP M0–M15, Ausbau in ROADMAP_AUSBAU). Abschnitt 6 nennt die ursprünglichen Ziel-Schnittstellen aus dem GDD; maßgeblich sind die Signaturen im Code.  
> **Quelle:** Überarbeitetes GDD Master 1.0, Kapitel 8, 10–15 (10.10.2026), ergänzt um spätere Entscheidungen (D-Nummern).

## 1. Anwendung („Apps“) und Laufzeit

**Eine Spielanwendung in Godot 4.7.2** (zuerst Windows-Desktop, später Android und iOS, D-119). Gameplay, Physik, UI und Speichern laufen vollständig im Spiel; es ist **ohne Server spielbar**. Die Online-Teile (Konto, Gilden, Ranglisten, Koop-Relay) liegen im eigenen Repo `soulwick-platform` (D-093, D-119) und sind optional: Jeder Aufruf aus dem Spiel darf scheitern, Spiellogik läuft nie auf dem Server.

```text
scenes/main.tscn  (Hauptmenü: ui/main_menu/)
          |
       scenes/game.tscn  (WorldController / aktive Welt)
          |
          +-- world/village/village.tscn
          +-- dungeon/dungeon.tscn
                  +-- DungeonManager
                  +-- RoomContainer (maximal 3 lebende Rauminstanzen)
                  +-- room_base.tscn / Vorlagen aus Plänen (dungeon/rooms/plans/)
```

`game.tscn` ist der Weltkontext; `village.tscn` und `dungeon.tscn` sind **unterschiedliche Welten**. Beim Wechsel Dorf ↔ Dungeon wird `player.tscn` neu instanziiert; beim Raumwechsel **innerhalb** des Dungeons bleibt die Spielerinstanz erhalten.

## 2. Domains / Verantwortlichkeiten (Single Source of Truth)

| Domain / Eigentümer | Besitzt | Besitzt ausdrücklich nicht |
| --- | --- | --- |
| `GameManager` (**Autoload**) | Spielphase, Pausengründe, Szenenwechsel | Run-Gold, Feind-KI |
| `RunManager` (**Autoload**) | Aktueller Run, Raumnummer, Run-Gold, Run-Abschluss/Quote | Preise, permanentes Gold |
| `SaveManager` (**Autoload**) | Versionsgeführter permanenter Spielstand, dauerhaftes Gold und Freischaltungen | Temporäre Waffen/Upgrades eines Runs |
| `EventBus` (**Autoload**) | Globale systemübergreifende Signale | **Keinerlei Gameplay-Zustand** |
| `WorldController` / `game.tscn` | Aktive Weltinstanz, Spielererzeugung bei Weltwechsel | Berechnung von Upgrades oder Shoppreisen |
| `DungeonManager` | Raumfolge, Auswahl der `.tscn`-Vorlagen, Platzierung, Raum-Streaming | Eigenständiges Gegner-Spawning |
| `RoomController` | Begegnungsstatus, Türen, aktive Gegner, Raumabschluss | Permanente Progression |
| `EnemySpawner` | Einmalige Anzahl-/Marker-/Gegnertypziehung pro Encounter | Raumtyp- und Run-Fortschritt |
| `WeaponController` | Zwei Slots, aktive Waffe, Auslösen von Angriffen | Finale Schadensermittlung |
| `UpgradeManager` | Runweite Upgrade-Stacks und Verfügbarkeit | Permanenter Speicherstand |
| `StatCalculator` | Einheitliche effektive Angriffs-/Waffenwerte | UI-Darstellung |
| `DamageProcessor` | Trefferberechtigung, Rundung, Schild/HP, Effektreihenfolge | Raum-Streaming |
| `EconomySystem` | Preislogik, Shopangebot, Kaufberechtigung/Transaktionsprüfung | Zweite Kopie von Run-Gold |
| `UIManager` | HUD, Menüs, Visualisierung und Eingaben | Autoritative Gameplay-Berechnungen |

**Regel:** Ein Zustand hat genau einen fachlichen Eigentümer. Andere Systeme lesen ihn über definierte, typisierte Methoden und reagieren auf Signale; sie halten keine unabhängigen autoritativen Kopien.

## 3. Verbindliche Verzeichnisstruktur

```text
res://
├── project.godot
├── scenes/                   # main.tscn (Hauptmenü), game.tscn
├── world/village/            # village.tscn, NPCs, Interaktionen
├── dungeon/
│   ├── dungeon.tscn          # DungeonManager, RoomContainer, Übergänge
│   ├── rooms/                # room_base.tscn, plans/, templates/, special/, trials/, campfire/, walls/ …
│   ├── modes/                # Minispiele (escort/, flame/, relic/, souls/, rifts/, hunt/, lightfire/, collapse/)
│   ├── variants/             # Wagnis-Altar, Elite-Nest, ältere Kampf-Varianten
│   ├── side/                 # Gang-Segmente in Seitenansicht (D-144)
│   ├── biomes/               # BiomeData je Biom (.tres)
│   ├── environment/          # TileSets, doors/, corridors/, deco/, traps/
│   └── spawning/             # enemy_spawner.gd, Gegner-Quellen
├── player/                   # player.tscn, Movement, WeaponController, Seitenansicht
├── characters/               # CharacterData (Held, Kleidungsfarbe)
├── enemies/                  # enemy_base, types/, data/
├── weapons/                  # weapon_data.gd, types/, data/, projectiles/
├── upgrades/                 # upgrade_manager, effects/, data/
├── economy/                  # economy_system, shop_offer, data/
├── meta/                     # Meta-Progression, Freischaltungen, Spielstände, Statistik
├── localization/             # translations.csv (en, de), Loc
├── components/               # health/, shield/, hitbox/, hurtbox/, combat/, visual/, audio/
├── ui/                       # main_menu/, hud/, menus/, options/, widgets/, damage_numbers/, boss_intro/
├── autoload/                 # game_manager, run_manager, save_manager, event_bus
├── art/                      # characters/, environment/, weapons/, ui/
├── audio/                    # music/, sfx/, ambient/
├── tests/                    # unit/ (GUT), manual/
├── tools/                    # Prüf-, Simulations- und Generator-Skripte
└── docs/
```

Unterordner dürfen passend ergänzt werden. **Nur die vier genannten Kern-Autoloads** sind vorgesehen. Dungeon-, Upgrade-, Economy- und UI-Manager sind **Feature-/Szenenkomponenten** und keine weiteren globalen Autoloads.

## 4. Zentrale Szenen und Nodes

| Szene | Erwartete Bausteine |
| --- | --- |
| `scenes/game.tscn` | WorldController, gemeinsamer Gameplay-Kontext |
| `world/village/village.tscn` | `TileMapLayer`, Buildings, NPCs, `DungeonEntrance` (`Area2D`), SpawnPoints |
| `dungeon/dungeon.tscn` | `RoomContainer`, `DungeonManager`, Übergangslogik, Effekte |
| `dungeon/rooms/room_base.tscn` | `Ground`/`Walls` (`TileMapLayer`), Doors, Gegner-Quellen bzw. `Marker2D`-Spawnpunkte (früher genau fünf, heute aus dem Plan, D-086, D-132), `EnemyContainer`, `EnemySpawner`, `RoomController` |
| `player/player.tscn` | `CharacterBody2D`, Visuals, Collision, Bewegung, Waffen, Health/Shield, Hurtbox |
| `enemies/enemy_base.tscn` | Visuelle/physische Basis, `HealthComponent`, Hitbox/Hurtbox, typabhängige KI |

Raumvorlagen sind eigenständig in Godot bearbeitbar. Der DungeonManager ist für die Rauminstanzen zuständig, **nicht** der EnemySpawner für die Raumliste oder das UI für den Encounter-Status.

## 5. Datenmodell und Persistenz

**Statische Definitionen:** Typisierte Godot-`Resource`-Klassen und `.tres`-Dateien, beispielsweise `WeaponData`, `UpgradeData`, `EnemyData`, Balancingparameter. **Kein JSON als Gameplay-Definitionsformat im MVP.** Technische Properties der Resources werden beim jeweiligen Feature finalisiert und validiert.

**Laufzeitstatus (nicht mit Resources verwechseln):**

| Modell / Status | Inhalte | Eigentümer | Persistiert nach Neustart? |
| --- | --- | --- | --- |
| `GameState` | Spielphase, Pausengründe | GameManager | Nein |
| `RunState` | Aktuelle Raumnummer, Run-Gold, Runstatus, aktive Run-Daten | RunManager | **Nein** |
| `PlayerState` im Run | HP, Schild, aktive Waffenslots, Attack-Status | Spieler/entsprechende Komponenten | **Nein** |
| `UpgradeState` | Upgrade-ID → aktuelle Stackzahl | UpgradeManager | **Nein** |
| `RoomState` | Raumindex, `PREPARED`/`ACTIVE`/`CLEARED`/`UNLOADED`, Encounter-Flag | DungeonManager / RoomController | **Nein** |
| `DamageData` | `amount`, `source`, `tags`, `origin` (`PRIMARY`/`SECONDARY`), `hit_id`, `knockback` | Angriffs-/Damage-Pfad | **Nein** |
| `PermanentSave` | Version, permanentes Gold, freigeschaltete Inhalte | SaveManager | **Ja** |

**Wichtige Invarianten:** Kein Run wird nach Programmneustart fortgesetzt; Run-Ende vergütet **höchstens einmal**; gespeicherte Dateien werden versioniert und validiert, fehlende oder defekte Dateien kontrolliert behandelt. **Speicherformat:** Godot-`ConfigFile` je Spielstand mit `[meta] version` und Migration älterer Stände (D-059, VORGESCHLAGEN; Code: `autoload/save_manager.gd`). Die Festlegung „kein JSON“ betrifft Godot-Gameplay-Resources, nicht das Speicherformat.

## 6. Interne „API“-Konventionen – keine HTTP-API

Godot-intern gelten **typisierte Methoden + Signale**, **keine REST-Endpunkte**:

1. **Zustand lesen:** Typisierter direkter Methodenaufruf (`get_current_room()`).
2. **Aktion ausführen:** Methode mit eindeutiger Erfolgs-/Fehlerrückgabe (`try_spend_run_gold(...)`).
3. **Zustandsänderung melden:** Signal **nach** erfolgreicher Änderung (`room_completed`, `weapon_changed`).
4. **Lokal kommunizieren:** Direkt gebundene Signale verwenden; **EventBus nur systemübergreifend**.
5. **Verträge ändern:** Schnittstellenänderung und Auswirkungen im Merge Request dokumentieren.

### Ziel-Schnittstellen (GDD-Designvertrag, noch nicht getestete Signaturen)

```gdscript
# Autoloads
GameManager.request_pause(reason)
GameManager.release_pause(reason)
GameManager.is_game_paused()
GameManager.change_scene(path)

RunManager.start_run()
RunManager.get_current_room()
RunManager.advance_room()
RunManager.add_run_gold(...)
RunManager.try_spend_run_gold(...)
RunManager.end_run(reason)

SaveManager.load_game()
SaveManager.save_game()
SaveManager.get_permanent_gold()
SaveManager.add_permanent_gold(...)
SaveManager.unlock_content(id)

# Domänendienste / Komponenten
DamageProcessor.process_hit(...) # exakte Signatur OFFEN
WeaponController.equip_weapon(weapon, slot)
WeaponController.switch_weapon()
WeaponController.get_active_weapon()
WeaponController.request_attack()
UpgradeManager.acquire_upgrade(...)
UpgradeManager.get_active_upgrades()
UpgradeManager.get_available_upgrades()
DungeonManager.prepare_next_room()
DungeonManager.activate_room(...)
DungeonManager.unload_unused_rooms()
RoomController.start_encounter()
RoomController.check_completion()
```

**Globale Signale** beispielsweise `room_entered`, `room_completed`, `weapon_changed`, `upgrade_acquired`, `run_ended`. **Lokale Signale** beispielsweise `health_changed`, `shield_changed`, `died`. Namen sind Designziele; Parametertypen, Fehlerformen und finale Signaturen vor Implementierung festlegen.

## 7. Wichtige Abläufe und Transaktionsgrenzen

### 7.1 Dungeon-Streaming (strikte Grenze: drei Instanzen)

- Raumstart: Raum 1 laden; bei Aktivierung Raum 2 vorbereiten.
- Raumzustände: `PREPARED` → `ACTIVE` → `CLEARED` → `UNLOADED`.
- Fenster um aktiven Raum N: höchstens `N−1`, `N`, `N+1`.
- Beim Betreten von N zunächst **N−2 vollständig entfernen**, **erst danach N+1 instanziieren**. `queue_free()` entfernt Nodes erst zum Frame-Ende: Die vierte existierende Rauminstanz muss auch temporär vermieden werden.
- Raumvorbereitung startet **keinen** Gegner-Encounter. Encounter startet beim ersten tatsächlichen Aktivieren des Raums genau **einmal**.
- `RoomController` meldet Raumabschluss genau einmal nach dem letzten erforderlichen Gegnertod; daraufhin Ausgang öffnen.
- Fehlerhafte Vorlagen/Marker niemals als erfolgreich abgeschlossenen Raum behandeln.

### 7.2 Spawn-Pipeline

```text
DungeonManager: Raumtyp + Vorlage
    -> RoomController: start_encounter() einmalig
    -> EnemySpawner: gültigen Raumtyp prüfen
    -> Anzahl und Wellen je Raumnummer (TESTWERTE, D-074, D-118)
    -> verschiedene Quellen/Marker ohne Zurücklegen wählen, bevorzugt hinter dem Spieler (D-132)
    -> Typ je Platz aus der Gegner-Tabelle des Bioms (D-075)
    -> EnemyContainer: Gegner instanziieren
    -> RoomController: Tode verfolgen -> room_completed einmalig
```

Miniboss/Boss haben **eigenen Encounter-Pfad**; Spezialräume bekommen **keinen normalen Wellenspawn**.

### 7.3 Schaden / Effekte

```text
Hitbox/Hurtbox-Kontakt
  -> Zielberechtigung + Hit-ID-Historie
  -> Unverwundbarkeit (ggf. blockiert, keine schadensabhängigen Folgen)
  -> StatCalculator: D_raw = (D_base + Σ flat) * (1 + Σ pct) * Π context
  -> DamageProcessor: einmalig auf 0,5 runden; gültiger Schaden min. 0,5
  -> Schild vollständig vor HP verrechnen
  -> Trefferfeedback, ggf. Spieler-Hit-I-Frames (0,5 s), Tod
  -> zulässige sekundäre Effekte, ON_KILL-Belohnungen
```

Die Herkunft `PRIMARY`/`SECONDARY` verhindert Rekursion. Ein sekundärer Treffer darf das Primärziel treffen, aber **keine neue sekundäre Explosion** auslösen. Ein Magierstab-Primär-AOE umfasst das direkt getroffene Ziel **einmal**. Sekundäre Kills gewähren die normalen ON_KILL-Heilungs-/Schildboni. **Hit-ID** gilt pro Angriffsinstanz; jeder Doppelschuss-Pfeil besitzt eigene Historie.

### 7.4 Gold und Shop – atomare Operationen

`EconomySystem` prüft Gültigkeit/Preis/Angebot; **`RunManager` führt Run-Gold**. Der Kauf wird nur als Gesamtaktion verbucht (Geld weg **und** Gegenstand erhalten, sonst keine Änderung). Bei Run-Ende berechnet RunManager die Quote **50 % (Tod/Abbruch)** oder **100 % (regulär)**; **SaveManager** sichert die dauerhafte Gutschrift **einmalig**. Bei ungeraden Beständen wird die 50-%-Auszahlung **aufgerundet** (D-062).

### 7.5 Pause / UI

`GameManager` hält **mehrere Pausengründe** separat. Simulation und sämtliche Gameplay-Timer/Projektile pausieren; UI bleibt trotz Pause bedienbar (entsprechender Godot-Process-Mode). Shop, Waffen-, Upgrade-Auswahl, Tab-Übersicht und Esc-Menü können unterschiedliche Pausengründe besitzen. Veraltete Gründe nach Szenenwechsel sicher entfernen.

## 8. Auth, Sicherheit und Entwicklungsumgebung

- **Authentifizierung:** Das Einzelspieler-Spiel braucht kein Konto. Anmeldung (Gerät, später Steam, Google Play, Game Center) gibt es nur für die Online-Teile; Ablauf und Verträge im Repo `soulwick-platform` (D-108, D-119).
- **Netzwerk-/Server-API:** HTTPS-API und WebSocket-Relay der Plattform, Quelle der Wahrheit sind die Verträge in `soulwick-platform/packages/contracts`. Keine Geheimnisse oder API-Schlüssel im Spiel-Repo; Spiellogik läuft nur beim Host (D-119).
- **Dateisicherheit:** Save-Daten validieren, Version überprüfen, fehlende/defekte Dateien kontrolliert behandeln; persistente Goldgutschrift nicht doppelt durchführen.
- **Dev-Umgebung:** Godot 4.7.2 stable, Standard-Build (D-051), GDScript, `.tres` und `.tscn` im Git; `.godot/` nicht versionieren; von Godot erzeugte `.uid`-Dateien im Git behalten.
- **Repository/Workflow:** privates GitHub-Repo `WebBude-de/soulwick`; Integrations-Branch `dev`, Feature-Branches von `dev`, Pull Request mit mindestens einem Review. Siehe [TECHSTACK.md](TECHSTACK.md) §3.

## 9. Nicht final spezifiziert

Im Code umgesetzt, aber nur als **Vorschlag** festgehalten und vom Team zu bestätigen: Speicherformat und Migration (D-059), Spezialraum-Portalziehung (D-058), eine Upgrade-Explosion je Angriffsinstanz (D-056), Physik-Layer (D-053). Weiter ohne Festlegung: gleichzeitige ON_KILL-Auslöser im selben Frame (heute seriell). Rückwärtsnavigation gibt es nicht (ein Tor pro Übergang, kein Zurück, D-143). Entschieden: Goldrundung aufrunden (D-062).

**Weiterlesen:** [PRD.md](PRD.md) · [TECHSTACK.md](TECHSTACK.md) · [ROADMAP.md](ROADMAP.md) · [DECISIONS.md](DECISIONS.md)
