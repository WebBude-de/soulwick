# Konzept Konto und Fortschritt – ein Konto, viele Anmeldungen, Spielstand in der Cloud, Level sichtbar

> **Stand:** 18.10.2026 · **Status:** Konzept, **VORGESCHLAGEN** (D-188). Verbindlich sind nur die genannten älteren Entscheidungen: ein Soulwick-Konto mit verknüpften Identitäten (D-121), Zusammenführen (D-122), ein Charakter je Konto, Spielstände sind Welten (D-152), Gast je Gerät (P-028), Konto-Profil über `PATCH /me` (P-034), Kontolöschung (P-026), kein Pay-to-win (D-176). Offene Fragen: Abschnitt 9.
> **Wunsch des Projektmitglieds (18.10.2026):** Der Spieler sieht im Spiel, wie weit er ist, ohne zu suchen, gern mit Leveln. Es gibt nur **ein Konto** je Mensch. Wer auf dem iPhone anfängt und später im Browser oder auf Steam weiterspielt, **verknüpft** die Plattformen, und die Spielstände sind **synchron und auf dem Server**. Anmeldung je Plattform: Browser mit Benutzername/Passwort, Steam über die Steam-ID, Handy über Game Center, Play Games oder das Gerät.
> **Pakete:** KF0–KF10 in [ROADMAP.md](ROADMAP.md), Strang K; Crossplay-Bezug CP1 und CP5 in [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md). Plattform-Teile gehören in `soulwick-platform/docs/ROADMAP.md` (trägt der Orchestrator nach Freigabe ein).

## 1. Ziel

Ein Mensch hat ein Soulwick-Konto, egal auf wie vielen Geräten er spielt. Jede Plattform meldet sich auf ihre Art an, und alle Anmeldungen zeigen auf dasselbe Konto. Daran hängen Profil, Gilden, Welten und ein **Konto-Level**, das bei jedem Run sichtbar steigt; das Spiel bleibt ohne Server spielbar (D-083, D-093).

## 2. Ist-Stand (18.10.2026)

| Bereich | Heute | Wo |
| --- | --- | --- |
| Anmeldung im Spiel | Gast je Installation (`POST /auth/device` mit zufälliger Geräte-ID), mit Dev-Key `POST /auth/dev`; Session-Token 30 Tage in `online.cfg`, Relay-JWT nur im Speicher | `online/session.gd:221-262`, `online/api_client.gd:36-61`, `online/online_config.gd:15-19, 205` |
| Store-Anmeldungen | Server prüft Steam-Ticket (`AuthenticateUserTicket`, Publisher-Schlüssel) und Play-Games-Code; Game Center antwortet `501`. **Im Spiel fehlt alles** (kein `PlatformServices`, kein GodotSteam) | Plattform `apps/api/src/routes/auth.ts:135, 155, 174`, `services/steam.ts`; Spiel MP6, CP1 |
| E-Mail/Passwort | nur für Admins (Better Auth, `disableSignUp`); Spieler bewusst ohne (D-121) | Plattform `apps/api/src/auth/auth.ts:72-76` |
| Identitäten | `player_identities` (`steam`, `device`, `google_play`, `game_center`), mehrere je Konto | Plattform `packages/db/prisma/schema.prisma:41-46, 112-120` |
| Verknüpfen, Trennen, Löschen | API fertig: Verknüpfungscode, Zusammenführen nach D-122, Trennen (nicht die letzte, P-021), Löschcode und `DELETE /me` (P-026). **Im Spiel ruft nichts davon** auf (Konto-Panel fehlt, CP1) | Plattform `apps/api/src/routes/me.ts:66, 91, 99, 109, 120, 161` |
| Profil | Name und Aussehen am Konto (`PATCH /me`), lokal `profile.cfg`, Abgleich beim Login | `characters/player_profile.gd:1-20`, `online/session.gd:340-401` |
| Spielstand | nur lokal: bis zu 3 Welten (`saves/slot_<n>.cfg`, Format v4: Gold, Kristalle, Schmiede, Proviant, Statistik, Gesehenes), Einstellungen in `settings.cfg`; im Browser in der IndexedDB je Domain | `autoload/save_manager.gd:1-24, 42-47`, `meta/save_slots.gd:9`, `docs/WEB_BUILD.md:47` |
| Auf dem Server | Konto, Identitäten, Profil, Gilden mit Gildenkasse, Run-Berichte (nur Koop- und Gilden-Runs, gemeldet vom Host), Bug-Meldungen; **kein Spielstand, kein Level** | Plattform `schema.prisma:81-104, 401-434`; Spiel `online/net_run.gd:283` |
| Fortschritt sichtbar | Hauptmenü: Welt, Gold, Kristalle, Rekord; Weltenliste: Rekord, Spielzeit; Chronik im Dorf: 12 Statistiken der Welt; Run-Ende nennt die nächste Schmiede-Stufe. Statistiken gelten je Welt, nichts gilt fürs Konto | `ui/main_menu/main_menu.gd:519-529`, `ui/main_menu/slot_panel.gd:359`, `ui/menus/village_ui.gd:87-98, 295-309`, `meta/stats_tracker.gd:10-22` |
| Entschieden / offen | Cloud-Save (CP5) nur als Vorschlag: lokal ist die Wahrheit, `GET`/`PUT /me/save`, 409 bei Konflikt mit Rückfrage, Steam Cloud aus; CP5 darf nach dem Release kommen. Sign in with Apple OFFEN (CP0 Frage 8) | [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) CP0, CP5; [ROADMAP.md](ROADMAP.md) Release-Tor |

