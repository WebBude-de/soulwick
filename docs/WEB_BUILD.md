# Web-Build: Soulwick im Browser und als App (PWA)

> **Stand:** 16.10.2026 (Launch-Prüfung lokal mit Docker, §9 und §10). Dokploy-App `soulwick-game` aus
> diesem Repo; `development` läuft auf `game-dev.playsoulwick.com`. Abweichungen beim Einrichten hier
> nachtragen. Plattform-Seite: `../soulwick-platform/infra/DOKPLOY.md`. **Launch-Checkliste für
> Produktion:** [LAUNCH.md](LAUNCH.md).

| Umgebung | Branch | Domain | Build-Argument |
| --- | --- | --- | --- |
| `development` | `dev` | `https://game-dev.playsoulwick.com` | `SOULWICK_ENV=development` (Standard) |
| `production` | `production` | `https://game.playsoulwick.com` | `SOULWICK_ENV=production` |

**Übergang (D-157):** Bis die Produktiv-Server laufen, hängt `game.playsoulwick.com` als **zweite Domain** an
derselben development-App (Test-Server `api-dev`/`play-dev`), damit Desktop- und Browser-Spieler zusammen spielen.
Dafür bei `soulwick-api` (development) `https://game.playsoulwick.com` zusätzlich in `CORS_ORIGINS` eintragen.

## 1. Was wo liegt

| Datei | Zweck |
| --- | --- |
| `Dockerfile` | Drei Stufen: **godot** (Debian, Godot 4.7.2 Linux, nur die Web-Vorlage, gecacht), **export** (Ton-Notlösung, Umgebung, Preset, Import, Export, Vorkomprimierung), **runtime** (Alpine + nginx mit Brotli, Port 80, `HEALTHCHECK` auf `/healthz`). |
| `.dockerignore` | Schickt nur das Nötige in den Build (ohne `.git`, `.godot`, `builds`, `docs`, `tests`, `_inbox`, `art/web` …). |
| `deploy/web/shell.html` | Eigene Startseite (Godot „Custom HTML Shell“): dunkel, Pixel-Logo, Ladebalken, „Klicken/Tippen zum Starten“ (der Klick erlaubt den Ton), Knopf **„Als App installieren“**, iOS-Hinweis, Fehlermeldung, Wechsel auf neue Versionen, Links **Impressum · Datenschutz**, Hinweis „Dreh dein Gerät“ (Handy hochkant). Texte DE/EN nach Browsersprache. |
| `deploy/web/offline.html` | Offline-Seite der installierten App (DE/EN). |
| `deploy/web/404.html` | Fehlerseite für Pfade, die es nicht gibt (DE/EN, Knopf „Soulwick spielen“ → `/`). |
| `deploy/web/icons/icon_144/180/512.png` | App-Icons: **gezeichnet** (Claude Design, geliefert 16.10.2026, Briefing §8). `python deploy/web/make_icons.py --force` erzeugt nur noch einen Ersatz aus `art/ui/logo_square.png`; ohne `--force` lässt das Skript vorhandene Icons stehen. |
| `deploy/web/nginx.conf` | Header, MIME, Kompression, Caching, 404-Seite (§5). |
| `deploy/web/web_preset.py` | Setzt die Web-Werte im Preset „Web“ (§3); idempotent. Die Werte stehen seit 16.10.2026 im echten `export_presets.cfg`; das Dockerfile ruft das Skript als Absicherung auf seiner **Kopie** auf (Log: „already up to date“). |
| `deploy/web/patch_service_worker.py` | Passt den von Godot erzeugten Service Worker an (§5 „Offline und Updates“); bricht den Build ab, wenn Godot den Worker so ändert, dass der Patch nicht mehr passt. |
| `deploy/web/fetch_template.py` | Holt aus dem offiziellen Vorlagen-Archiv (1,3 GB) per HTTP-Range nur `web_nothreads_release.zip` (10 MB) und prüft SHA-512. |
| `deploy/.gdignore` | Godot importiert `deploy/` nicht (nichts davon landet in der `.pck`). |

