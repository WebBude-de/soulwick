# Web-Build: Soulwick im Browser und als App (PWA)

> **Stand:** 16.10.2026. Dokploy-App `soulwick-game` aus diesem Repo. Noch nicht auf dem Server erprobt;
> Abweichungen beim ersten Einrichten hier nachtragen. Plattform-Seite: `../soulwick-platform/infra/DOKPLOY.md`.

| Umgebung | Branch | Domain | Build-Argument |
| --- | --- | --- | --- |
| `development` | `dev` | `https://game-dev.playsoulwick.com` | `SOULWICK_ENV=development` (Standard) |
| `production` | `production` | `https://game.playsoulwick.com` | `SOULWICK_ENV=production` |

## 1. Was wo liegt

| Datei | Zweck |
| --- | --- |
| `Dockerfile` | Drei Stufen: **godot** (Debian, Godot 4.7.2 Linux, nur die Web-Vorlage, gecacht), **export** (Ton-Notlösung, Umgebung, Preset, Import, Export, Vorkomprimierung), **runtime** (Alpine + nginx mit Brotli, Port 80, `HEALTHCHECK` auf `/healthz`). |
| `.dockerignore` | Schickt nur das Nötige in den Build (ohne `.git`, `.godot`, `builds`, `docs`, `tests`, `_inbox`, `art/web` …). |
| `deploy/web/shell.html` | Eigene Startseite (Godot „Custom HTML Shell“): dunkel, Pixel-Logo, Ladebalken, „Klicken/Tippen zum Starten“ (der Klick erlaubt den Ton), Knopf **„Als App installieren“**, iOS-Hinweis, Fehlermeldung, Wechsel auf neue Versionen. Texte DE/EN nach Browsersprache. |
| `deploy/web/offline.html` | Offline-Seite der installierten App (DE/EN). |
| `deploy/web/icons/icon_144/180/512.png` | App-Icons, erzeugt aus `art/ui/logo_square.png` (Kerze und Kristall ohne Rahmen, gestuftes violettes Leuchten, ganzzahlig skaliert); neu erzeugen mit `python deploy/web/make_icons.py`. Gezeichnete Icons: §8. |
| `deploy/web/nginx.conf` | Header, MIME, Kompression, Caching (§5). |
| `deploy/web/web_preset.py` | Setzt die Web-Werte im Preset „Web“ (§3); idempotent. Das Dockerfile ruft es auf seiner **Kopie** auf. |
| `deploy/web/fetch_template.py` | Holt aus dem offiziellen Vorlagen-Archiv (1,3 GB) per HTTP-Range nur `web_nothreads_release.zip` (10 MB) und prüft SHA-512. |
| `deploy/.gdignore` | Godot importiert `deploy/` nicht (nichts davon landet in der `.pck`). |

## 2. Ablauf im Image

1. **godot** (gecacht): Godot `4.7.2-stable` Linux von `github.com/godotengine/godot-builds`, SHA-512 aus `SHA512-SUMS.txt` fest im Dockerfile; Web-Vorlage per `fetch_template.py` (CRC32 + festgelegte SHA-512, ermittelt aus dem offiziellen `Godot_v4.7.2-stable_export_templates.tpz`). Dauert Sekunden statt 1,3 GB Download.
2. **export** (läuft bei jeder Spieländerung):
   - **Git LFS:** Der Ton liegt in LFS. Klont Dokploy ohne LFS, liegen nur Zeiger-Dateien da; dann erzeugt der Build den Ton mit `tools/generate_audio.py` und `tools/generate_music.py` neu (dauert einige Minuten). Eigene `.ogg`/`.mp3` fehlen in dem Fall (Zeiger werden entfernt, das Spiel nimmt das erzeugte `.wav`). Besser: §6 „LFS“.
   - `online/environment.cfg`: `env="<SOULWICK_ENV>"`, genau wie `tools/export_build.sh` (gleiche `sed`-Zeile). Erlaubt: `development`, `production`, `local` (§7).
   - `python3 deploy/web/web_preset.py export_presets.cfg` (nur in der Kopie im Image).
   - `godot --headless --audio-driver Dummy --import`, dann `--export-release "Web" /out/index.html`. Der Import-Cache (`.godot`) bleibt als BuildKit-Cache-Mount zwischen Builds erhalten.
   - Schrift `PixelifySans` (OFL) nach `fonts/`, `robots.txt` (development: `Disallow: /`), `.br`/`.gz`-Kopien.
3. **runtime:** `alpine:3.22` + `nginx` + `nginx-mod-http-brotli`, `nginx -t` beim Bauen.

## 3. Werte im Export-Preset „Web“