**Vorab gebaut (18.10.2026, ohne offene Entscheidung):** Die Weltenliste zeigt „Schmiede 10/20“ neben dem Rekord (`SaveSlots.forge_progress`, Test `test_save_slots.gd`).

**Wichtigster Widerspruch:** D-121 sagt „Konto ohne E-Mail und Passwort“; der Wunsch nennt Benutzername/Passwort für den Browser. Das ist Frage 1 (Abschnitt 9).

## 3. Ein Konto, viele Identitäten

### 3.1 Datenmodell

- **Konto** = `players` (wie heute): Anzeigename, Aussehen, Gilden, Runs, neu **XP** und **Cloud-Welten**.
- **Identität** = eine Art, sich anzumelden (`player_identities`, Anbieter + Nutzer-ID des Anbieters, eindeutig je Anbieter). Beliebig viele je Konto, jede höchstens an einem Konto.

| Identität | Wo | Nachweis am Server | Neu? |
| --- | --- | --- | --- |
| `device` (Gast) | jede Installation, auch Browser | die geheime Geräte-ID (P-028) | – |
| `steam` | Steam | Sitzungsticket, `AuthenticateUserTicket` mit Publisher-Schlüssel | – |
| `google_play` | Android | Server-Auth-Code von Play Games v2, Tausch bei Google | – |
| `game_center` | iOS | Signatur von `fetchItems(forIdentityVerificationSignature:)`, Zertifikat nur von Apple-Domains, Zeitfenster | Prüfung fehlt (P14) |
| `password` (Benutzername + Passwort) | überall, gedacht für den Browser | Better Auth (argon2id), Benutzername eindeutig, nur zum Anmelden, nie öffentlich | neu, wenn Frage 1 = a oder b |
| `apple`, `google`, `discord` | Social-Login | OAuth/OpenID beim Anbieter | nur, wenn Frage 2 es will |

- **Benutzername ≠ Anzeigename.** Der Benutzername ist ein Login (eindeutig, privat, ohne Moderation, weil ihn niemand sieht); der Anzeigename bleibt `PlayerName` (nicht eindeutig, 3 Wechsel je 24 h, P-034).
- Technisch (Vorschlag für die Plattform-Entscheidung): Benutzername und Passwort liegen an der vorhandenen `auth_users`-Zeile des Spielers (Better-Auth-Plugin `username`, Anmeldung `credential`); `GET /me/identities` zeigt sie als Anbieter `password`. Keine Registrierung ohne Konto: Benutzername und Passwort werden immer an ein bestehendes (Gast-)Konto **angehängt**.

