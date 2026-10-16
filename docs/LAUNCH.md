# Launch-Checkliste: Web-App und Produktion

> **Stand:** 16.10.2026 (Claude, nach der lokalen Prüfung mit Docker, [WEB_BUILD.md](WEB_BUILD.md) §9–§11).
> Reihenfolge einhalten, abhaken mit Datum. **[PM]** = Projektmitglied klickt (Cloudflare, Dokploy,
> GitHub, eRecht24, Geräte in der Hand), **[C]** = Claude (Code, lokale Prüfung, Doku, Smoke-Test per
> `curl`/Playwright). Agenten committen und pushen nie; Merge, Push und Branches macht das Projektmitglied.
> Plattform-Details: `../soulwick-platform/infra/DOKPLOY.md` (§2 DNS/TLS, §4 Variablen, §5 Backups, §13).

**Ziel:** `https://game.playsoulwick.com` (Spiel), `https://playsoulwick.com` (Website),
`https://api.playsoulwick.com` (API), `wss://play.playsoulwick.com/v1` (Relay). Heute läuft nur
`development` (`game-dev`, `dev`, `api-dev`, `play-dev`).

**Stand der Prüfung am 16.10.2026, 07:20:** `dev.playsoulwick.com`, `api-dev` und `play-dev` antworten 200.
**`game-dev.playsoulwick.com` antwortet 502** (Cloudflare „error code: 502“, auch `/healthz`): Container
läuft nicht oder baut gerade. `api.playsoulwick.com` antwortet 404 (Produktion noch nicht eingerichtet),
`game.playsoulwick.com` 404.

## 1. Vorab entscheiden

- [ ] **[PM]** Freigabe der Browser-Version in Produktion (D-148 steht auf `OFFEN`). Bis dahin bleibt
  `GAME_URL` von `soulwick-web` in `production` leer (keine Knöpfe auf der Website).
- [ ] **[PM]** Online-Teil zum Launch: `LIVE_FEATURES` der Website (`false` = Teaser ohne Ranglisten) und ob
  `soulwick-relay`/`soulwick-admin` in `production` schon laufen sollen (DOKPLOY.md §4 „Produktion vorerst“).