`export_presets.cfg` selbst ist (noch) unverändert; das Image setzt die Werte in seiner Kopie. Damit auch
`tools/export_build.*` (Release-Zip, lokal) dieselbe Seite und App-Daten bekommt, diese Werte in
`[preset.N.options]` des Presets **„Web“** eintragen (oder `python deploy/web/web_preset.py` im Repo-Root
laufen lassen):

```ini
html/export_icon=false
html/custom_html_shell="res://deploy/web/shell.html"
progressive_web_app/enabled=true
progressive_web_app/ensure_cross_origin_isolation_headers=true
progressive_web_app/offline_page="res://deploy/web/offline.html"
progressive_web_app/display=1
progressive_web_app/orientation=1
progressive_web_app/icon_144x144="res://deploy/web/icons/icon_144.png"
progressive_web_app/icon_180x180="res://deploy/web/icons/icon_180.png"
progressive_web_app/icon_512x512="res://deploy/web/icons/icon_512.png"
progressive_web_app/background_color=Color(0.08235294, 0.07450981, 0.12156863, 1)
```

- `html/export_icon=false`: Ohne `application/config/icon` wäre das Favicon das Godot-Logo; die Seite verlinkt stattdessen `index.144x144.png` und `index.180x180.png` (Apple).
- `display=1` = eigenes Fenster (standalone), `orientation=1` = Querformat, Hintergrund `#15131f`.
- Unverändert bleiben `variant/thread_support=false` (einfädig, braucht keine Cross-Origin-Isolation) und die Filter.
- Godot erzeugt daraus `index.manifest.json` (Name aus `application/config/name`), `index.service.worker.js`, `index.offline.html` und die Icons `index.<n>x<n>.png`.

## 4. Startseite (Shell) im Detail

- Lädt Engine und Spieldaten sofort mit Fortschritt, startet aber erst nach Klick/Tipp/Enter: Der Browser erlaubt Ton erst nach einer Eingabe.
- **„Als App installieren“** (unten rechts) erscheint nur, wenn der Browser die Installation anbietet (`beforeinstallprompt`, Chrome/Edge/Android) oder auf **iOS-Safari** (dort öffnet er den Hinweis „Teilen → Zum Home-Bildschirm → Hinzufügen“). Nach der Installation und in der installierten App ist er weg.
- **`?install`** in der URL (z. B. `https://game.playsoulwick.com/?install` als Link von der Website) öffnet den Install-Hinweis sofort; je nach Browser mit Knopf „Jetzt installieren“, iOS-Schritten oder einem Hinweis, welcher Browser es kann.
- **Neue Version:** Ist im Hintergrund eine neue Version angekommen, lädt die Seite sie, solange noch der Startbildschirm offen ist (sonst würde die gespeicherte alte starten). Während des Spielens wird nichts neu geladen; die neue Version kommt beim nächsten Start.
- Fehlt dem Browser etwas (z. B. WebGL 2), steht dort eine verständliche Meldung; Einzelheiten nur in der Konsole.
- Spielstände liegen im Browser (IndexedDB der Domain); `game-dev` und `game` haben getrennte Stände.

## 5. Server-Verhalten (nginx)

| Was | Wert |
| --- | --- |
| Header überall | `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`, `Cross-Origin-Resource-Policy: same-origin`, `X-Content-Type-Options: nosniff`, `Referrer-Policy` |
| MIME | `.wasm` → `application/wasm`, `.pck` → `application/octet-stream`, `.manifest.json` → `application/manifest+json`, `.ttf` → `font/ttf` |
| Kompression | vorkomprimiert `.br` (Brotli 9) und `.gz`; nginx liefert, was der Browser kann |
| Caching | `index.html`, Service Worker, Manifest, `.pck`, `.wasm`, `.js`: `no-cache` (Browser prüft per ETag, bei gleichem Stand 304); Icons 1 Tag, Schrift 30 Tage |
| Healthcheck | `GET /healthz` → `ok` |

**Warum kein Versions-Query:** Godot lädt immer `index.pck`/`index.wasm` unter festem Namen. Langes
Caching würde dem Service Worker beim Update alte Dateien unterschieben. Mit `no-cache` + ETag kostet ein
unveränderter Besuch nur kleine 304-Antworten; offline und in der installierten App liefert der Service
Worker aus seinem eigenen Cache. COOP/COEP braucht der einfädige Build nicht, sie schaden aber nicht (API-
Aufrufe laufen mit CORS, WebSockets sind nicht betroffen) und halten den Weg zu einem Build mit Threads offen.

## 6. Dokploy: App `soulwick-game` anlegen

