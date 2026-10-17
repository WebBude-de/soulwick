# Releases und Builds

> **Stand:** 17.10.2026 · Entscheidung: [D-148](DECISIONS.md) · Workflows: [`.github/workflows/`](../.github/workflows/) · Hilfsskripte: [`tools/ci/`](../tools/ci/), [`tools/steam/`](../tools/steam/) · Stores, Signaturen, Konten: [STORES.md](STORES.md)

Windows-, Linux-, macOS- und Android-Builds baut **GitHub Actions** und legt sie als **GitHub-Release** ins Repo. Dieselbe Pipeline ist für die Stores vorbereitet (Google-Play-Bundle, iOS, Steam, Signaturen für Windows und macOS); diese Schritte laufen nur, wenn ihre Secrets gesetzt sind ([STORES.md](STORES.md)). Die **Browser-Version** baut und hostet Dokploy selbst (`Dockerfile`, `deploy/web/`, D-148); sie ist nicht Teil dieser Pipeline. Lokal geht dasselbe mit `tools/export_build.sh` bzw. `tools/export_build.ps1` (§7).

## 1. Was die Pipeline macht

| Workflow | Auslöser | Ergebnis |
| --- | --- | --- |
| `ci.yml` | Push auf `main`/`dev`, jeder Pull Request, „Run workflow“ | `validate_project.gd` + GUT (Linux, headless, ohne Ton); `actionlint` und `shellcheck` |
| `release.yml` | Tag `v*`, Push auf `dev` (D-157) oder „Run workflow“ | Prüfen → Exporte (Windows, Linux, macOS, Android) → Boot-Check des Linux-Builds → GitHub-Release |

Store-Schritte laufen nur, wenn ihre Secrets gesetzt sind (`tools/ci/store_flags.sh`; ohne Secrets übersprungen, der Lauf bleibt grün): Windows-Signatur, macOS-Notarisierung, Google-Play-Bundle (AAB) mit Upload in den internen Test, iOS-Xcode-Projekt bzw. IPA mit TestFlight, Steam-Beta-Branch ([STORES.md](STORES.md)). AAB, IPA und Xcode-Projekt kommen **nicht** ins öffentliche Release, sondern liegen 30 Tage als Artefakte am Lauf.

Dateien im Release (`<v>` = Version, `<env>` = Umgebung):

| Plattform | Datei | Hinweis |
| --- | --- | --- |
| Windows | `Soulwick-<v>-<env>-windows.zip` | ohne Signatur warnt SmartScreen („Weitere Informationen → Trotzdem ausführen“) |
| Linux | `Soulwick-<v>-<env>-linux.zip` | x86_64 |
| macOS | `Soulwick-<v>-<env>-macos.zip` | Universal, nur ad-hoc signiert, **nicht notarisiert** (§6) |
| Android | `Soulwick-<v>-<env>-android.apk` | Android 7+, Installation aus unbekannten Quellen |
| alle | `Soulwick-<v>-<env>-SHA256SUMS.txt` | Prüfsummen |

Releases: `https://github.com/WebBude-de/soulwick/releases`; jeder Lauf hängt die Dateien zusätzlich 90 Tage als Artefakte an.

## 2. Eine Version veröffentlichen

**Automatisch bei jedem Push auf `dev` (D-157):** Die Pipeline baut Windows, Linux, macOS und Android gegen die
Test-Server und veröffentlicht sie als Vorabversion `v<version>-dev.<Lauf>` (z. B. `v0.9.1-dev.42`). Ohne
Store-Uploads. Es bleiben die neuesten 5 Dev-Vorabversionen stehen (`DEV_RELEASES_KEPT`), ältere samt Tag werden
gelöscht. Reine Doku- und Web-Änderungen (`docs/`, `*.md`, `deploy/`, `Dockerfile`) starten keinen Build. Ein
neuer Push bricht einen noch laufenden Dev-Build ab.

**Mit Tag (normaler Weg):**

1. `application/config/version` in `project.godot` setzen (z. B. `0.9.1`), committen, per Pull Request nach `main` bringen.
2. Auf diesem Stand taggen und pushen:

   ```bash
   git tag v0.9.1
   git push origin v0.9.1
   ```

3. Unter **Actions → Release** zusehen (≈ 15–25 Minuten, mit Cache weniger). Danach steht das Release unter **Releases**.

**Ohne Tag (manuell):** Actions → **Release** → „Run workflow“ → Branch wählen, `env` (development/production) und `prerelease` (ja/nein). Der Lauf legt den Tag selbst an.

