# Web-Build: Soulwick im Browser und als App (PWA)

> **Stand:** 17.10.2026 · Entscheidung D-148, D-157, D-182 (hochkant). Dokploy-App `soulwick-game` aus diesem Repo; Plattform-Seite: `../soulwick-platform/infra/DOKPLOY.md`. **Launch-Checkliste für Produktion:** [LAUNCH.md](LAUNCH.md). Abweichungen beim Einrichten hier nachtragen.

| Umgebung | Branch | Domain | Build-Argument |
| --- | --- | --- | --- |
| `development` | `dev` | `https://game-dev.playsoulwick.com` | `SOULWICK_ENV=development` (Standard) |
| `production` | `production` | `https://game.playsoulwick.com` | `SOULWICK_ENV=production` |

**Übergang (D-157):** Bis die Produktiv-Server laufen, hängt `game.playsoulwick.com` als zweite Domain an derselben development-App (Test-Server `api-dev`/`play-dev`), damit Desktop- und Browser-Spieler zusammen spielen. Dafür bei `soulwick-api` (development) `https://game.playsoulwick.com` zusätzlich in `CORS_ORIGINS` eintragen.

## 1. Was wo liegt

| Datei | Zweck |
| --- | --- |
| `Dockerfile` | drei Stufen: Godot und Web-Vorlage (gecacht), Export, nginx mit Brotli (Port 80, Healthcheck `/healthz`) |
| `.dockerignore` | nur das Nötige in den Build (ohne `.git`, `.godot`, `builds`, `docs`, `tests`, `_inbox`) |
| `deploy/web/shell.html`, `offline.html`, `404.html` | eigene Startseite, Offline- und Fehlerseite (DE/EN nach Browsersprache) |
| `deploy/web/icons/` | App-Icons (geliefert, §8) |
| `deploy/web/nginx.conf` | Header, MIME, Kompression, Caching (§5) |
| `deploy/web/web_preset.py` | prüft und setzt die Werte des Presets „Web“ (§3), idempotent |
| `deploy/web/patch_service_worker.py` | passt den Service Worker von Godot an (§5); bricht ab, wenn der Patch nicht mehr passt |
| `deploy/web/fetch_template.py` | holt aus dem Vorlagen-Archiv nur die Web-Vorlage (HTTP-Range, SHA-512 geprüft) |
| `deploy/.gdignore` | Godot importiert `deploy/` nicht |

## 2. Ablauf im Image

1. **godot** (gecacht): Godot 4.7.2 Linux und die Web-Vorlage, beide mit fester SHA-512 im Dockerfile.
2. **export** (bei jeder Spieländerung): `online/environment.cfg` mit der Umgebung (wie `tools/export_build.sh`; erlaubt `development`, `production`, `local`), Preset prüfen, `--import` mit Cache zwischen Builds, `--export-release "Web"`, Service Worker patchen, `robots.txt` je Umgebung, `.br`/`.gz`-Kopien.
3. **runtime:** Alpine + nginx, Kopfzeilen je Umgebung, `nginx -t` beim Bauen.

**Git LFS:** Der Ton liegt in LFS. Klont Dokploy ohne LFS, erzeugt der Build den Ton mit `tools/generate_audio.py` und `tools/generate_music.py` neu (einige Minuten länger, eigene `.ogg`/`.mp3` fehlen dann). Sauber wird es mit `git-lfs` auf dem Server (§6 Schritt 5).

## 3. Preset „Web“

Die Werte stehen im Preset „Web“ in `export_presets.cfg` (damit auch `tools/export_build.*` dieselbe Seite baut); `web_preset.py` prüft sie im Image nur noch. Die Gründe:

- `html/export_icon=false`: sonst wäre das Favicon das Godot-Logo; die Seite verlinkt die eigenen Icons.
- PWA an, eigenes Fenster (standalone), Ausrichtung beliebig (`progressive_web_app/orientation=0`, D-182: hochkant schaltet das Spiel selbst um), Hintergrund `#15131f`, eigene Offline-Seite und Icons.
- `variant/thread_support=false`: einfädig, braucht keine Cross-Origin-Isolation und läuft überall.

## 4. Startseite (Shell)

