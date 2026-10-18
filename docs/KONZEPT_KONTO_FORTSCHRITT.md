# Konzept Konto und Fortschritt – ein Konto, viele Anmeldungen, Spielstand in der Cloud, Level sichtbar

> **Stand:** 18.10.2026 · **Status:** **VERBINDLICH** (D-188, Antworten des Projektmitglieds vom 18.10.2026), alle Zahlen **TESTWERT**. Ersetzt D-121 im Punkt „ohne E-Mail und Passwort“; D-122 (Zusammenführen), D-152 (ein Charakter, Welten), P-028 (Gast je Gerät), P-034 (Profil), P-026 (Löschen) und D-176 (kein Pay-to-win) gelten weiter. Offen ist nur noch, was Abschnitt 9 nennt.
> **Wunsch des Projektmitglieds (18.10.2026):** Der Spieler sieht im Spiel, wie weit er ist, ohne zu suchen, mit Leveln. Es gibt nur **ein Konto** je Mensch. Wer auf dem iPhone anfängt und später im Browser oder auf Steam weiterspielt, **verknüpft** die Plattformen, und die Spielstände sind **synchron und auf dem Server**.
> **Pakete:** KF0–KF11 in [ROADMAP.md](ROADMAP.md), Strang K; Crossplay-Bezug CP0, CP1, CP5 in [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md). Plattform-Teile gehören in `soulwick-platform/docs/ROADMAP.md` (trägt der Orchestrator ein), Verträge in `packages/contracts` immer zuerst.

## 1. Ziel

Ein Mensch hat ein Soulwick-Konto, egal auf wie vielen Geräten und Plattformen er spielt. Jede Plattform meldet sich auf ihre Art an, alle Anmeldungen zeigen auf dasselbe Konto. Daran hängen Profil, Gilden, Welten und ein **Konto-Level**, das bei jedem Run sichtbar steigt; das Spiel bleibt ohne Server spielbar (D-083, D-093), und wer nichts eintippen will, spielt als Gast sofort los.

## 2. Ist-Stand (18.10.2026)

| Bereich | Heute | Wo |
| --- | --- | --- |
| Anmeldung im Spiel | Gast je Installation (`POST /auth/device` mit zufälliger Geräte-ID), mit Dev-Key `POST /auth/dev`; Session-Token 30 Tage in `online.cfg`, Relay-JWT nur im Speicher | `online/session.gd:221-262`, `online/api_client.gd:36-61`, `online/online_config.gd:15-19, 205` |
| Store-Anmeldungen | Server prüft Steam-Ticket (`AuthenticateUserTicket`, Publisher-Schlüssel) und Play-Games-Code; Game Center antwortet `501`. **Im Spiel fehlt alles** (kein `PlatformServices`, kein GodotSteam) | Plattform `apps/api/src/routes/auth.ts:135, 155, 174`, `services/steam.ts`; Spiel MP6, CP1 |
| E-Mail/Passwort | nur für Admins (Better Auth, `disableSignUp`); Spieler bisher bewusst ohne (D-121, jetzt ersetzt) | Plattform `apps/api/src/auth/auth.ts:72-76` |
| Identitäten | `player_identities` (`steam`, `device`, `google_play`, `game_center`), mehrere je Konto | Plattform `packages/db/prisma/schema.prisma:41-46, 112-120` |
| Verknüpfen, Trennen, Löschen | API fertig: Verknüpfungscode, Zusammenführen nach D-122, Trennen (nicht die letzte, P-021), Löschcode und `DELETE /me` (P-026). **Im Spiel ruft nichts davon** auf | Plattform `apps/api/src/routes/me.ts:66, 91, 99, 109, 120, 161` |
| Profil | Name und Aussehen am Konto (`PATCH /me`), lokal `profile.cfg`, Abgleich beim Login | `characters/player_profile.gd:1-20`, `online/session.gd:340-401` |
| Spielstand | nur lokal: bis zu 3 Welten (`saves/slot_<n>.cfg`, Format v4), Einstellungen in `settings.cfg`; im Browser in der IndexedDB je Domain | `autoload/save_manager.gd:353-395`, `meta/save_slots.gd:9`, `docs/WEB_BUILD.md:47` |
| Auf dem Server | Konto, Identitäten, Profil, Gilden mit Gildenkasse, Run-Berichte (nur Koop- und Gilden-Runs, gemeldet vom Host), Bug-Meldungen; **kein Spielstand, kein Level** | Plattform `schema.prisma:81-104, 401-434`; Spiel `online/net_run.gd:283` |
| Fortschritt sichtbar | Hauptmenü: Welt, Gold, Kristalle, Rekord; Weltenliste: Rekord, Spielzeit, **Schmiede x/20** (seit 18.10.2026); Chronik im Dorf: Statistiken der Welt; Run-Ende nennt die nächste Schmiede-Stufe. Nichts gilt fürs Konto | `ui/main_menu/main_menu.gd:519-529`, `ui/main_menu/slot_panel.gd:359-369`, `ui/menus/village_ui.gd:87-98, 295-309`, `meta/stats_tracker.gd:10-22` |