## 2. Ablauf im Image

1. **godot** (gecacht): Godot `4.7.2-stable` Linux von `github.com/godotengine/godot-builds`, SHA-512 aus `SHA512-SUMS.txt` fest im Dockerfile; Web-Vorlage per `fetch_template.py` (CRC32 + festgelegte SHA-512, ermittelt aus dem offiziellen `Godot_v4.7.2-stable_export_templates.tpz`). Dauert Sekunden statt 1,3 GB Download.
2. **export** (läuft bei jeder Spieländerung):
   - **Git LFS:** Der Ton liegt in LFS. Klont Dokploy ohne LFS, liegen nur Zeiger-Dateien da; dann erzeugt der Build den Ton mit `tools/generate_audio.py` und `tools/generate_music.py` neu (dauert einige Minuten). Eigene `.ogg`/`.mp3` fehlen in dem Fall (Zeiger werden entfernt, das Spiel nimmt das erzeugte `.wav`). Besser: §6 „LFS“.
   - `online/environment.cfg`: `env="<SOULWICK_ENV>"`, genau wie `tools/export_build.sh` (gleiche `sed`-Zeile). Erlaubt: `development`, `production`, `local` (§7).
   - `python3 deploy/web/web_preset.py export_presets.cfg` (nur in der Kopie im Image).
   - `godot --headless --audio-driver Dummy --import`, dann `--export-release "Web" /out/index.html`. Der Import-Cache (`.godot`) bleibt als BuildKit-Cache-Mount zwischen Builds erhalten.
   - Schrift `PixelifySans` (OFL) nach `fonts/`, `404.html`, Service Worker patchen
     (`patch_service_worker.py`), `robots.txt` und `X-Robots-Tag` (nur `production` darf in
     Suchmaschinen; development: `Disallow: /` und `noindex, nofollow`), `.br`/`.gz`-Kopien.
3. **runtime:** `alpine:3.22` + `nginx` + `nginx-mod-http-brotli`, `/etc/nginx/soulwick-env.conf`
   (Kopf-Zeilen je Umgebung), `nginx -t` beim Bauen.

## 3. Werte im Export-Preset „Web“

**Erledigt (16.10.2026):** Die Werte stehen in `[preset.5.options]` des Presets **„Web“** im echten
`export_presets.cfg` (eingetragen mit `python deploy/web/web_preset.py`), damit auch `tools/export_build.*`
dieselbe Seite und App-Daten bekommt. `web_preset.py` im Dockerfile ändert damit nichts mehr und bleibt als
Absicherung drin. Die Werte:

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
- **Impressum · Datenschutz** unten links verlinken auf die Website derselben Umgebung (`game-dev.*` →
  `dev.playsoulwick.com`, sonst `playsoulwick.com`, Pfade `/imprint` und `/privacy`), öffnen einen neuen
  Tab und starten das Spiel nicht.
- **Handy hochkant:** Läuft das Spiel auf einem Touch-Gerät im Hochformat, liegt der Hinweis „Dreh dein
  Gerät – Soulwick spielt sich im Querformat“ darüber; Drehen oder ein Tipp blendet ihn aus.
- Bei offenem Install-Dialog (`?install`) behält der Dialog den Fokus, auch wenn das Laden fertig wird;
  Escape schließt ihn.
- **iOS-Safari:** Installieren nur über „Teilen → Zum Home-Bildschirm“ (der Knopf öffnet die Anleitung).
  Vollbild gibt es auf dem iPhone nur als Home-Bildschirm-App (`apple-mobile-web-app-capable`,
  `display: standalone`); im Safari-Tab bleiben die Leisten. Ton: Godot legt den Audio-Kontext beim Start
  an und setzt ihn bei jeder Eingabe fort, spätestens der erste Tipp im Spiel schaltet den Ton frei. Der
  Stummschalter des iPhones schaltet Web-Ton stumm (Standard von Safari, bewusst nicht umgangen).