| Auslöser | Tag | Umgebung | Pre-Release |
| --- | --- | --- | --- |
| Tag `v0.9.1` | `v0.9.1` | Variable `RELEASE_ENV`, Standard **development** | ja, solange `development` |
| Tag `v0.9.1-beta.1` (alles mit `-`) | wie gepusht | immer `development` | ja |
| „Run workflow“, `development` | `v0.9.1-dev.<Laufnummer>` | development | immer ja |
| „Run workflow“, `production`, Pre-Release ja | `v0.9.1-rc.<Laufnummer>` | production | ja |
| „Run workflow“, `production`, Pre-Release nein | `v0.9.1` | production | nein („Latest“) |

Regeln:

- Der Tag ohne `v` und ohne Zusatz muss gleich der Version in `project.godot` sein, sonst bricht der Lauf ab. Bei „Run workflow“ ohne Pre-Release darf es den Tag `v<version>` noch nicht geben (dann Version erhöhen).
- Wird derselbe Tag noch einmal gebaut („Re-run“), ersetzt der Lauf Dateien und Text des vorhandenen Release.
- **Release-Notizen:** kurze Anleitung (Download, SmartScreen, macOS, Android „Unbekannte Quellen“), bei `development` der Link zur Browser-Testversion, dann die Commits seit dem letzten Tag (bei einem normalen Release seit dem letzten normalen Release) und ein Vergleichslink. Sie lassen sich danach auf GitHub von Hand bearbeiten.
- **Fehlgeschlagen oder falsch getaggt?** Release unter Releases → „Delete“ löschen, Tag löschen (`git push --delete origin v0.9.1 && git tag -d v0.9.1`) und neu taggen.

## 3. development und production

`<env>` ist die **Server-Umgebung** des Builds (Plattform P-018). Das Skript schreibt sie für den Export in `online/environment.cfg`; ein Build spricht nur mit den Servern seiner Umgebung. Im Editor gilt immer `local` (localhost), `-- env=development` schaltet auf den Dev-Server.

| | development | production |
| --- | --- | --- |
| Server | `api-dev.playsoulwick.com`, `play-dev.playsoulwick.com` (Test) | `api.playsoulwick.com`, `play.playsoulwick.com` |
| Release | immer **Pre-Release**, Titel „(Testversion)“ | normales Release („Latest“), außer als Pre-Release gewählt |
| Android-Schlüssel | Debug-Schlüssel des Build-PCs (`ANDROID_DEBUG_KEYSTORE_BASE64`) | Release-Schlüssel (`ANDROID_KEYSTORE_*`) |

**Warum Standard `development`:** Die Produktiv-Server laufen noch nicht. Ein `production`-Build wäre heute online immer „Offline“. Ein Tag ohne Zusatz baut deshalb vorerst gegen die Test-Server. Wenn das Projektmitglied entscheidet, dass normale Releases gegen die Produktion gehen, in GitHub die Variable `RELEASE_ENV` auf `production` setzen (§4), ohne den Workflow zu ändern. Bis dahin geht `production` nur über „Run workflow“.

## 4. Einmalig in GitHub einrichten

Settings → **Secrets and variables → Actions**. Secrets erscheinen nie im Log (GitHub maskiert sie); die Pipeline legt den Schlüssel nur im temporären Ordner des Läufers ab, nie im Repo. Hier stehen die Secrets für die APK; alle weiteren (Google Play, Apple, Windows-Signatur, Steam) mit Anleitung in [STORES.md](STORES.md).

| Art | Name | Inhalt | Nötig für |
| --- | --- | --- | --- |
| Secret | `ANDROID_DEBUG_KEYSTORE_BASE64` | `debug.keystore` des Build-PCs als Base64 | development-APKs, die sich über lokal gebaute installieren lassen |
| Secret | `ANDROID_KEYSTORE_BASE64` | Release-Keystore als Base64 | production-APKs |
| Secret | `ANDROID_KEYSTORE_PASSWORD` | Passwort des Keystores | production |
| Secret | `ANDROID_KEY_ALIAS` | Alias des Schlüssels (z. B. `soulwick`) | production |
| Secret | `ANDROID_KEY_PASSWORD` | Passwort des Schlüssels (bei PKCS12 = Keystore-Passwort) | production, optional |
| Variable | `RELEASE_ENV` | `development` (Standard) oder `production` | Umgebung von Tags ohne Zusatz |
| Variable | `WEB_PLAY_URL` | z. B. `https://game.playsoulwick.com` | Browser-Link in production-Releases (development verlinkt immer `game-dev.playsoulwick.com`) |