## 3. Ein Konto, viele Anmeldungen

### 3.1 Datenmodell

- **Konto** = `players` (wie heute): Anzeigename, Aussehen, Gilden, Runs, neu **XP** und **Cloud-Welten**.
- **Identität** = eine Art, sich anzumelden: Anbieter + Nutzer-ID des Anbieters, eindeutig je Anbieter, beliebig viele je Konto, jede höchstens an einem Konto. Der Vertrag zeigt alle Arten in einer Liste (`GET /me/identities`).
- **Better Auth für Spieler** (Erweiterung von P-027): Benutzername/Passwort, Magic Link und Social-Logins laufen über Better Auth an der `auth_users`-Zeile des Spielers; Store-Anmeldungen und Gast bleiben eigene Prüfungen im Plugin `soulwickPlayerAuth`. Wie `auth_accounts` und `player_identities` zusammenspielen, legt die Plattform in einem P-Eintrag fest (Vorgabe: eine Identitätsliste nach außen, keine doppelte Wahrheit).

| Identität | Wo | Nachweis am Server |
| --- | --- | --- |
| `device` (Gast) | jede Installation, auch Browser; stiller Einstieg | die geheime Geräte-ID (P-028) |
| `steam` | Steam (Ticket) **und Browser** (Steam OpenID 2.0, Rückfrage `check_authentication` bei `steamcommunity.com`) – dieselbe SteamID64, also dasselbe Konto | Publisher-Schlüssel bzw. OpenID-Prüfung |
| `google_play` | Android, still | Server-Auth-Code von Play Games v2 |
| `game_center` | iOS, still | Signatur, Zertifikat nur von Apple-Domains, Zeitfenster |
| `password` | überall | Benutzername (eindeutig, privat, nicht der Anzeigename) + Passwort (argon2id) |
| `email` (Magic Link) | überall | Einmal-Link an die E-Mail-Adresse, 15 min gültig (TESTWERT) |
| `google`, `apple`, `discord` | überall (Apple auf iOS nativ) | OAuth/OpenID beim Anbieter |

- **Benutzername ≠ Anzeigename.** Der Benutzername ist ein privater Login, der Anzeigename bleibt `PlayerName` (nicht eindeutig, 3 Wechsel je 24 h, P-034).
- **E-Mail** gibt es nur, wenn der Spieler Magic Link wählt oder ein Social-Login sie liefert; sie wird nie angezeigt und nie für Werbung genutzt. Passwort vergessen = Magic Link (wenn eine E-Mail hinterlegt ist) oder Anmeldung über eine andere Identität.

### 3.2 Anmeldung je Plattform