## 5. Server-Verhalten (nginx)

| Was | Wert |
| --- | --- |
| Header überall | `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`, `Cross-Origin-Resource-Policy: same-origin`, `X-Content-Type-Options: nosniff`, `Referrer-Policy` |
| MIME | `.wasm` → `application/wasm`, `.pck` → `application/octet-stream`, `.manifest.json` → `application/manifest+json`, `.ttf` → `font/ttf` |
| Kompression | vorkomprimiert `.br` (Brotli 9) und `.gz`; nginx liefert, was der Browser kann |
| Caching | `index.html`, Service Worker, Manifest, `.pck`, `.wasm`, `.js`: `no-cache` (Browser prüft per ETag, bei gleichem Stand 304); Icons 1 Tag, Schrift 30 Tage |
| Suchmaschinen | `production`: `robots.txt` mit `Allow: /`; sonst `Disallow: /` und Kopfzeile `X-Robots-Tag: noindex, nofollow` |
| Fehlerseite | unbekannte Pfade → `404.html` mit Status 404 (direkt nicht abrufbar) |
| Healthcheck | `GET /healthz` → `ok` |

**Warum kein Versions-Query:** Godot lädt immer `index.pck`/`index.wasm` unter festem Namen. Langes
Caching würde dem Service Worker beim Update alte Dateien unterschieben. Mit `no-cache` + ETag kostet ein
unveränderter Besuch nur kleine 304-Antworten; offline und in der installierten App liefert der Service
Worker aus seinem eigenen Cache. COOP/COEP braucht der einfädige Build nicht, sie schaden aber nicht (API-
Aufrufe laufen mit CORS, WebSockets sind nicht betroffen) und halten den Weg zu einem Build mit Threads offen.

### Offline und Updates (Service Worker)

- Godot registriert den Worker `index.service.worker.js` erst, wenn das Spiel gestartet ist. Er legt beim
  Installieren Seite, Engine-JS, Offline-Seite, Audio-Worklets und (gepatcht) Manifest, Schrift und Icons
  in einen Cache je Version (`Soulwick-sw-cache-<Exportzeit>`); `index.pck` und `index.wasm` kommen beim
  nächsten Laden dazu. Danach startet das Spiel auch ohne Netz (Online-Teil natürlich nicht).
- **Patch** (`patch_service_worker.py`): Godot fand die Seite nur unter `/index.html`. Aufrufe von `/` und
  `/?install` (Links der Website) bekamen offline die Fehlerseite des Browsers. Jetzt liefert der Worker
  für den Ordner und mit beliebiger Query die gespeicherte `index.html`; Schrift und Icons gibt es offline.
- **Neue Version:** Jeder Export hat eine neue Cache-Version, der Browser holt den geänderten Worker beim
  nächsten Aufruf. Ist der Startbildschirm noch offen, schickt die Seite `update` an den wartenden Worker,
  der übernimmt und lädt die Seite neu (alter Cache wird gelöscht). Läuft das Spiel schon, passiert nichts;
  die neue Version kommt beim nächsten Start. Geprüft 16.10.2026 (§9).
- Ohne gespeicherte Spieldateien und ohne Netz zeigt der Worker `index.offline.html`.

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

**Geliefert (16.10.2026):** Die gezeichneten Icons (Claude Design) liegen unter
`deploy/web/icons/icon_144.png`, `icon_180.png`, `icon_512.png`. `make_icons.py` ist nur noch der Ersatz
aus `logo_square` und überschreibt sie nur mit `--force`. Neue Fassungen mit **gleichem Namen** ablegen;
das Preset bleibt gleich. Ursprüngliches Briefing:

| Datei | Größe | Wofür | Beschreibung |
| --- | --- | --- | --- |
| `deploy/web/icons/icon_512.png` | 512 × 512 | Android-Startbildschirm, Splash, Desktop-App | Kerze mit violettem Seelen-Kristall (wie `logo_square`) in Pixel-Art, auf 128 × 128 gezeichnet und ×4 skaliert (nearest neighbor). Motiv in der mittleren **80 %** (Android schneidet rund/als Squircle zu), Hintergrund vollflächig `#15131f` mit leichtem violettem Schein hinter der Flamme, **keine Transparenz**, kein Text. |
| `deploy/web/icons/icon_180.png` | 180 × 180 | iOS Home-Bildschirm (Apple Touch Icon) | Gleiches Motiv, für 180 eigens gesetzt (z. B. 60 × 60 Pixel-Art ×3); iOS rundet die Ecken selbst, also ohne eigenen Rahmen/Ecken, keine Transparenz. |
| `deploy/web/icons/icon_144.png` | 144 × 144 | Favicon, Windows/Chrome-App-Liste | Gleiches Motiv, 48 × 48 Pixel-Art ×3; Kontrast so, dass es auch auf 32 px (Tab) erkennbar bleibt. |

Optional später (braucht eine Preset- bzw. Shell-Erweiterung): 192 × 192 (Chrome-Empfehlung) und ein
„maskable“-Icon mit größerem Rand.

## 9. Lokal geprüft (16.10.2026)

Docker Desktop, Image `soulwick-game` (development, dazu ein `production`-Build), Container auf eigenem
Port, Chromium 151 (Playwright, headless, `--mute-audio`) mit echter GPU (ANGLE/D3D11) und zum Vergleich
SwiftShader. Testskript und Bilder lagen im Scratchpad der Sitzung (nicht im Repo).

| Prüfung | Ergebnis |
| --- | --- |
| Startseite, Hauptmenü, Run per Tastatur und Maus | Profil anlegen, Welt anlegen, Dorf, zum Dungeon laufen, Raum 1 freikämpfen, **Raum 2 erreicht** („Neuer Rekord: Raum 2“). |
| Touch (Pixel 7 und iPhone 14, quer) | Startseite „Tippen zum Starten“, Menüs per Tipp. **Zwei-Stick-Steuerung ging nicht** (Spiel-Fehler, §11); mit der Korrektur in einer Testkopie laufen, zielen und angreifen auf beiden Profilen. |
| Hochkant | Spiel klein mit Rändern → Hinweis „Dreh dein Gerät“ (neu); Startseite ohne Überlappung (Knopf und Fußzeile neu angeordnet). |
| Installierbarkeit | Manifest ohne Fehler, `Page.getInstallabilityErrors` leer, `beforeinstallprompt` kommt, Knopf und `?install`-Dialog mit „Jetzt installieren“; iPhone-Kennung: Anleitung „Teilen → Zum Home-Bildschirm“. |
| Service Worker | registriert nach dem Start; zweiter Besuch kommt aus dem Cache. Offline starten `/index.html`, **`/` und `/?install`** (vor dem Patch: Fehlerseite des Browsers), Schrift offline vorhanden. |
| Update | neue Cache-Version auf dem Server → die offene Startseite lädt neu, nur der neue Cache bleibt. |
| `crossOriginIsolated` | `true` (COOP/COEP von nginx), `SharedArrayBuffer` vorhanden. |
| Umgebung | development ruft `https://api-dev.playsoulwick.com/public/config`, production `https://api.playsoulwick.com/public/config`; lokal lehnt die API CORS ab (erwartet). |
| robots, 404 | dev: `Disallow` und `X-Robots-Tag: noindex, nofollow`; prod: `Allow`, kein Header. Unbekannter Pfad → eigene 404-Seite. |
| Spiel-Tests | `validate_project`: 1153 Dateien, 0 Fehler; GUT: 1565 Tests, 1563 grün, 2 ausstehend (Online-Tests ohne Schlüssel). |