Im Projekt `soulwick`, je Umgebung (`development`, später `production`) eine Application:

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

1. Die GitHub-App von Dokploy braucht zusätzlich Zugriff auf das Repo **`soulwick`** (GitHub → Organisation
   `WebBude-de` → Settings → GitHub Apps → Dokploy → Repository access).
2. **DNS (Cloudflare):** A-Record (bei IPv6 auch AAAA) `game-dev` bzw. `game` auf die VPS-IP, **mit Proxy**
   (orange Wolke). Eine Ebene unter der Domain, deshalb `game-dev` statt `game.dev` (Plattform P-029).
3. **TLS:** Certificate Provider **None**; Traefik nimmt das Cloudflare-Ursprungszertifikat
   (`*.playsoulwick.com`), das schon in Dokploy liegt. Kein Let's Encrypt.
4. **Watch Paths** (nur bauen, wenn sich das Spiel ändert):
   `autoload/**`, `art/**`, `audio/**`, `characters/**`, `components/**`, `dungeon/**`, `economy/**`,
   `enemies/**`, `localization/**`, `meta/**`, `online/**`, `player/**`, `scenes/**`, `ui/**`,
   `upgrades/**`, `weapons/**`, `world/**`, `addons/**`, `deploy/web/**`, `project.godot`,
   `export_presets.cfg`, `default_bus_layout.tres`, `Dockerfile`, `.dockerignore`.
   Neue Spielordner hier ergänzen. Docs-, Test- und Tool-Änderungen bauen dann nicht neu.
5. **LFS:** Ob Dokploy beim Klonen Git-LFS-Dateien holt, ist nicht erprobt. Ohne LFS greift die Notlösung
   aus §2 (Ton wird synthetisch erzeugt, Build einige Minuten länger, eigene Ton-Dateien fehlen). Sauber
   wird es, wenn auf dem Server `git-lfs` installiert und global aktiviert ist (`apt install git-lfs` und
   `git lfs install --system`); im Build-Log steht sonst „Audio files are Git LFS pointers“.
6. Deployen; im Log: `godot --import`, `savepack`, `nginx: configuration file … test is successful`.
   Prüfen: `https://game-dev.playsoulwick.com/healthz` → `ok`, dann die Seite.
7. **Dokploy-Aufräumen:** Löscht die tägliche Docker-Bereinigung den Build-Cache, lädt der nächste Build
   Godot (~60 MB) und die Vorlage (10 MB) neu und importiert das Projekt komplett; das kostet nur Zeit.

### Für die Plattform (soulwick-platform, nicht hier ändern)

- **`GAME_URL`:** Die Spiel-Adresse steht zentral als Umgebungs-Variable `GAME_URL` der Plattform
  (development `https://game-dev.playsoulwick.com`, production `https://game.playsoulwick.com`).
- **CORS:** Das Spiel im Browser ruft die API von einer anderen Domain auf. Bei `soulwick-api`:
  `CORS_ORIGINS=${{environment.WEB_URL}},${{environment.ADMIN_URL}},${{environment.GAME_URL}}`.
  Ohne das schlagen Anmeldung, Ranglisten und Gilden im Browser fehl (Einzelspieler geht trotzdem; im
  Hauptmenü steht dann „Offline · Einzelspieler geht“). Der Relay (WebSocket) braucht kein CORS.
- **Website:** Bei `soulwick-web` `GAME_URL=${{environment.GAME_URL}}` (production bleibt bis zur
  Freischaltung leer). Die Knöpfe verlinken auf `<GAME_URL>/` („Im Browser spielen“) und
  `<GAME_URL>/?install` („Als App installieren“).

## 7. Lokal prüfen

```bash
docker build -t soulwick-game .                                          # development
docker build --build-arg SOULWICK_ENV=production -t soulwick-game:prod .
docker run --rm -p 18080:80 soulwick-game                                # http://localhost:18080
curl -sI http://localhost:18080/index.wasm -H "Accept-Encoding: br"      # Header prüfen
```

**Gegen die lokale Plattform** (`bun dev` in `soulwick-platform`, API `http://localhost:8787`, Relay
`ws://localhost:8790`; die lokale API erlaubt CORS von `http://localhost:18080`):

```bash
docker build --build-arg SOULWICK_ENV=local -t soulwick-game:local .
docker run --rm -p 18080:80 soulwick-game:local
```

`SOULWICK_ENV` erlaubt `development` (Standard), `production` und `local`; alles andere bricht den Build ab.
Ein `development`-Container auf `localhost:18080` spricht mit `api-dev`, die ihn per CORS ablehnt
(erwartet; das Spiel läuft dann offline).