### 3.2 Anmeldung je Plattform

| Plattform | Beim Start (still) | Im Konto-Panel zusätzlich |
| --- | --- | --- |
| Browser | Gast (`device`) | „Konto sichern“ = Benutzername + Passwort anlegen; „Anmelden“ mit Benutzername + Passwort; Code eingeben |
| Steam | Steam-Ticket, sonst Gast | Benutzername + Passwort, Code |
| Android | Play Games v2, sonst Gast | Benutzername + Passwort, Code |
| iOS | Game Center, sonst Gast | Benutzername + Passwort, Code |
| Editor/Tests | Dev-Login oder Gast | – |

Der Spieler muss nie etwas eintippen, um zu spielen. Auf Steam, Android und iOS reicht die stille Store-Anmeldung, damit das Konto eine Neuinstallation übersteht; nur im Browser und bei reinen Gästen hängt es an der Installation (P-028). Deshalb zeigt das Spiel Gästen nach dem ersten Run mit mindestens 10 Minuten Spielzeit (TESTWERT) einmal „Konto sichern“ und danach dauerhaft einen kleinen Hinweis im Konto-Panel.

### 3.3 Verknüpfen

1. **Anmeldung hinzufügen** (neu, Hauptweg): Angemeldet auf Gerät A tippt man „Mit Steam verbinden“, „Benutzername anlegen“ usw. Das Spiel schickt den **Nachweis** der neuen Identität (Ticket, Code, Signatur, Passwort), nie eine nackte ID. Neue Route `POST /me/identities` (Vorschlag), Vertrag zuerst in `packages/contracts/src/identity.ts`.
2. **Anmelden auf neuem Gerät:** Im Browser „Anmelden“ mit Benutzername + Passwort; das Gerät hatte schon ein Gastkonto → das ist eine Zusammenführung (3.4).
3. **Verknüpfungscode** (gebaut, D-121): Gerät A zeigt 6 Zeichen, Gerät B gibt sie ein. Bleibt für Geräte ohne gemeinsame Anmeldung (z. B. Steam und iPhone, ohne Passwort).

Gehört die neue Identität schon einem anderen Konto, gilt immer 3.4.

### 3.4 Zusammenführen (D-122, ergänzt)

D-122 gilt weiter: Das **ältere** Konto bleibt, nie still, gesperrte Konten nie. Ergänzungen:

- **„Leeres Konto“** heißt künftig: keine Gilde, keine Runs, **0 XP** und **keine Cloud-Welt mit mehr als 5 Minuten Spielzeit** (TESTWERT; die beim Erststart automatisch angelegte „Welt 1“ zählt so nicht als Fortschritt).
- **XP** beider Konten werden **addiert** (nur Optik, niemand verliert etwas).
- **Cloud-Welten:** Das bleibende Konto behält seine; die des anderen kommen in freie Plätze (höchstens 3, TESTWERT wie `SLOT_COUNT`). Reicht der Platz nicht, wählt der Spieler im Bestätigungsdialog, welche bleiben; die übrigen liegen 30 Tage (TESTWERT) im Archiv und lassen sich in der Weltenliste zurückholen.
- **Profil:** Name und Aussehen des bleibenden Kontos (D-122). Kosmetik-Besitz (WK2, CP6) wird vereinigt.
- Der Dialog zeigt beide Konten mit Name, Level, Gilden, Welten (Rekord, Schmiede, Spielzeit) und sagt in einem Satz, welches bleibt.

### 3.5 Trennen

- Jede Identität außer der letzten lässt sich trennen (P-021). Wer die Identität **dieses Geräts** trennt, wird hier abgemeldet; das Gerät bekommt eine neue Geräte-ID, damit es nicht still wieder im alten Konto landet.
- Benutzername + Passwort trennen löscht die Zugangsdaten; Passwort ändern nur mit dem alten Passwort oder über eine andere angemeldete Identität.
- **Passwort vergessen** ohne E-Mail (Frage 1 = a): über eine andere verknüpfte Identität anmelden und neu setzen, oder mit dem **Wiederherstellungscode** (12 Zeichen, einmal beim Anlegen gezeigt, nur als Hash gespeichert, TESTWERT). Ohne beides ist das Konto über dieses Passwort nicht mehr erreichbar; das sagt der Anlegen-Dialog ehrlich.

