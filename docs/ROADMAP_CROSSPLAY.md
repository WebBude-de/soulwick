# ROADMAP Crossplay – Steam, Google Play, App Store und Browser

> **Stand:** 17.10.2026 · **Zielbild:** D-108 (zusammen spielen über alle Plattformen). **Entschieden:** Host-Modell plus eigener Relay, Publisher **WebBude** (D-119); **gemeinsamer Release auf allen Versionen** – Browser, Steam, Android, iOS (D-179, ersetzt die Reihenfolge Steam → Android → iOS aus D-119); Konto-Modell (D-121, D-122); Touch mit zwei Sticks (D-155); Geschäftsmodell als Arbeitsgrundlage (D-176); Zielgruppe und Altersfreigabe (D-173); Code offen, Inhalte geschützt (D-177). **OFFEN:** Ranglisten je Plattform, Sign in with Apple, Relay-Regionen, Preise.
> **Einordnung:** keine eigene Phase. Konto und Relay gehören zu Phase 3 ([ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md)), Stores gehören ins Release-Tor (alle drei gemeinsam, D-179), Käufe kommen frühestens mit dem Release. Übersicht: [ROADMAP.md](ROADMAP.md). Schritt-für-Schritt für Konten, Secrets und Store-Formulare: [STORES.md](STORES.md); Browser in Produktion: [LAUNCH.md](LAUNCH.md).
> **Plattform-Repo:** P11, P13–P22 in `soulwick-platform/docs/ROADMAP.md`, Konzept `soulwick-platform/docs/KONZEPT_ONLINE.md`. Technik im Spiel: [MULTIPLAYER.md](MULTIPLAYER.md). **Abhaken** nur mit Nachweis (Tests, Datum); jedes Paket ist für **einen** Agenten geschnitten, Spiel- und Plattform-Teile werden getrennt vergeben.

## Überblick

| Paket | Ergebnis | Stand 17.10.2026 |
| --- | --- | --- |
| CP0 | Entscheidungen | 1–6 und 9 entschieden, 7, 8 und 10 OFFEN |
| CP1 | Soulwick-Konto mit Identitäten, Verknüpfungscode, Konto löschen | Plattform gebaut (P14, P15); Konto-Panel im Spiel offen |
| CP2 | Mobil und Touch | Prototyp gebaut (Android-APK, Zwei-Stick-Touch); Gerätetest und Leistung offen |
| CP3 | Relay mit Raumcodes | gebaut (P13, `relay_peer.gd`), läuft in `development`; Abnahme Teil A/B und `production` offen |
| CP4 | Stores (Steam, Google Play, App Store) | offen; alle drei zum Release (D-179); Schritte in STORES.md |
| CP5 | Cross-Progression (Cloud-Save) | offen |
| CP6 | Käufe und Werbung | Modell entschieden (D-176); Bau offen |
| CP7 | Build-CI und Store-Uploads | Pipeline vorbereitet (D-156, D-157), nichts hochgeladen; noch kein Store-Konto, auch kein Apple-Konto |

**Reihenfolge:** CP1 (Spiel-Teil) vor dem Release. CP2-Gerätetest (Android und iPhone) vor den Handy-Stores. CP4 für alle drei Stores mit MP10 (Steam) und nach dem CP2-Gerätetest; released wird gemeinsam auf Steam, Google Play, App Store und im Browser (D-179, statt Steam → Google Play → App Store aus D-119). iOS gehört damit zum Release: Apple-Konto (D-U-N-S-Nummer, Tage bis Wochen) früh anlegen; Signieren und Notarisieren laufen ohne eigenen Mac auf dem macOS-Läufer der CI (`tools/ci/ios_build.sh`, `tools/ci/macos_sign.sh`, CP7). CP5 nach CP1. CP6 frühestens mit CP4, Werbung nur auf dem Handy.

## CP0 – Entscheidungen

