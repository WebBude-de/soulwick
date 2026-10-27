# Stores und Signaturen: Checkliste je Plattform

> **Stand:** 17.10.2026 · Pipeline: [RELEASE.md](RELEASE.md), [`.github/workflows/release.yml`](../.github/workflows/release.yml) · Roadmap: [ROADMAP.md](ROADMAP.md) CP4, CP6, CP7, MP10 · Entscheidungen: D-119 (Publisher WebBude), **D-179** (gemeinsamer Release auf allen Stores, Store-Knöpfe der Website), D-148 (Releases), **D-173** (Zielgruppe ab 13, keine Kinder-Bereiche), **D-176** (Preise und Modell), **D-177** (Code offen, Inhalte geschützt)
>
> Preise, Fristen und Store-Vorgaben ändern sich. Sie sind hier nach bestem Wissen (Oktober 2026) eingetragen und **vor jeder Zahlung bzw. Einreichung auf der Seite des Stores zu prüfen**. Alles mit Geld, Konten und Verträgen entscheidet das Projektmitglied für WebBude.

Die Pipeline ist für alle Stores **vorbereitet**: Ohne Secrets läuft sie wie bisher (GitHub-Release mit Windows, Linux, macOS und APK, dazu ein iOS-Xcode-Projekt als Artefakt), mit Secrets kommen Signaturen und Uploads dazu. Welche Schritte ein Lauf macht, steht oben in der Lauf-Zusammenfassung („Signaturen und Stores in diesem Lauf“).

## 0. Überblick

| Plattform | Ohne Konto/Secrets (heute) | Mit Konto und Secrets | Konto, Kosten |
| --- | --- | --- | --- |
| Windows | `Soulwick.exe` im ZIP, unsigniert (SmartScreen-Warnung) | Authenticode-Signatur in der Pipeline | Code-Signing: Azure Trusted Signing ≈ 10 USD/Monat oder Zertifikat ≈ 200–400 €/Jahr |
| Linux | ZIP mit `Soulwick.x86_64` | – (Linux braucht keine Signatur) | – |
| macOS | Universal-App, ad-hoc signiert, nicht notarisiert (Gatekeeper-Warnung) | Developer-ID-Signatur + Notarisierung | Apple Developer Program 99 USD (in DE 99 €) pro Jahr |
| Android | APK zum Selbst-Installieren | AAB für Google Play, Upload in „Interner Test“ | Google Play 25 USD einmalig |
| iOS | Xcode-Projekt als Artefakt (Mac + Xcode zum Bauen) | signierte IPA, Upload zu TestFlight | Apple Developer Program (s. o.) |
| Steam | – | Upload per SteamPipe auf einen Beta-Branch | Steam Direct 100 USD je App |
| Browser | Dokploy (D-148, nicht hier) | – | – |

**Release (D-179):** gemeinsam auf Steam, Google Play und App Store, dazu die Browser-Version; das ersetzt die Reihenfolge Steam → Google Play → App Store aus D-119. Darum alle drei Konten früh anlegen (Apple braucht die D-U-N-S-Nummer, Tage bis Wochen) und den Termin erst festlegen, wenn alle Prüfungen durch sind: Steam 30 Tage Wartezeit nach Steam Direct und mindestens 2 Wochen „Demnächst verfügbar“ (§5), Google einige Tage beim ersten Produktions-Release (§3), Apple meist 1–3 Tage (§4). Windows-Signatur lohnt sich zuerst für Steam nicht (Steam startet die EXE ohne SmartScreen), sondern für den Direkt-Download auf GitHub und der Website.

**Was in jeden Store-Eintrag gehört:**

- **Preis und Modell (D-176, Arbeitsentscheidung):** Steam mit kleinem Preis (Größenordnung 3–5 €, genauer Preis OFFEN), ohne Werbung, Start-Kosmetik inklusive; Google Play und App Store **kostenlos**, später Werbung (nur Handy, nur zwischen Runs), „Werbefrei“ als Einmalkauf und Kosmetik (ROADMAP CP6); Browser kostenlos. Verkauft werden nur Kosmetik und Werbefreiheit, **keine Lootboxen**.
- **Umfang (D-179):** Store-Seiten beschreiben den Release-Umfang wie vorhanden: Koop mit Freunden, KI-Bosse („Wünsch dir einen Boss“), Flint als Begleiter, Dorf ausbauen und Freunde ins Dorf einladen. Der Party-Modus kommt nach dem Release. Released wird erst nach dem Release-Tor in [ROADMAP.md](ROADMAP.md), auf allen Stores gemeinsam.
- **Zielgruppe (D-173):** ab 13; nie für Kinder-Bereiche anmelden (Google Play Familienprogramm, Apple Kids), keine Werbung an Kinder. Die Altersfreigabe ergibt sich aus den Fragebögen (§7), nicht aus unserer Wahl.
- **Lizenz (D-177):** Code GPL-3.0; Grafik, Musik, Klang, Logo, der Name „Soulwick“ und die Figuren (Flint, Huhn) alle Rechte vorbehalten (`LICENSE-ASSETS.md` in beiden Repos). GPL mit App-Store- und Steamworks-Bedingungen vor dem ersten Store-Release mit Fachanwalt klären (D-177 OFFEN).