- Lädt Engine und Spieldaten sofort mit Fortschritt, startet aber erst nach Klick, Tipp oder Enter: Erst dann erlaubt der Browser Ton.
- **„Als App installieren“** erscheint nur, wenn der Browser es anbietet, oder auf iOS-Safari (dort mit Anleitung „Teilen → Zum Home-Bildschirm“). `?install` in der URL öffnet den Hinweis sofort (Link der Website). `?room=ABC123` ist ein Einladungslink (D-190): Die Startseite prüft den Raumcode, zeigt „Tippen zum Beitreten“ und startet das Spiel mit `-- room=ABC123`; ungültige Codes werden verworfen.
- **Neue Version** lädt nur, solange der Startbildschirm offen ist; im laufenden Spiel wird nie neu geladen.
- Spielstände liegen im Browser (IndexedDB je Domain); `game-dev` und `game` haben getrennte Stände.
- Impressum und Datenschutz unten links, auf schmalen Bildschirmen mittig (Website derselben Umgebung, neuer Tab).
- Kein Dreh-Hinweis mehr (D-182): Im Hochformat zeigt das Spiel auf Handy und Tablet oben das Spielbild und darunter einen Handheld-Controller (`ui/touch/portrait_*.gd`) und schaltet beim Drehen live um; die Startseite selbst prüft die Ausrichtung nicht.
- iOS-Safari: Vollbild nur als Home-Bildschirm-App; der Stummschalter des iPhones schaltet Web-Ton stumm (bewusst nicht umgangen).
- **Koop im versteckten Tab (D-183):** Ein Skript vor Godots Engine-Skript hüllt `window.requestAnimationFrame` ein. Sichtbar kommen die Bilder wie immer vom Browser; ist der Tab versteckt und das Spiel in einem Koop-Raum (`online/web_keep_alive.gd` schaltet es von Raumbeitritt bis Verlassen an), treibt ein kleiner Worker die Hauptschleife alle 16 ms, gezeichnet wird dann nicht. Einzelspieler bleibt unverändert. Grenzen: Energiesparen, Safari/iOS und Handy-Browser im Hintergrund.

## 5. Server-Verhalten (nginx)

| Was | Wert |
| --- | --- |
| Header | COOP `same-origin`, COEP `require-corp`, CORP `same-origin`, `nosniff`, `Referrer-Policy` |
| Kompression | vorkomprimiert Brotli und gzip |
| Caching | `index.html`, Service Worker, Manifest, `.pck`, `.wasm`, `.js`: `no-cache` mit ETag; Icons 1 Tag, Schrift 30 Tage |
| Suchmaschinen | nur `production` erlaubt; sonst `Disallow: /` und `X-Robots-Tag: noindex, nofollow` |
| Fehlerseite, Healthcheck | unbekannte Pfade → `404.html`; `GET /healthz` → `ok` |

- **Kein Versions-Query:** Godot lädt `index.pck`/`index.wasm` immer unter festem Namen; langes Caching würde dem Service Worker alte Dateien unterschieben. `no-cache` + ETag kostet unverändert nur kleine 304-Antworten.
- COOP/COEP braucht der einfädige Build nicht, sie schaden nicht (API mit CORS, WebSockets nicht betroffen) und halten den Weg zu Threads offen.
- **Service Worker:** Godot registriert ihn nach dem Start und cacht je Version; danach startet das Spiel auch offline (ohne Online-Teil). Der Patch liefert die gespeicherte Seite auch für `/` und `/?install` (Links der Website) und cacht Schrift und Icons.

## 6. Dokploy: App `soulwick-game` anlegen

Im Projekt `soulwick`, je Umgebung eine Application:

| Einstellung | `development` | `production` |
| --- | --- | --- |
| Name / App Name | `soulwick-game` / `soulwick-game-dev` | `soulwick-game` / `soulwick-game-prod` |
| Provider | GitHub (App der Organisation `WebBude-de`), Repository **`WebBude-de/soulwick`** | gleich |
| Branch | `dev` | `production` |
| Build Type | **Dockerfile**, Dockerfile Path `Dockerfile`, **Docker Context Path `.`** | gleich |
| Build-Argument (*Environment → Build-time Arguments*) | `SOULWICK_ENV=development` | `SOULWICK_ENV=production` |
| Domain | `game-dev.playsoulwick.com`, Path `/`, **Container Port 80**, HTTPS an, **Certificate Provider None** | `game.playsoulwick.com`, sonst gleich |
| Replicas | 1 (mehr geht, der Container hat keinen Zustand) | 1 |
| Auto Deploy | an, mit Watch Paths (unten) | an oder manuell |