`localhost` gilt als sichere Umgebung: Service Worker und Install-Knopf funktionieren dort auch ohne HTTPS.
Ein anderer Rechner im Netz braucht HTTPS. Der Docker-Build läuft unter Linux im Container; unter Windows
genügt Docker Desktop.

Ohne Docker: `python deploy/web/web_preset.py <kopie>/export_presets.cfg` in einer **Kopie** des Projekts,
dann `godot --headless --audio-driver Dummy --path <kopie> --export-release "Web" <ordner>/index.html`
und den Ordner mit einem Server ausliefern, der `.wasm` als `application/wasm` sendet.

## 8. Grafik-Briefing: App-Icons

Heute: `deploy/web/icons/icon_144.png`, `icon_180.png`, `icon_512.png`, erzeugt von `make_icons.py` aus
`logo_square` (Motiv ×2 bzw. ×6 auf `#15131f`, ca. 70 % Höhe). Gezeichnete Icons optional mit **gleichem Namen** ablegen; das Preset bleibt gleich.

| Datei | Größe | Wofür | Beschreibung |
| --- | --- | --- | --- |
| `deploy/web/icons/icon_512.png` | 512 × 512 | Android-Startbildschirm, Splash, Desktop-App | Kerze mit violettem Seelen-Kristall (wie `logo_square`) in Pixel-Art, auf 128 × 128 gezeichnet und ×4 skaliert (nearest neighbor). Motiv in der mittleren **80 %** (Android schneidet rund/als Squircle zu), Hintergrund vollflächig `#15131f` mit leichtem violettem Schein hinter der Flamme, **keine Transparenz**, kein Text. |
| `deploy/web/icons/icon_180.png` | 180 × 180 | iOS Home-Bildschirm (Apple Touch Icon) | Gleiches Motiv, für 180 eigens gesetzt (z. B. 60 × 60 Pixel-Art ×3); iOS rundet die Ecken selbst, also ohne eigenen Rahmen/Ecken, keine Transparenz. |
| `deploy/web/icons/icon_144.png` | 144 × 144 | Favicon, Windows/Chrome-App-Liste | Gleiches Motiv, 48 × 48 Pixel-Art ×3; Kontrast so, dass es auch auf 32 px (Tab) erkennbar bleibt. |

Optional später (braucht eine Preset- bzw. Shell-Erweiterung): 192 × 192 (Chrome-Empfehlung) und ein
„maskable“-Icon mit größerem Rand.

## 9. Lokal geprüft (16.10.2026)

Docker Desktop, Chromium 1234 (Playwright, SwiftShader), Container auf `localhost:18080`:

- Startseite lädt in ~1 s (lokal), Hauptmenü erscheint nach Klick; Konsole ohne Fehler außer der erwarteten
  CORS-Ablehnung von `api-dev` für `localhost` (Spiel zeigt „Offline · Einzelspieler geht“).
- Übertragen beim ersten Besuch: **26,2 MB** (index.pck 18,2 MB, index.wasm 7,9 MB, beides Brotli).
- Header (COOP/COEP, `application/wasm`, `font/ttf`, Brotli, Cache-Control) wie in §5; `crossOriginIsolated` = true.
- Manifest ohne Fehler, Service Worker registriert, `Page.getInstallabilityErrors` leer, `beforeinstallprompt`
  kommt in einem normalen Chrome-Profil → Knopf „Als App installieren“ sichtbar; `?install` öffnet den Dialog
  mit „Jetzt installieren“. iPhone-Safari-Kennung: Knopf + Hinweis „Teilen → Zum Home-Bildschirm“.
  (In Inkognito-/Wegwerf-Profilen bietet Chrome die Installation nie an, dort bleibt der Knopf aus.)
- Image **218 MB**; Build kalt ~7–11 min (je nach Netz: apt + Godot-Download), danach bei Spieländerungen
  Import + Export ~40–50 s und Vorkomprimierung ~40 s plus Kontext-Upload.

## 10. Offen

- Projekt-Icon (`application/config/icon`) und Boot-Splash fehlen im Projekt: Desktop-Builds zeigen das
  Godot-Logo; im Web-Build kann beim Start kurz der Standard-Splash erscheinen (Projekteinstellung, nicht Teil dieses Pakets).
- Preset-Werte aus §3 ins echte `export_presets.cfg` übernehmen (dann ist `web_preset.py` im Image wirkungslos, schadet aber nicht).
- Server-Architektur: Das Dockerfile lädt Godot für **x86_64**. Ein ARM-Server bräuchte `linux.arm64`.
- Auf iOS ist WebGL 2 vorhanden, die Leistung auf älteren Geräten aber ungetestet.