| Plattform | Beim Start (still) | „Anmeldung hinzufügen“ bzw. „Anmelden“ |
| --- | --- | --- |
| Browser | Gast (`device`) | Benutzername/Passwort, Magic Link, Google, Apple, Discord, Steam |
| Steam | Steam-Ticket | Benutzername/Passwort, Magic Link, Google, Apple, Discord |
| Android | Play Games v2, sonst Gast | wie Steam, dazu Steam |
| iOS | Game Center, sonst Gast | wie Android; **Sign in with Apple** ist Pflicht und steht oben (Apple 4.8) |
| Editor/Tests | Dev-Login oder Gast | – |

- **Web-Anmeldung aus dem Spiel:** OAuth und Magic Link laufen auf der Website. Das Spiel startet eine Anmelde-Anfrage (`POST /auth/web-login`, Vorschlag), öffnet `playsoulwick.com/login/<code>` im Browser bzw. Popup, der Spieler meldet sich dort an, das Spiel holt die Sitzung ab (Abfrage alle 2 s, Anfrage 10 min gültig, TESTWERT). So braucht kein Build eigene OAuth-Weiterleitungen. Ausnahme: Sign in with Apple auf iOS nativ (`ASAuthorization`).
- Gäste sehen nach dem ersten Run mit mindestens 10 Minuten Spielzeit (TESTWERT) einmal „Konto sichern“ und danach dauerhaft einen Hinweis im Konto-Panel; im Browser und bei reinen Gästen hängt das Konto sonst an der Installation (P-028).

### 3.3 Verknüpfen und hochstufen

1. **Anmeldung hinzufügen** (Hauptweg): angemeldet, auch als Gast, „Mit Discord verbinden“, „Benutzername anlegen“ usw. Der Server bekommt den **Nachweis** der neuen Identität, nie eine nackte ID. So wird ein Gastkonto hochgestuft, ohne etwas zu verlieren.
2. **Anmelden auf einem Gerät mit eigenem Gastkonto:** Die neue Identität gehört schon einem Konto → Zusammenführen (3.4).
3. **Verknüpfungscode** (gebaut, D-121) bleibt für Geräte ohne gemeinsame Anmeldung.
4. **Kein automatisches Verknüpfen über die E-Mail:** Liefert ein Social-Login dieselbe E-Mail wie ein anderes Konto, wird nichts still verbunden (Schutz vor Übernahme); der Spieler verknüpft selbst.

### 3.4 Zusammenführen (D-122, ergänzt)

D-122 gilt weiter: Das **ältere** Konto bleibt, Bestätigung im Spiel, gesperrte Konten nie. Ergänzungen:

- **„Leeres Konto“** = keine Gilde, keine Runs, 0 XP, keine Cloud-Welt über 5 Minuten Spielzeit (TESTWERT); es geht ohne Rückfrage auf.
- **XP** beider Konten zählen zusammen (je Run-ID einmal, 5.6).
- **Cloud-Welten:** gleiche Welt-ID wird nach 4.3 gemischt; verschiedene kommen in freie Plätze (höchstens 3, TESTWERT); reicht der Platz nicht, bleiben die zuletzt gespielten, die übrigen liegen 30 Tage im Archiv und lassen sich im Konto-Panel zurückholen.
- **Profil:** Name und Aussehen des bleibenden Kontos (D-122); Kosmetik-Besitz (WK2, CP6) wird vereinigt.

### 3.5 Trennen und Löschen

- Jede Identität außer der letzten lässt sich trennen (P-021). Wer die Identität **dieses Geräts** trennt, wird hier abgemeldet und bekommt eine neue Geräte-ID.
- Konto löschen (P-026) entfernt auch Cloud-Welten, Sicherungen, XP, E-Mail und Zugangsdaten und widerruft die Apple-Tokens (Pflicht bei Sign in with Apple); lokale Welten bleiben auf dem Gerät, der Dialog sagt das.

### 3.6 Sicherheit

