# ROADMAP Multiplayer – Koop, Einladen per Link, Gilden, Ranglisten und Steam

> **Stand:** 17.10.2026 · **Phase 3** (D-179): Koop ist der Kern (D-173), danach kommen die KI-Bosse; beides ist beim Release im Spiel (Release-Tor in [ROADMAP.md](ROADMAP.md)). Übersicht aller Phasen: [ROADMAP.md](ROADMAP.md).
> **Status:** MP1, MP1b, MP2 und MP3 gebaut (14.10.2026), Gilden zum großen Teil (MP8, 16.10.2026); die Testversion läuft gegen die Test-Server (MP4). Offen sind vor allem **Einladen per Link aus dem Browser (MP2b)**, Koop-Gefühl (MP5), Steam (MP6, MP10), Gilden-Schmiede und Ranglisten.
> **Entscheidungen:** D-080 (Schnelles Spiel + Gilde), D-081 (getrennter Fortschritt, gemeinsame Kasse), D-082 (Ranglisten), D-083 (Server), D-084 (Skalierung, Wiederbeleben), D-085/D-123 (Menüs, Abbruch), D-119 (Host + eigener Relay), D-121/D-122 (Konten), D-124 (Netzwerk-Reihenfolge), D-126 (gemeinsamer Run), D-147 (Online-Menü, mehrere Gilden), D-158 (Countdown beim Raumwechsel), D-161 (Einstieg), D-176 (Browser kostenlos, Einladen per Link) in [DECISIONS.md](DECISIONS.md).
> **Technik und Testanleitungen:** [MULTIPLAYER.md](MULTIPLAYER.md) · **Plattform:** `soulwick-platform/docs/ROADMAP.md` (P13–P22) · **Abhaken** nur mit Nachweis (Tests, Datum).

## Überblick

| Paket | Ergebnis | Stand |
| --- | --- | --- |
| MP0 | Entscheidungen | fast fertig, zwei Details offen |
| MP1 | Code verträgt mehrere Spieler (ohne Netzwerk) | gebaut |
| MP1b | API-Client im Spiel, Anmeldung, offline-sicher | gebaut |
| MP2 | Schnelles Spiel: Raum mit Raumcode, zusammen im Dorf (Relay) | gebaut, Handtest offen |
| **MP2b** | **Einladen per Link: Link antippen → im Browser direkt in der Lobby** | **neu, offen** |
| MP3 | Gemeinsamer Dungeon-Run, gemeinsame Kasse | gebaut, Handtest offen |
| MP4 | Testversion für Freunde (Builds gegen die Test-Server) | teilweise |
| MP5 | Koop-Gefühl: Feinschliff, L-Räume, Räume nur im Koop | offen |
| MP6 | Steam als Zusatz: Anmeldung, Einladung mit Raumcode | offen |
| MP7 | Server-Grundlage auf Dokploy | development läuft, production offen |
| MP7b | Website und Admin-Panel | Grundgerüst gebaut, Rest im Plattform-Repo |
| MP8 | Dauerhafte Gilden mit Gilden-Fortschritt | großteils gebaut, Schmiede offen |
| MP9 | Ranglisten für Spieler und Gilden | offen |
| MP10 | Eigene Steam-App, Playtest, Release-Vorbereitung | offen |

**Reihenfolge:** MP2b vor dem Abschluss von MP4 (der Link ist der Weg, wie Freunde die Testversion erreichen), dann MP5, danach MP6/MP10 (Steam) und MP9. MP7, MP7b und die Plattform-Pakete dürfen jederzeit parallel laufen, weil sie keinen Spielcode berühren. Transport und Aufbau stehen in [MULTIPLAYER.md](MULTIPLAYER.md) §2 (Host rechnet, der Relay leitet nur weiter, D-119).

## Erledigt

| Paket | Ergebnis (Details im Code und in MULTIPLAYER.md) | Nachweis |
| --- | --- | --- |
| MP1 | Nächster lebender Spieler als Ziel, Eingabe-Objekte je Spieler, `GameMode` (`SOLO`, `QUICK`, `GUILD`), Pause und HitStop je Modus, Server-Regel „kein eigener Spieler beim Host nötig“ | GUT 850/850, `mp_local_sim.gd` mit 2–4 Spielern, 14.10.2026 |
| MP1b | `online/api_client.gd`, `online/session.gd` (Node, kein Autoload), Dev- und Gast-Anmeldung, offline zuerst | `test_api_client.gd`, `test_api_integration.gd`, 14.10.2026 |
| MP2 | Online-Menü mit Raum erstellen/beitreten, `relay_peer.gd`, `lobby_client.gd`, Spieler je Verbindung, Fehlermeldungen `LOBBY_ERR_*` | `tools/net_smoke.gd` 3/3, 14.10.2026 |
| MP3 | Gemeinsamer Run nach D-126: Host entscheidet, Gegner und Räume repliziert, gemeinsame Kasse, Upgrades je Spieler, Am-Boden und Wiederbeleben, Abbruch-Regeln, Countdown beim Raumwechsel (D-158) | `tools/net_run_smoke.gd` (Räume 1–16), 14.10.2026 |