**Wo die Secrets hinkommen:** GitHub → Repository `WebBude-de/soulwick` → *Settings → Secrets and variables → Actions*. **Secrets** sind geheim (Schlüssel, Passwörter, Zertifikate; GitHub maskiert sie im Log). **Variables** sind nicht geheim (App-ID, Branch-Namen). Das Repo ist öffentlich: Schlüsseldateien, Passwörter, Zertifikate und Profile **nie** ins Repo, nie in Issues, Chats oder Mails. Dateien als Base64 hinterlegen:

```powershell
# Windows PowerShell: Datei als Base64 in die Zwischenablage
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Pfad\datei.p12")) | Set-Clipboard
```

```bash
# Git Bash / macOS / Linux: direkt als Secret (GitHub-CLI)
base64 -w0 datei.p12 | gh secret set NAME --repo WebBude-de/soulwick     # macOS: base64 -i datei.p12
```

Jedes Original (Keystore, `.p12`, `.p8`, Passwörter) gehört zusätzlich in den Passwort-Manager des Teams. Ein verlorener Android-Upload-Schlüssel lässt sich über Google zurücksetzen, ein verlorenes Apple-Zertifikat neu ausstellen; die Original-Dateien sind trotzdem die einzige Kopie, die wir haben.

**Alle Namen auf einen Blick** (Details in den Abschnitten):

| Art | Name | Plattform | Abschnitt |
| --- | --- | --- | --- |
| Secret | `ANDROID_DEBUG_KEYSTORE_BASE64` | Android (APK, development) | [RELEASE.md](RELEASE.md) §4 |
| Secret | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Android (APK production, **AAB**) | §3 |
| Secret | `PLAY_SERVICE_ACCOUNT_JSON` | Google Play Upload | §3 |
| Variable | `PLAY_TRACK` (Standard `internal`), `PLAY_RELEASE_STATUS` (Standard `completed`) | Google Play Upload | §3 |
| Secret | `APPLE_TEAM_ID` | iOS, macOS | §4 |
| Secret | `IOS_DISTRIBUTION_CERT_BASE64`, `IOS_DISTRIBUTION_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64` | iOS | §4 |
| Secret | `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64` | TestFlight, macOS-Notarisierung | §4 |
| Secret | `MACOS_DEVELOPER_ID_CERT_BASE64`, `MACOS_DEVELOPER_ID_CERT_PASSWORD` | macOS | §2 |
| Secret | `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_SIGNING_PROFILE`, `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` | Windows (Weg A) | §1 |
| Secret | `WINDOWS_SIGN_PFX_BASE64`, `WINDOWS_SIGN_PFX_PASSWORD` | Windows (Weg B) | §1 |
| Secret | `STEAM_USERNAME`, `STEAM_CONFIG_VDF` | Steam | §5 |
| Variable | `STEAM_APP_ID`, optional `STEAM_DEPOT_WINDOWS`, `STEAM_DEPOT_LINUX`, `STEAM_DEPOT_MACOS`, `STEAM_BRANCH` (Standard `beta`), `STEAM_BRANCH_DEVELOPMENT`, `STEAM_PREVIEW` | Steam | §5 |
| Variable | `RELEASE_ENV`, `WEB_PLAY_URL` | alle | [RELEASE.md](RELEASE.md) §4 |

**Store-Uploads abschalten:** Bei „Run workflow“ das Häkchen *store_upload* entfernen; dann baut der Lauf alles, lädt aber nichts zu Steam, Google Play oder TestFlight hoch. Tags laden immer hoch, sobald die Secrets da sind.

**Versionsnummern für Stores:** Jeder Upload braucht eine neue, größere Build-Nummer, auch für Testbuilds derselben Version. Die Pipeline rechnet sie aus dem Tag (`tools/ci/release_meta.sh`): `(Major·10000 + Minor·100 + Patch)·100 + Zähler`, Zähler = 99 für ein normales Release, sonst die Zahl am Ende des Tags (höchstens 98).

| Tag | Android `versionCode` (AAB) / iOS Build | APK (Selbst-Installieren) |
| --- | --- | --- |
| `v0.9.1-beta.1` | 90101 | 901 |
| `v0.9.1-beta.2` | 90102 | 901 |
| `v0.9.1` | 90199 | 901 |
| `v0.9.2-beta.1` | 90201 | 902 |

Darum Testbuilds für die Stores als `v<version>-beta.<n>` taggen. Manuelle Läufe heißen `-dev.<Laufnummer>`/`-rc.<Laufnummer>`; ab Lauf 98 bekommen sie alle den Zähler 98, dann lehnt der Store den zweiten ab → Version erhöhen. Die APK behält die kurze Nummer, damit lokal gebaute APKs weiter als Update installieren.

## 1. Windows

**Stand:** Die EXE ist unsigniert. Wer sie aus dem ZIP startet, sieht einmal SmartScreen („Unbekannter Herausgeber → Weitere Informationen → Trotzdem ausführen“). Über Steam erscheint diese Warnung nicht.

**Lokal testen (ohne alles):** `powershell -ExecutionPolicy Bypass -File tools/export_build.ps1` baut `builds\development\<version>\windows\Soulwick.exe`; doppelklicken genügt ([RELEASE.md](RELEASE.md) §7).