| # | Frage | Status |
| --- | --- | --- |
| 1 | **Geschäftsmodell** | **ENTSCHIEDEN als Arbeitsgrundlage (D-176, 17.10.2026):** Browser kostenlos ohne Konto; Handy kostenlos mit Werbung, „Werbefrei“ als Einmalkauf, Kosmetik; Steam mit kleinem Preis ohne Werbung, Start-Kosmetik inklusive. Nur Kosmetik und Werbefreiheit werden verkauft, keine Lootboxen. **OFFEN:** Preise, Zahlungsweg im Browser, Käufe über Plattformen hinweg (CP6). |
| 2 | **Konto-Modell** | **ENTSCHIEDEN (D-121, D-122):** Soulwick-Konto ohne E-Mail und Passwort, Plattform-Identitäten verknüpft per 6-stelligem Code, Konto löschen in der App und per Web-Formular. |
| 3 | **Lobby/Relay** | **ENTSCHIEDEN (D-119):** Host-Modell + eigener Relay mit Raumcodes; WebRTC und dedizierter Server später. |
| 4 | **Plattform-Reihenfolge** | **ENTSCHIEDEN (D-119), geändert durch D-179 (17.10.2026):** gemeinsamer Release auf allen Versionen (Browser, Steam, Android, iOS). Vorher Steam → Android → iOS (iOS später, kein Mac); signiert wird jetzt auf dem macOS-Läufer der CI. |
| 5 | **Touch-Steuerung** | **ENTSCHIEDEN (D-155, D-168):** zwei Sticks (links laufen, rechts zielen und automatisch angreifen); Zielhilfe nur für Fernwaffen, solange der Ziel-Stick ausgelenkt ist, abschaltbar (Option „Zielhilfe (Touch)“). |
| 6 | **Altersfreigabe** | **ENTSCHIEDEN (D-173, 17.10.2026):** Store-Zielgruppe **ab 13**; keine Anmeldung für Kinder-Bereiche (Google Play Familienprogramm, Apple Kids), keine Werbung an Kinder. Die Freigabe selbst ergibt sich aus dem IARC-Fragebogen bzw. dem Fragebogen der Stores, wir wählen sie nicht (erwartet niedrig: Pixel-Kampf ohne Blut). **OFFEN:** ob KI-Bosse, Käufe und Koop mit Fremden die Freigabe anheben; ob Google ein Spiel mit niedlichem Maskottchen als „spricht Kinder an“ einstuft. |
| 7 | **Ranglisten** je Plattform oder gemeinsam (D-082) | **OFFEN.** Vorschlag: gemeinsam mit Plattform-Kennzeichen am Eintrag. |
| 8 | **Sign in with Apple** | **OFFEN.** Vorschlag: nur Game Center und Play Games als Login, kein Social-Login → kein Sign in with Apple nötig (App-Store-Regel 4.8); mit dem Fragebogen in CP4 prüfen. |
| 9 | **Publisher** | **ENTSCHIEDEN (D-119):** WebBude, Firmenkonten bei Steam, Google und Apple (Apple wegen D-179 schon vor dem Release). |
| 10 | **Relay-Regionen** | **OFFEN.** Vorschlag: eine Instanz (EU) zuerst, je Region erst bei messbarer Latenz außerhalb Europas. |

- [ ] Fragen 7, 8 und 10 als D-Eintrag beantworten (VERBINDLICH oder bewusst „später“).
- [ ] D-108 auf VERBINDLICH setzen (inhaltlich durch D-119, D-121, D-155, D-173 und D-176 entschieden) und in D-083 auf D-119 verweisen (Integrator, DECISIONS).
- [ ] Plattform: `soulwick-platform/docs/PRD.md` §3.8 und §4 („Geschäftsmodell OFFEN“, „keine Zahlungsdaten bis CP6“) auf D-176 bringen (`api-dev` oder Integrator dort).

## CP1 – Soulwick-Konto und Identitäten

**Gebaut (Plattform P14, P15, P20):** Anmeldung je Provider (Steam, Google Play, Gast je Gerät), Verknüpfungscode, Zusammenführen nach D-122, vollautomatische Löschung, Löschcode für die Website (`POST /me/deletion-code`, P-026). Bezeichnungen im Spiel: Bereich „Konto“/„Account“, Knöpfe „Konto löschen“/„Delete account“ und „Löschcode für die Website“ (wie `soulwick-platform/apps/web/messages/*/deletion.json`).