- **Kein Vertrauen in IDs vom Client:** Jede Identität wird am Server mit dem Nachweis des Anbieters geprüft (Steam-Ticket bzw. OpenID-Rückfrage, Play-Games-Code, Game-Center-Signatur, OAuth-Code mit PKCE und `state`, Magic-Link-Token, Passwort). Die Geräte-ID wird nie angezeigt.
- Passwörter: argon2id, Mindestlänge 10 (TESTWERT), Rate-Limit je IP und je Benutzername, gleiche Antwort für „unbekannt“ und „falsch“. Magic Links: einmal gültig, nur als Hash gespeichert, Rate-Limit je Adresse und IP, kein Hinweis, ob die Adresse ein Konto hat.
- Anmeldung hinzufügen und Zusammenführen nur mit gültiger Sitzung **und** Nachweis; danach werden die Sitzungen des gelöschten Kontos widerrufen. Die Web-Anmeldung bindet die Sitzung nur an die Anfrage, die das Spiel gestartet hat (Code einmalig, kurz gültig).
- Cloud-Welten sind **unzuverlässige Daten**: Größe, Format und Zusammenfassung werden geprüft, der Inhalt speist nie Ranglisten, Gildenkasse oder Käufe (Käufe prüft der Server getrennt, CP6, D-177). XP sind gedeckelt (5.6) und nur Optik.

## 4. Cloud-Save (zum Release, D-188)

### 4.1 Was wird synchronisiert

| Was | Synchron? | Wie |
| --- | --- | --- |
| Profil (Name, Aussehen, später Kosmetik) | ja (gebaut) | `PATCH /me` (P-034) |
| **Welten** (je Welt die ganze Datei, ab v5 mit Welt-ID, später Dorf-Deko) | **ja** | eine Cloud-Welt je Welt (4.2), Konflikte nach 4.3 |
| **XP / Konto-Level** | **ja** | als Zuwächse je Run-ID (5.6) |
| Gilden, Gildenkasse, Run-Berichte | schon auf dem Server | – |
| Einstellungen (Lautstärke, Grafik, Touch, Tasten, Sprache) | **nein**, je Gerät | Handy und PC brauchen andere Werte |
| Laufender Run, Run-Protokolle, Feedback, `online.cfg` | nein | bleiben auf dem Gerät (D-040) |

### 4.2 Ablauf

- **Offline zuerst:** Gespielt wird immer aus der lokalen Datei; der Server ist der gemeinsame Stand zwischen den Geräten.
- Spielstand **v5**: `[world] id` (UUID), `[cloud] base_version`, `dirty`, `player_id` (zuletzt abgeglichenes Konto). Migration v4 → v5 vergibt die Welt-ID.
- Server je Cloud-Welt: `version` (steigt bei jedem Hochladen), Daten (≤ 64 KB, TESTWERT), Spielstand- und Spielversion, Plattform, Zeit, Zusammenfassung (Name, Rekord, Schmiede, Spielzeit, zuletzt gespielt).
- **Abgleich** beim Login, beim Betreten des Dorfs (holen), nach jedem Run-Ende, beim Verlassen des Dorfs und beim Schließen bzw. Wechsel in den Hintergrund (hochladen, best effort); im Dorf höchstens alle 5 Minuten, wenn `dirty` (TESTWERT). Nie während eines Runs. Ohne Server spielt man weiter, `dirty` bleibt.
- Neuinstallation oder geleerter Browser holt die Welten nach der Anmeldung zurück. Steam Cloud und Play-Games-Speicherstände bleiben aus (eine Wahrheit).

### 4.3 Konflikte: mischen statt fragen (wie große Spiele)

**Kein Dialog.** Hat sich die Welt lokal und auf dem Server seit `base_version` geändert, mischt das Spiel beide Stände nach festen Regeln und lädt das Ergebnis hoch (`PUT` mit der neuen `baseVersion`; wechselt der Server-Stand dazwischen, wird erneut gemischt). „Zuletzt gespielt“ heißt das größere `[profile] last_played`; der Server setzt Zeitstempel aus der Zukunft (mehr als 5 min, TESTWERT) beim Hochladen auf seine Uhrzeit. Der Stand, dessen „zuletzt gespielt“-Felder verworfen wurden, bleibt **30 Tage als Sicherung** auf dem Server (TESTWERT) und lässt sich im Konto-Panel wiederherstellen (wird dann als neuer Stand hochgeladen, die Mischregel greift nicht rückwärts).