### 3.6 Sicherheit

- **Kein Vertrauen in IDs vom Client:** Jede Identität wird am Server mit dem Nachweis des Anbieters geprüft (Steam-Ticket mit Publisher-Schlüssel und `identity`, Play-Games-Code-Tausch, Game-Center-Signatur, Passwort). Die Geräte-ID ist ein Geheimnis und wird nie angezeigt (P-028).
- Passwörter: Better Auth mit argon2id, Mindestlänge 10 (TESTWERT), Rate-Limit je IP und je Benutzername, gleiche Antwort für „unbekannt“ und „falsch“, kein Hinweis, ob ein Benutzername existiert, außer beim Anlegen (dort mit Rate-Limit).
- Identität hinzufügen oder Konten zusammenführen nur mit gültiger Sitzung **und** Nachweis der neuen Identität; danach werden die Sitzungen des gelöschten Kontos widerrufen.
- Cloud-Welten sind **unzuverlässige Daten**: Größe, Format und Zusammenfassung werden geprüft, der Inhalt speist nie Ranglisten, Gildenkasse oder Käufe (Käufe prüft der Server getrennt, CP6, D-177).
- XP kommen vom Client und sind darum gedeckelt (5.6) und nur Optik; nichts, was man kaufen oder in Ranglisten werten kann, hängt daran.

## 4. Cloud-Save

### 4.1 Was wird synchronisiert

| Was | Synchron? | Wie |
| --- | --- | --- |
| Profil (Name, Aussehen, später Kosmetik) | ja (gebaut) | `PATCH /me` (P-034) |
| **Welten** (je Welt die ganze Datei: Gold, Kristalle, Schmiede, Proviant, Freischaltungen, Gesehenes, Statistik, Weltname, später Dorf-Deko) | **ja** | eine Cloud-Welt je Welt, als Ganzes (4.2) |
| **XP / Konto-Level** | **ja** | als Zuwächse, nie als Gesamtwert (5.6) |
| Gilden, Gildenkasse, Run-Berichte | schon auf dem Server | – |
| Einstellungen (Lautstärke, Grafik, Touch, Tasten, Sprache) | **nein**, je Gerät | Handy und PC brauchen andere Werte |
| Laufender Run | nein | wird nie gespeichert (D-040) |
| Run-Protokolle, Feedback, `online.cfg` | nein | bleiben auf dem Gerät |

### 4.2 Wahrheit und Ablauf

- **Offline zuerst:** Gespielt wird immer aus der lokalen Datei. Der **Server ist der gemeinsame Stand** zwischen den Geräten: Wer zuletzt erfolgreich hochlädt, setzt ihn.
- Jede Welt bekommt eine feste **Welt-ID** (UUID, Spielstand v5) statt der Platznummer als Erkennung. Lokal merkt sich die Welt `base_version` (zuletzt abgeglichene Server-Version) und `dirty` (seitdem geändert).
- Server: je Cloud-Welt `version` (steigt bei jedem Hochladen), Daten (≤ 64 KB, TESTWERT; heutige Welten haben wenige KB), Spielstand-Version, Spielversion, Gerät/Plattform, Zeit und eine kleine **Zusammenfassung** (Name, Rekord, Schmiede, Spielzeit, zuletzt gespielt) für Liste und Konfliktdialog.
- **Abgleich** beim Login, beim Betreten des Dorfs (holen), nach jedem Run-Ende, beim Verlassen des Dorfs und beim Schließen bzw. Wechsel in den Hintergrund (hochladen, best effort); im Dorf höchstens alle 5 Minuten, wenn `dirty` (TESTWERT). Nie während eines Runs.
- Fällt der Server aus, spielt man weiter; `dirty` bleibt, der nächste Abgleich holt nach.
- Eine Neuinstallation oder ein geleerter Browser holt die Welten nach der Anmeldung zurück.