**Spiel (`player-dev` oder `village-dev`, Freigabe `ui/options/`, `online/`):**

- [ ] Konto-Panel `ui/options/account_panel.gd`: verknüpfte Plattformen, Verknüpfungscode anzeigen und eingeben, „Konto löschen“ mit Bestätigung, „Löschcode für die Website“; Offline-Betrieb bleibt unverändert.
- [ ] Hinweis „Konto verknüpfen“ für Gastkonten (sonst geht das Gastkonto mit der Installation verloren, P-028).
- [ ] Echte Anmeldung: Steam mit eigener AppID (MP10), Google Play Games aus der Spur „Interner Test“ (CP7), Game Center mit iOS.

**Fertig, wenn:** sich eine Person auf dem PC (Steam) und einem Handy (Play Games) anmeldet, beide per Code verknüpft, auf beiden dieselbe Gilde und Kosmetik sieht und „Konto löschen“ im Spiel alles entfernt.

**Koop-Check:** Konto, Token und Identitäten am lokalen Client (`online/session.gd`), kein Autoload; keine Spiellogik betroffen.

## CP2 – Mobil und Touch

**Gebaut (15.–17.10.2026):** Android-APK und -AAB, Renderer `gl_compatibility`, Zwei-Stick-Touch (`TouchInput`, `TouchOverlay`, D-155, D-168), Menüs fürs Handy (D-169), Browser-Version mit Touch.

- [ ] Gerätetest: ein Run über 10 Räume auf einem echten Android-Mittelklasse-Handy (App und Browser), ≥ 50 fps (TESTWERT); iPhone als App (TestFlight) und im Browser.
- [ ] `tools/perf_check.gd` (neu): Bildrate und Zeichenaufrufe über N Räume; Stufe „Mobil“ in den Optionen (weniger Partikel, einfachere Schatten); Bildrate auf 60 begrenzen. Gilt auch für den Look-Strang (ROADMAP.md, Strang L).
- [ ] `smoke_test.gd` steuert den Bot über das Eingabe-Objekt (nicht über `Input`), damit Touch und Maus denselben Weg nehmen.
- [ ] iOS-Export über den macOS-Läufer der CI (CP7, braucht das Apple-Konto), Safe Area auf echten Geräten (iPhone und iPad) prüfen; gehört zum Release (D-179).

**Koop-Check:** Eingaben nur über das Eingabe-Objekt (MP1); kein `Engine.time_scale`; keine neuen `get_first_node_in_group(&"player")`.

## CP3 – Relay und Raumcodes

**Gebaut:** Relay `apps/relay` (P13, Raumcodes, Weiterleitung ohne Lesen, Schutz, Metriken), im Spiel `online/relay_peer.gd` und `lobby_client.gd` (MP2), Versionsprüfung (P16); `play-dev.playsoulwick.com` läuft. Protokoll und Betrieb: `soulwick-platform/docs/KONZEPT_ONLINE.md`.

- [ ] Teil A abnehmen: zwei Rechner an verschiedenen Orten spielen per Raumcode fünf Räume zusammen.
- [ ] Teil B: ein PC-Host und ein Android-Client über mobile Daten (nicht dasselbe WLAN) spielen fünf Räume zusammen; ebenso PC und Browser auf dem Handy.
- [ ] Relay in `production` (`play.playsoulwick.com`, Plattform P17, [LAUNCH.md](LAUNCH.md)).
- [ ] Einladen per Link nutzt denselben Beitritt (MP2b); Raumcodes mit Regions-Präfix erst, wenn Frage 10 so entschieden wird.

**Koop-Check:** Verbindungsart hinter `MultiplayerPeer` austauschbar (Relay, optional ENet, später WebRTC oder dedizierter Server); keine Spiellogik kennt den Transport.

## CP4 – Stores

