# ROADMAP Crossplay – Steam, Google Play und App Store

> **Stand:** 14.10.2026 · **Status:** Zielbild vom Projektmitglied genannt (D-108, **VORGESCHLAGEN**), **noch nichts gebaut, Details OFFEN**. Kommt als eigene Phase **nach** [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) (Phase 3, D-106). Nur die Entscheidungen **CP0** fallen **vor MP2**, weil sie Lobby (MP2), Steam (MP6) und Anmeldung (MP7) verändern können. Das Plattform-Repo bereitet parallel nur die Datenbank vor (`soulwick-platform/docs/ROADMAP.md` P11, P-014).
> **Entscheidungen:** D-080 (Gruppenmodi), D-081 (getrennter Fortschritt), D-082 (Ranglisten), D-083 (Server, Host-Modell), D-084/D-085 (Koop-Regeln), D-093 (zwei Repos), **D-108** (Zielbild Crossplay) in [DECISIONS.md](DECISIONS.md). Plattform: `soulwick-platform/docs/PRD.md` §3.8, `ARCHITECTURE.md` §3 und §7, `DECISIONS.md` P-014.
> **Anforderungen:** [PRD.md](PRD.md) Abschnitt 7.1 und 7.6 · **Technik:** [MULTIPLAYER.md](MULTIPLAYER.md) · **Abhaken** nur mit Nachweis (Tests, Datum). Jedes Paket ist für **einen Agenten** geschnitten; Spiel- und Plattform-Teile werden getrennt vergeben.

## Überblick

```text
Steam (PC)              Google Play (Android)        App Store (iOS)
   │ Steam-Ticket           │ Play Games Services         │ Game Center
   ▼                        ▼                             ▼
┌───────────────────────────────────────────────────────────────────┐
│ Soulwick-Konto (players) ──── player_identities (1..n je Spieler) │  soulwick-api (Plattform-Repo)
├───────────────────────────────────────────────────────────────────┤
│ Lobbys mit Raumcode, Relay (CP3, OFFEN) ──── soulwick-relay       │  eigener Container (ändert D-083)
└───────────────────────────────────────────────────────────────────┘
   Das Spiel bleibt im Host-Modell: ein Spieler rechnet, der Relay leitet nur Pakete weiter.
```

| Paket | Ergebnis | Spiel? | Plattform? | Stores? |
| --- | --- | --- | --- | --- |
| **CP0** | **Entscheidungen** (vor MP2): Geschäftsmodell, Konto-Modell, Lobby/Relay, Reihenfolge, Touch, Altersfreigabe | – | – | – |
| CP1 | Soulwick-Konto und Identitäten (Steam, Google Play Games, Game Center, Geräte-ID), Verknüpfungscode, Konto löschen in-App | Konto-UI | ja | – |
| CP2 | Mobile-Build und Touch (Android/iOS-Export, virtueller Stick, Auto-Aim, UI-Skalierung, Leistung) | ja | – | Test-Builds |
| CP3 | Lobby- und Relay-Server (Raumcodes, Container `soulwick-relay`, NAT-Traversal) | ja | ja | – |
| CP4 | Stores (Steamworks, Google Play Console, App Store Connect; IARC/USK; Datenschutz-Labels; Screenshots/Trailer) | Export | Website-Badges | ja |
| CP5 | Cross-Progression (Cloud-Save über die API, Konfliktregeln) | ja | ja | – |
| CP6 | Geschäftsmodell und Käufe (OFFEN; Tabellen `purchases`/`entitlements` erst dann) | ja | ja | ja |

**Reihenfolge:** CP0 vor MP2. CP1 braucht den Server (MP7) und kommt vor jedem Store-Release. CP2 darf als **Prototyp nach MP1** vorgezogen werden, weil die Frage „Touch ja/nein“ nur mit echtem Spielgefühl zu beantworten ist (Vorschlag). CP3 nur, wenn CP0 sich für einen eigenen Relay entscheidet. CP4 nach MP10 (Steam) und CP2 (Mobil). CP5 nach CP1. CP6 nach CP0 und frühestens mit CP4.