**Signieren in der Pipeline** (`tools/ci/sign_windows.sh`, Werkzeug jsign, läuft auf dem Linux-Läufer; die eingebettete `.pck` liegt in einem eigenen PE-Abschnitt und übersteht die Signatur, lokal geprüft):

- **Weg A, empfohlen: Azure Trusted Signing** (bei Microsoft inzwischen „Artifact Signing“). Kein USB-Token, etwa 10 USD/Monat (Basic). Voraussetzung laut Microsoft: Organisation mit nachweisbarer Geschäftsgeschichte (bisher drei Jahre) in einem unterstützten Land, darunter EU-Staaten; vor dem Abschluss prüfen, ob WebBude das erfüllt.
  1. Azure-Konto für WebBude, Ressource „Trusted Signing Account“ anlegen (Region z. B. West Europe → Endpunkt `https://weu.codesigning.azure.net`).
  2. Identitätsprüfung (Organisation) abschließen, Zertifikatsprofil „Public Trust“ anlegen.
  3. App-Registrierung (Microsoft Entra ID) mit Client-Secret anlegen und ihr auf dem Konto die Rolle „Trusted Signing Certificate Profile Signer“ geben.
  4. Secrets: `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT` (Kontoname), `AZURE_SIGNING_PROFILE` (Profilname), `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`.
- **Weg B: Zertifikat als Datei** `WINDOWS_SIGN_PFX_BASE64` + `WINDOWS_SIGN_PFX_PASSWORD`. Seit Juni 2023 geben die Zertifizierungsstellen neue OV/EV-Zertifikate nur noch auf Hardware-Token oder in Cloud-HSMs aus; eine `.pfx`-Datei gibt es praktisch nur noch für ältere Zertifikate. Cloud-HSMs (SSL.com eSigner, DigiCert KeyLocker, Google/AWS KMS) unterstützt jsign auch; dafür müsste `sign_windows.sh` um den jeweiligen `--storetype` erweitert werden.

**Hinweis:** Auch signierte EXEs warnen bei SmartScreen anfangs, bis die Signatur „Reputation“ hat (Downloads über Wochen). Microsoft Store ist ein möglicher späterer Weg (signiert dort selbst), aktuell nicht geplant.

## 2. macOS

**Stand:** Universal-App (Intel + Apple Silicon), ad-hoc signiert, **nicht notarisiert**: Gatekeeper blockiert den ersten Start (Anleitung in [RELEASE.md](RELEASE.md) §6). Für Steam reicht das zum Testen, für einen öffentlichen Download nicht; zum Release (D-179) kommt die notarisierte Version mit dem Apple-Konto.

**Mit Konto** (`tools/ci/macos_sign.sh`, Job `macos_sign` auf `macos-latest`): signiert mit „Developer ID Application“ und Hardened Runtime (ohne Ausnahmen: kein JIT, keine fremden Bibliotheken), notarisiert mit `notarytool`, heftet das Ticket an (`stapler`) und ersetzt das ZIP. GitHub-Release und Steam nehmen dann die notarisierte App; die Release-Notizen lassen den Gatekeeper-Hinweis weg.

1. **Apple Developer Program** für WebBude (Organisation: D-U-N-S-Nummer nötig, kostenlos bei Dun & Bradstreet, dauert Tage bis Wochen), 99 USD bzw. 99 €/Jahr. Dasselbe Konto gilt für iOS (§4).
2. Zertifikat **„Developer ID Application“** anlegen (nur der Account Holder darf das): Xcode → Settings → Accounts → Manage Certificates, oder developer.apple.com → Certificates. Auf einem Mac aus der Schlüsselbundverwaltung **mit privatem Schlüssel** als `.p12` exportieren (eigenes Passwort).
3. **App-Store-Connect-API-Schlüssel** (§4, Punkt 4) – derselbe wie für TestFlight.
4. Secrets: `APPLE_TEAM_ID`, `MACOS_DEVELOPER_ID_CERT_BASE64`, `MACOS_DEVELOPER_ID_CERT_PASSWORD`, dazu die drei `APP_STORE_CONNECT_API_*`. Fehlt der API-Schlüssel, bleibt der Build unsigniert (Warnung im Lauf), weil eine Signatur ohne Notarisierung nichts bringt.

**Später mit GodotSteam (MP6/MP10):** `libsteam_api.dylib` liegt dann in `Contents/Frameworks`; das Skript signiert alles dort mit. Kommen weitere GDExtensions dazu, im Lauf auf Fehler der Notarisierung achten.

## 3. Android / Google Play

**Stand:** APK zum Selbst-Installieren (wie bisher). Neu: Job `android_aab` baut ein **Android App Bundle** über Gradle (Godot-Android-Build-Vorlage, NDK 29), signiert mit dem Release-Schlüssel (= Upload-Schlüssel für Play), prüft es (`tools/ci/check_aab.sh`: Paket, `versionCode`, Ziel-API, Signatur) und legt es als Artefakt `store-android-aab` ab (30 Tage). Der Job läuft nur, wenn `ANDROID_KEYSTORE_BASE64` gesetzt ist; ohne bleibt es bei der APK.