### 4.3 Konflikte

| Lokal | Server | Ergebnis |
| --- | --- | --- |
| unverändert | gleich | nichts |
| unverändert | neuer | Server-Stand still übernehmen |
| geändert | gleich `base_version` | hochladen (`PUT` mit `baseVersion`) |
| geändert | neuer als `base_version` | **Konflikt**: die API antwortet `409 version_conflict` mit dem Server-Stand; das Spiel zeigt beide Stände als Karten (Rekord, Schmiede, Spielzeit, zuletzt gespielt, Gerät) und fragt, welcher bleibt |
| geändert | auf anderem Gerät gelöscht | fragen: „Welt behalten“ oder „auch hier löschen“ |

Nie still zusammenführen (Gold kann ausgegeben sein, also lässt sich nicht sicher mischen), nie Verlust ohne Rückfrage: Der verworfene Stand bleibt als Sicherung (lokal `*.conflict.bak`, auf dem Server 30 Tage im Archiv, TESTWERT). Vorausgewählt ist der Stand mit der längeren Spielzeit (Frage 7).

### 4.4 Erster Abgleich auf einem Gerät

Ein Gerät mit lokalen Welten meldet sich zum ersten Mal mit einem Konto an, das schon Cloud-Welten hat (typisch: erst Gast im Browser, dann mit Benutzername angemeldet):

- Konto ohne Cloud-Welten → alle lokalen Welten hochladen, Hinweis „Welten gesichert“.
- Gerät ohne Welten → Cloud-Welten herunterladen, direkt weiterspielen.
- Beide haben Welten → ein Dialog „Auf diesem Gerät“ / „In deinem Konto“: passen alle in 3 Plätze, bleiben alle; sonst wählt der Spieler, der Rest geht ins Archiv (wie 3.4).

### 4.5 Grenzen und Plattformspeicher

- Höchstens 3 Cloud-Welten je Konto (TESTWERT, wie `SaveSlots.SLOT_COUNT`), Archiv 30 Tage, Rate-Limit fürs Hochladen.
- **Eine Wahrheit:** Steam Cloud und Play Games „Gespeicherte Spiele“ bleiben aus (CP5, MP10).
- Gesperrte Konten laden nicht hoch; Löschen des Kontos löscht die Cloud-Welten mit, lokale Welten auf dem Gerät bleiben (der Löschdialog sagt das).

## 5. Fortschritt sichtbar

### 5.1 Drei Ebenen, keine Doppelung

| Ebene | Was | Gilt für | Macht stärker? |
| --- | --- | --- | --- |
| **Konto-Level** (neu) | XP aus allem, was man spielt, Level-Zahl am Namen, Belohnungen nur Optik | das Konto, alle Welten, Solo und Koop, alle Geräte | **nein** (D-176; Koop bleibt fair, D-081) |
| **Welt** (gebaut) | Schmiede-Stufen (Gold), Proviant (Kristalle), Freischaltungen, Rekord, Chronik | eine Welt | ja, nur im Solo (D-081) |
| **Run** (gebaut) | Waffen, Upgrades, Run-Gold | ein Run | ja, nur in diesem Run |

Das Level ersetzt nichts: Die Schmiede bleibt der Weg, stärker zu werden, die Chronik bleibt die Statistik der Welt. Das Level beantwortet „Wie viel habe ich insgesamt gespielt und geschafft?“ und ist die Quelle für freispielbare Kosmetik (KONZEPT_BEGLEITER_KOSMETIK §5, Meilensteine).

### 5.2 XP-Quellen (alle TESTWERT)

| Quelle | XP |
| --- | ---: |
| Raum geschafft (auch Minispiel- und Arenaräume) | 5 |
| Champion besiegt | 10 |
| Boss besiegt | 50 |
| Neuer Konto-Rekord (tiefster Raum über alle Welten) | 5 je Raum über dem alten Rekord |
| Run über das Portal beendet | 20 |
| Erster Run des Tages | 25 |
| Koop-Bonus (2–4 Spieler) | +20 % auf den Run (Frage 5) |