Image **218 MB**; Build bei Spieländerungen ~60–80 s (Import-Cache warm).

## 10. Leistung im Browser (Mobil)

Gemessen mit dem Geräteprofil „Pixel 7 quer“ (863 × 360 CSS-Pixel, DPR 2,625 → Canvas 2265 × 945),
CPU-Drosselung über das DevTools-Protokoll. **Die GPU ist eine Desktop-Karte**: Die Bildraten zeigen die
CPU-Seite, nicht die Füllrate eines Handys. Grobe Werte, je Lauf ±20 %.

| Messung | CPU ×1 | CPU ×4 (Mittelklasse) | CPU ×6 (schwach) |
| --- | --- | --- | --- |
| Download erster Besuch | 25,0 MB (pck 17,8, wasm 7,7, Rest 0,1) | gleich | gleich |
| Startseite bereit (lokal, inkl. wasm-Kompilierung) | 0,5–0,9 s | 1,2 s | 1,6 s |
| Tipp → Spiel läuft (Hauptthread blockiert) | 4,9–7 s | 15–22 s | 32 s |
| Hauptmenü (ungebremst, rAF) | 360 fps | 270 fps | 190 fps |
| Dorf | 211 fps (p95 5,6 ms) | 56–62 fps (p95 20–25 ms) | 36–44 fps (p95 28–36 ms) |
| Speicher (Browser-Messung der Seite) | 58 MB Startseite → 228 MB Menü → 266 MB Dorf | gleich | 280 MB |

- **Ladezeit über das Netz** (25 MB): ~4 s bei 50 Mbit/s, ~20 s bei 10 Mbit/s (typisches 4G), über 2 min
  bei 1,6 Mbit/s. Zweiter Besuch: nur kleine 304-Antworten bzw. Service-Worker-Cache.
- **Der Start ist der größte Hebel:** Nach dem Tipp blockiert Godot den Hauptthread am Stück (Engine-Setup
  ~2 s bis zur Grafik-Initialisierung, dann Autoloads und Hauptszene). Auf schwachen Handys 15–30 s ohne
  Bildaufbau, nur die CSS-Animation (Leuchten) läuft weiter. Ab etwa 20 s kann Android „Seite reagiert
  nicht“ anbieten. Ursachen im Debug-Build profilieren (Autoload-`_ready`, Hauptmenü, Übersetzungen).
- **SwiftShader** (Software-Grafik, ×4): Dorf 3,9 fps. Zeigt nur, dass ohne GPU nichts geht; echte Handys
  haben WebGL 2 in Hardware.
- **Renderer:** Web läuft immer mit **Compatibility (WebGL 2 / GLES 3)**, Konsole: „OpenGL ES 3.0 (WebGL
  2.0) – Compatibility“. Desktop nutzt Forward+ (`config/features`), Mobil `gl_compatibility`. Das passt;
  Unterschiede zwischen Forward+ und Compatibility (2D-Leuchten, Shader) einmal nebeneinander ansehen.
- **Auflösung:** Mit `canvas_items` zeichnet das Spiel in voller Geräteauflösung (Pixel 7: 2,1 MP, iPhone
  14 quer: 2,3 MP) inklusive Vollbild-Shadern (Sicht, Nachbearbeitung). Auf Handy-GPUs ist das die
  Füllraten-Grenze; das ließ sich hier nicht messen (Desktop-GPU). Vorschläge für `project.godot` in §11.
- Speicher ~270–280 MB im Dorf: für aktuelle Handys in Ordnung; ältere iPhones beenden Tabs früher.

## 11. Offen

**Spiel-Code (nicht Teil des Web-Pakets, für den Integrator):**