**Werte im Bundle:** Paket `com.webbude.soulwick`, `minSdk` 24 (Android 7), **`targetSdk` 36** (Android 16). Google Play verlangt für neue Apps und Updates die Ziel-API des Vorjahres; ab 31.08.2026 ist das API 36 (vor der Einreichung in der Play Console unter „Richtlinienstatus“ prüfen; die Prüfung im Lauf schlägt unter 36 fehl, Wert `MIN_TARGET_SDK` in `check_aab.sh`). 64-Bit (arm64-v8a) und 32-Bit-ARM sind drin; 16-KB-Speicherseiten unterstützt Godot 4.7 mit AGP 8.6.

**Build-Vorlage:** `android/` liegt nicht im Repo; die Pipeline legt sie je Lauf frisch aus den Export-Vorlagen an (`--install-android-build-template`). Erst wenn ein Plugin (Google Play Games, Billing, Werbung) Änderungen daran braucht, wird `android/` eingecheckt.

**Bis zur Veröffentlichung:**

1. **Konto:** Google Play Console als **Organisation** WebBude (25 USD einmalig, D-U-N-S-Nummer, Identitätsprüfung). Persönliche Konten, die nach November 2023 angelegt wurden, müssen vor der Produktion 14 Tage lang mit mindestens 12 Testern geschlossen testen; Organisationskonten nicht (ROADMAP CP7).
2. **Release-Schlüssel** erzeugen und hinterlegen: [RELEASE.md](RELEASE.md) §4 („Release-Keystore erzeugen“); Secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Dieser Schlüssel ist für Play der **Upload-Schlüssel**.
3. App in der Play Console anlegen (Name „Soulwick“, Spiel, **kostenlos**, D-176). Eine kostenlose App lässt sich bei Google später nicht mehr kostenpflichtig machen; Geld kommt über In-App-Käufe (CP6).
4. Tag `v<version>-beta.1` pushen → Artefakt `store-android-aab` aus dem Lauf herunterladen → **das erste AAB von Hand** hochladen: *Testen → Interner Test → Neuer Release*. Dabei **Play App Signing** aktivieren (Google verwaltet den App-Signaturschlüssel, unser Schlüssel bleibt Upload-Schlüssel und ist bei Verlust über den Support ersetzbar).
5. **Interner Test:** Tester-Liste (bis 100 Google-Konten per E-Mail), Opt-in-Link an die Tester schicken. Interne Tests brauchen keine Prüfung durch Google.
6. **Automatischer Upload (optional):**
   1. Google Cloud: Projekt anlegen, „Google Play Android Developer API“ aktivieren, Dienstkonto anlegen, JSON-Schlüssel erzeugen.
   2. Play Console → *Nutzer und Berechtigungen* → Dienstkonto-E-Mail einladen, für die App: „Releases für Test-Tracks verwalten“ (für Produktion zusätzlich „Releases in Produktion …“).
   3. Secret `PLAY_SERVICE_ACCOUNT_JSON` = Inhalt der JSON-Datei (so wie sie ist oder Base64).
   4. Ab jetzt lädt jeder Lauf das AAB in den Track `PLAY_TRACK` (Standard `internal`) hoch (`tools/ci/play_upload.sh`, ohne Fremd-Action). Ist die App selbst in der Console noch ein Entwurf, verlangt Google `PLAY_RELEASE_STATUS=draft` (Variable) und die Freigabe von Hand.
7. **Store-Eintrag:** Texte DE/EN, Grafiken (§6), Datenschutzerklärung-URL, Kontakt-E-Mail, Kategorie „Spiele → Action“ oder „Rollenspiel“, Formular **„Datensicherheit“** (§8), **Inhaltsbewertung** (IARC, §7), **Zielgruppe ab 13** (D-173; nicht im Familienprogramm, sonst greifen die Familien-Richtlinien; die Altersfreigabe ist davon unabhängig; OFFEN in D-173: ob Google das Spiel wegen des niedlichen Maskottchens trotzdem als „spricht Kinder an“ einstuft), **Werbung: nein**, bis CP6 Werbung auf dem Handy einbaut (dann „Ja“ und das Formular „Datensicherheit“ neu), App-Zugriff: „ohne Anmeldung nutzbar“.
8. Konto-Löschung als **Webseite** angeben (Pflicht für Apps mit Konto; Plattform P15) und in der App (Hauptmenü).
9. Geschlossener Test → offener Test → Produktion (gestaffelter Rollout). Google prüft beim ersten Produktions-Release einige Tage.

## 4. iOS / App Store

**Stand:** Job `ios` auf `macos-latest` exportiert bei jedem Lauf das **Xcode-Projekt** (Artefakt `store-ios-xcode`, 30 Tage) – Version aus `project.godot`, Build-Nummer wie Android, Bundle-ID `com.webbude.soulwick`, iPhone und iPad, Ausrichtung nach Sensor (quer und hochkant, D-182), deckendes Übergangs-Icon `deploy/web/icons/icon_512.png`. Ohne Apple-Secrets ist das alles; Fehler in diesem Job färben den Lauf nicht rot. **Mit Secrets** baut `tools/ci/ios_build.sh` daraus Archiv und **IPA** (Artefakt `store-ios-ipa`) und lädt sie optional zu **TestFlight** hoch.