**Warum eigenes Konto und eigener Relay (Empfehlung des Spiel-Orchestrators, Entscheidung in CP0):** Steam-Lobbys und Steam-Relay (MP6) funktionieren nur zwischen Steam-Konten. Ein Android- oder iOS-Spieler hat kein Steam, Google Play Games und Game Center kennen sich gegenseitig nicht. Crossplay braucht deshalb eine **plattformneutrale** Stelle, die alle kennen: ein Soulwick-Konto, an dem die Plattform-Identitäten hängen, und eine Lobby mit Raumcode, die über den eigenen Server läuft. Among Us macht es genauso (Raumcode + verknüpftes Konto). ENet (MP2) und Steam (MP6) bleiben für Entwicklung, LAN und reine PC-Gruppen bestehen; die Verbindungsart ist hinter `MultiplayerPeer` austauschbar ([MULTIPLAYER.md](MULTIPLAYER.md) §2).

## CP0 – Entscheidungen (vor MP2)

Nichts davon ist entschieden. Die Spalte „Empfehlung“ ist ein Vorschlag von Claude und ersetzt keine Entscheidung.

| # | Frage | Optionen | Empfehlung (Vorschlag) | Wer entscheidet | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | **Geschäftsmodell** | (a) mobil kostenlos, PC bezahlt (wie Among Us) · (b) überall kostenlos, Kosmetik später · (c) überall bezahlt | Keine ohne Zahlen. (a) ist am einfachsten (keine Käufe im Spiel), wirft aber die Fairness-Frage Käufer/Gratis-Spieler auf; (b) braucht Kosmetik-Content und Kaufabwicklung (CP6) | Projektmitglied mit dem Team (Rechte am Uni-Projekt, MP10) | **OFFEN** |
| 2 | **Konto-Modell** | (a) eigenes Soulwick-Konto, Plattform-Identitäten verknüpft · (b) nur Plattform-Konten, keine Verknüpfung (kein Cross-Progression) · (c) E-Mail/Passwort-Konto | (a): ohne E-Mail, ohne Passwort; Identitäten reichen, Verknüpfung per Code | Projektmitglied | **OFFEN** |
| 3 | **Lobby/Relay** | (a) eigener Lobby-/Relay-Server `soulwick-relay` mit Raumcodes · (b) Steam-Relay für PC plus eigener Relay nur für Mobil · (c) nur Steam (kein Crossplay) | (a): ein Weg für alle, Steam bleibt Zusatz für Einladungen; ändert D-083 | Projektmitglied (Betrieb, Kosten) mit dem Team | **OFFEN** |
| 4 | **Plattform-Reihenfolge** | (a) Steam zuerst, Mobil später · (b) alle gleichzeitig | (a): MP10 ist ohnehin zuerst; Mobil erst nach dem CP2-Prototyp | Projektmitglied | **OFFEN** |
| 5 | **Touch-Steuerung** für ein maus-gezieltes Spiel | (a) virtueller Stick + Auto-Aim/Zielhilfe + Angriffsknopf · (b) zwei Sticks (Bewegen, Zielen) · (c) kein Mobil, nur Controller/PC | Prototyp in CP2 entscheidet; (a) als Startpunkt, Zielhilfe nur auf Mobil als TESTWERT | Projektmitglied nach dem Prototyp | **OFFEN** |
| 6 | **Altersfreigabe** | IARC-Fragebogen (Google Play, App Store → USK/PEGI), Steam-Fragebogen | Pixel-Gewalt ohne Blut: vermutlich USK 12 / PEGI 12 (Schätzung, mit dem Fragebogen prüfen) | Team | **OFFEN** |
| 7 | **Ranglisten** (D-082) je Plattform oder gemeinsam | (a) gemeinsam mit Plattform-Kennzeichen am Eintrag · (b) je Plattform getrennt | (a), passt zum Crossplay-Gedanken; Zielhilfe auf Mobil muss dann sichtbar sein | Team | **OFFEN** |
| 8 | **Sign in with Apple** | nur Pflicht, wenn die iOS-App einen anderen Social-Login (z. B. Google) anbietet (App-Store-Regel 4.8) | Nur Game Center und Play Games als Plattform-Login, keinen Social-Login → kein Sign in with Apple nötig; mit dem Fragebogen in CP4 prüfen | Team (CP4) | **OFFEN** |