## MP0 – Entscheidungen

- [x] Gruppenmodi, getrennter Fortschritt, Ranglisten, Server, Skalierung, Menüs/Abbruch (D-080 bis D-085, D-123).
- [x] Die Netzwerk-Sitzung lebt als Node unter der Spielszene, kein neuer Autoload (`online/session.gd`, D-121, D-044).
- [ ] Details bestätigen: Gilden-Fortschritt und Gildenkasse ausgeben (Vorschlag D-081, OFFEN in D-161), Ranglisten-Wertung (Vorschlag D-082).
- [ ] D-001 („lokales“ Roguelite) an das Online-Spiel anpassen (Integrator, DECISIONS).

## MP2 und MP3 – offene Handtests

- [ ] MP2: zwei Instanzen auf einem Rechner und zwei Rechner in **verschiedenen** Netzen laufen per Raumcode zusammen durchs Dorf (Anleitung [MULTIPLAYER.md](MULTIPLAYER.md) §3b).
- [ ] MP3: zwei Spieler erreichen zusammen den ersten Boss, von Hand mit zwei Fenstern bzw. zwei Rechnern (Anleitung §3c).

## MP2b – Einladen per Link (D-176, D-179)

**Ziel:** Ein Spieler tippt im Online-Menü „Freunde einladen“, schickt den Link per Messenger oder Discord; wer ihn öffnet, landet im Browser ohne Download, ohne Konto und ohne Raumcode-Tippen in der Lobby des Hosts. Das ist der Einstieg in einer Minute (D-173).

**Link (Vorschlag):** `https://game.playsoulwick.com/?room=ABC123` auf der Spiel-Domain (D-148, D-157); `game-dev.playsoulwick.com` in der Testumgebung. Der Link trägt nur den Raumcode, nichts Persönliches. OFFEN: zusätzlich ein kurzer Link über die Website (z. B. `playsoulwick.com/play?room=ABC123` mit Vorschaubild und Weiterleitung) – braucht ein Paket im Plattform-Repo (`web-dev`).

**Spiel (Fach-Agent `player-dev` mit Freigabe `online/**`, `ui/menus/online/**`, `ui/main_menu/**`; Shell als Integrator):**

- [ ] Shell der Browser-Version (`deploy/web/shell.html`) liest `?room=` und gibt den Code ans Spiel weiter (wie heute `?install`, [WEB_BUILD.md](WEB_BUILD.md) §4); ungültige Codes werden verworfen.
- [ ] Neu `online/invite_link.gd`: Link bauen und lesen (Alphabet und Länge wie die Raumcodes, D-121/CP3), Umgebung aus `OnlineConfig`.
- [ ] Online-Menü und Lobby: Knopf „Link kopieren“, auf Handys „Teilen“ (Teilen-Menü des Browsers bzw. des Systems); Raumcode bleibt daneben sichtbar.
- [ ] Ankunft über einen Link: kurzer Erststart (Name und Figur auf einer Seite, D-152), Gast-Anmeldung im Hintergrund (P-028), Welt automatisch (D-161), dann sofort Beitritt; das Hauptmenü wird übersprungen.
- [ ] Fehlerfälle als ein Satz mit Ausweg: Raum voll, Run läuft schon („Du kommst ins Dorf, sobald der Run endet“, wenn der Relay das zulässt), Raum abgelaufen, andere Spielversion, Server nicht erreichbar → Knopf „Selbst spielen“.
- [ ] Native Builds (Windows, Linux, macOS, Android-APK): „Link kopieren“ funktioniert auch dort; einen geöffneten Link nehmen sie erst später an (OFFEN: Android App Links, iOS Universal Links, Steam-Einladung bleibt MP6).

**Fertig, wenn:** das Projektmitglied einen Link aus der Testversion an einen Kollegen schickt und dieser auf einem Android-Handy und am PC im Browser in **unter einer Minute** (TESTWERT, mit Ladezeit) in der Lobby steht, ohne den Code einzutippen; GUT für Link bauen/lesen und alle Fehlerfälle grün; ein stummer, kopfloser Browser-Test (Playwright, `--mute-audio`) öffnet den Link gegen die Test-Server.

**Koop-Check:** keine Spiellogik betroffen; der Beitritt läuft über `lobby_client.gd` wie mit Raumcode; Konto und Token in `online/session.gd`, kein neuer Autoload.