1. Die GitHub-App von Dokploy braucht Zugriff auf das Repo **`soulwick`** (GitHub → Organisation `WebBude-de` → Settings → GitHub Apps → Dokploy → Repository access).
2. **DNS (Cloudflare):** A-Record (bei IPv6 auch AAAA) `game-dev` bzw. `game` auf die VPS-IP, **mit Proxy**. Eine Ebene unter der Domain, deshalb `game-dev` statt `game.dev` (Plattform P-029).
3. **TLS:** Certificate Provider **None**; Traefik nimmt das Cloudflare-Ursprungszertifikat (`*.playsoulwick.com`), das schon in Dokploy liegt.
4. **Watch Paths** (nur bauen, wenn sich das Spiel ändert): `autoload/**`, `art/**`, `audio/**`, `characters/**`, `components/**`, `dungeon/**`, `economy/**`, `enemies/**`, `localization/**`, `meta/**`, `online/**`, `player/**`, `scenes/**`, `ui/**`, `upgrades/**`, `weapons/**`, `world/**`, `addons/**`, `deploy/web/**`, `project.godot`, `export_presets.cfg`, `default_bus_layout.tres`, `Dockerfile`, `.dockerignore`. Neue Spielordner hier ergänzen.
5. **LFS:** Ob Dokploy Git-LFS-Dateien holt, ist nicht erprobt. Sauber wird es mit `apt install git-lfs` und `git lfs install --system` auf dem Server; im Build-Log steht sonst „Audio files are Git LFS pointers“ (§2).
6. Deployen; im Log `godot --import`, `savepack`, `nginx: configuration file … test is successful`. Prüfen: `https://game-dev.playsoulwick.com/healthz` → `ok`, dann die Seite.
7. Löscht die Docker-Bereinigung den Build-Cache, lädt der nächste Build Godot und die Vorlage neu; das kostet nur Zeit.

### Für die Plattform (soulwick-platform, nicht hier ändern)

- **`GAME_URL`** der Plattform: development `https://game-dev.playsoulwick.com`, production `https://game.playsoulwick.com`.
- **CORS:** Bei `soulwick-api` `CORS_ORIGINS=${{environment.WEB_URL}},${{environment.ADMIN_URL}},${{environment.GAME_URL}}`; ohne das schlagen Anmeldung, Ranglisten und Gilden im Browser fehl (Einzelspieler geht trotzdem). Der Relay braucht kein CORS.
- **Website:** bei `soulwick-web` `GAME_URL=${{environment.GAME_URL}}` (production bis zur Freischaltung leer); die Knöpfe verlinken `<GAME_URL>/` und `<GAME_URL>/?install`.

## 7. Lokal prüfen

```bash
docker build -t soulwick-game .                                          # development
docker build --build-arg SOULWICK_ENV=production -t soulwick-game:prod .
docker run --rm -p 3110:80 soulwick-game                                 # http://localhost:3110
curl -sI http://localhost:3110/index.wasm -H "Accept-Encoding: br"       # Header prüfen
```

Gegen die lokale Plattform (`bun dev` in `soulwick-platform`; die lokale API erlaubt CORS von `http://localhost:3110`): `docker build --build-arg SOULWICK_ENV=local -t soulwick-game:local .`, dann wie oben starten. Kürzer: `tools/web_local.sh` baut das Image nur neu, wenn sich der Code seit dem letzten Bau geändert hat (Git-Revision als Image-Label), und startet es als Container `soulwick-game-local` auf 3110 (`--build` erzwingt den Bau, `--stop` beendet ihn); so startet es auch der Projekt-Desktop. Ein `development`-Container auf `localhost` spricht mit `api-dev`, die ihn per CORS ablehnt (erwartet, das Spiel läuft dann offline).

`localhost` gilt als sichere Umgebung: Service Worker und Install-Knopf gehen dort ohne HTTPS; ein anderer Rechner im Netz braucht HTTPS. Browser-Tests (Playwright/Chromium) immer stumm mit `--mute-audio` (AGENTS.md §7).

**Keep-alive von Hand prüfen (D-183):** Im Browser einen Koop-Raum öffnen, den Tab 10–20 s verdecken (anderer Tab, Fenster minimieren), zurückkehren und in der Konsole `soulwickShell.stats()` aufrufen. Erwartet (in echten Browsern noch nicht gemessen, D-183 OFFEN): `keepAlive: true`, `worker: true`, `ticks` gestiegen, `hiddenPeriods` um 1 höher, `longestGapMs` unter 100; Werte um 1000 heißen, der Browser drosselt den Worker trotzdem. Ein Mitspieler am Desktop sieht dabei kein „Warte auf den Host …“. Außerhalb eines Raums bleibt `keepAlive: false`.

Ohne Docker: in einer **Kopie** des Projekts `python deploy/web/web_preset.py <kopie>/export_presets.cfg`, dann `godot --headless --audio-driver Dummy --path <kopie> --export-release "Web" <ordner>/index.html` und den Ordner mit einem Server ausliefern, der `.wasm` als `application/wasm` sendet.