Gezählt wird beim Run-Ende aus der Run-Zusammenfassung (`RunManager.get_last_summary()`, `RunRecap`); jeder Spieler bekommt seine eigenen XP aus seinen eigenen Zahlen, auch im Koop. Ein früher erster Run (6 Räume) bringt etwa 30–60 XP.

### 5.3 Level-Kurve (TESTWERT)

XP für Level L insgesamt: **50 · L · (L − 1)**. Level 2 bei 100 XP, Level 3 bei 300, Level 5 bei 1 000, Level 10 bei 4 500, Level 20 bei 19 000, Level 50 bei 122 500. Kein Höchstlevel (der Dungeon endet auch nie); Belohnungen bis Level 50. Grob: Level 5 nach 15–20 Runs, Level 10 nach 50–70 Runs. Die Kurve steht als eine Funktion im Vertrag (`packages/contracts`) und gleich im Spiel, damit beide dasselbe Level zeigen.

### 5.4 Wo man es sieht

| Wo | Was |
| --- | --- |
| Hauptmenü | neben dem Namen Level-Abzeichen und XP-Balken („Level 7 · 340 / 700 XP“); unten wie heute Welt, Währungen, Rekord |
| Run-Ende | „+86 XP“ mit Aufschlüsselung (Räume, Bosse, Rekord, Koop), der Balken füllt sich, beim Aufstieg ein Banner mit der Belohnung |
| Profil (Figur, Spiegel) | Level, XP bis zum nächsten, nächste Belohnung als Vorschau, freigespielte Teile |
| Fortschritt-Übersicht (neu, Hauptmenü und Chronik) | Konto (Level, Konto-Rekord, Bosse gesamt) · diese Welt (Schmiede x/20, Rekord, Bosse, erreichte Biome, Freischaltungen) · **Nächste Ziele** (nächste leistbare Schmiede-Stufe, nächster Boss bei Raum 15·n, nächste Level-Belohnung) |
| Weltenliste | Rekord, **Schmiede x/20** (gebaut), Spielzeit |
| Lobby, Gildenliste | Level-Zahl am Platz bzw. am Mitglied (Frage 6) |

### 5.5 Belohnungen je Level (Vorschlag, nur Optik)

- Jedes Level: die Zahl am Namensschild.
- Alle 5 Level ein Kosmetik-Teil aus WK2 (Wick-Hut, Flammenfarbe, Lichtfarbe, Rücken-Teil, Rahmen fürs Namensschild), dazu Titel bei 10, 25 und 50 („Dochtträger“, „Lichtbringer“, „Seelenwächter“; Namen OFFEN, Glossar).
- Was man über Level freispielt, kann man nicht kaufen, und umgekehrt (KONZEPT_BEGLEITER_KOSMETIK §5). Nie Gold, Kristalle, Stärke oder Abkürzungen.
- Die Liste der Teile entsteht in WK0/WK2; das Level liefert nur den Zeitpunkt.

### 5.6 Speichern und Abgleich der XP

- XP sind **Zuwächse**: Jeder Run erzeugt einen Eintrag (Run-ID, XP, Zeit), lokal in `user://progress.cfg` (je Installation, neben `profile.cfg`; Skript-Läufe schreiben nie hinein, AGENTS.md Regel 4).
- Online gehen die offenen Einträge mit `POST /me/xp` an den Server (Vorschlag); die Run-ID verhindert doppeltes Zählen. Zwei Geräte offline können also nie in Konflikt geraten, die Summe stimmt immer.
- Der Server deckelt je Eintrag (2 000 XP) und je Tag (20 000 XP, beides TESTWERT) und zählt den Rest nicht; `PlayerSelf` bekommt `xp` und `level`, Gildenmitglieder und Lobby-Profile `level`.
- Offline und ohne Konto steigt das Level trotzdem (lokale Summe); beim ersten Login werden die lokalen Einträge dem Konto gutgeschrieben.