**OFFEN:** Website-Kurzlink mit Vorschau (welche Daten die Vorschau zeigen darf: Vorschlag nur Spielerzahl, kein Name); ob ein Link nach dem Ende des Raums auf „Selbst spielen“ oder auf die Website führt; ob Räume für Einladungen länger offen bleiben als 10 Minuten ohne Start (TESTWERT, CP3).

## MP4 – Testversion für Freunde

**Gebaut:** Builds für Windows, Linux, macOS, Android und Browser je Umgebung, jeder Push auf `dev` wird eine Testversion (D-148, D-156, D-157); Versionsprüfung im Hauptmenü; Anleitung „Mit Freunden testen“ in der [README](../README.md) und in jedem ZIP.

- [ ] 2–4 Personen an verschiedenen Orten spielen einen Run zusammen über die Test-Server (Online-Test am 16.10.2026, D-158; Abnahme durch das Projektmitglied bestätigen).
- [ ] Rückmeldungen sammeln (Lag, Abbrüche, Schwierigkeit, Spaß) und die Relay-Metriken (Bytes/s je Raum) ansehen.

## MP5 – Koop-Gefühl (D-084)

**Schon mit MP3 gebaut:** Skalierung nach Spielerzahl (`online/coop_rules.gd`), Am-Boden und Wiederbeleben, Namensschilder, Marker für Gefallene.

- [ ] Skalierung mit `balance_sim.gd` für 1–4 Bots messen und als TESTWERT nachstellen (Agent `balance`).
- [ ] Raumgröße L für 3–4 Spieler im Koop nutzen: die L-Pläne baut Phase 2 (ROADMAP_AUSBAU „Phase 2b – Rest“), hier der Anschluss über `DungeonManager.get_room_sizes()` und ein Lauf mit 3–4 Spielern.
- [ ] Eigener Lichtkreis je Spieler auch für Mitspieler sichtbar, Pfeil zu Mitspielern außerhalb des Bildes.
- [ ] Räume nur im Koop ([KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md) §3.11: Doppelgänger, Staffel, Geteiltes Licht, Zwei Schalter, Wettstreit, Rettung) – Kandidaten auch für den Party-Modus ([KONZEPT_PARTY_MODUS.md](KONZEPT_PARTY_MODUS.md)).
- [ ] Rest aus MULTIPLAYER.md §3c „Noch nicht repliziert“ (Fallen-Takt, Flüche des Pakt-Altars, Händler in der Geheimnische).

## MP6 – Steam als Zusatz (Test-AppID 480)

Steam ist **kein Transport** (D-119, Plattform P-017): auch Steam-Spieler verbinden sich über den Relay.

- [ ] **GodotSteam** (GDExtension) einbinden, Kompatibilität mit Godot 4.7.2 prüfen; nur über die Schnittstelle `PlatformServices` mit Null-Implementierung für Editor, Headless, Browser und Mobil.
- [ ] **Freunde einladen** (Steam-Overlay) und „Spiel beitreten“ über Rich Presence; die Einladung trägt nur den Raumcode, der Beitritt läuft über `lobby_client.gd`.
- [ ] Anmeldung mit Steam-Sitzungsticket an `/auth/steam` vorbereiten; echt prüfbar erst mit eigener AppID (MP10, Plattform P14).
- [ ] Testen mit zwei Rechnern und zwei Steam-Konten.

**Fertig, wenn:** ein Freund über eine Steam-Einladung einem Run beitritt.

## MP7 – Server-Grundlage auf Dokploy (D-083, parallel möglich)

**Gebaut:** API, Relay, Datenbank und Gast-Anmeldung im Plattform-Repo (P1, P7, P8, P13, P20); die Umgebung `development` läuft (`api-dev`, `play-dev`).

- [ ] Umgebung `production` einrichten (Checkliste [LAUNCH.md](LAUNCH.md) §4–§5, Plattform P2, P17).
- [ ] Tägliches Datenbank-Backup in `production`, Wiederherstellung einmal getestet.
- [ ] Datenschutzerklärung (eRecht24) mit allen Datenkategorien: Plattform-IDs, Name, Aussehen, Gilde, Run-Berichte, Bug-Meldungen, Relay-Verbindungsdaten.

## MP7b – Website und Admin-Panel (parallel möglich)

Grundgerüst gebaut (13.10.2026); alles Weitere steht im Plattform-Repo (P9, P10, P12, P18, P21, P22). Offen aus Spielsicht nur: Rechtstexte live, Website-Knöpfe „Im Browser spielen“ erst nach der Freigabe (D-148 OFFEN).