## 8. App-Icons

Geliefert von Claude Design (16.10.2026): `deploy/web/icons/icon_144.png`, `icon_180.png`, `icon_512.png` (Motiv in den mittleren 80 %, vollflächiger Grund `#15131f`, keine Transparenz). Neue Fassungen mit gleichem Namen ablegen. `python deploy/web/make_icons.py --force` erzeugt nur einen Ersatz aus `art/ui/logo_square.png`. Später optional: 192 × 192 und ein „maskable“-Icon.

## 9. Lokal geprüft (16.10.2026)

Docker-Image (development und production) mit Chromium (Playwright, headless, stumm): Start, Profil und Welt anlegen, Dorf, Raum 1 freikämpfen; Touch-Profile Pixel 7 und iPhone 14 (nach der Korrektur der Zwei-Stick-Steuerung); Installierbarkeit ohne Fehler; Service Worker offline für `/`, `/?install` und `/index.html`; Update auf neue Version; `crossOriginIsolated`; Umgebungen sprechen mit ihrer API; robots und 404 je Umgebung. Image 218 MB, Build bei Spieländerungen ~60–80 s mit warmem Cache.

## 10. Leistung im Browser (Mobil)

Gemessen mit dem Geräteprofil „Pixel 7 quer“ und CPU-Drosselung; die GPU war eine Desktop-Karte, die Zahlen zeigen also die CPU-Seite. Grobe Werte, je Lauf ±20 %.

| Messung | CPU ×1 | CPU ×4 (Mittelklasse) | CPU ×6 (schwach) |
| --- | --- | --- | --- |
| Download erster Besuch | 25 MB (pck 17,8, wasm 7,7) | gleich | gleich |
| Tipp → Spiel läuft | 5–7 s | 15–22 s | 32 s |
| Dorf | 211 fps | 56–62 fps | 36–44 fps |
| Speicher im Dorf | 266 MB | gleich | 280 MB |

- **Der Start ist der größte Hebel:** Nach dem Tipp blockiert Godot den Hauptthread am Stück; auf schwachen Handys 15–30 s ohne Bild, ab etwa 20 s kann Android „Seite reagiert nicht“ anbieten. Ursachen im Debug-Build profilieren (Autoload-`_ready`, Hauptmenü, Übersetzungen).
- Ladezeit über das Netz: ~4 s bei 50 Mbit/s, ~20 s bei 10 Mbit/s; der zweite Besuch kommt aus dem Cache.
- Web läuft immer mit dem Compatibility-Renderer (WebGL 2); das Spiel zeichnet in voller Geräteauflösung inklusive Vollbild-Shadern, auf Handy-GPUs die Füllraten-Grenze (§11).

## 11. Offen

**Spiel-Code (für den Integrator):**

- **Vollbild in Android-Browsern:** Die Startseite ruft weder `requestFullscreen()` noch `screen.orientation.lock()` auf (geprüft 17.10.2026). Möglich wäre `requestFullscreen()` beim Tipp, aber ohne Ausrichtungssperre, weil das Spiel quer und hochkant läuft und beim Drehen selbst umschaltet (D-182); vorher muss `GameOptions.apply_window_mode()` im Browser übersprungen werden (`OS.has_feature("web")`), sonst beendet das Spiel das Vollbild sofort.
- **Rechtstexte im Spiel:** Die Startseite verlinkt Impressum und Datenschutz, das laufende Spiel nicht; Eintrag im Hauptmenü ergänzen (Web: `OS.shell_open`).

**Vorschläge für `project.godot` (nichts geändert):**

- `application/config/icon` setzen (Desktop-Builds zeigen sonst das Godot-Logo).
- Auf Handys im Browser in 1280 × 720 rendern statt in voller Auflösung: `display/window/stretch/mode.web_android="viewport"` und `.web_ios="viewport"`; erst auf einem echten Mittelklasse-Handy vergleichen.
- Bildrate im Browser auf 60 begrenzen, falls 120-Hz-Handys heiß laufen: `application/run/max_fps.web=60` (prüfen, ob Godot das im Web beachtet).
- Kleineres Paket: Musik als Ogg Vorbis statt WAV wäre etwa halb so groß (`tools/generate_music.py`).

**Weiteres:** Das Dockerfile lädt Godot für x86_64, ein ARM-Server bräuchte `linux.arm64`. Echte Geräte fehlen noch: iOS-Safari und ein Android-Mittelklasse-Handy einmal von Hand prüfen ([LAUNCH.md](LAUNCH.md) §8).