## 6. Pflichten der Plattformen

- **Apple, App Review 4.8 (Login-Dienste):** Wer einen Login über einen fremden oder sozialen Dienst (Google, Discord, Facebook …) als Konto-Login anbietet, muss zusätzlich eine gleichwertige datensparsame Option anbieten, z. B. „Sign in with Apple“. Eigene Konten (Benutzername/Passwort) und Game Center fallen nicht darunter. Mit Frage 2 = a ist kein Sign in with Apple nötig; beantwortet CP0 Frage 8. Mit dem aktuellen Wortlaut in CP4 prüfen.
- **Apple 5.1.1(v):** Wer Konten anlegt (auch still als Gast), muss sie in der App löschen lassen. Die API kann es (`DELETE /me`), das Konto-Panel (KF6) muss es zeigen. Spielen ohne Anmeldung bleibt möglich (5.1.1: kein Login-Zwang für Funktionen ohne Konto).
- **Google Play:** Löschen in der App und über eine Web-Adresse (gebaut, P-026); Formular „Datensicherheit“ um Benutzername, Spielstand in der Cloud und XP ergänzen.
- **Steam:** keine Pflicht zum Konto; Steam Cloud aus (eine Wahrheit).
- **Datenschutz (DSGVO):** Datensparsam: Benutzername statt E-Mail (Frage 1), Passwort nur als Hash, keine IP in Sitzungen (P-027). Datenschutzerklärung (eRecht24) um Benutzername, Cloud-Welten und XP ergänzen; Auskunft und Datenübertragbarkeit (Art. 15, 20) später als „Meine Daten herunterladen“ (Vorschlag, gleicher Code-Weg wie die Löschung); Löschen umfasst Cloud-Welten und XP. Rechtsgrundlage Vertragserfüllung (Konto und Cloud-Save als Funktion des Spiels), mit Zielgruppe ab 13 (D-173) mit Fachanwalt bzw. eRecht24 prüfen.

## 7. Koop-Check und Leitplanken

- Konto, Token, Identitäten und Abgleich am lokalen Client (`online/session.gd`, neu `online/cloud_save.gd`), kein neuer Autoload (D-044).
- Konto-Level ist reine Optik: keine Wirkung auf Schaden, HP, Gold oder Gegner; im Koop starten alle gleich (D-081). Das Level kommt zu Mitspielern über das Profil, nie über Spielpakete.
- XP zählt jeder Client für seinen eigenen Spieler aus den eigenen Run-Zahlen; der Host rechnet keine XP für andere.
- Cloud-Save nur für Einzelspieler-Welten; Gruppen-Fortschritt bleibt auf dem Server getrennt (D-081). Koop-Runs eines Clients ändern seine eigene Welt wie heute (Auszahlung, Statistik).
- Plattform-SDKs (GodotSteam, Play Games, Game Center) nur über `PlatformServices` mit Null-Implementierung für Editor, Headless und Browser, damit alle Tests ohne SDK laufen.
- Tests fassen den echten Spielstand und `progress.cfg` nie an (AGENTS.md Regel 4).

## 8. Pakete (Überblick)

Ausführlich mit Dateien, Prüfung und Koop-Check in [ROADMAP.md](ROADMAP.md), Strang K. Reihenfolge: KF0 → KF1 → KF2 (nur lokal, sofort möglich) → Plattform KF3 ‖ KF5 ‖ KF8 (Verträge zuerst) → KF4, KF6, KF7, KF9 → KF10 (Abnahme).