**Ziel:** Soulwick als Testversion, später als Release, in Steam, Google Play und App Store. Konten, Gebühren, Secrets und Formulare Schritt für Schritt: [STORES.md](STORES.md). Store-Grafiken geliefert (SPRITES_V11).

**Release (D-179):** erst, wenn das Release-Tor in [ROADMAP.md](ROADMAP.md) erfüllt ist; gemeinsam auf Steam, Google Play und App Store, dazu die Browser-Version. Store-Seiten beschreiben den Release-Umfang wie vorhanden (Koop mit Freunden, KI-Bosse, Wick als Begleiter, Dorf ausbauen und Freunde ins Dorf einladen); der Party-Modus kommt danach. Öffentlich (Social Media) geht es erst ab dem Release; ob die Steam-Seite „Demnächst verfügbar“ (mindestens 2 Wochen vor dem Release) schon dazu zählt, ist OFFEN (D-179).

- [ ] **Steam** (MP10): kleiner Preis (Größenordnung 3–5 €, D-176, OFFEN), Start-Kosmetik inklusive, keine Werbung.
- [ ] **Google Play:** kostenlos (D-176), Zielgruppe **ab 13**, nicht im Familienprogramm (D-173); IARC-Fragebogen; „Enthält Werbung“ und „In-App-Käufe“ erst angeben, wenn CP6 sie einbaut.
- [ ] **App Store:** kostenlos (D-176), Altersfragebogen von Apple, Kategorie nicht „Kinder“ (D-173); Konto löschen in der App (5.1.1 (v)); GPL-3.0 und App-Store-Bedingungen mit Fachanwalt klären (D-177 OFFEN).
- [ ] Gemeinsam: Store-Texte DE und EN aus den Website-Texten (für Spieler, nicht an Kinder gerichtet), Screenshots aus dem echten Spiel, Datenschutzerklärung und Impressum (eRecht24), Support-Adresse; Melden und Filtern von Spieler- und Gildennamen (nutzergenerierte Inhalte, D-152 OFFEN).
- [ ] Gemeinsamer Termin (Vorschlag): erst festlegen, wenn alle Prüfungen durch sind (Steam: 30 Tage nach Steam Direct, Seite mindestens 2 Wochen „Demnächst verfügbar“; Google: erster Produktions-Release einige Tage; Apple: App-Prüfung meist 1–3 Tage); alle Builds mit derselben `protocolVersion`.
- [ ] Website: Store-Links in `soulwick-platform/apps/web/content/stores.json` eintragen; mit `LIVE_FEATURES=true` erscheinen die offiziellen Badges unverändert, vorher eigene Pixel-Knöpfe ohne fremde Logos ([STORES.md](STORES.md) §6, D-179).

**Fertig, wenn:** je Store ein Test-Build (Steam Playtest, interne Play-Spur, TestFlight) von drei Testpersonen installiert wurde und die Store-Einträge in DE und EN als Entwurf stehen.

## CP5 – Cross-Progression (Cloud-Save)

**Ziel:** Der Einzelspieler-Spielstand (Welten, D-152) folgt dem Konto von PC zu Handy und zurück. Braucht CP1. Profil (Name, Aussehen) und Gilden liegen schon am Konto (P-034, D-081).

**Plattform (`api-dev`):** Vertrag `GET`/`PUT /me/save`, Tabelle `player_saves` (Spieler, `version`, Daten ≤ 64 KB, Spielversion, Zeit, Gerät), Tests. **Spiel (`village-dev`):** `online/cloud_save.gd` (neu), Haken `SaveManager.export_blob()`/`import_blob()`, Dialog bei Konflikt.

- [ ] Offline zuerst: der lokale Stand ist die Wahrheit, die Cloud ein Spiegel; Abgleich beim Betreten und Verlassen des Dorfs und nach jedem Run-Ende.
- [ ] Konfliktregel: `PUT` schickt die gelesene `version`; passt sie nicht, antwortet die API `409` mit dem Server-Stand, und das Spiel fragt, welcher Stand bleibt. Nie still zusammenführen, nie Verlust ohne Rückfrage.
- [ ] Eine Wahrheit: mit Soulwick-Cloud-Save bleibt Steam Cloud aus (Vorschlag).
- [ ] Tests fassen den echten Spielstand nie an (AGENTS.md Regel 4).