**Feldklassen des Spielstands (v4, v5):**

| Abschnitt / Feld | Bedeutung | Klasse | Mischregel |
| --- | --- | --- | --- |
| `[meta] version` | Format | – | höhere Version; ältere Seite wird vorher migriert |
| `[meta_upgrades] <id>` | Schmiede-Stufen | monoton | Maximum je Stufe |
| `[progress] unlocked` | Freischaltungen (Gegner-Hinweise, Dorf-Ereignisse) | monoton | Vereinigung |
| `[seen] ids`, `[seen] all` | gesehene Erklärungen und Ankündigungen | monoton | Vereinigung bzw. ODER |
| `[stats] deepest_room`, `best_run_gold` | Rekorde | monoton | Maximum |
| `[stats] runs`, `deaths`, `exits`, `rooms_cleared`, `kills`, `bosses`, `champions`, `gold_earned`, `gold_banked`, `crystals_earned`, `play_time` | Chronik-Zähler | monoton | Maximum je Feld (Vorgabe 18.10.2026) |
| `[stats] rescued_villagers`, `rescued_chickens` | gerettete Dorfbewohner und Hühner | monoton | Maximum |
| `[profile] created` | Anlage der Welt | monoton | Minimum |
| `[profile] last_played` | zuletzt gespielt | – | Maximum |
| `[progress] permanent_gold`, `permanent_crystals` | Währungen | zuletzt gespielt | vom zuletzt gespielten Stand |
| `[progress] second_weapon` | gewählte zweite Startwaffe | zuletzt gespielt | dito (gilt nur, wenn Arsenal ≥ 1 nach dem Mischen) |
| `[boosts] pending` | gekaufter Proviant | zuletzt gespielt | dito |
| `[world] name` | Weltname | zuletzt gespielt | dito |
| `[legacy_profile] *` | Altdaten für den Erststart | zuletzt gespielt | dito |
| `[world] id` (v5) | Welt-ID | gleich | muss gleich sein, sonst zwei Welten |
| `[cloud] *` (v5) | Abgleich-Daten | lokal | nie hochgeladen, nach dem Mischen neu gesetzt |
| Dorf-Deko (WK5, v5+) | aktueller Dorfzustand | zuletzt gespielt | ganzer Abschnitt vom zuletzt gespielten Stand |
| Freigespielte Kosmetik (WK2) | Besitz | monoton | liegt am Konto, nicht in der Welt; Vereinigung |

**Neue Felder** bekommen ihre Klasse im selben Paket, das sie einführt (Pflicht im Bericht; Standard: „zuletzt gespielt“). Die Regeln stehen an einer Stelle im Code (`meta/save_merge.gd`, Vorschlag) mit einem Test je Feld.

**Bekannte Grenzen (bewusst hingenommen):** Zähler nehmen das Maximum, bei echtem Parallelspiel auf zwei Geräten zählt also nur das fleißigere; Schmiede-Stufen kommen vom einen, Gold vom anderen Gerät, gekaufte Stufen können so einmal „zurückerstattet“ wirken. Beides betrifft nur den Einzelspieler (D-081) und ist selten; genauer ginge es später mit Basis-Zuwachs-Rechnung, wenn die Basis lokal mitgespeichert wird.

### 4.4 Erster Abgleich auf einem Gerät

Kein Dialog: Welten werden über die Welt-ID zugeordnet. Gleiche ID → mischen (4.3). Neue lokale Welten werden hochgeladen, neue Cloud-Welten heruntergeladen, solange Plätze frei sind (3, TESTWERT); sonst bleiben die zuletzt gespielten, der Rest geht 30 Tage ins Archiv (Konto-Panel). Ein Hinweis nennt, was passiert ist („2 Welten gesichert, 1 Welt aus dem Konto geladen“).

