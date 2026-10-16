# Releases und Builds

> **Stand:** 16.10.2026 · Entscheidung: [D-148](DECISIONS.md) · Workflows: [`.github/workflows/`](../.github/workflows/) · Hilfsskripte: [`tools/ci/`](../tools/ci/)

Windows-, Linux-, macOS- und Android-Builds baut **GitHub Actions** und legt sie als **GitHub-Release** ins Repo. Die **Browser-Version** baut und hostet Dokploy selbst (`Dockerfile`, `deploy/web/`, D-148); sie ist nicht Teil dieser Pipeline. Lokal geht dasselbe mit `tools/export_build.sh` bzw. `tools/export_build.ps1` (§7).

## 1. Was die Pipeline macht

| Workflow | Auslöser | Ergebnis |
| --- | --- | --- |
| `ci.yml` | Push auf `main`/`dev`, jeder Pull Request, „Run workflow“ | `validate_project.gd` + GUT (Linux, headless, ohne Ton) |
| `release.yml` | Tag `v*` oder „Run workflow“ | Prüfen → Exporte → GitHub-Release mit allen Dateien |

Ablauf von `release.yml` (alles auf `ubuntu-latest`):

1. **Version und Tests:** Version aus `project.godot` lesen und mit dem Tag vergleichen (Abbruch bei Abweichung, wie im PowerShell-Skript), Umgebung festlegen, `validate_project.gd` und GUT.
2. **Desktop** (parallel zu 3): Godot 4.7.2 und die Export-Vorlagen von den offiziellen Godot-Releases laden (SHA-512 geprüft, danach im Cache), Projekt importieren, `tools/export_build.sh` für Windows, Linux und macOS, dann **Boot-Check**: das Linux-ZIP entpacken und `Soulwick.x86_64 --headless --audio-driver Dummy --quit-after 300 -- offline` starten; Skript- oder Ladefehler brechen ab.
3. **Android:** JDK 17 (Temurin), Android-SDK (platform-tools, build-tools 35.0.1 und 36.1.0, platforms 35 und 36; kein NDK, kein Gradle), Signaturschlüssel aus den Secrets (§4), Export, danach `apksigner verify` und `aapt dump badging` (Paket, Version, Architekturen im Log).
4. **Release:** Dateien einsammeln, Prüfsummen, Release-Notizen (Anleitung + Commits seit dem letzten Tag), Release anlegen.

Dateien im Release (`<v>` = Version, `<env>` = Umgebung):

| Plattform | Datei | Hinweis |
| --- | --- | --- |
| Windows | `Soulwick-<v>-<env>-windows.zip` | `Soulwick.exe` + `LIESMICH.txt`. Nicht signiert: SmartScreen warnt („Weitere Informationen → Trotzdem ausführen“). |
| Linux | `Soulwick-<v>-<env>-linux.zip` | x86_64, `Soulwick.x86_64` + `LIESMICH.txt`, Boot-Check in der Pipeline |
| macOS | `Soulwick-<v>-<env>-macos.zip` | `Soulwick.app`, Universal (Intel + Apple Silicon), nur ad-hoc signiert, **nicht notarisiert** (§6) |
| Android | `Soulwick-<v>-<env>-android.apk` | Android 7+, armeabi-v7a + arm64-v8a; Installation aus unbekannten Quellen |
| alle | `Soulwick-<v>-<env>-SHA256SUMS.txt` | Prüfsummen der Dateien |

Die Dateien liegen danach unter **Releases** im Repo (`https://github.com/WebBude-de/soulwick/releases`). Jeder Lauf hängt sie zusätzlich 90 Tage als Artefakte an (Actions → Lauf → „Artifacts“).

## 2. Eine Version veröffentlichen

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

`<env>` ist die **Server-Umgebung** des Builds ([MULTIPLAYER.md](MULTIPLAYER.md) §3d, Plattform P-018). Das Skript schreibt sie für den Export in `online/environment.cfg`; ein Build spricht nur mit den Servern seiner Umgebung.