**Koop-Check:** nur Einzelspieler-Zustand; Gruppen-Fortschritt bleibt getrennt (D-081).

## CP6 – Käufe und Werbung (D-176, D-177)

**Ziel:** Geld nur über Kosmetik und „Werbefrei“, fair auf allen Plattformen, Käufe am Konto und auf dem Server geprüft. Die Kosmetik selbst kommt aus Strang W (ROADMAP.md, WK2).

**Regeln (D-176):**

- Verkauft werden nur **Kosmetik** (Spielfigur, Wick, Dorf) und **„Werbefrei“** (Einmalkauf, nur Handy). Kein Gold, keine Kristalle, keine Stärke, keine Abkürzung (kein Pay-to-win). **Keine Lootboxen** und keine Zufallspakete: jeder Gegenstand ist direkt mit sichtbarem Preis kaufbar.
- **Steam:** Kaufpreis, Start-Kosmetik inklusive, keine Werbung; Kosmetik zusätzlich kaufbar (Steam-Mikrotransaktionen).
- **Browser:** keine Werbung, solange es geht; Kosmetik später.
- **Handy:** Werbung nur hier und nur in zwei Formen: freiwillige **Belohnungsvideos** (nur auf Tipp des Spielers) und **ruhige Banner zwischen Runs** (Dorf, Run-Ende; ohne Ton). **Nie im Kampf** (D-176); **nie im Dungeon, nie während eines Koop-Runs** (Vorschlag). „Werbefrei“ entfernt die Banner.
- **Werbenetzwerk mit Blick auf jüngere Mitspieler wählen** (D-173): Anzeigen mit niedriger Inhaltseinstufung, keine personalisierte Werbung ohne Einwilligung (DSGVO; auf iOS App Tracking Transparency), Netzwerk mit Selbstzertifizierung für Familien-Richtlinien bevorzugen, auch wenn Soulwick nicht im Familienprogramm ist (Vorschlag).

**Prüfung am Konto (D-177):** Gekauftes liegt am Soulwick-Konto auf dem Server, nie nur im Spiel. Google Play und App Store über ihre Quittungen (Google Play Developer API, App Store Server API), Steam über das Sitzungsticket und die Steam Web API (Besitz der App und Mikrotransaktionen). Rückerstattungen kommen über die Store-Benachrichtigungen und entziehen den Gegenstand. Mitspieler sehen Kosmetik über das Profil; der Server lässt dort nur zu, was das Konto besitzt (Vorschlag, `PATCH /me`, P-034). Ein selbst gebautes Spiel kann lokal alles freischalten, online aber nichts Gekauftes vortäuschen.

**Plattform (`api-dev`, Verträge zuerst):** `packages/contracts` (neu: Käufe und Berechtigungen), Tabellen `purchases` (Provider, Bestell-ID, Produkt, Status, Quittung) und `entitlements` (Spieler, Gegenstand, Quelle) in `packages/db`, Quittungsprüfung je Store, Admin-Ansicht. **Spiel:** Dorfladen für Kosmetik (`village-dev`), Store-Anbindung über `PlatformServices` (Play Billing, StoreKit, Steam; Plugins und Export-Presets: Integrator), Werbe-SDK nur im Android-/iOS-Export.

- [ ] Je Store ein Testkauf in der Sandbox, serverseitig bestätigt und als Berechtigung am Konto sichtbar; eine Rückerstattung entzieht ihn.
- [ ] „Werbefrei“ entfernt die Banner auf allen Geräten des Kontos (soweit die Store-Regeln das erlauben, siehe OFFEN).
- [ ] Werbung nur zwischen Runs; ein automatischer Test prüft, dass im Dungeon und im Koop nie eine Anzeige angefordert wird.
- [ ] Datenschutz-Angaben neu: Werbe-ID und Werbenetzwerk in Google „Datensicherheit“, Apple „App-Datenschutz“ und eRecht24 ([STORES.md](STORES.md) §8).