**Voraussetzung: Apple Developer Program** (99 USD bzw. 99 €/Jahr, Organisation WebBude mit D-U-N-S-Nummer). Weil iOS zum Release gehört (D-179), muss das Konto vor dem Release stehen; anlegen und bezahlen entscheidet das Projektmitglied für WebBude. Ohne Konto keine IPA, kein TestFlight, kein App Store. Ein eigener Mac ist nicht nötig: Signieren und Hochladen laufen auf dem macOS-Läufer von GitHub (für öffentliche Repos kostenlos). Zum Ansehen auf dem iPhone reicht dann TestFlight.

**Bis zur Veröffentlichung:**

1. Konto anlegen, **Team-ID** notieren (developer.apple.com → Membership) → Secret `APPLE_TEAM_ID`.
2. **App-ID** `com.webbude.soulwick` registrieren (Identifiers; keine Zusatzfunktionen nötig; Game Center erst mit CP1).
3. Zertifikat **„Apple Distribution“** erstellen (Certificates → `+`), auf einem Mac als `.p12` mit privatem Schlüssel exportieren → `IOS_DISTRIBUTION_CERT_BASE64`, `IOS_DISTRIBUTION_CERT_PASSWORD`. Ohne Mac: Zertifikatsanfrage (CSR) mit `openssl` erzeugen, Zertifikat herunterladen und mit `openssl pkcs12 -export` zur `.p12` verbinden.
4. **App-Store-Connect-API-Schlüssel:** App Store Connect → Benutzer und Zugriff → Integrationen → Team-Schlüssel, Rolle „App-Manager“. Die `.p8`-Datei gibt es nur einmal zum Download → `APP_STORE_CONNECT_API_KEY_BASE64` (Base64 der ganzen Datei), dazu `APP_STORE_CONNECT_API_KEY_ID` (Schlüssel-ID) und `APP_STORE_CONNECT_API_ISSUER_ID` (Aussteller-ID oben auf der Seite). Derselbe Schlüssel notarisiert macOS (§2).
5. **Bereitstellungsprofil** „App Store Connect“ (früher „App Store“) für die App-ID und das Distributionszertifikat anlegen, herunterladen → `IOS_PROVISIONING_PROFILE_BASE64`. Läuft nach einem Jahr ab, mit dem Zertifikat erneuern.
6. **App in App Store Connect anlegen** (Name, Hauptsprache Deutsch, Bundle-ID, SKU z. B. `soulwick`). Ohne diesen Eintrag nimmt TestFlight keinen Upload an.
7. Tag `v<version>-beta.1` pushen → IPA landet in TestFlight (Verarbeitung durch Apple: Minuten bis eine Stunde). **Interne Tester** (bis 100 Mitglieder des Teams) sofort; **externe Tester** (bis 10 000, per Link) nach einer kurzen Beta-Prüfung.
8. **Store-Eintrag:** Texte, Screenshots für iPhone **und** iPad (§6), Datenschutz-URL, Support-URL, **App-Datenschutz** („Nutrition Labels“, §8), **Altersfreigabe** (Apple-Fragebogen, §7; Kategorie nicht „Kinder“, D-173), Exportvorschriften: nur HTTPS → „keine Verschlüsselung außer der Standard-Ausnahme“ (Godot setzt `ITSAppUsesNonExemptEncryption = NO`).
9. Prüfregeln, die uns betreffen: digitale Käufe nur über In-App-Kauf (3.1.1), keine Lootboxen (D-176); Konto löschen **in der App** (5.1.1 (v)), Melden und Filtern nutzergenerierter Namen (1.2; Filter für anstößige Namen ist laut D-152 noch offen), Sign in with Apple nur bei Social-Login (CP0 Frage 8, OFFEN), Spiel muss ohne Konto spielbar sein (ist es: Gastkonto).
10. Einreichen zur App-Prüfung (meist 1–3 Tage).

**Noch offen im Projekt:** GPL-3.0 und App-Store-Nutzungsbedingungen (D-177 OFFEN); Touch-Steuerung auf dem iPhone getestet? (CP2: Gerätetest offen); Renderer `gl_compatibility` läuft auf iOS über ANGLE/Metal, Leistung auf einem echten Gerät prüfen; Safe Area (Notch, Dynamic Island) prüfen.

## 5. Steam

**Stand:** Job `steam` lädt Windows, Linux und macOS (notarisiert, falls §2 eingerichtet) per **steamcmd/SteamPipe** hoch und setzt den Build auf einen **Beta-Branch** live. Vorlagen: [`tools/steam/app_build.vdf`](../tools/steam/app_build.vdf), [`tools/steam/depot_build.vdf`](../tools/steam/depot_build.vdf), Skript [`tools/steam/steam_upload.sh`](../tools/steam/steam_upload.sh). Den Standard-Branch (`default`) schaltet immer ein Mensch in Steamworks frei; das Skript verweigert ihn.

**Nicht hier:** Steamworks im Spiel (GodotSteam, Anmeldung, Freunde einladen, Rich Presence, Erfolge, Steam Cloud) gehört zur Multiplayer-Roadmap ([ROADMAP.md](ROADMAP.md) MP6 und MP10). Der Upload funktioniert auch ohne: Steam startet die EXE einfach.

**Bis zur Veröffentlichung:**