- [ ] **[PM]** Bug-Reports in Produktion an oder aus. Heute: im `production`-Build **aus** (DevFeedback ist
  nur außerhalb von `production` an), in `development` an (F9/#, Touch-Knopf oben rechts).
- [ ] **[PM]** Support-Adresse für `SUPPORT_EMAIL` (Pflicht in `production`; Vorlage: `hello@playsoulwick.com`).
- [ ] **[PM]** Vorschläge für `project.godot` annehmen oder ablehnen (WEB_BUILD.md §11: Boot-Splash,
  Rendern in 1280 × 720 auf Handys, Bildrate 60, Musik als Ogg).

## 2. Spiel-Code fertig machen

- [ ] **[C]** Zwei-Stick-Steuerung im Browser reparieren (Blocker für Handys): `ui/touch/touch_overlay.gd`,
  `_is_desktop_input()` wertet emulierte Mausbewegungen (`device = 32`) als echte Maus. Korrektur und
  Nachweis in WEB_BUILD.md §11; danach Touch-Lauf wiederholen und Android-Export gegenprüfen.
- [ ] **[C]** Konsolenfehler `keyboard_get_keycode_from_physical` im Web abstellen (`input_glyphs.gd`,
  `controls_info.gd`).
- [ ] **[C]** Optional: Fenstermodus im Browser nicht anwenden, dann Vollbild + Querformat beim Start-Tipp auf
  Android (WEB_BUILD.md §11); Link „Impressum · Datenschutz“ im Hauptmenü (Web).
- [ ] **[C]** Prüfen: `validate_project`, GUT, `smoke_test`, Docker-Build `development` und `production`,
  Browser-Lauf bis Raum 2 (Tastatur) und Touch-Lauf (Pixel 7, iPhone 14). Ergebnis in WEB_BUILD.md §9.
- [ ] **[PM]** Pull Requests `feature/*` → `dev` → `main` mergen (TECHSTACK.md §3).
- [ ] **[PM]** Branch **`production`** anlegen, in **beiden** Repos (gibt es noch nicht; heute nur `dev`,
  `main`, `feature/*`): `git push origin main:production`. Auf `production` nie direkt committen.

## 3. Cloudflare (Zone `playsoulwick.com`)

- [ ] **[PM]** **DNS:** A-Record (bei IPv6 auch AAAA) auf die VPS-IP, jeweils **mit Proxy** (orange Wolke):
  `@`, `api`, `play`, `game`; `admin` erst, wenn das Admin-Panel in `production` läuft; `www` als
  Platzhalter mit Redirect-Regel auf `https://playsoulwick.com` (DOKPLOY.md §2).
- [ ] **[PM]** **SSL/TLS → Übersicht: Full (strict).** Das Ursprungszertifikat `playsoulwick.com` +
  `*.playsoulwick.com` liegt schon in Dokploy (gilt für alle Hosts eine Ebene tief, auch `game`).
- [ ] **[PM]** **Edge-Zertifikate:** „Always Use HTTPS“ an (Service Worker und Installieren brauchen HTTPS).
- [ ] **[PM]** **Netzwerk:** WebSockets an (Standard; Relay).
- [ ] **[PM]** **Speed → Optimierung:** Rocket Loader **aus** (schreibt Skript-Tags um und kann die Engine
  stören); keine HTML-Umschreibungen (E-Mail-Verschleierung o. Ä.) für `game.*`.
- [ ] **[PM]** **Cache-Regel für das Spiel** (Caching → Cache Rules → Create): Name „game: nicht am Rand
  cachen“, Ausdruck
  `(http.host in {"game.playsoulwick.com" "game-dev.playsoulwick.com"} and http.request.uri.path.extension in {"wasm" "pck" "js" "html" "json"})`
  → **Bypass cache**. Grund: `index.pck`, `index.wasm`, `index.js` heißen in jeder Version gleich; eine
  Kopie am Rand würde neuen Besuchern alte Dateien geben und der Service Worker würde sie für die neue
  Version speichern. nginx sendet `no-cache` + ETag (Browser fragt nach, 304), das reicht. Die Regel schützt
  vor einer späteren „Cache Everything“-Regel für die ganze Zone. Icons und Schrift dürfen am Rand liegen.
  Edge-Caching für `.wasm`/`.pck` erst später und nur mit automatischem Purge nach jedem Deploy.
- [ ] **[C]** Nach dem Einrichten prüfen: `cf-cache-status` für `index.pck`/`index.wasm` ist `BYPASS` oder
  `DYNAMIC`, `content-encoding: br` kommt an, COOP/COEP-Header sind da (§8).

## 4. Dokploy: Umgebung `production`

Reihenfolge wie in DOKPLOY.md §7: Datenbank → API → Relay → Web → Spiel → Admin. App Names mit `-prod`.

- [ ] **[PM]** Projekt `soulwick` → Umgebung **`production`** anlegen.
- [ ] **[PM]** **Geheimnisse** neu erzeugen, nur für `production` (DOKPLOY.md §3): `BETTER_AUTH_SECRET`,
  `RELAY_INTERNAL_KEY`, `DEV_AUTH_KEY`, DB-Passwort; im Passwort-Manager ablegen.
- [ ] **[PM]** **DB** `soulwick-postgres` (App Name `soulwick-postgres-prod`, PostgreSQL 17, kein externer
  Port); Internal Connection URL kopieren.
- [ ] **[PM]** **Backups:** Settings → Destinations (S3, z. B. Hetzner Object Storage); bei
  `soulwick-postgres-prod` täglich `0 3 * * *`, 14 Stück aufbewahren. **Wiederherstellung einmal in
  `development` testen** (DOKPLOY.md §5). Vor jedem Release mit Migration ein manuelles Backup.
- [ ] **[PM]** **`soulwick-api`** (`apps/api/Dockerfile`, Context `.`, Branch `production`, Port 8787,
  Domain `api.playsoulwick.com`, HTTPS, Certificate Provider None, 1 Replica). Deploy, Log bis
  `"msg":"listening"`, `Seed admin: … created`.
- [ ] **[PM]** **`soulwick-relay`** (falls entschieden, §1): Port 8790, Domain `play.playsoulwick.com`,
  **Auto Deploy aus**, 1 Replica.
- [ ] **[PM]** **`soulwick-web`**: Port 3000, Domain `playsoulwick.com` (kein `www` in Dokploy).
- [ ] **[PM]** **`soulwick-game`** (dieses Repo, WEB_BUILD.md §6): Repository `WebBude-de/soulwick`, Branch
  `production`, Dockerfile `Dockerfile`, Context `.`, **Build-Argument `SOULWICK_ENV=production`**,
  Domain `game.playsoulwick.com`, **Container Port 80**, HTTPS, Certificate Provider None, Watch Paths aus
  WEB_BUILD.md §6. Im Build-Log: `Web preset already up to date`, `index.service.worker.js: patched`,
  `nginx … test is successful`. Kommt „Audio files are Git LFS pointers“, `git-lfs` auf dem Server
  einrichten (WEB_BUILD.md §6 Punkt 5).
- [ ] **[PM]** `soulwick-admin` (optional): Domain `admin.playsoulwick.com`, vorher **Basic Auth** oder
  Cloudflare Access (DOKPLOY.md §8). Nach dem ersten Login Passwort ändern, `DEFAULT_ADMIN_PASSWORD` löschen.

## 5. Variablen `production`

- [ ] **[PM]** **Variablen der Umgebung** (DOKPLOY.md §4, Block „production“), u. a.:

  ```dotenv
  WEB_URL=https://playsoulwick.com
  ADMIN_URL=https://admin.playsoulwick.com
  GAME_URL=https://game.playsoulwick.com
  API_PUBLIC_URL=https://api.playsoulwick.com
  RELAY_PUBLIC_URL=wss://play.playsoulwick.com
  API_INTERNAL_URL=http://soulwick-api-prod:8787
  RELAY_INTERNAL_URL=http://soulwick-relay-prod:8790
  SUPPORT_EMAIL=<Support-Adresse>
  ```

- [ ] **[PM]** **`soulwick-api` → Environment:**
  `CORS_ORIGINS=${{environment.WEB_URL}},${{environment.ADMIN_URL}},${{environment.GAME_URL}}`
  (ohne `GAME_URL` scheitern Anmeldung, Ranglisten, Bug-Reports im Browser; Einzelspieler geht). Gilt schon
  vor der Freischaltung. Dazu `GUEST_AUTH_ENABLED=true`, `TRUST_PROXY=true`, `DEV_AUTH_ENABLED` nach
  Bedarf (zum Steam-Start `false`), Start-Admin.
- [ ] **[PM]** **`soulwick-web` → Environment:** `LIVE_FEATURES` laut §1; `GAME_URL=` **leer** bis zur
  Freigabe, dann `GAME_URL=${{environment.GAME_URL}}` und Web neu deployen (Knöpfe „Im Browser spielen“,
  „Web-App installieren“).
- [ ] **[PM]** `soulwick-game` braucht keine Laufzeit-Variablen; die Umgebung steckt im Build-Argument.
- [ ] **[C]** Abgleich: Variablen gegen DOKPLOY.md §4 lesen lassen (Projektmitglied schickt die Liste
  ohne Geheimnisse), Abweichungen markieren.

## 6. Rechtstexte

- [ ] **[PM]** eRecht24: Projekt für `playsoulwick.com` anlegen, **API-Schlüssel und Plugin-Schlüssel**
  erzeugen (fehlen noch) und bei `soulwick-api` als `ERECHT24_API_KEY`/`ERECHT24_PLUGIN_KEY` eintragen,
  API neu starten. Ohne beide zeigt die Website einen Platzhalter.
- [ ] **[PM]** Datenschutzerklärung im eRecht24-Generator um die Web-App ergänzen: Hosting (VPS,
  Dokploy), Cloudflare (Proxy, Übermittlung USA), Spielstände lokal im Browser (IndexedDB/Local Storage,
  keine Cookies), Gast-Konto mit Geräte-ID und Name, Ranglisten/Gilden, Bug-Reports mit Bildschirmfoto
  (90 Tage), Server-Logs. nginx im Spiel-Container protokolliert nur die Adresse des vorgeschalteten
  Proxys, keine Spieler-IP.
- [ ] **[C]** Prüfen: `https://playsoulwick.com/imprint` und `/privacy` zeigen den echten Text; die
  Startseite des Spiels verlinkt beide (unten links, neuer Tab, `game.*` → `playsoulwick.com`).

## 7. Betrieb: Bug-Reports, Monitoring, Rollback

- [ ] **[PM]** **Uptime-Überwachung** (z. B. UptimeRobot/Uptime Kuma, minütlich):
  `https://game.playsoulwick.com/healthz` („ok“), `https://api.playsoulwick.com/health` (503 bei DB-Fehler),
  `https://play.playsoulwick.com/health`, `https://playsoulwick.com/`. Benachrichtigung per E-Mail.
- [ ] **[PM]** **Logs:** Dokploy → Application → Logs. API und Relay schreiben JSON-Zeilen, das Spiel nur
  nginx-Zugriffe (Fehler stehen auf stderr). Container-Zustand über `HEALTHCHECK` (Spiel `/healthz`).
- [ ] **[PM]** **Bug-Reports:** Admin-Panel → Bug-Reports (nur wenn in §1 eingeschaltet; Grenze 10 je
  Spieler und Stunde). Auswerten wie in `docs/feedback/README.md`; Claude wertet Meldungen auf Zuruf aus.
- [ ] **[PM]** **Rollback Spiel/Web/Admin** (ohne Zustand): Dokploy → Application → Deployments → älteren
  erfolgreichen Build erneut deployen; geht das nicht, den Branch `production` auf den letzten guten Commit
  setzen (`git push --force-with-lease origin <commit>:production`), Dokploy baut ihn neu. Beim Spiel
  bekommen Spieler die zurückgesetzte Version wie ein Update (neue Cache-Version).
- [ ] **[PM]** **Rollback API:** wie oben, aber Migrationen werden nicht zurückgedreht; nur
  rückwärtskompatible Migrationen ausliefern (DOKPLOY.md §9). Relay nie während einer Spielrunde deployen.
- [ ] **[C]** Nach jedem Deploy den Smoke-Test (§8) laufen lassen und das Ergebnis melden.

## 8. Smoke-Test nach dem Deploy

Erst `development` (`game-dev`, `api-dev`, `play-dev`, `dev`), dann `production`.

**[C] per `curl` (Git Bash):**

```bash
G=https://game.playsoulwick.com; A=https://api.playsoulwick.com
curl -s $G/healthz                                    # ok
curl -sI $G/ | grep -i "cross-origin\|cache-control\|x-robots"   # COOP/COEP/CORP, no-cache, KEIN X-Robots-Tag
curl -s $G/robots.txt                                 # Allow: /   (development: Disallow: /)
curl -sI -H "Accept-Encoding: br" $G/index.wasm | grep -i "content-type\|content-encoding\|cf-cache"
                                                      # application/wasm, br, BYPASS/DYNAMIC
curl -s $G/index.manifest.json                        # name Soulwick, start_url ./index.html, Icons
curl -s $G/index.service.worker.js | head -1          # /* soulwick: patched … */
curl -sI $G/gibt-es-nicht | head -1                   # 404 (eigene Seite)
curl -s $A/health                                     # "status":"ok","db":"ok"
curl -s $A/public/config                              # relayUrl wss://play.playsoulwick.com/v1, guestAuth true
curl -sI -H "Origin: $G" $A/public/config | grep -i access-control-allow-origin   # = $G
curl -s https://play.playsoulwick.com/health          # "status":"ok"
curl -sI https://www.playsoulwick.com/ | head -3      # 301 → https://playsoulwick.com/
```

**[C] per Playwright (stumm, headless):** Startseite, Klick, Hauptmenü ohne „dev“-Kennung und mit
„Online bereit“, Run bis Raum 2, Touch-Lauf Pixel 7/iPhone 14, Installierbarkeit, Offline-Start von `/`,
`crossOriginIsolated`.

**[PM] auf echten Geräten:**

- [ ] Desktop Chrome/Edge: `https://game.playsoulwick.com`, Spiel startet, Ton nach dem Klick, Hauptmenü
  unten rechts nur die Version und „Online bereit“; „Als App installieren“ → eigenes Fenster.
- [ ] Desktop Firefox und Safari (Mac): Spiel startet (Installieren gibt es dort nicht, der Dialog erklärt das).
- [ ] Android (Chrome, Mittelklasse): Laden (Zeit notieren), Tipp → Spiel (Zeit notieren), Zwei-Stick-
  Steuerung, Hinweis „Dreh dein Gerät“ hochkant, installieren, App vom Startbildschirm, Flugmodus →
  App startet trotzdem (Einzelspieler). Gerät warm? Bildrate ruckelt?
- [ ] iPhone (Safari): Start, Ton nach dem ersten Tipp (Stummschalter aus), „Als App installieren“ →
  Anleitung → Zum Home-Bildschirm → App öffnet ohne Safari-Leisten, Spielstand bleibt nach Neustart.
- [ ] Website `https://playsoulwick.com`: Knöpfe „Im Browser spielen“ und „Web-App installieren“ (nur
  nach Freigabe), Impressum, Datenschutz, `/delete-account` mit Support-Adresse.
- [ ] Neue Version: kleine Änderung deployen, offene Startseite lädt einmal neu, laufendes Spiel nicht.

## 9. Fehlt im Plattform-Repo (dort nichts geändert, offene Arbeit einer anderen Sitzung)

- `infra/DOKPLOY.md` §0/§6 nennen als Dev-Branch noch `feature/platform-foundation`; inzwischen gibt es
  `dev` und `main`. §13 „Produktion später einrichten“ erwähnt `soulwick-game` nicht (Reihenfolge, Port 80,
  Build-Argument) und keine Cache-Regel für `game.*`.
- `apps/web/content/legal/` enthält nur die README: ohne eRecht24-Schlüssel zeigt die Website den
  Platzhalter. Das reicht nicht für den Launch.
- Produktions-Vorlagen der Variablen liegen nur lokal (`.env.prod`, gitignored); die Liste in
  DOKPLOY.md §4 ist die Quelle. `apps/api/.env.example` enthält lokal schon `http://localhost:18080` in
  `CORS_ORIGINS`.