- **Zwei-Stick-Steuerung im Browser (Blocker für Mobil):** `ui/touch/touch_overlay.gd`,
  `_is_desktop_input()`. Godot erzeugt aus jedem Fingerzug eine `InputEventMouseMotion` mit
  `device = 32` (nicht `DEVICE_ID_EMULATION`); sie gilt als echte Maus, setzt `touched = false`, blendet
  die Steuerung aus und lässt die Sticks los. Folge: Die Steuerung erscheint nur kurz, die Figur läuft
  nicht, ein Tipp schlägt über die emulierte Maus zu. Korrektur (in einer Testkopie geprüft, Pixel 7 und
  iPhone 14): Mausbewegungen nie als Wechsel zur Desktop-Steuerung werten, nur Maustasten:

  ```gdscript
  if event is InputEventMouseButton:
  	return event.device != InputEvent.DEVICE_ID_EMULATION
  ```

  Wahrscheinlich betrifft das auch den Android-Export (gleiche Emulation); dort gegenprüfen.
- **Konsolenfehler im Browser:** `DisplayServer.keyboard_get_keycode_from_physical` gibt es im Web nicht
  („Not supported by this display server“, 44× bis zum Dorf). In `ui/icons/input_glyphs.gd`
  (`engine_key_name`) und `ui/options/controls_info.gd` zusätzlich zu `headless` auch `Web` ausnehmen
  (`DisplayServer.get_name() not in ["headless", "Web"]`).
- **Vollbild in Android-Browsern:** Die Startseite könnte beim Tipp `requestFullscreen()` und
  `screen.orientation.lock("landscape")` aufrufen. Das Spiel setzt beim Start aber den gespeicherten
  Fenstermodus (`GameOptions.apply_window_mode`, Standard „Fenster“) und würde das Vollbild sofort
  beenden. Erst `apply_window_mode()` im Browser überspringen (`OS.has_feature("web")`), dann das Vollbild
  in der Shell einschalten. Auf dem iPhone gibt es Vollbild nur als Home-Bildschirm-App.
- **Rechtstexte im Spiel:** Die Startseite verlinkt Impressum und Datenschutz; im laufenden Spiel gibt es
  keinen Link. Für „ständig erreichbar“ einen Eintrag im Hauptmenü ergänzen (Web: `OS.shell_open`).

**Vorschläge für `project.godot` (nur vorgeschlagen, nichts geändert):**

- `application/boot_splash/show_image=false` und
  `application/boot_splash/bg_color=Color(0.08235294, 0.07450981, 0.12156863, 1)` (`#15131f` wie die
  Startseite), damit beim Start kein grauer Godot-Splash aufblitzt; dazu `application/config/icon`
  (Desktop-Builds zeigen sonst das Godot-Logo).
- Auf Handys im Browser in 1280 × 720 rendern und skalieren statt in voller Geräteauflösung, per
  Feature-Override nur dort: `display/window/stretch/mode.web_android="viewport"` und
  `display/window/stretch/mode.web_ios="viewport"` (Pixel-Art bleibt scharf, ~3× weniger Pixel). Erst auf
  einem echten Mittelklasse-Handy vergleichen (Textschärfe, Bildrate).
- Bildrate im Browser auf 60 begrenzen, falls 120-Hz-Handys heiß laufen: `application/run/max_fps.web=60`
  (vorher prüfen, ob Godot das im Web-Hauptloop beachtet).
- Kleineres Paket: Die Musik liegt als WAV (QOA) vor (`audio/music`, 78 MB roh, der Großteil der 17,8 MB
  `index.pck`). Als Ogg Vorbis wäre sie etwa halb so groß (Sache von `tools/generate_music.py`).

**Weiteres:**

- Server-Architektur: Das Dockerfile lädt Godot für **x86_64**. Ein ARM-Server bräuchte `linux.arm64`.
- Echte Geräte fehlen: iOS-Safari (WebGL 2, Ton nach Tipp, Speichergrenze) und ein Android-Mittelklasse-
  Handy (Bildrate, Wärme, Startzeit) einmal von Hand prüfen, Liste in [LAUNCH.md](LAUNCH.md) §8.