1. **Steamworks-Konto** für WebBude (partner.steamgames.com): Firmendaten, Steuerformular (W-8BEN-E), Bankkonto, Identitätsprüfung.
2. **Steam Direct:** 100 USD je App (wird nach 1 000 USD Umsatz der App erstattet). Danach **30 Tage Wartezeit** bis zum frühesten Release; die Store-Seite muss mindestens **2 Wochen** als „Demnächst verfügbar“ sichtbar sein. Valve prüft Store-Seite und Build (je einige Werktage).
3. App-ID notieren → Variable `STEAM_APP_ID`.
4. **Depots** in Steamworks → SteamPipe → Depots: eins je Betriebssystem (Windows, Linux + SteamOS, macOS). Steam schlägt die IDs App-ID + 1, + 2, … vor; weichen sie ab, Variablen `STEAM_DEPOT_WINDOWS`, `STEAM_DEPOT_LINUX`, `STEAM_DEPOT_MACOS` setzen.
5. **Startoptionen** (Installation → Allgemein): Windows `Soulwick.exe`, Linux `Soulwick.x86_64` (Steam Linux Runtime 3.0 „sniper“ wählen), macOS `Soulwick.app`. Danach „Veröffentlichen“ in Steamworks.
6. **Branch** `beta` anlegen (SteamPipe → Builds → Branches; mit Passwort für eine geschlossene Testgruppe). Eigener Branch für development-Builds: z. B. `dev` anlegen und Variable `STEAM_BRANCH_DEVELOPMENT=dev` setzen; ohne gehen beide Umgebungen auf `STEAM_BRANCH` (Standard `beta`).
7. **Build-Konto:** eigenes Steam-Konto nur für die Pipeline (nicht das persönliche) mit Steam Guard per E-Mail; in Steamworks → Benutzer und Berechtigungen nur „Edit App Metadata“ und „Publish App Changes To Steam“ für Soulwick.
8. **`config.vdf` erzeugen** (einmal, auf einem eigenen Rechner): steamcmd installieren, `steamcmd +login <build-konto>` → Passwort und Steam-Guard-Code eingeben → `quit`. Die Datei `config/config.vdf` im steamcmd-Ordner (Linux/macOS oft `~/Steam/config/config.vdf`) enthält danach den Anmelde-Token. Secrets: `STEAM_USERNAME` = Kontoname, `STEAM_CONFIG_VDF` = Base64 dieser Datei. Meldet der Lauf später „Steam login failed“, ist der Token abgelaufen → Schritt wiederholen.
9. Tag pushen → Build erscheint unter SteamPipe → Builds und ist im Branch live. Testen: Steam-Bibliothek → Soulwick → Eigenschaften → Betas.
10. **Steam Playtest** (eigene Playtest-App, kostenlos) für Freunde ohne Kauf, optional.
11. **Store-Seite:** Texte DE/EN, Grafiken (§6), Systemanforderungen, Fragebogen zu Inhalten (§7), **kleiner Preis** (Größenordnung 3–5 €, D-176, genauer Preis OFFEN), keine Werbung, Start-Kosmetik inklusive; Kosmetik später als Steam-Mikrotransaktion (CP6). Dann „Demnächst verfügbar“, nach mindestens 2 Wochen Release.

**Probelauf ohne Upload:** Variable `STEAM_PREVIEW=1` setzen: steamcmd prüft Anmeldung, Depots und Dateien, lädt aber nichts hoch und setzt nichts live. Danach die Variable wieder löschen.

## 6. Store-Texte, Grafiken und Screenshots

**Grafiken geliefert** (17.10.2026, Maße und Dateinamen in [SPRITES_V11.md](design/sprites/delivered/SPRITES_V11.md), Ablage `art/store/`). Neue Motive mit dem Maskottchen Flint folgen mit [SPRITES_V13.md](design/sprites/SPRITES_V13.md). **Es fehlen noch Texte und Screenshots.**

**Store-Knöpfe auf der Website (D-179):**

- **Vor dem Release** (noch keine Store-Links): eigene Pixel-Knöpfe ohne fremde Logos oder Badges, nur mit Plattformnamen („Browser“, „PC · Steam“, „Android“, „iPhone & iPad“) und dem Zustand „zum Release“ / „at release“.
- **Mit echtem Store-Link** (`soulwick-platform/apps/web/content/stores.json`: `steam`, `google_play`, `app_store`) und `LIVE_FEATURES=true`: das offizielle Badge des Stores, unverändert, als Link auf die Produktseite; es darf in unserem Pixel-Rahmen stehen, wird aber nicht nachgezeichnet.
- **Regeln der Stores** (vor dem Einbau auf deren Badge-Seiten nachlesen): **Apple** – Badge unverändert, nur als Link auf die App im App Store, in einer Reihe mit anderen Stores zuerst. **Google** – Farbe, Proportionen und Abstand nicht ändern, Link auf die App, mindestens so groß wie andere Badges daneben. **Valve** – nur freigegebene Steam-Grafiken, unverändert, nicht mit anderen Logos verbunden.
- **Badge-Dateien** nur von den offiziellen Badge-Seiten und nur, wenn sie ohne Anmeldung herunterladbar sind; sonst bleibt ein Platz mit Dateinamen in `soulwick-platform/apps/web/public/brand/README.md` und `soulwick-platform/docs/design/web/BRIEFING_WEB.md`.