| ID | Ergebnis | Repo |
| --- | --- | --- |
| KF0 | Fragen aus Abschnitt 9 beantworten, D-188 verbindlich | – |
| KF1 | Fortschritt-Übersicht (Konto-Teil zuerst lokal, Welt, nächste Ziele) | Spiel |
| KF2 | Konto-Level lokal: XP je Run, Level-Kurve, „+XP“ am Run-Ende, Abzeichen im Menü | Spiel |
| KF3 | XP und Level am Konto: Vertrag, Tabelle, `POST /me/xp`, `level` in Profil, Gilde, Zusammenführen | Plattform |
| KF4 | XP-Abgleich und Level bei anderen (Lobby, Gilde) | Spiel |
| KF5 | Anmeldung hinzufügen (`POST /me/identities`), Benutzername + Passwort, Wiederherstellungscode, „leeres Konto“ neu, Game-Center-Prüfung | Plattform |
| KF6 | Konto-Panel (CP1 Spiel-Teil, erweitert): Anmeldungen, Konto sichern, Anmelden, Code, Zusammenführen, Trennen, Löschen | Spiel |
| KF7 | `PlatformServices`: stille Store-Anmeldung (Steam mit MP6, Play Games, Game Center) | Spiel |
| KF8 | Cloud-Welten: Vertrag, Tabelle, Routen, Konflikt `409`, Archiv, Zusammenführen, Löschen | Plattform |
| KF9 | Spielstand v5 (Welt-ID, Abgleich-Daten), `online/cloud_save.gd`, Dialoge für Konflikt und ersten Abgleich | Spiel |
| KF10 | Abnahme: Browser → Steam → Android → iPhone mit einem Konto, Welten und Level gleich | beide |

## 9. Offene Fragen (für KF0)

| # | Frage | Optionen (Empfehlung zuerst) |
| --- | --- | --- |
| 1 | **Anmeldung im Browser** (ändert D-121, wenn a oder b) | **a)** Benutzername + Passwort ohne E-Mail, mit Wiederherstellungscode · b) E-Mail + Passwort mit Rücksetz-Mail (braucht Mailversand, mehr Daten) · c) nur Social-Login (Discord/Google/Apple) · d) wie heute: nur Gast + Verknüpfungscode |
| 2 | **Social-Logins** zusätzlich | **a)** vorerst keine (kein Sign in with Apple nötig, CP0 Frage 8) · b) Discord im Browser (passt zur Zielgruppe; dann auf iOS auch Sign in with Apple) · c) Google und Apple überall |
| 3 | **Cloud-Save zum Release?** | **a)** ja, ins Release-Tor (gemeinsamer Release mit Crossplay, Browser-Speicher geht leicht verloren) · b) kurz nach dem Release (erster Abgleich lädt lokale Welten hoch) · c) später wie bisher |
| 4 | **Konto-Level** | **a)** ja, Konto-Level mit XP, Belohnungen nur Optik · b) nur Fortschritt-Übersicht ohne Level · c) Level je Welt statt je Konto |
| 5 | **Koop-Bonus auf XP** | **a)** +20 % im Koop (Koop ist der Kern, D-173) · b) gleich wie allein |
| 6 | **Level für andere sichtbar** | **a)** ja, in Lobby und Gilde · b) nur für einen selbst |
| 7 | **Konflikt zwischen zwei Geräten** | **a)** immer fragen, Stand mit mehr Spielzeit vorausgewählt, Verlierer 30 Tage als Sicherung · b) automatisch der zuletzt gespielte, mit Sicherung und Hinweis |

Delegiert und darum nur TESTWERT (Abschnitte 3–5, Balance-Agent bzw. Plattform): XP-Werte, Level-Kurve, Deckel, Grenzen der Cloud-Welten, Archivdauer, Zeitpunkt des Hinweises „Konto sichern“, Regel „leeres Konto“, XP-Summe beim Zusammenführen.

**Weiterlesen:** [ROADMAP.md](ROADMAP.md) (Strang K) · [ROADMAP_CROSSPLAY.md](ROADMAP_CROSSPLAY.md) (CP1, CP5) · [KONZEPT_BEGLEITER_KOSMETIK.md](KONZEPT_BEGLEITER_KOSMETIK.md) (§5 Freispielen) · [MULTIPLAYER.md](MULTIPLAYER.md) · [DECISIONS.md](DECISIONS.md) (D-121, D-122, D-152, D-188) · `soulwick-platform/docs/KONZEPT_ONLINE.md` §3
