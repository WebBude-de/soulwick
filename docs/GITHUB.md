# GitHub einrichten: Spiel und Plattform

> **Stand:** 17.10.2026 · **Für:** das Projektmitglied (Agenten ändern auf GitHub nichts) · **Gilt für:**
> `WebBude-de/soulwick` und `WebBude-de/soulwick-platform` · Entscheidungen: D-148 (Open Source),
> D-177 (Code offen, Inhalte geschützt) · Releases: [RELEASE.md](RELEASE.md)
>
> Jeder Schritt hat einen **Klickpfad** und, wo GitHub das erlaubt, einen **`gh`-Befehl**. GitHub CLI
> einmal installieren und anmelden: `winget install GitHub.cli`, dann `gh auth login`. Die Befehle
> sind einzeilig und laufen in PowerShell und Bash. Am Ende steht eine [Checkliste](#14-checkliste).

## 0. Ausgangslage (17.10.2026)

- Beide Repos sind öffentlich, Default-Branch `main`, Issues an, Wiki aus, Discussions aus, Projects an.
  Beschreibung und Website sind gesetzt (alte Texte), Topics fehlen.
- **`main` ist alt:** Lizenz und Workflows liegen erst auf `dev` bzw. den Feature-Branches. Die neue
  README, `LICENSE-ASSETS.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`,
  Issue-Formulare, PR-Vorlage, `.github/assets/` und diese Datei **sind noch nicht committet (nur im
  Arbeitsordner)**, in beiden Repos. GitHub zeigt sie (und die Lizenz „GPL-3.0“ oben rechts) erst,
  wenn sie auf `main` liegen → zuerst Schritt 1.
- Die Organisation `WebBude-de` ist verifiziert und hat ein Profil-README (Agentur) im Repo
  `WebBude-de/.github`.
- **Links, die heute noch ins Leere gehen** (README und Website verweisen darauf):
  - `https://game.playsoulwick.com` (404): Domain noch nicht an der Dokploy-App `soulwick-game`
    (D-157, [WEB_BUILD.md](WEB_BUILD.md)). Läuft: `game-dev.playsoulwick.com`.
  - `https://playsoulwick.com/leaderboards` (404): `LIVE_FEATURES=false` in production
    ([LAUNCH.md](LAUNCH.md) §1).
  - Bis dahin tragen die Links den Zusatz „(from release)“. **Vor dem Merge auf `main`** entweder
    beides einschalten und die Zusätze entfernen oder die Links herausnehmen, und zwar an allen
    Stellen:
    - `README.md` beider Repos: Linkzeile oben („Play in your browser“, „Leaderboards“); im Spiel
      zusätzlich der Satz unter „Status“ („from the release on, the browser version runs at …“)
    - `SECURITY.md` (Spiel), Tabelle „Supported versions“ („browser version at …“)
    - `.github/ISSUE_TEMPLATE/config.yml` beider Repos: `about` von „Play Soulwick“ („Website with
      the game, the browser version and the leaderboards.“)
    - das Profil-README-Schnipsel in §13 („Im Browser spielen“)
- **`hello@playsoulwick.com` empfängt noch keine Mails** (kein MX-Eintrag), und Private
  Vulnerability Reporting ist in beiden Repos aus. `SECURITY.md`, `CODE_OF_CONDUCT.md` und
  `LICENSE-ASSETS.md` verweisen auf beides → Aufgabe in §1, vor dem Merge auf `main`.

## 1. Neue Dateien auf `main` bringen

0. **Committen** (Agenten nur auf ausdrückliche Ansage): die neuen Dateien aus §0 zusammen mit
   `README.md` und `THIRD_PARTY.md`. Spiel: auf dem Feature-Branch. Plattform: auf einem neuen Feature-Branch von `dev`
   (der Arbeitsordner steht heute direkt auf `dev`). Je ein Pull Request nach `dev`.
1. **[Projektmitglied] E-Mail und Sicherheitsmeldungen, vor dem Merge auf `main`:**
   - Mail für `playsoulwick.com` einrichten, z. B. Cloudflare → `playsoulwick.com` → **Email → Email
     Routing** → aktivieren (Cloudflare legt die MX- und SPF-Einträge an) → Custom address `hello` →
     Weiterleitung an ein Team-Postfach (Zieladresse über die Bestätigungsmail freischalten) →
     Testmail von einer fremden Adresse an `hello@playsoulwick.com` schicken. Email Routing leitet
     nur weiter; geantwortet wird aus dem Team-Postfach.
   - Private Vulnerability Reporting in beiden Repos einschalten (§7.1), sonst führt der Knopf in
     `SECURITY.md` ins Leere.
   - Die Adresse steht in: Spiel `SECURITY.md`, `CODE_OF_CONDUCT.md`, `LICENSE-ASSETS.md` (zweimal);
     Plattform `SECURITY.md`, `CODE_OF_CONDUCT.md`, `LICENSE-ASSETS.md` (zweimal); dazu als Vorlage
     für `SUPPORT_EMAIL` in [LAUNCH.md](LAUNCH.md). Wird es eine andere Adresse, alle diese Stellen
     ändern.
2. Die Links aus §0 klären: einschalten oder herausnehmen.
3. Spiel: die Feature-Branches nach `dev`, dann ein Pull Request `dev` → `main` (Merge-Commit, kein
   Squash, siehe §12). Plattform: Pull Request `dev` → `main`. Danach prüfen: Startseite zeigt Banner
   und Badges, rechts „GPL-3.0 license“, unter „Issues → New issue“ erscheinen „Bug report“ und
   „Idea“.

## 2. Beschreibung, Website, Topics

Klickpfad: Repo-Startseite → Zahnrad neben **About** → Description, Website, Topics.

```bash
gh repo edit WebBude-de/soulwick --description "A modern pixel-art roguelite you jump into with your friends: endless dungeon, bosses, mini-games, co-op. Made with Godot 4." --homepage "https://playsoulwick.com"
gh repo edit WebBude-de/soulwick --add-topic godot,godot4,gdscript,game,roguelite,roguelike,pixel-art,top-down,dungeon-crawler,coop,multiplayer,indie-game,open-source
gh repo edit WebBude-de/soulwick-platform --description "Website, player API, co-op relay and admin panel for Soulwick (playsoulwick.com). Bun, Next.js, Hono, Prisma." --homepage "https://playsoulwick.com"
gh repo edit WebBude-de/soulwick-platform --add-topic nextjs,bun,hono,prisma,turborepo,typescript,postgresql,websocket,tailwindcss,game-backend,leaderboard,open-source
```

## 3. Startseite: About-Kasten

Zahnrad neben **About** → unter „Include in the home page“:

| Häkchen | Spiel | Plattform | Warum |
| --- | --- | --- | --- |
| Releases | an | aus | Spiel-Downloads liegen in den Releases; die Plattform hat keine |
| Packages | aus | aus | keine GitHub Packages |
| Deployments | aus | aus | `release.yml` nutzt Environments; die Liste verwirrt Besucher eher |

Kein `gh`-Befehl, nur per Klick.

## 4. Social Preview (Vorschaubild beim Teilen)

Settings → General → **Social preview** → Edit → Upload an image:

- Spiel: `.github/assets/social-preview.png` (1280 × 640, 146 KB)
- Plattform: `soulwick-platform/.github/assets/social-preview.png` (mit Untertitel „Platform · Website
  · API · Co-op relay“)

Kein `gh`-Befehl (GitHub bietet dafür keine API). Neu erzeugen, z. B. nach neuer Keyart oder Tagline:
`python tools/make_github_images.py` (Banner und Vorschau beider Repos; mit
`--shots <ordner eines tools/screenshots.gd-Laufs>` auch die README-Screenshots).

## 5. Funktionen: Issues, Discussions, Wiki, Projects

| Funktion | Empfehlung | Grund |
| --- | --- | --- |
| Issues | an (beide) | Fehler und Ideen über die Formulare |
| Discussions | **Spiel an**, Plattform aus | Fragen, „Show and tell“ (Clips, Screenshots, Fan-Runs) und Ankündigungen gehören nicht in Issues; passt zur Clip-Strategie (D-173). Plattform-Fragen gehen mit in die Spiel-Discussions. Kostet etwas Moderation. |
| Wiki | aus (beide) | Die Doku lebt versioniert im Repo (`docs/`, D-178); ein Wiki würde veralten |
| Projects | aus, solange ihr keine GitHub Projects nutzt | weniger Reiter für Besucher |

```bash
gh repo edit WebBude-de/soulwick --enable-issues --enable-discussions --enable-wiki=false --enable-projects=false
gh repo edit WebBude-de/soulwick-platform --enable-issues --enable-discussions=false --enable-wiki=false --enable-projects=false
```

Discussions danach einrichten: Reiter **Discussions** → Kategorien „Announcements“, „Q&A“, „Ideas“,
„Show and tell“ behalten, „General“ und „Polls“ nach Geschmack. Danach in
`.github/ISSUE_TEMPLATE/config.yml` beider Repos einen Kontakt-Link „Questions“ auf
`https://github.com/WebBude-de/soulwick/discussions` ergänzen (Auftrag an einen Agenten).

## 6. Labels

Die Issue-Formulare setzen `bug`/`idea` und `game`/`platform`; fehlende Labels lässt GitHub still weg.
`good first issue` und `help wanted` zeigt GitHub Neulingen besonders an. `--force` aktualisiert
vorhandene Labels.

```bash
gh label create bug --color d73a4a --description "Something is broken" --force -R WebBude-de/soulwick
gh label create idea --color a2eeef --description "Suggestion for something new or better" --force -R WebBude-de/soulwick
gh label create "good first issue" --color 7057ff --description "Good for newcomers" --force -R WebBude-de/soulwick
gh label create "help wanted" --color 008672 --description "Extra attention is welcome" --force -R WebBude-de/soulwick
gh label create game --color f3c85c --description "The game (Godot)" --force -R WebBude-de/soulwick
gh label create platform --color 6e56cf --description "Website, API, relay, admin panel" --force -R WebBude-de/soulwick
gh label create art-needed --color e99695 --description "Needs artwork, music or sound from the team" --force -R WebBude-de/soulwick
```

Dieselben sieben Zeilen noch einmal mit `-R WebBude-de/soulwick-platform`. Optional das
Standard-Label `enhancement` löschen (ersetzt durch `idea`): `gh label delete enhancement --yes -R …`.

## 7. Sicherheit

Schnellweg für alles in diesem Abschnitt: Organisation → Settings → **Advanced Security →
Configurations** → „GitHub recommended“ auf beide Repos anwenden (für öffentliche Repos kostenlos).
Danach die Punkte unten nur noch kontrollieren.

### 7.1 Private Vulnerability Reporting

Damit funktioniert der Knopf „Report a vulnerability“, auf den `SECURITY.md` verweist.
Repo → Settings → **Advanced Security** (früher „Code security“) → Private vulnerability reporting →
Enable.

```bash
gh api -X PUT repos/WebBude-de/soulwick/private-vulnerability-reporting
gh api -X PUT repos/WebBude-de/soulwick-platform/private-vulnerability-reporting
```

### 7.2 Secret Scanning und Push Protection

Findet versehentlich eingecheckte Schlüssel und blockt sie schon beim Push (wichtig, seit beide Repos
öffentlich sind, D-148). Settings → Advanced Security → Secret Protection: „Secret scanning“ und „Push
protection“ an.

```bash
gh api -X PATCH repos/WebBude-de/soulwick -f "security_and_analysis[secret_scanning][status]=enabled" -f "security_and_analysis[secret_scanning_push_protection][status]=enabled"
gh api -X PATCH repos/WebBude-de/soulwick-platform -f "security_and_analysis[secret_scanning][status]=enabled" -f "security_and_analysis[secret_scanning_push_protection][status]=enabled"
```

Meldet GitHub einen Fund in der Historie: Schlüssel **sofort austauschen** (Dokploy, Stores,
`docs/STORES.md`), Löschen aus Git allein reicht nicht.

### 7.3 Dependabot

Settings → Advanced Security → Dependabot: „Dependabot alerts“ an, „Dependabot security updates“ an.

```bash
gh api -X PUT repos/WebBude-de/soulwick/vulnerability-alerts
gh api -X PUT repos/WebBude-de/soulwick/automated-security-fixes
gh api -X PUT repos/WebBude-de/soulwick-platform/vulnerability-alerts
gh api -X PUT repos/WebBude-de/soulwick-platform/automated-security-fixes
```

Ehrlich, was das bringt (Stand GitHub-Doku Oktober 2026):

- **Spiel:** keine Paketmanager-Abhängigkeiten (Godot und GUT liegen im Repo). Sinnvoll ist nur, die
  Actions in den Workflows aktuell zu halten (Versions-Updates, Datei unten).
- **Plattform (Bun):** Dependabot kann für `bun.lock` **Versions-Updates** (Ökosystem `bun`), aber
  **keine Security-Updates**. Der Dependency Graph liest `bun.lock` nicht, nur die `package.json`-Dateien;
  Alerts sind deshalb unvollständig (keine transitiven Pakete, nur Versionsbereiche). Ergänzung:
  `bun audit` lokal bzw. später in einer CI der Plattform.

Vorschlag für `.github/dependabot.yml` (anlegen lasst ihr einen Agenten; Workflow-Dateien gehören dem
Integrator):

```yaml
# soulwick/.github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: monthly }
    target-branch: dev
```

```yaml
# soulwick-platform/.github/dependabot.yml
version: 2
updates:
  - package-ecosystem: bun
    directory: /
    schedule: { interval: weekly }
    target-branch: dev
    groups:
      minor-and-patch: { update-types: [minor, patch] }
```

### 7.4 Code Scanning (optional)

Settings → Advanced Security → Code scanning → CodeQL analysis → **Default**. Prüft in der Plattform
TypeScript und in beiden Repos die GitHub-Actions-Workflows; GDScript kennt CodeQL nicht. Kostenlos für
öffentliche Repos, läuft bei Push und Pull Request.

## 8. Branch-Schutz mit Rulesets

Ziel laut [TECHSTACK.md](TECHSTACK.md) §3: kein direkter Push auf `main` und `dev`, jeder Pull Request
mit einem Review einer anderen Person, CI grün, kein Force-Push. Für ein kleines Team mit einer
Ausnahme: **Admins dürfen einen Pull Request auch ohne Review mergen** (Bypass „nur für Pull
Requests“), damit niemand blockiert ist, wenn die zweite Person fehlt. Direkte Pushes bleiben auch
für Admins gesperrt. Ausnahme: `production` der Plattform wird direkt vorgespult und bekommt ein
eigenes Ruleset (unten).

Klickpfad: Settings → **Rules → Rulesets → New ruleset → New branch ruleset**

| Feld | Spiel | Plattform |
| --- | --- | --- |
| Name | `main und dev` | `main und dev`, dazu ein eigenes Ruleset `production` (unten) |
| Enforcement status | Active | Active |
| Bypass list | Repository admin und Organization admin, je „For pull requests only“ | dasselbe |
| Target branches | Include by pattern: `main`, `dev` | `main`, `dev` |
| Restrict deletions | an | an |
| Block force pushes | an | an |
| Require a pull request before merging | an: 1 approval, „Dismiss stale approvals“, „Require conversation resolution“ | an, gleich |
| Require status checks to pass | an: `Validate and unit tests`, `Workflows and shell scripts` | **noch nicht** (die Plattform hat keinen CI-Workflow) |

Die Status-Checks lassen sich erst auswählen, wenn CI einmal auf einem Pull Request gelaufen ist.

Per `gh`: den Block als `ruleset-soulwick.json` speichern und hochladen (Rolle `5` = Repository admin, dazu die Organisations-Admins). Danach im Klickpfad kontrollieren, dass beide in der Bypass-Liste stehen:

```json
{
  "name": "main und dev",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main", "refs/heads/dev"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" },
    { "actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "pull_request" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "Validate and unit tests" },
          { "context": "Workflows and shell scripts" }
        ]
      }
    }
  ]
}
```

```bash
gh api -X POST repos/WebBude-de/soulwick/rulesets --input ruleset-soulwick.json
```

Plattform: dieselbe Datei **ohne** den Block `required_status_checks`; hochladen nach
`repos/WebBude-de/soulwick-platform/rulesets`. Sobald die Plattform eine CI hat (Vorschlag: eigenes
Paket mit `bun run check`, `typecheck`, `test` mit Postgres-Service, `build`), deren Jobs als
Status-Checks ergänzen.

**Plattform: eigenes Ruleset für `production`.** Der Branch wird nur vorgespult, also direkt gepusht
(`git push origin main:production`, `soulwick-platform/infra/DOKPLOY.md` §10). Eine
Pull-Request-Pflicht würde genau das blockieren. Deshalb sperrt dieses Ruleset nur Löschen und
Force-Push; Fast-Forward-Pushes bleiben möglich. Ohne Bypass-Liste, damit auch Admins nicht
force-pushen. Klickpfad wie oben: Name `production`, Target `production`, nur „Restrict deletions“
und „Block force pushes“. Per `gh` als `ruleset-production.json`:

```json
{
  "name": "production",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/production"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [{ "type": "deletion" }, { "type": "non_fast_forward" }]
}
```

```bash
gh api -X POST repos/WebBude-de/soulwick-platform/rulesets --input ruleset-production.json
```

Optional dürfen nur Admins vorspulen: ein **zweites** Ruleset `production nur Admins` mit „Restrict
updates“, in der Bypass-Liste Repository admin und Organization admin mit „Always“. Getrennt, weil
ein Bypass für das ganze Ruleset gilt; im ersten würde er auch Löschen und Force-Push freigeben.

```json
{
  "name": "production nur Admins",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/production"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": 1, "actor_type": "OrganizationAdmin", "bypass_mode": "always" }
  ],
  "rules": [{ "type": "update", "parameters": { "update_allows_fetch_and_merge": false } }]
}
```

Hinweise:

- `release.yml` legt Tags `v*-dev.*` an und löscht alte wieder; deshalb **kein** Tag-Ruleset für `v*`.
- Agenten committen nur auf Feature-Branches; jeder Merge nach `dev` ist ein Push und startet wie
  bisher die Testversion (D-157).

## 9. GitHub Actions

Settings → **Actions → General**:

| Einstellung | Wert | Grund |
| --- | --- | --- |
| Actions permissions | „Allow WebBude-de, and select non-WebBude-de, actions and reusable workflows“ + „Allow actions created by GitHub“ | Die Workflows nutzen nur `actions/*` und eigene Actions |
| Approval for running fork pull request workflows | „Require approval for all external contributors“ | Fremder Code läuft erst nach eurem Klick auf „Approve and run“ |
| Workflow permissions | „Read repository contents and packages permissions“ | Read-only als Standard; `release.yml` fordert `contents: write` selbst an |
| Allow GitHub Actions to create and approve pull requests | aus | |

```bash
gh api -X PUT repos/WebBude-de/soulwick/actions/permissions -F enabled=true -f allowed_actions=selected
gh api -X PUT repos/WebBude-de/soulwick/actions/permissions/selected-actions -F github_owned_allowed=true -F verified_allowed=false
gh api -X PUT repos/WebBude-de/soulwick/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors
gh api -X PUT repos/WebBude-de/soulwick/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
```

Für die Plattform dieselben vier Zeilen mit `soulwick-platform` (gilt dann für künftige Workflows).
Schlägt ein Befehl fehl, weil GitHub den Endpunkt umbenannt hat: Klickpfad nehmen.

- Secrets und Variablen der Releases (Signaturen, Stores, `RELEASE_ENV`): [STORES.md](STORES.md),
  [RELEASE.md](RELEASE.md). Workflows aus Forks bekommen keine Secrets; das ist GitHub-Standard.
- Optional: Settings → Environments → `production` → „Required reviewers“ = ihr selbst. Dann wartet ein
  production-Release auf euren Klick.

## 10. Git LFS (Klänge im Spiel-Repo)

Die `.wav`/`.ogg`/`.mp3`-Dateien liegen in Git LFS (`.gitattributes`).

- Settings → General → Archives → **„Include Git LFS objects in archives“** an. Sonst fehlen im
  „Download ZIP“ die Klänge.
- Speicher und Bandbreite zählen auf das Kontingent der Organisation, auch Clones von Fremden:
  Organisation → Settings → Billing and licensing → Usage → Git LFS gelegentlich ansehen. Die CI
  cacht LFS-Dateien.

## 11. Releases und Tags

Ablauf, Tags `v*` und Secrets: [RELEASE.md](RELEASE.md). Für die Startseite:

- Jeder Push auf `dev` erzeugt eine Vorabversion `v<version>-dev.<lauf>`; die README verlinkt die
  Release-Seite, nicht eine feste Version.
- Das erste echte Release (Tag ohne Zusatz) auf der Release-Seite mit „Set as the latest release“
  markieren; dann zeigt die Startseite es rechts unter „Releases“.

## 12. Merge-Einstellungen

Settings → General → **Pull Requests**: Squash merging an (Commit-Titel = PR-Titel, damit das
Commit-Format `feat(scope): …` aus dem PR-Titel kommt), Merge commits an (für `dev` → `main`), Rebase
merging aus, „Always suggest updating pull request branches“ an, „Automatically delete head branches“
an.

```bash
gh repo edit WebBude-de/soulwick --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false --allow-update-branch --delete-branch-on-merge
gh api -X PATCH repos/WebBude-de/soulwick -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=COMMIT_MESSAGES
gh repo edit WebBude-de/soulwick-platform --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false --allow-update-branch --delete-branch-on-merge
gh api -X PATCH repos/WebBude-de/soulwick-platform -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=COMMIT_MESSAGES
```

## 13. Organisation `WebBude-de`

- **Avatar:** bleibt das WebBude-Logo (die Organisation ist die Agentur). Soulwick zeigt sich über
  angeheftete Repos, Social Preview und das Profil-README.
- **Angeheftete Repos:** Organisationsseite → „Customize pins“ → `soulwick` und `soulwick-platform`.
- **Profil-README:** liegt schon in `WebBude-de/.github` unter `profile/README.md` (Agentur-Text in
  Sie-Form). Vorschlag: diesen Abschnitt vor „Projekt anfragen“ einfügen (das Bild erscheint, sobald
  der Banner auf `main` liegt; „Im Browser spielen“ erst übernehmen, wenn `game.playsoulwick.com`
  läuft, §0):

  ```markdown
  ### Open Source: Soulwick

  <a href="https://playsoulwick.com"><img src="https://raw.githubusercontent.com/WebBude-de/soulwick/main/.github/assets/banner.webp" alt="Soulwick – Grab your friends. Light the dark." width="100%" /></a>

  **Soulwick** ist unser eigenes Spiel: ein Pixel-Roguelite, in das man mit Freunden reinrennt – jeder Run anders, jeder Boss ein Clip. Gebaut mit Godot, dazu Website, Spieler-API und Koop-Relay mit Next.js, Hono, Prisma und Bun. Der Code ist offen (GPL-3.0), Mitmachen ist ausdrücklich erwünscht.

  | Repository | Was |
  | --- | --- |
  | [soulwick](https://github.com/WebBude-de/soulwick) | das Spiel (Godot 4.7.2) |
  | [soulwick-platform](https://github.com/WebBude-de/soulwick-platform) | Website, Spieler-API, Koop-Relay, Admin-Panel |

  [playsoulwick.com](https://playsoulwick.com) · [Im Browser spielen](https://game.playsoulwick.com)
  ```

  Gemeinsame Community-Dateien im Repo `.github` braucht es nicht: beide Repos haben eigene.
- **Verifizierte Domain `playsoulwick.com`:** Organisation → Settings → **Verified and approved
  domains** → Add a domain → `playsoulwick.com`. GitHub zeigt einen TXT-Eintrag (Name und Wert); bei
  Cloudflare als DNS-Eintrag **ohne Proxy** anlegen, dann „Verify“. Danach zeigt die
  Organisationsseite die Domain mit Haken.
- **Zwei-Faktor-Pflicht:** Organisation → Settings → Authentication security → „Require two-factor
  authentication“ (vorher prüfen, dass alle Mitglieder 2FA haben).
- **Basisrechte:** Organisation → Settings → Member privileges → Base permissions „Read“; Schreibrechte
  je Repo vergeben.

## 14. Checkliste

- [ ] Neue Dateien committen: Spiel auf dem Feature-Branch, Plattform auf einem Feature-Branch von
      `dev`, je Pull Request nach `dev` (§1, Schritt 0)
- [ ] **[Projektmitglied]** Mail für `playsoulwick.com` (`hello@` → Team-Postfach, Testmail) und
      Private Vulnerability Reporting in beiden Repos, vor dem Merge auf `main` (§1, §7.1)
- [ ] `game.playsoulwick.com` an `soulwick-game` hängen (D-157) und `LIVE_FEATURES` in production
      klären, dann „(from release)“ entfernen – oder die Links herausnehmen; an allen Stellen aus §0
      (beide READMEs mit Linkzeile, Status-Satz im Spiel, `SECURITY.md`, beide `config.yml`, §13)
- [ ] Neue Dateien per Pull Request auf `main` (§1)
- [ ] Beschreibung, Website, Topics (§2)
- [ ] About-Häkchen: Releases nur im Spiel, Packages und Deployments aus (§3)
- [ ] Social Preview hochladen, beide Repos (§4)
- [ ] Discussions im Spiel an, Wiki und Projects aus (§5)
- [ ] Labels in beiden Repos (§6)
- [ ] „GitHub recommended“-Sicherheitskonfiguration oder einzeln: Private Vulnerability Reporting,
      Secret Scanning mit Push Protection, Dependabot Alerts und Security Updates (§7)
- [ ] `dependabot.yml` für beide Repos von einem Agenten anlegen lassen (§7.3)
- [ ] Rulesets für `main`/`dev` in beiden Repos, dazu `production` in der Plattform (nur Löschen und
      Force-Push gesperrt, Vorspulen bleibt möglich) (§8)
- [ ] Actions: nur GitHub-Actions erlaubt, Fork-Freigabe für alle Externen, Token read-only (§9)
- [ ] LFS-Dateien in Archiven an (§10)
- [ ] Merge-Einstellungen (§12)
- [ ] Organisation: Repos anheften, Profil-README ergänzen, Domain verifizieren, 2FA-Pflicht (§13)
- [ ] Später: CI-Workflow für die Plattform als Paket, dann als Status-Check ins Ruleset (§8)