**Ton der Texte:** für Spieler ab 13, nicht an Kinder gerichtet (D-173); Kernsatz „Das Pixel-Roguelite, in das du mit Freunden reinrennst“ und Tagline „Grab your friends. Light the dark.“ (D-173, D-174); nach außen „moderne Pixel-Art“, nicht „8-Bit“; alles aus dem Release-Umfang (§0) steht wie vorhanden da, nur Späteres (Party-Modus) als „kommt“ (D-179); Beispiele für Wunschbosse sind erfunden, keine echten Personen (D-179 OFFEN); keine Engine-, Server- oder API-Wörter.

**Texte (je DE und EN):**

| Was | Länge | Wo |
| --- | --- | --- |
| Name | „Soulwick“ (Play ≤ 30, Apple ≤ 30 Zeichen) | alle |
| Kurzbeschreibung | ≤ 80 Zeichen (Play), Untertitel ≤ 30 (Apple), ≤ 300 (Steam) | alle |
| Beschreibung | ≤ 4 000 Zeichen (Play, Apple), Steam „Über dieses Spiel“ frei | alle |
| Werbetext | ≤ 170 Zeichen (Apple, änderbar ohne Prüfung) | Apple |
| Stichwörter | ≤ 100 Zeichen, kommagetrennt (Apple) | Apple |
| Neuigkeiten je Version | kurz, aus den Release-Notizen | alle |
| Support-E-Mail, Datenschutz-URL, Website | `/de/datenschutz`, `/en/privacy` (eRecht24) | alle |

**Screenshots und Trailer** (aus dem echten Spiel mit `tools/screenshots.gd`, dann zuschneiden; keine Mockups; Pixel-Art ganzzahlig skaliert):

| Datei (Vorschlag) | Maße | Store | Inhalt |
| --- | --- | --- | --- |
| `art/store/screenshots/desktop_*.png` | 1920×1080 | Steam (≥ 5), Play (Tablet/Chromebook) | Koop mit Freunden zuerst (D-173), Wunschboss mit Banner, Boss, Minispiel-Raum, Dorf mit Flint und Besuch, Upgrade-Auswahl |
| `art/store/screenshots/play_phone_*.png` | 1920×1080 quer | Google Play (2–8, für Empfehlungen ≥ 4 quer) | wie oben, mit Touch-Knöpfen |
| `art/store/screenshots/iphone69_*.png` | 2868×1320 quer (iPhone 6,9″) | Apple (1–10) | wie oben, mit Touch-Knöpfen |
| `art/store/screenshots/ipad13_*.png` | 2752×2064 quer (iPad 13″) | Apple (1–10, Pflicht, weil iPad unterstützt) | wie oben |
| Trailer (optional) | 1920×1080, 30–90 s; Apple-Vorschau 886×1920/1920×886, 15–30 s | alle (Play als YouTube-Link) | Spielszenen, kein Text-Overload |

## 7. Altersfreigabe

| Store | Verfahren | Hinweis |
| --- | --- | --- |
| Google Play | **IARC**-Fragebogen in der Play Console (kostenlos); ergibt USK, PEGI, ESRB usw. | Pflicht vor jedem Track außer „Intern“ |
| Apple | eigener Fragebogen in App Store Connect (Stufen 4+, 9+, 13+, 16+, 18+) | Pflicht vor der Einreichung |
| Steam | Inhaltsfragebogen in Steamworks (Gewalt, Online-Interaktion); Altersfreigaben (USK/PEGI) können dort ergänzt werden | Pflicht vor der Store-Prüfung |

Antworten, die für Soulwick gelten (Stand des Spiels, zur Prüfung durch das Team): Fantasy-Gewalt gegen nicht-menschliche Gegner (Skelette, Schleim, Schatten) in Pixel-Optik, kein Blut, keine Sprache mit Schimpfwörtern, keine Glücksspiel-Mechanik mit Echtgeld, bis CP6 keine Käufe (danach In-App-Käufe nur Kosmetik und Werbefrei, **keine zufälligen Gegenstände**, D-176), **Nutzer interagieren** (Koop über Raumcode, Spieler- und Gildennamen sind für andere sichtbar), keine Weitergabe des Standorts. Die Freigabe ergibt sich aus dem Fragebogen, wir wählen sie nicht (D-173, CP0 Frage 6); erwartet wird eine niedrige Stufe. Davon unabhängig ist die **Zielgruppe ab 13** (§0, §3). OFFEN (D-173): ob KI-Bosse (nutzergenerierte Inhalte), Käufe und Koop mit Fremden die Freigabe anheben. KI-Bosse und Dorf-Besuche gehören zum Release-Umfang (D-179) und damit schon in den ersten Fragebogen vor dem Release; mit Käufen und Werbung (CP6) neu ausfüllen.

## 8. Datenschutz-Angaben

Was das Spiel online schickt (Server `api.playsoulwick.com`, Relay `play.playsoulwick.com`; Test: `api-dev`/`play-dev`). Grundlage für Google „Datensicherheit“, Apple „App-Datenschutz“ und die Datenschutzerklärung (eRecht24, D-119). Mit dem Plattform-Team und dem Quelltext abgleichen, bevor es in die Formulare geht.