## MP8 – Dauerhafte Gilden (D-080, D-081, D-147)

**Gebaut (16.10.2026; Nachweis: `tests/unit/test_online_menu.gd` 35 Tests, Live-Test gegen lokale API 1.1.0 und Relay mit bis zu drei Spielprozessen; Regeln MULTIPLAYER.md §3f):** Gilden-API mit bis zu 5 Gilden je Spieler, Online-Menü mit Gilden, Gilden-Räume nur für Mitglieder, Gildenräume auf der Gildenseite (D-161), Gildenkasse aus Gilden-Runs nach der Gold-Regel.

- [ ] Gilden-Schmiede: kauft aus der Kasse, gleichzeitige Käufe mit Versionsprüfung (kein doppeltes Abbuchen); was die Kasse kaufen darf, ist OFFEN (D-161).
- [ ] Meta-Boni aus der Gilden-Schmiede im Gilden-Run (`MetaProgression`-Quelle „Gilde“, MP1).
- [ ] Mit Steam: Mitglieder direkt aus der Freundesliste einladen.

**Fertig, wenn:** drei Personen eine Gilde gründen bzw. beitreten, einen Gilden-Run spielen, danach in der Gilden-Schmiede kaufen und die Kasse für alle gleich ist.

## MP9 – Ranglisten (D-082)

- [ ] Run-Bericht `POST /runs` auch für Einzelspieler-Runs (angemeldet und online); Host meldet Gruppen-Runs (gebaut für Gilden-Runs, MP8).
- [ ] Plausibilitätsprüfung auf dem Server (Mindestdauer je Raum, bekannte Spielversion); verdächtige Einträge markieren statt löschen.
- [ ] Ranglisten Spieler Solo, Spieler Gruppe, Gilden; jeweils Allzeit und Saison (monatlich); gemeinsam oder je Plattform ist OFFEN (CP0 Frage 7).
- [ ] Anzeige im Spiel (Chronik oder Gildenhaus): Top 50 und die eigene Position.
- [ ] Testphasen-Ranglisten zum Steam-Start zurücksetzen.

## MP10 – Eigene Steam-App und Release-Vorbereitung

**Release (D-179):** Steam ist der erste Release (D-119). Er kommt erst, wenn das Release-Tor in [ROADMAP.md](ROADMAP.md) erfüllt ist (Koop, KI-Bosse, Wick als Begleiter, Dorf ausbauen und besuchen); die Store-Seite beschreibt diesen Umfang, der Party-Modus kommt danach.

- [ ] Rechte am Spiel im Team klären (schriftlich, WebBude als Publisher, D-119); Lizenzen aller Grafiken, Schriften, Musik und Addons prüfen; Code GPL-3.0, Inhalte geschützt (D-177, `LICENSE-ASSETS.md`); GPL mit dem Steamworks-SDK mit Fachanwalt klären (D-177 OFFEN).
- [ ] Steamworks-Konto für WebBude, Steam Direct, eigene AppID; Steam-Anmeldung am Server auf die AppID umstellen.
- [ ] Builds per SteamPipe auf einen Beta-Branch (Pipeline vorbereitet, [STORES.md](STORES.md) §5), **Steam Playtest** für Freunde.
- [ ] Store-Seite mit kleinem Preis (Größenordnung 3–5 €, D-176, Preis OFFEN), Start-Kosmetik inklusive, Screenshots, Trailer; Steam-Erfolge; Steam Cloud nur, wenn CP5 nicht kommt (eine Wahrheit; Vorschlag, CP5).

## Risiken

- Netzlast durch viele Gegner (×2,8 bei 4 Spielern); über den Relay zählt jedes Byte doppelt und kostet Server-Traffic.
- Ranglisten sind fälschbar, solange der Host rechnet; für den Anfang akzeptiert (D-082).
- Host im Hintergrund (D-183): Im Browser läuft das Spiel des Hosts in einem Raum auch im versteckten Tab weiter (Keep-alive in `deploy/web/shell.html`); Energiesparen, Safari/iOS, Handy-Browser und Apps im Hintergrund halten es trotzdem an. Dann warten die Mitspieler ruhig („Warte auf den Host …“) und können nach 15 s den Raum verlassen; erst wenn die Verbindung des Hosts abreißt, endet der Run für alle (D-085).
- Einladungs-Links können weitergereicht werden; ein Raum ist trotzdem höchstens 4 Spieler groß, der Host kann Spieler entfernen (Relay `kick`).
- Der Server braucht Betrieb: Updates, Backups, Datenschutz.

**Weiterlesen:** [ROADMAP.md](ROADMAP.md) · [MULTIPLAYER.md](MULTIPLAYER.md) · [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) · [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) · [DECISIONS.md](DECISIONS.md)