| | development | production |
| --- | --- | --- |
| Server | `api-dev.playsoulwick.com`, `play-dev.playsoulwick.com` (Test) | `api.playsoulwick.com`, `play.playsoulwick.com` |
| Release | immer **Pre-Release**, Titel „(Testversion)“ | normales Release („Latest“), außer als Pre-Release gewählt |
| Android-Schlüssel | Debug-Schlüssel des Build-PCs (`ANDROID_DEBUG_KEYSTORE_BASE64`) | Release-Schlüssel (`ANDROID_KEYSTORE_*`) |

**Warum Standard `development`:** Die Produktiv-Server laufen noch nicht. Ein `production`-Build wäre heute online immer „Offline“. Ein Tag ohne Zusatz baut deshalb vorerst gegen die Test-Server. Wenn das Projektmitglied entscheidet, dass normale Releases gegen die Produktion gehen, in GitHub die Variable `RELEASE_ENV` auf `production` setzen (§4), ohne den Workflow zu ändern. Bis dahin geht `production` nur über „Run workflow“.

## 4. Einmalig in GitHub einrichten

Settings → **Secrets and variables → Actions**. Secrets erscheinen nie im Log (GitHub maskiert sie); die Pipeline legt den Schlüssel nur im temporären Ordner des Läufers ab, nie im Repo.

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

| Prüfung | Wo | Bricht ab bei |
| --- | --- | --- |
| Version = Tag | `tools/ci/release_meta.sh` | Abweichung, Tag ohne `v`, unbekannte Umgebung |
| Alle Dateien laden | `validate_project.gd` | Lade-/Parse-Fehler |
| Unit-Tests | GUT | rotem Test |
| Downloads | SHA-512 aus den Godot-Releases | veränderter oder kaputter Download |
| Boot-Check | `tools/ci/boot_check.sh` (Linux-ZIP) | Exit-Code ≠ 0, `SCRIPT ERROR`, `Parse Error`, `Failed to load` |
| APK-Signatur | `apksigner verify` | ungültiger Signatur |

Der Windows-Build wird auf dem Linux-Läufer exportiert und dort nicht gestartet; lokal startet `tools/export_build.ps1` ihn wie bisher einmal headless.

## 6. macOS

Ohne Apple-Konto ist der Build nur **ad-hoc signiert** (Godots eingebaute Signatur, geht auch auf Linux) und nicht notarisiert. Er läuft trotzdem auf Intel und Apple Silicon, macOS warnt aber beim ersten Start:

- bis macOS 14: Rechtsklick auf `Soulwick.app` → „Öffnen“ → „Öffnen“,
- ab macOS 15: einmal öffnen (wird blockiert), dann *Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“*,
- oder im Terminal: `xattr -cr /Applications/Soulwick.app`.

Notarisieren (keine Warnung) braucht ein Apple-Developer-Konto (99 €/Jahr) und kommt erst mit einem Store-Release (D-148).

## 7. Lokal bauen

```bash
# Git Bash / Linux / macOS
GODOT="C:/Tools/Godot/Godot_v4.7.2-stable_win64.exe" tools/export_build.sh development "" "windows linux macos"
```

```powershell
powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Platforms windows,linux,macos
powershell -ExecutionPolicy Bypass -File tools/export_build.ps1 -Env development -Platforms android
```

Die Export-Vorlagen von Godot 4.7.2 müssen installiert sein (Editor → Export-Vorlagen verwalten). Android braucht zusätzlich JDK 17 und das Android-SDK ([MULTIPLAYER.md](MULTIPLAYER.md) §3d). Die Dateien landen in `builds/<env>/<version>/` (nicht versioniert).

## 8. Noch nicht in der Pipeline

- **iOS:** braucht einen Mac mit Xcode und ein Apple-Konto (D-119, CP7: später über einen Cloud-Mac).
- **Google Play:** `.aab` statt `.apk` und Upload (CP7); bis dahin APK zum Selbst-Installieren.
- **Signieren:** Windows (Code-Signing-Zertifikat) und macOS (Notarisierung) kosten Geld; ohne sie warnen die Systeme beim ersten Start.
- **Steam:** eigener Upload-Weg (CP4/CP7).
- **Browser-Version:** über Dokploy, nicht hier (D-148).