**Was ohne Secrets passiert** (`tools/ci/android_signing.sh`):

| Umgebung | vorhanden | Signatur | Release |
| --- | --- | --- | --- |
| development | `ANDROID_DEBUG_KEYSTORE_BASE64` | Debug-Schlüssel des Build-PCs | normal (Pre-Release) |
| development | nichts | **neuer** Debug-Schlüssel je Lauf | Hinweis „Android nur zum Testen“ |
| production | `ANDROID_KEYSTORE_*` | Release-Schlüssel | normal |
| production | nur Debug-Secret / nichts | Debug-Schlüssel bzw. neuer Schlüssel | Pre-Release, Titel „(nur Test)“, Hinweis in den Notizen |

**Wichtig bei Android:** Ein Handy installiert ein Update nur, wenn es mit **demselben Schlüssel** signiert ist wie die installierte App. Sonst „App nicht installiert“ → alte App deinstallieren, der Spielstand auf dem Handy geht verloren. Deshalb den Debug-Schlüssel des Build-PCs als Secret hinterlegen (dann passen CI- und lokale APKs zusammen) und den Release-Schlüssel nie wechseln.

### Debug-Schlüssel des Build-PCs hinterlegen

Der Schlüssel liegt unter `%APPDATA%\Godot\keystores\debug.keystore` (Alias `androiddebugkey`, Passwort `android`; `tools/export_build.ps1` legt ihn beim ersten Android-Build an). Base64 in die Zwischenablage (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:APPDATA\Godot\keystores\debug.keystore")) | Set-Clipboard
```

Dann in GitHub: Settings → Secrets and variables → Actions → **New repository secret** → Name `ANDROID_DEBUG_KEYSTORE_BASE64`, Inhalt einfügen. Mit der GitHub-CLI geht es in einem Schritt (Git Bash): `base64 -w0 "$APPDATA/Godot/keystores/debug.keystore" | gh secret set ANDROID_DEBUG_KEYSTORE_BASE64 --repo WebBude-de/soulwick`.

### Release-Keystore erzeugen (einmal, für production und später Google Play)

```powershell
keytool -genkeypair -v -keystore soulwick-release.p12 -storetype PKCS12 -alias soulwick `
  -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=WebBude, O=WebBude, C=DE"
```

`keytool` liegt im JDK 17 (`C:\Program Files\Java\jdk-17.0.5\bin`). Es fragt nach einem Passwort (lang, zufällig, aus dem Passwort-Manager); bei PKCS12 gilt es für Keystore und Schlüssel. Ein älterer JKS-Keystore mit eigenem Schlüssel-Passwort geht auch: Die Pipeline wandelt ihn dann selbst um (Godot gibt `apksigner` nur ein Passwort mit).

Hinterlegen: Base64 wie oben (`soulwick-release.p12` statt `debug.keystore`) als `ANDROID_KEYSTORE_BASE64`, dazu `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` = `soulwick`, `ANDROID_KEY_PASSWORD` = dasselbe Passwort. Fingerabdruck notieren: `keytool -list -v -keystore soulwick-release.p12` (Zeile „SHA256“); `apksigner` zeigt ihn im Lauf unter „Check APK“.

**Sicher aufbewahren:**

- Keystore-Datei und Passwort in den **Passwort-Manager** des Teams (Datei als Anhang) und eine zweite Kopie offline (verschlüsselter USB-Stick an einem sicheren Ort).
- **Nie** ins Repo (es ist öffentlich), nie per Chat oder Mail, nie in `export_presets.cfg` (dort bleiben die Keystore-Felder leer).
- Geht der Schlüssel verloren, kann keine installierte App mehr ein Update bekommen. Für Google Play später „Play App Signing“ nutzen: Dann ist dieser Schlüssel nur der Upload-Schlüssel und lässt sich bei Verlust über Google zurücksetzen ([ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) CP7).
- Die lokale Datei nach dem Hochladen aus dem Download-Ordner löschen.

## 5. Was die Pipeline prüft

Ein Lauf bricht ab bei: Version ≠ Tag (`tools/ci/release_meta.sh`), Lade- oder Parse-Fehlern (`validate_project.gd`), rotem GUT-Test (Systemsprache Deutsch über `LANG=de_DE.UTF-8`, weil einige Tests die deutschen Texte von „auto“ erwarten), veränderten Godot-Downloads (SHA-512), Fehlern im Boot-Check (`tools/ci/boot_check.sh`), ungültiger APK- oder AAB-Signatur (`apksigner`, `tools/ci/check_aab.sh`), fehlgeschlagener Windows-Signatur oder macOS-Notarisierung und Fehlern in Workflows oder Shell-Skripten. Der Windows-Build wird auf Linux exportiert und dort nicht gestartet; lokal startet `tools/export_build.ps1` ihn einmal headless.

## 6. macOS

Ohne Apple-Konto ist der Build nur **ad-hoc signiert** (Godots eingebaute Signatur, geht auch auf Linux) und nicht notarisiert. Er läuft trotzdem auf Intel und Apple Silicon, macOS warnt aber beim ersten Start:

- bis macOS 14: Rechtsklick auf `Soulwick.app` → „Öffnen“ → „Öffnen“,
- ab macOS 15: einmal öffnen (wird blockiert), dann *Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“*,
- oder im Terminal: `xattr -cr /Applications/Soulwick.app`.

Notarisieren (keine Warnung) braucht ein Apple-Developer-Konto (99 €/Jahr). Die Pipeline ist dafür vorbereitet (Job `macos_sign`): Sobald die Secrets aus [STORES.md](STORES.md) §2 gesetzt sind, ist das macOS-ZIP signiert und notarisiert, und die Release-Notizen lassen diesen Hinweis weg.

## 7. Lokal bauen

**Nur schnell die EXE testen:** `powershell -ExecutionPolicy Bypass -File tools/export_build.ps1` (Windows, Umgebung development) baut `builds\development\<version>\windows\Soulwick.exe` und startet sie einmal headless zur Probe. Danach die EXE doppelklicken; der Ordner `builds/` ist nicht versioniert.

```bash
# Git Bash / Linux / macOS
GODOT="C:/Tools/Godot/Godot_v4.7.2-stable_win64.exe" tools/export_build.sh development "" "windows linux macos"
# Store-Formate: Xcode-Projekt (geht auf jedem Rechner) und Google-Play-Bundle (Gradle, Release-Schlüssel nötig)
GODOT=... tools/export_build.sh development "" ios
GODOT=... VERSION_CODE=90101 GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... tools/export_build.sh development "" android-aab
```

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Platforms windows,linux,macos
powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Env development -Platforms android
```

Die Dateien landen in `builds/<env>/<version>/` (nicht versioniert).

**Einmalig auf dem Build-PC:**

1. **Export-Vorlagen** für Godot 4.7.2: Editor → *Export-Vorlagen verwalten* → *Herunterladen und installieren* (oder *Aus Datei installieren* mit `Godot_v4.7.2-stable_export_templates.tpz`); sie liegen danach in `%APPDATA%/Godot/export_templates/4.7.2.stable/`.
2. **Android:** JDK 17; Android-SDK nach `%LOCALAPPDATA%\Android\Sdk` (Command-line Tools nach `cmdline-tools\latest`, dann `sdkmanager --licenses` und `sdkmanager "platform-tools" "build-tools;35.0.1" "platforms;android-35" "build-tools;36.1.0" "platforms;android-36"`); in den Godot-Editoreinstellungen *Export → Android* `java_sdk_path` und `android_sdk_path` setzen. NDK, CMake und Gradle braucht nur das Google-Play-Bundle.
3. **Debug-Schlüssel** `%APPDATA%\Godot\keystores\debug.keystore` (Alias `androiddebugkey`, Passwort `android`; das Skript legt ihn an). Er gehört zu diesem PC: Baut ein anderer PC die APK, müssen Freunde die alte App erst deinstallieren (Spielstand weg). Deshalb als Secret hinterlegen (§4).

APK prüfen: `aapt dump badging <apk>` (Paket, `versionCode`, Architekturen), `apksigner verify --print-certs <apk>`. Installieren am PC mit USB-Debugging: `adb install -r <apk>`.

## 8. Stores

Vorbereitet, aber erst mit Konten und Secrets aktiv: Google Play (AAB, interner Test), App Store (IPA, TestFlight), Steam (Beta-Branch), Signaturen für Windows und macOS. Konten, Kosten, Secrets, Schritte bis zur Veröffentlichung, fehlende Grafiken, Altersfreigabe und Datenschutz-Angaben: [STORES.md](STORES.md). Steamworks im Spiel (GodotSteam, Einladungen, Erfolge) gehört zu [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP6/MP10. Die **Browser-Version** läuft über Dokploy, nicht hier (D-148).