## 5. Fortschritt sichtbar

### 5.1 Drei Ebenen, keine Doppelung

| Ebene | Was | Gilt für | Macht stärker? |
| --- | --- | --- | --- |
| **Konto-Level** (neu) | XP aus allem, was man spielt, Level-Zahl am Namen, Belohnungen nur Optik | das Konto, alle Welten, Solo und Koop, alle Geräte | **nein** (D-176; Koop bleibt fair, D-081) |
| **Welt** (gebaut) | Schmiede-Stufen (Gold), Proviant (Kristalle), Freischaltungen, Rekord, Chronik | eine Welt | ja, nur im Solo (D-081) |
| **Run** (gebaut) | Waffen, Upgrades, Run-Gold | ein Run | ja, nur in diesem Run |

Das Level ersetzt nichts: Die Schmiede bleibt der Weg, stärker zu werden, die Chronik die Statistik der Welt. Das Level beantwortet „Wie viel habe ich insgesamt geschafft?“ und ist eine Quelle für freispielbare Kosmetik (KONZEPT_BEGLEITER_KOSMETIK §5).

### 5.2 XP-Quellen (alle TESTWERT)

| Quelle | XP |
| --- | ---: |
| Raum geschafft (auch Minispiel- und Arenaräume) | 5 |
| Champion besiegt | 10 |
| Boss besiegt | 50 |
| Neuer Konto-Rekord (tiefster Raum über alle Welten) | 5 je Raum über dem alten Rekord |
| Run über das Portal beendet | 20 |
| Erster Run des Tages | 25 |
| Koop-Bonus (2–4 Spieler) | +20 % auf den Run |

Gezählt wird beim Run-Ende aus der Run-Zusammenfassung (`RunManager.get_last_summary()`, `RunRecap`); jeder Spieler bekommt seine XP aus seinen eigenen Zahlen, auch im Koop. Ein früher erster Run (6 Räume) bringt etwa 30–60 XP.

### 5.3 Level-Kurve (TESTWERT)

XP für Level L insgesamt: **50 · L · (L − 1)**. Level 2 bei 100 XP, 3 bei 300, 5 bei 1 000, 10 bei 4 500, 20 bei 19 000, 50 bei 122 500. Kein Höchstlevel; Belohnungen bis Level 50. Grob: Level 5 nach 15–20 Runs, Level 10 nach 50–70 Runs. Die Kurve steht als Funktion im Vertrag und gleich im Spiel.

### 5.4 Wo man es sieht

| Wo | Was |
| --- | --- |
| Hauptmenü | neben dem Namen Level-Abzeichen und XP-Balken („Level 7 · 340 / 700 XP“); unten wie heute Welt, Währungen, Rekord |
| Run-Ende | „+86 XP“ mit Aufschlüsselung (Räume, Bosse, Rekord, Koop), der Balken füllt sich, beim Aufstieg ein Banner mit der Belohnung |
| Profil (Figur, Spiegel) | Level, XP bis zum nächsten, nächste Belohnung als Vorschau, freigespielte Teile |
| Fortschritt-Übersicht (neu, Hauptmenü und Chronik) | Konto (Level, Konto-Rekord, Bosse gesamt) · diese Welt (Schmiede x/20, Rekord, Bosse, erreichte Biome, Freischaltungen) · **Nächste Ziele** (nächste leistbare Schmiede-Stufe, nächster Boss bei Raum 15·n, nächste Level-Belohnung) |
| Weltenliste | Rekord, Schmiede x/20 (gebaut), Spielzeit |
| Lobby, Gilde, **Rangliste** | Level-Zahl am Platz, am Mitglied und am Eintrag (D-188) |

### 5.5 Belohnungen je Level (Vorschlag, nur Optik)