**OFFEN:** Preise; Zahlungsweg für Kosmetik im Browser (Vorschlag: zuerst gar keiner, im Browser nur freispielbare Kosmetik); ob Käufe plattformübergreifend am Konto gelten (Store-Regeln prüfen: Apple App Review 3.1.1/3.1.3(b) „Multiplatform Services“, Google-Play-Zahlungsrichtlinie, Steam); was ein Belohnungsvideo gibt (Vorschlag: nur Kosmetik-Fortschritt oder etwas, das es auch ohne Video gibt, nie Stärke); wo Belohnungsvideos angeboten werden (Vorschlag: nur im Dorf und am Run-Ende); ob „Werbefrei“-Käufer die Video-Belohnungen ohne Video bekommen (Vorschlag: ja); Wahl des Werbenetzwerks.

**Fertig, wenn:** je Store ein Sandbox-Kauf serverseitig bestätigt ist, „Werbefrei“ wirkt, Werbung nur an den erlaubten Stellen erscheint und die Datenschutz-Angaben angepasst sind.

**Koop-Check:** Kosmetik ist reine Optik und kommt bei Mitspielern über das Profil; nichts davon in der Spiellogik oder in Spielpaketen; keine Werbung während eines Koop-Runs, auch nicht beim Client.

## CP7 – Build-CI und Store-Uploads

**Gebaut (D-148, D-156, D-157):** `release.yml` baut Windows, Linux, macOS, Web, Android (APK, AAB) und iOS (Xcode-Projekt, IPA mit Secrets); jeder Push auf `dev` wird eine Testversion; Uploads zu Steam, Google Play und TestFlight sowie Signaturen sind vorbereitet und laufen, sobald die Secrets gesetzt sind ([STORES.md](STORES.md), [RELEASE.md](RELEASE.md)).

- [ ] Konten für WebBude anlegen (Projektmitglied): Steam Direct, Google Play als Organisation und Apple Developer Program (iOS und notarisierte macOS-Version, zum Release nötig, D-179); Kosten und Fristen in STORES.md.
- [ ] Erster echter Upload: Windows in einen Steam-Beta-Branch, Android in die Play-Spur „Interner Test“, iOS nach TestFlight, ohne Handarbeit aus der CI.
- [ ] Dedicated-Server-Export (Linux, headless) als Artefakt in der CI, damit er nicht unbemerkt kaputtgeht.
- [ ] Signaturschlüssel nur als Secrets, Originale im Passwort-Manager; nie im Repo (D-148).

**Koop-Check:** alle Builds einer Version tragen dieselbe `protocolVersion`, sonst finden sie sich im Relay nicht.

## Lokal testen (ohne Stores)

| Was | Wie |
| --- | --- |
| Dienste | im Plattform-Repo `bun run services:up`, dann `bun dev` (API 8787, Relay 8790) |
| Vier Spieler auf einem PC | Godot *Debug → Ausführungsinstanzen anpassen*, `-- instance=1..4`, Beitritt per Raumcode ([MULTIPLAYER.md](MULTIPLAYER.md) §3b) |
| Handy (Android) | Export per USB, `adb reverse tcp:8787 tcp:8787` und `adb reverse tcp:8790 tcp:8790` |
| Browser | `game-dev.playsoulwick.com` gegen die Test-Server; lokal [WEB_BUILD.md](WEB_BUILD.md) §7 |
| Steam | Test-AppID 480 mit `steam_appid.txt`; zwei Steam-Konten brauchen zwei Rechner |
| Schlechtes Netz | Relay-Optionen `--sim-latency` und `--sim-loss` |
| Automatisch | `tools/net_smoke.gd`, `tools/net_run_smoke.gd`; `bun test` im Plattform-Repo |

## Dedizierter Server (später)