- [ ] Frage 1–8 beantworten; jede Antwort als D-Eintrag (VERBINDLICH oder bewusst „später“) in [DECISIONS.md](DECISIONS.md).
- [ ] D-108 auf VERBINDLICH setzen oder anpassen; D-083 („kein Echtzeit-Spielverkehr über den Server“) bei Antwort 3a ändern.
- [ ] [PRD.md](PRD.md) §7.6 (Steam) um die anderen Stores ergänzen, neuer Abschnitt §7.8 „Crossplay“; [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP2 (Raumcode statt nur IP?) und MP6 (Steam-Relay nur noch für PC-Gruppen?) anpassen.
- [ ] Plattform: `soulwick-platform/docs/PRD.md` §3.8 von OFFEN auf die getroffenen Antworten bringen.

**Dateien:** `docs/DECISIONS.md`, `docs/PRD.md`, `docs/ROADMAP_MULTIPLAYER.md`, `docs/MULTIPLAYER.md`, `docs/ROADMAP_CROSSPLAY.md`; Plattform `docs/PRD.md`.

**Fertig, wenn:** alle acht Fragen einen D-Eintrag haben und MP2 weiß, ob Lobbys über IP/Steam oder über Raumcodes auf dem eigenen Server laufen.

## CP1 – Soulwick-Konto und Identitäten

**Ziel:** Ein Spieler hat ein Soulwick-Konto mit beliebig vielen Identitäten (`steam`, `device`, `google_play`, `game_center`) und kann Geräte verknüpfen, ohne E-Mail oder Passwort. Grundlage ist `player_identities` aus P11 (Plattform); hier kommen die Routen und die Spiel-Oberfläche dazu.

**Plattform (`api-dev`):** `packages/contracts/src/auth.ts` (neu: `POST /auth/google-play`, `POST /auth/game-center`, `POST /me/link-code`, `POST /auth/link`, `DELETE /me/identities/:provider`), `apps/api/src/services/identities.ts`, `apps/api/src/routes/auth.ts`, `routes/me.ts`, `routes/admin/players.ts` (Identitäten anzeigen), Tests. **Spiel (`village-dev` oder `player-dev`, nach MP7):** `online/api_client.gd` (HTTP-Client aus MP7), `online/session.gd` (Konto und Token am lokalen Client, Node in `game.tscn`, kein neuer Autoload, D-044), `ui/options/account_panel.gd` (neu).

- [ ] Anmeldung je Provider: Steam-Ticket (MP7/MP10), Google Play Games Services v2 (Server-Auth-Code → serverseitig prüfen), Game Center (signierte Prüfung mit `publicKeyUrl`, `signature`, `salt`, `timestamp`), Geräte-ID nur in der Testphase. Jede Anmeldung findet oder erzeugt eine Identität; eine neue Identität ohne Konto erzeugt ein Konto.
- [ ] **Verknüpfungscode wie Among Us:** Gerät A fordert `POST /me/link-code` an (6–8 Zeichen, 10 Minuten gültig, TESTWERT), Gerät B schickt ihn mit seiner Identität an `POST /auth/link`; die Identität von B hängt danach am Konto von A. Hängt die Identität von B bereits an einem anderen Konto mit Fortschritt, fragt das Spiel nach (Konto behalten oder wechseln), nie stilles Zusammenführen.
- [ ] Identität entkoppeln (`DELETE /me/identities/:provider`), die letzte Identität darf nicht entkoppelt werden.
- [ ] **Konto löschen in-App** (Store-Pflicht, App Store 5.1.1 (v), Google Play „Datenlöschung“): Knopf im Konto-Panel → Bestätigung → `DELETE /me`; löscht Konto, Identitäten, Mitgliedschaft; Run-Teilnahmen werden anonymisiert (bestehende Regel). Gesperrte Spieler weiter nach P-108.
- [ ] Spiel: Konto-Panel zeigt verknüpfte Plattformen, Verknüpfungscode (anzeigen/eingeben) und „Konto löschen“; Offline-Betrieb bleibt unverändert möglich.
- [ ] Datenschutz: nur Provider-Nutzer-IDs speichern; Datenschutzerklärung im eRecht24-Projekt um Google Play Games und Game Center ergänzen (P-013, Push).

**Fertig, wenn:** sich eine Person auf dem PC (Steam) und einem Handy (Play Games oder Game Center) anmeldet, beide per Code verknüpft und auf beiden dieselbe Gilde sieht; „Konto löschen“ im Spiel entfernt alles; API-Tests für Verknüpfen, Konflikt, Entkoppeln und Löschen grün.

**Koop-Check:** Konto, Token und Identitäten liegen am lokalen Client (`online/session.gd`), nicht in einem Autoload; keine Spiellogik betroffen.

## CP2 – Mobile-Build und Touch

**Ziel:** Soulwick läuft auf Android und iOS mit Touch-Steuerung, lesbarer UI und stabiler Bildrate. Darf als Prototyp nach MP1 vorgezogen werden (siehe Überblick).

**Agent:** `player-dev` (Eingabe, HUD) mit Haken für den Integrator in `project.godot`. **Dateien:** `export_presets.cfg` (neu: Android, iOS), `player/player_input.gd` (Eingabe-Objekt aus MP1: neue Implementierung `TouchInput`), `ui/touch/` (neu: virtueller Stick, Knöpfe für Angriff, Dash, Waffe wechseln, Interaktion, Menü), `ui/hud/*` (Skalierung, sichere Bereiche), `tools/perf_check.gd` (neu, misst Bildrate und Zeichenaufrufe über N Räume); Haken: `project.godot` (Eingabe-Aktionen für Touch, `display/window/handheld`, Stretch-Modus), `player/player.gd` (Zielhilfe als Parameter).

- [ ] Android-Export (SDK, Debug-Keystore, später Upload-Key) und iOS-Export (Xcode nötig: Mac leihen oder Cloud-Mac, siehe Risiken); Builds als `.apk`/`.aab` bzw. `.ipa`.
- [ ] Touch-Schema nach CP0 Frage 5: linker virtueller Stick bewegt; Angriff per Knopf oder Halten mit **Zielhilfe** (nächster Gegner im Lichtkreis, TESTWERT Winkel/Reichweite, nur auf Mobil aktiv); Dash-, Waffenwechsel-, Interaktions- und Menü-Knopf; Tab-Übersicht als Knopf. Optional zweiter Stick zum Zielen.
- [ ] UI auf 480×270 bleibt; auf Handys (16:9 bis 20:9) ganzzahlig skaliert, Ränder mit Hintergrund gefüllt, HUD und Knöpfe außerhalb der Aussparungen (Safe Area), Berührungsflächen mindestens 48 px auf dem Gerät.
- [ ] Leistung: Sicht-Shader, Nachbearbeitung und Partikel auf einem Mittelklasse-Android messen (`perf_check.gd`); Zielwert 60 fps, mindestens 50 fps (TESTWERT); Stufe „Mobil“ in den Optionen (weniger Partikel, einfachere Schatten); Bildrate auf 60 begrenzen (Akku).
- [ ] Automatischer Test: `smoke_test.gd` steuert den Bot über das Eingabe-Objekt (nicht über `Input`), damit Touch und Maus denselben Weg nehmen.

**Fertig, wenn:** ein Run über 10 Räume auf einem Android-Gerät mit Touch spielbar ist (≥ 50 fps), das Projektmitglied das Spielgefühl als „gut genug“ einstuft und CP0 Frage 5 damit beantwortet ist.

**Koop-Check:** Eingaben nur über das Eingabe-Objekt (MP1); Zielhilfe als Eigenschaft des Spielers; keine neuen `get_first_node_in_group(&"player")`; kein `Engine.time_scale`.

## CP3 – Lobby- und Relay-Server (`soulwick-relay`)

**Ziel:** Spieler auf PC, Android und iOS treffen sich über einen **Raumcode**; der eigene Server vermittelt und leitet die Pakete weiter (Relay), damit niemand Ports freigeben muss. Das Spiel bleibt im **Host-Modell** (D-083): der Host rechnet, der Relay versteht die Pakete nicht. Nur bauen, wenn CP0 Frage 3 für (a) oder (b) ausfällt; dann ändert ein neuer D-Eintrag D-083 („kein Echtzeit-Spielverkehr über den Server“) in „Weiterleitung ja, Spiellogik nein“.

**Plattform (`api-dev` + Integrator für `infra/`):** `packages/contracts/src/lobby.ts` (neu), `apps/api/src/routes/lobbies.ts`, `apps/api/src/services/lobbies.ts` (Raumcodes, Spielversion, Plattform, Spielerliste), `apps/relay/` (neu, eigener Container `soulwick-relay`), `infra/docker-compose.yml`, `infra/DOKPLOY.md`. **Spiel (`player-dev`/Netzwerk-Agent):** `online/lobby_client.gd`, `online/relay_peer.gd` (dritte Verbindungsart neben ENet und Steam), Gildengebäude: „Raumcode erstellen“ / „Raumcode eingeben“ neben „Beitreten (IP)“.

- [ ] Transport entscheiden (zu Beginn von CP3): (a) `WebSocketMultiplayerPeer` über den Relay (läuft auf allen Plattformen, TLS über Traefik, einfach), (b) `WebRTCMultiplayerPeer` mit Signalisierung über die API, STUN und TURN-Fallback (coturn-Container; weniger Latenz, mehr Betrieb), (c) ENet-UDP durch den Relay. Vorschlag: (a) zuerst, (b) nur bei messbaren Latenzproblemen.
- [ ] Lobby in der API: `POST /lobbies` (Host, Spielversion, Plattform) → Code (6 Zeichen, ohne verwechselbare Zeichen), `GET /lobbies/:code`, `DELETE /lobbies/:code`; Ablauf nach 10 Minuten ohne Start (TESTWERT); höchstens 4 Spieler (D-084); gleiche Spielversion Pflicht (`KNOWN_GAME_VERSIONS`).
- [ ] Relay: nimmt Verbindungen mit Spieler-Token und Lobby-Code an, leitet Pakete zwischen Host und Clients weiter, kennt keine Spielregeln; Grenzen je Verbindung (Pakete/s, Bytes/s, TESTWERT); zustandslos neu startbar; Logs und `/health`.
- [ ] Spiel: Raumcode statt IP für Internet-Spiele; IP/LAN (MP2) und Steam-Einladung (MP6) bleiben; Fehlermeldungen (Code unbekannt, voll, andere Version, Relay nicht erreichbar) wie in MP2.
- [ ] Betrieb: Container in Dokploy, Domain `relay.<domain>`, Kosten und Datenvolumen beobachten (D-083 Betrieb).

**Fertig, wenn:** ein PC-Host (Steam) und ein Android-Client über mobile Daten (nicht dasselbe WLAN) per Raumcode fünf Räume zusammen spielen; ein Neustart des Relay-Containers verliert keine Daten (es gibt keine).

**Koop-Check:** Verbindungsart hinter `MultiplayerPeer` austauschbar, keine Logikänderung; Lobby-Zustand liegt beim Host und im Server, nicht in Autoloads.

## CP4 – Stores

**Ziel:** Soulwick in allen drei Stores als Testversion, später als Release. Steam ist in [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP10 beschrieben; hier kommen Google Play und App Store dazu und die gemeinsamen Pflichten.

**Wer:** Konten, Gebühren und Rechte: Projektmitglied mit dem Team (MP10: Rechte am Uni-Projekt, Lizenzen für den Verkauf). **Dateien:** `export_presets.cfg`, `art/store/` (neu, Briefing in einer späteren `SPRITES_V*.md`: Play-Icon 512×512, Feature-Grafik 1024×500, App-Store-Icon 1024×1024, Screenshots je Gerätegröße), Plattform `apps/web` (echte Store-Badges statt der Pixel-Chips, nur `web-dev`), eRecht24-Projekt (Datenschutzerklärung).

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

## Koop-Check für Crossplay-Pakete

Zusätzlich zu den fünf Fragen aus [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) („Koop-Check für jedes Paket“) beantwortet jeder Bericht mit „ja“:

- [ ] Eingabequelle (Maus, Touch, Controller, Netz) ist eine Implementierung des Eingabe-Objekts aus MP1; Spiellogik fragt nie `Input` direkt.
- [ ] Verbindungsart (ENet, Steam, Relay) ist hinter `MultiplayerPeer` austauschbar; keine Spiellogik kennt die Plattform.
- [ ] Konto, Token und Identitäten liegen am lokalen Client (`online/session.gd` in `game.tscn`), nicht in einem neuen Autoload (D-044); Zustand je Spieler am Spieler.
- [ ] Plattform-SDKs (GodotSteam, Play Games, Game Center) nur über eine gemeinsame Schnittstelle `PlatformServices` mit Null-Implementierung für Editor und Headless, damit alle Tests ohne SDK laufen.

## Risiken

- **iOS braucht einen Mac:** Godot exportiert für iOS nur mit Xcode (Signatur). Das Projektmitglied hat keinen Mac; Optionen: Mac leihen, Cloud-Mac, macOS-Runner in einer CI. Dazu die jährliche Apple-Gebühr.
- **Touch für ein maus-gezieltes Spiel:** Zielhilfe verändert die Balance und kann Crossplay unfair wirken lassen (PC zielt frei, Mobil mit Hilfe); Zielhilfe nur auf Mobil, eigene TESTWERTE, Plattform-Kennzeichen in Ranglisten (CP0 Frage 7).
- **Leistung auf Handys:** Sicht-Shader, Nachbearbeitung und ×2,8 Gegner bei vier Spielern (D-084) auf schwachen Geräten.
- **Eigener Relay = Betrieb:** Kosten, Datenvolumen, Latenz (EU-Server für Spieler in Übersee), Angriffsfläche; ändert D-083.
- **Store-Prüfungen:** Konto löschen in-App, Datenschutz-Labels, Altersfreigabe, Testpflichten für neue Google-Play-Konten; Ablehnungen verschieben Releases.
- **Rechte und Lizenzen** (MP10) gelten für alle Stores; Uni-Teamprojekt klären, bevor Geld fließt.
- **Zwei Spielstand-Wahrheiten** (Steam Cloud und Soulwick-Cloud) führen zu Konflikten; nur eine wählen (CP5).
- **Offenes Geschäftsmodell** blockiert Store-Einträge (Preis) und CP6; Entscheidung früh treffen, auch wenn „später“.
- **Betrug:** Der Host rechnet (D-082 nimmt fälschbare Ranglisten in Kauf); Crossplay vergrößert den Kreis. Plausibilitätsprüfung und Markieren bleiben der Weg.
- **Umfang:** Die ganze Phase kommt nach Phase 3. Nur CP0 (und optional der CP2-Prototyp) dürfen vorgezogen werden, damit MP2–MP7 nicht zweimal gebaut werden.

**Weiterlesen:** [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [MULTIPLAYER.md](MULTIPLAYER.md) · [PRD.md](PRD.md) · [DECISIONS.md](DECISIONS.md) · `soulwick-platform/docs/ROADMAP.md` (P11) · `soulwick-platform/docs/PRD.md` §3.8