- Jedes Level: die Zahl am Namensschild.
- Alle 5 Level ein Kosmetik-Teil aus WK2 (Wick-Hut, Flammenfarbe, Lichtfarbe, Rücken-Teil, Rahmen fürs Namensschild), dazu Titel bei 10, 25 und 50 (Namen OFFEN, Glossar).
- Was man über Level freispielt, kann man nicht kaufen, und umgekehrt. Nie Gold, Kristalle, Stärke oder Abkürzungen. Die Teile entstehen in WK0/WK2.

### 5.6 Speichern und Abgleich der XP

- XP sind **Zuwächse**: Jeder Run erzeugt einen Eintrag (Run-ID, XP, Zeit), lokal in `user://progress.cfg` (je Installation, neben `profile.cfg`; Skript-Läufe schreiben nie hinein, AGENTS.md Regel 4).
- Online gehen offene Einträge mit `POST /me/xp` an den Server; die Run-ID zählt **genau einmal**, zwei Geräte geraten nie in Konflikt.
- Deckel je Eintrag 2 000 XP und je Tag 20 000 XP (TESTWERT); `PlayerSelf` bekommt `xp` und `level`, Gildenmitglieder, Lobby-Profile und Ranglisten-Einträge `level`.
- Offline und ohne Konto steigt das Level trotzdem; beim ersten Login werden die lokalen Einträge dem Konto gutgeschrieben.

## 6. Pflichten der Plattformen

- **Apple 4.8 (Login-Dienste):** Weil Google, Discord und Steam als Login angeboten werden, ist **Sign in with Apple auf iOS Pflicht** (D-188, beantwortet CP0 Frage 8). Apple-Relay-Adressen („E-Mail verbergen“) bekommen Magic Links nur, wenn die Absenderdomain bei Apple registriert ist.
- **Apple 5.1.1(v):** Konto löschen in der App (API gebaut, Konto-Panel KF6); bei Sign in with Apple die Tokens beim Löschen über Apples REST-API widerrufen. Spielen ohne Anmeldung bleibt möglich.
- **Google Play:** Löschen in der App und per Web-Adresse (gebaut, P-026); „Datensicherheit“ um E-Mail (optional), Benutzername, Cloud-Welten, XP ergänzen.
- **Steam:** Steam OpenID im Browser nach den Steam-Markenregeln („Sign in through Steam“-Knopf unverändert); Steam Cloud aus.
- **Google, Discord:** OAuth-Apps je Umgebung, Markenregeln der Knöpfe; Discord-Nutzer sind ab 13 (passt zu D-173).
- **Datenschutz (DSGVO):** E-Mail ist jetzt möglich: nur für die Anmeldung, nie für Werbung, löschbar mit dem Konto; Datenschutzerklärung (eRecht24) um E-Mail, Social-Logins (Google, Apple, Discord, Steam), Mailversand-Anbieter, Cloud-Welten und XP ergänzen; Auftragsverarbeitung mit dem Mailversand-Anbieter. Auskunft und Datenübertragbarkeit (Art. 15, 20) als „Meine Daten herunterladen“ (Vorschlag, später). Rechtsgrundlage Vertragserfüllung, Zielgruppe ab 13 (D-173), mit Fachanwalt bzw. eRecht24 prüfen.

## 7. Koop-Check und Leitplanken

- Konto, Token, Identitäten und Abgleich am lokalen Client (`online/session.gd`, neu `online/cloud_save.gd`), kein neuer Autoload (D-044).
- Konto-Level ist reine Optik; im Koop starten alle gleich (D-081). Das Level kommt zu Mitspielern über das Profil, nie über Spielpakete.
- XP zählt jeder Client für seinen eigenen Spieler; der Host rechnet keine XP für andere.
- Cloud-Save nur für Einzelspieler-Welten; Gruppen-Fortschritt bleibt auf dem Server getrennt (D-081).
- Plattform-SDKs (GodotSteam, Play Games, Game Center, Sign in with Apple) nur über `PlatformServices` mit Null-Implementierung für Editor, Headless und Browser.
- Tests fassen den echten Spielstand und `progress.cfg` nie an (AGENTS.md Regel 4).