| Daten | Wann | Zweck | Google-Kategorie | Apple-Kategorie |
| --- | --- | --- | --- | --- |
| Geräte-/Installations-ID des **Gastkontos** (zufällig erzeugt, nicht die Hardware-ID) | erste Online-Nutzung | Anmeldung ohne Passwort | Geräte- oder andere IDs | Kennungen → Geräte-ID |
| Konto-ID, Anzeigename, Aussehen der Figur (D-152) | Login, Profiländerung | Konto, Anzeige für Mitspieler | Personenbezogene Daten → Nutzer-IDs; Name | Kennungen → Nutzer-ID; Kontaktinfo → Name |
| Run-Berichte (Räume, Zeit, Gold, Mitspieler), Gilde, Ranglisten | nach einem Online-Run | Spielfunktion, Ranglisten | App-Aktivitäten → Sonstige Aktionen | Nutzerinhalte → Gameplay-Inhalte |
| **Bug-Reports**: Text, Kategorien, Markierungen, **Screenshot des Spiels**, Kontext (Ort im Spiel, Seed, Auflösung, Sprache), Spielversion, Plattform | nur wenn der Spieler eine Meldung abschickt | Fehlerbehebung | App-Info und Leistung → Diagnose; Sonstige nutzergenerierte Inhalte | Diagnose; Nutzerinhalte → Kundensupport |
| IP-Adresse, Zeitpunkt (technisch, Server-Logs und Relay-Verbindung) | jede Verbindung | Betrieb, Missbrauchsschutz | (in der Datenschutzerklärung nennen; Google zählt reine Protokolldaten nicht als „erhoben“, prüfen) | – |
| Zum Release: Wünsche für KI-Bosse (Bausteine, ggf. Freitext), erzeugte Bosse (Beschreibung, Bilder), Meldungen (KI3, KI8) | beim Wünschen bzw. Melden | Spielfunktion, Moderation, Kosten; Verarbeitung beim KI-Anbieter als Auftragsverarbeiter in der Datenschutzerklärung nennen | App-Aktivitäten → Sonstige nutzergenerierte Inhalte | Nutzerinhalte → Gameplay-Inhalte |
| Zum Release: Dorf-Schnappschuss (Gebäudestufen, Deko, Zeitpunkt; keine Freitexte, WK6) | beim Freigeben des Dorfs für Besuche | Dorf besuchen | App-Aktivitäten → Sonstige nutzergenerierte Inhalte | Nutzerinhalte → Gameplay-Inhalte |
| Später: Steam-ID, Google-Play-Games-ID, Game-Center-ID (CP1) | Verknüpfung | Anmeldung | Nutzer-IDs | Kennungen |
| Später: Käufe (Store, Bestell-ID, Produkt, Quittung) und Berechtigungen (CP6) | Kauf | Kauf am Konto prüfen (D-177) | Finanzinformationen → Kaufverlauf | Käufe → Kaufverlauf |
| Später, nur Handy: Werbe-ID und Daten des Werbenetzwerks (CP6) | Anzeige zwischen Runs | Werbung (D-176) | Geräte- oder andere IDs; Werbung | Kennungen → Geräte-ID; ggf. Tracking |

Für alle Zeilen: **verknüpft mit dem Konto**, **nicht für Tracking oder Werbung**, **nicht an Dritte verkauft**, Übertragung **verschlüsselt** (HTTPS/WSS), **Löschung** auf Anfrage in der App und per Webseite (Plattform P15). Bis CP6: keine Werbe-ID, keine Analyse-SDKs, kein Standort. Mit Werbung auf dem Handy (D-176) ändern sich Formulare, Privacy Manifest und Datenschutzerklärung; dazu Einwilligung nach DSGVO und auf iOS App Tracking Transparency, nicht personalisierte Werbung als Standard (Vorschlag, Rücksicht auf jüngere Mitspieler, D-173).

iOS verlangt dieselben Angaben zusätzlich im **Privacy Manifest** (`PrivacyInfo.xcprivacy`, Godot-Optionen `privacy/collected_data/*` im iOS-Preset). Die Godot-Vorlage trägt die Gründe für die genutzten System-APIs (Dateizeit, Speicherplatz, Startzeit) schon ein; die erhobenen Datentypen setzen wir erst, wenn die Tabelle oben vom Team bestätigt ist.

## 9. Lokal bauen und prüfen

```bash
# Git Bash (Windows) / Linux / macOS
GODOT="C:/Tools/Godot/Godot_v4.7.2-stable_win64.exe" tools/export_build.sh development "" ios          # Xcode-Projekt
GODOT=... VERSION_CODE=90101 GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... GODOT_ANDROID_KEYSTORE_RELEASE_USER=soulwick \
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=... tools/export_build.sh development "" android-aab              # AAB (Gradle, JDK 17, SDK + NDK)
tools/ci/check_aab.sh builds/development/0.9.1/Soulwick-0.9.1-development-android.aab 90101
```

`tools/export_build.sh` legt die Presets „Android AAB“ und „iOS“ für den Export mit [`tools/ci/store_presets.py`](../tools/ci/store_presets.py) an und stellt `export_presets.cfg` danach wieder her. Ein Release-Schlüssel gehört auch lokal nur in eine Umgebungsvariable, nie in die Presets.