Godot exportiert einen „Dedicated Server“ (Linux, headless). Er wird ein eigenes Paket, sobald eines davon stört: Handy- oder Browser-Hosts (App bzw. Tab im Hintergrund = Run-Ende nach D-085), Cheats in Ranglisten oder häufige Host-Abbrüche. Hosting zuerst als Container auf dem eigenen VPS (Dokploy), bei Bedarf über einen Anbieter mit Regionen. Voraussetzung im Code steht schon: Die Spielwelt setzt keinen eigenen Spieler beim Host voraus ([MULTIPLAYER.md](MULTIPLAYER.md) §4a).

## Koop-Check für Crossplay-Pakete

Zusätzlich zu den fünf Fragen aus [ROADMAP_AUSBAU.md](ROADMAP_AUSBAU.md) beantwortet jeder Bericht mit „ja“:

- [ ] Eingabequelle (Maus, Touch, Controller, Netz) ist eine Implementierung des Eingabe-Objekts aus MP1; Spiellogik fragt nie `Input` direkt.
- [ ] Verbindungsart hinter `MultiplayerPeer` austauschbar; keine Spiellogik kennt die Plattform.
- [ ] Konto, Token, Identitäten und Käufe am lokalen Client (`online/session.gd`) bzw. auf dem Server, nicht in einem neuen Autoload (D-044).
- [ ] Plattform-SDKs (GodotSteam, Play Games, Game Center, Billing, Werbung) nur über `PlatformServices` mit Null-Implementierung für Editor, Headless und Browser, damit alle Tests ohne SDK laufen.

## Risiken

- **iOS braucht Apple-Konto und Mac:** Signieren nur mit Xcode auf macOS; ohne eigenen Mac über den macOS-Läufer der CI (`tools/ci/ios_build.sh`, für die macOS-Version `tools/ci/macos_sign.sh`), dazu die jährliche Apple-Gebühr und die D-U-N-S-Nummer. Weil iOS zum Release gehört (D-179), muss das vor dem Release stehen; getestet wird über TestFlight auf echten Geräten.
- **Gemeinsamer Release:** drei Store-Prüfungen gleichzeitig; eine Ablehnung verschiebt den Termin für alle (Vorschlag: Termin erst nach bestandenen Prüfungen festlegen, CP4).
- **Leistung auf Handys:** Sicht-Shader, Nachbearbeitung, moderner Look (Strang L) und ×2,8 Gegner bei vier Spielern auf schwachen Geräten.
- **Eigener Relay = Betrieb:** Kosten, Datenvolumen, Latenz außerhalb Europas (Frage 10), Angriffsfläche; Einzelspieler bleibt offline spielbar.
- **Versionsversatz zwischen Stores:** Crossplay braucht dieselbe `protocolVersion`; das Hauptmenü sperrt Online mit Update-Hinweis (P16).
- **Store-Prüfungen und Zielgruppe:** Wer in der Play Console „unter 13“ angibt oder als kindgerichtet eingestuft wird, unterliegt den Familien-Richtlinien (Werbung, Daten, Login); deshalb Zielgruppe ab 13 und kindgerechte Werbung von Anfang an (D-173, CP6).
- **Werbung und Datenschutz:** Ein Werbe-SDK bringt Werbe-ID, Einwilligungsdialog und neue Store-Angaben; falsch eingestellt gefährdet es die Store-Freigabe.
- **Rechte und Lizenzen** (MP10, D-177): Vertrag mit allen Mitwirkenden, GPL und Store-/Steamworks-Bedingungen mit Fachanwalt, Marke „Soulwick“ prüfen. Klären, bevor Geld fließt.
- **Zwei Spielstand-Wahrheiten** (Steam Cloud und Soulwick-Cloud): nur eine wählen (CP5).
- **Betrug:** Der Host rechnet (D-082); Käufe prüft trotzdem immer der Server (D-177).

**Weiterlesen:** [ROADMAP.md](ROADMAP.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [STORES.md](STORES.md) · [LAUNCH.md](LAUNCH.md) · [MULTIPLAYER.md](MULTIPLAYER.md) · [DECISIONS.md](DECISIONS.md) · `soulwick-platform/docs/ROADMAP.md`