## 8. Pakete (Überblick)

Ausführlich mit Dateien, Prüfung und Koop-Check in [ROADMAP.md](ROADMAP.md), Strang K. **Alle gehören ins Release-Tor** (D-188: zum Release steht alles auf allen Plattformen).

| ID | Ergebnis | Repo, Agent |
| --- | --- | --- |
| KF0 | Entscheidungen (erledigt 18.10.2026, D-188) | – |
| KF1 | Fortschritt-Übersicht | Spiel, `village-dev` |
| KF2 | Konto-Level lokal, „+XP“ am Run-Ende | Spiel, `village-dev` |
| KF3 | XP und Level am Konto, `level` in Profil, Gilde, Rangliste | Plattform, `api-dev` |
| KF4 | XP-Abgleich, Level in Lobby, Gilde, Rangliste | Spiel, `player-dev` |
| KF5 | Better Auth für Spieler: Benutzername/Passwort, Magic Link, Google, Apple, Discord, Steam OpenID, Anmeldung hinzufügen, Web-Anmeldung, Game-Center-Prüfung | Plattform, `api-dev` |
| KF6 | Konto-Panel im Spiel | Spiel, `player-dev` |
| KF7 | `PlatformServices`: stille Store-Anmeldung, Sign in with Apple nativ | Spiel, `player-dev` |
| KF8 | Cloud-Welten: Vertrag, Tabelle, Routen, Sicherungen, Archiv | Plattform, `api-dev` |
| KF9 | Spielstand v5, Mischregeln, `online/cloud_save.gd` | Spiel, `village-dev` |
| KF10 | Abnahme auf allen Plattformen | beide, Orchestrator |
| KF11 | Anmeldeseiten der Website (Login, Magic Link, Social, Web-Anmeldung aus dem Spiel) | Plattform, `web-dev` |

**Reihenfolge:** Spiel KF1 → KF2 sofort (ohne Server). Plattform **ein `api-dev` nach dem anderen**, Verträge zuerst: KF3 → KF8 → KF5, danach KF11 (`web-dev`). Spiel: KF4 nach KF3, KF9 nach KF8, KF6 nach KF5 und KF11, KF7 mit MP6, MP10 und CP7 → KF10. Konten bei Google, Apple, Discord, Steam und beim Mailversand legt das Projektmitglied früh an (Vorlauf).

## 9. Noch offen

| Frage | Vorschlag |
| --- | --- |
| Mailversand-Anbieter für Magic Links | ein EU-Anbieter mit Auftragsverarbeitungsvertrag (z. B. Brevo oder Mailjet; Postmark als Alternative); Absender `login@playsoulwick.com`, SPF/DKIM/DMARC; nur Anmelde-Mails |
| Namen der Level-Titel | mit WK0 festlegen (Glossar) |
| Welche Kosmetik je Level | mit WK0/WK2 |

Delegiert und darum TESTWERT: XP-Werte, Koop-Bonus +20 %, Level-Kurve, Deckel, Grenzen der Cloud-Welten, Sicherungs- und Archivdauer, Zeitpunkt des Hinweises „Konto sichern“, Regel „leeres Konto“, Gültigkeit von Magic Link und Web-Anmeldung, Passwort-Mindestlänge.

**Weiterlesen:** [ROADMAP.md](ROADMAP.md) (Strang K) · [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) (CP0, CP1, CP5) · [KONZEPT_BEGLEITER_KOSMETIK.md](KONZEPT_BEGLEITER_KOSMETIK.md) (§5 Freispielen) · [MULTIPLAYER.md](MULTIPLAYER.md) · [DECISIONS.md](DECISIONS.md) (D-121, D-122, D-152, D-188) · `soulwick-platform/docs/KONZEPT_ONLINE.md` §3
