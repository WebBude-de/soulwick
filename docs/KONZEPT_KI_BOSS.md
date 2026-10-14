# Konzept „Traumweber“ – KI-generierte Wunschbosse

> **Stand:** 13.10.2026 · **Status:** Idee und Konzept für später (Advanced Feature). **Nichts davon ist beschlossen oder gebaut.** Offene Punkte: Abschnitt 11.  
> **Umsetzungsplan:** [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) · **Voraussetzung:** Server aus [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) MP7 · **Grafikregeln:** [SPRITES.md](SPRITES.md)

## 1. Die Idee in drei Sätzen

Nach einem Bosskampf erscheint ein geheimnisvoller **Traumweber**, und der Spieler beschreibt ihm in einem Chat seinen eigenen **Albtraum-Boss**, z. B. „ein Riesenzombie, der Grabsteine wirft“ oder „ein Lach-Emoji, das mich beißt“. Im Hintergrund erzeugt eine KI daraus Verhalten, Werte, Texte und **Sprites im Stil des Spiels**, während der Spieler normal weiterspielt. Ein paar Räume später tritt der Spieler gegen genau diesen Boss an.

**Warum das stark ist:** Jeder Run kann etwas Einmaliges enthalten, Spieler erzählen sich ihre verrücktesten Bosse („Ich hab gegen einen Toaster mit Laseraugen gekämpft“), und es entstehen Inhalte zum Teilen mit Freunden und Gilden.

## 2. Leitprinzip: Die KI wählt aus einem Baukasten, sie programmiert nicht

Die KI darf das Spiel **nicht** verändern und schreibt **keinen Code**. Sie erzeugt ausschließlich eine **Boss-Beschreibung als Daten** (JSON), die aus einem festen **Baukasten** zusammengesetzt ist:

| Was die KI bestimmt | Womit | Grenzen |
| --- | --- | --- |
| Name, Titel, Sprüche | freier Text | Längenlimit, Filter, keine Formatierungsbefehle |
| Aussehen | Bildbeschreibung → Sprite-Pipeline (Abschnitt 6) | fester Stil, feste Größe, feste Palette |
| Bewegung | Auswahl: verfolgen, Abstand halten, springen, teleportieren | Tempo in festen Stufen |
| Angriffe | 2–4 **Module** aus dem Katalog (Abschnitt 4) | Parameter in festen Bereichen |
| Phase zwei | zusätzliche Module, Wutausbruch | wie normale Bosse (`BossRules`) |
| Diener | bestehende Gegnertypen | höchstens `MAX_MINIONS` |
| Effekte auf den Spieler | keiner, Betäubung, Blendung | feste Dauern |
| Töne | Auswahl aus vorhandenen Soundeffekten | nur Liste |

Das Spiel **prüft jede Beschreibung selbst noch einmal** (Schema, Wertebereiche, Budget) und lädt nur Daten und PNG-Bilder. Dadurch:

- **kein Neukompilieren** nötig: Die Daten werden zur Laufzeit in ein `EnemyData` übersetzt, Bilder per `Image.load_png_from_buffer` geladen,
- **kein Sicherheitsrisiko** durch fremden Code,
- **das Spiel bleibt das Spiel:** gleiche Regeln, gleiche Lesbarkeit, gleiche Fairness.

Nebeneffekt: Derselbe Baukasten erlaubt auch **handgeschriebene Bosse als JSON** (für das Team, für Tests, später für Modding).

## 3. Ablauf für den Spieler

1. **Boss besiegt** (Raum 15, 30, …). Im Checkpoint-Raum steht zusätzlich zum Portal der **Schrein des Traumwebers** (optional, E zum Benutzen).
2. **Chat im Spielstil:** Ein Dialog wie die anderen Menüs, mit Pixel-Rahmen. Der Traumweber spricht in seiner Rolle: *„Flüstere mir deinen Albtraum zu, Wanderer …“* Der Spieler tippt eine Beschreibung (max. 300 Zeichen).
3. **Nachfrage (höchstens zwei):** Ist die Beschreibung zu dünn („ein Boss“), fragt der Traumweber nach: *„Und womit greift er an?“* Ist sie zu wild für den Baukasten, schlägt er die nächstbeste Umsetzung vor.
4. **Zusammenfassung und Schwierigkeit:** Eine Karte zeigt, was entstehen wird: Name, 3–4 Stichpunkte zu den Angriffen. Der Spieler wählt **Leicht, Normal, Schwer oder Albtraum** und bestätigt.
5. **Weiterspielen:** Im HUD steht dezent *„Der Traumweber webt … (2/3)“*. Die Erzeugung dauert typischerweise 1–3 Minuten.
6. **Der Albtraum erscheint:** Frühestens **3 Räume** später ersetzt der Wunschboss den nächsten **Miniboss-Raum**. Es gibt einen Titel-Banner mit Name und Spruch, dann folgt der Kampf.
7. **Belohnung** nach Schwierigkeit (Abschnitt 5). Der Boss landet in der persönlichen **Albtraum-Galerie**.

**Wenn etwas schiefgeht:** Ist der Boss bis zum Slot nicht fertig, kommt er beim nächsten Miniboss-Slot. Scheitert die Erzeugung oder wird die Beschreibung abgelehnt, sagt der Traumweber *„Der Traum zerfiel …“*, und der normale Miniboss kommt. **Ohne Internet** ist der Schrein nicht sichtbar; das restliche Spiel ist nicht betroffen.

**Eigener Modus „Arena der Albträume“** (später): ein Ort im Dorf, an dem man einen Boss beschreibt und ihn **direkt** in einer Arena bekämpft, mit fester Ausrüstung je Schwierigkeit. Dort kann man auch alte Bosse aus der Galerie erneut spielen und Bosse **mit Freunden oder der Gilde teilen** (Code oder Gilden-Galerie).

## 4. Baukasten – Module

Fast alles existiert schon in `EnemyData`, `enemy_base.gd` und `BossRules`. Neu nötige Module sind markiert.

| Modul | Beispiel aus einem Prompt | Grundlage im Code |
| --- | --- | --- |
| Nahkampf (Biss, Schlag) | Emoji beißt | `AttackKind.MELEE` |
| Gezielter Schuss / Fächer | Fußballstar schießt Bälle | `RANGED`, `projectile_count` |
| Ring / Spirale | Zombie spuckt Maden im Kreis | `volley_*`, `enrage_spiral` |
| Sturmangriff | Stier rennt los | `Special.SHIELD_CHARGE` |
| Sprung mit Aufprall | Riesenzombie springt, Erde bebt | `Special.LEAP_SLAM`, `landing_ring` |
| Teleport | Geist verschwindet | `Special.TELEPORT` |
| Bodenflächen / Eruption | Lava, Säurepfützen | `Special.ERUPTION` |
| Diener beschwören | Zombie ruft Skelette | `summon_data` |
| Betäuben / Blenden | Blitzlicht, Schrei | `stun_duration`, Blendung |
| Tod mit Nachspiel | zerfällt in kleine Emojis | `death_spawn` |
| **neu:** Zielsuchendes Geschoss | Fluch verfolgt dich | – |
| **neu:** Abprallendes Geschoss | Ball prallt von Wänden ab | Abprall-Logik der Spielerpfeile |
| **neu:** Umkreisende Geschosse | Planeten um den Boss | – |
| **neu:** Spur | Schleimspur, Feuerspur | – |
| **neu:** Strahl (mit langer Vorwarnung) | Laseraugen | – |

**Fairness-Regeln (fest, nicht von der KI änderbar):**
- Jeder Angriff hat eine sichtbare Vorwarnung von mindestens 0,5 s.
- Höchstens 40 gegnerische Geschosse gleichzeitig.
- Keine Sofort-Tode.
- Geschosse bekommen automatisch den roten bzw. orangen Gegner-Leuchtrand, damit sie im Dunkeln lesbar bleiben.
- Bewegungstempo höchstens so schnell wie der Spieler.

## 5. Schwierigkeit und Budget (TESTWERTE)

Jedes Modul kostet **Punkte**, z. B. ein Fächer mit 3 Geschossen 2 Punkte, mit 7 Geschossen 4 Punkte, Diener 3 Punkte. Die gewählte Schwierigkeit legt das Budget fest. Die KI muss darin bleiben; der Server und das Spiel rechnen nach und kürzen notfalls.

| Schwierigkeit | Budget | HP- und Schadensfaktor | Belohnung |
| --- | ---: | ---: | --- |
| Leicht | 6 | ×0,8 | 1 Kristall, Gold wie Miniboss |
| Normal | 10 | ×1,0 | 2 Kristalle |
| Schwer | 14 | ×1,25 | 4 Kristalle |
| Albtraum | 18 | ×1,5 | 6 Kristalle + Galerie-Abzeichen |

Grundwerte (HP, Schaden) kommen aus der normalen Boss-Formel des Raums. Die KI kann einen Boss also **nicht** übermächtig oder wertlos machen, sie verteilt nur das Budget.

## 6. Sprites im Stil des Spiels

Die KI darf den **Inhalt** bestimmen, nicht den **Stil**. Ablauf auf dem Server:

1. **Bildbeschreibung:** Das Sprachmodell schreibt aus dem Wunsch eine Bildbeschreibung (Motiv, Farben, Pose), ohne Stilangaben.
2. **Feste Stilvorgabe:** Der Server ergänzt immer denselben Stilteil (Pixel-Art, 3/4-Draufsicht, Blick nach rechts, dunkle Kontur, transparenter Hintergrund, begrenzte Palette) und gibt **vorhandene Boss-Sprites als Stilreferenz** mit.
3. **Bildgenerator** (Anbieter OFFEN) erzeugt ein großes Bild.
4. **Nachbearbeitung** (deterministisch, eigener Code):
   - Hintergrund entfernen
   - auf **64×64** (Boss) bzw. **16×16** (Geschoss) verkleinern
   - auf die **Spielpalette** reduzieren
   - 1-px-Kontur
   - Mittelpunkt und Fußlinie ausrichten

   Damit sieht jedes Bild am Ende wirklich nach diesem Spiel aus, egal was der Generator liefert.
5. **Prüfung:** Ein Modell mit Bildverständnis prüft das Ergebnis: Passt es zur Beschreibung? Ist es lesbar? Enthält es Text, Logos oder ein erkennbares echtes Gesicht? Bei Fehlern bis zu zwei neue Versuche, sonst ein Ersatz-Sprite (eingefärbte Schattengestalt).
6. **Animation:** Zunächst **prozedural** wie bei den Platzhaltern: Atmen und Wippen, Laufwackeln, Ausholen mit Weißblitz, Auflösen beim Tod (Shader gibt es schon). Später optional 2–4 erzeugte Frames.

## 7. Technik

```text
Spiel ──HTTPS──► soulwick-api (Server, MP7)
  │               ├─ Chat und Beschreibung ──► Sprachmodell (Claude, strukturierte Ausgabe)
  │               ├─ Moderation             ──► Sprachmodell
  │               ├─ Sprites                ──► Bildgenerator + Nachbearbeitung + Bildprüfung
  │               └─ speichert Boss (JSON + PNGs), Job-Status, Kosten
  └─◄── lädt Boss-JSON + PNGs, prüft selbst nach, baut EnemyData zur Laufzeit
```

- **Sprachmodell:** Claude über das offizielle TypeScript-SDK (`@anthropic-ai/sdk`) im Server-Container, Modell `claude-opus-5-5`. **Strukturierte Ausgabe** (JSON-Schema über `output_config.format` bzw. `messages.parse()` mit Zod) garantiert gültiges JSON. Systemprompt und Modulkatalog sind fest und werden per Prompt-Caching wiederverwendet. Effort `low` bis `medium` (vorher messen). Ablehnungen (`stop_reason: "refusal"`) werden als „Der Traum zerfiel“ behandelt.
- **Schlüssel** (Claude, Bildgenerator) liegen **nur** auf dem Server, nie im Spiel.
- **Jobs:** `POST /dreams` startet (Wunsch, Schwierigkeit, Chatverlauf), `GET /dreams/{id}` liefert Status und Ergebnis. Das Spiel fragt alle paar Sekunden nach.
- **Im Spiel:** neuer `BossSpecLoader`. Er prüft die Daten, baut daraus ein `EnemyData`, lädt die Texturen und speichert alles in `user://dreams/` zwischen. Text wird von Formatierungsbefehlen bereinigt (kein BBCode in `RichTextLabel`).
- **Multiplayer:** Der Host verteilt JSON und PNGs (wenige KB) an alle Clients.

**Kosten (grobe Schätzung, messen in KI3):**
- Sprachmodell: Listenpreis von `claude-opus-5-5` ist 4 $ bzw. 20 $ pro Million Ein- bzw. Ausgabe-Token (Stand 09/2026). Chat mit bis zu zwei Nachfragen, Beschreibung und Bildprüfung kosten je Boss grob **0,05–0,20 $**.
- Bildgenerierung kommt hinzu, abhängig vom Anbieter.
- Dagegen helfen: Kontingent je Spieler (Testphase: 3 Bosse pro Tag) und eine **Tagesobergrenze** für Ausgaben auf dem Server, ab der der Schrein „ruht“.

## 8. Beispiele

| Wunsch des Spielers | Daraus wird (Schwierigkeit Normal, Budget 10) |
| --- | --- |
| „Ein Riesenzombie, der Grabsteine wirft“ | **Der Modernde Koloss**: langsam verfolgend; Fächer aus 3 Grabsteinen (2); Sprung mit Aufprall-Ring (3); Phase zwei: beschwört 2 Skelette (3); stirbt und zerfällt (Rest). |
| „Cristiano Ronaldo, der mich mit Fußbällen beschießt“ | Echte Personen werden zu einer **fiktiven Hommage** (Abschnitt 9): **Der Goldene Stürmer** (Nr. 7, ohne Namen, ohne echtes Gesicht); abprallende Bälle (3); Sturmangriff „Sprint“ (3); Phase zwei: Ballring (4). |
| „Ein Lach-Emoji, das mich beißt“ | **Grinsender Schrecken**: schnell, Nahkampf-Biss (2); Teleport (3); beim Tod zerfällt er in 4 Mini-Emojis (3); Phase zwei: Lach-Schrei blendet (2). |
| „asdf“ oder „der stärkste Boss aller Zeiten“ | Nachfrage des Traumwebers; das Budget begrenzt die Stärke trotzdem. |
| beleidigende oder verbotene Inhalte | Ablehnung in der Rolle des Traumwebers, normaler Miniboss. |

## 9. Grenzen, Recht und Moderation

- **Echte Personen:** Name und Gesicht realer Menschen (Persönlichkeitsrechte, Recht am eigenen Bild) werden **nicht** übernommen. Die KI macht daraus eine **fiktive Figur** mit ähnlichem Thema. Gilt auch für Politiker und Influencer. *(Empfehlung, Teamentscheidung nötig.)*
- **Geschützte Figuren und Marken** (z. B. Figuren aus anderen Spielen, Logos, Vereinswappen): ebenfalls nur als freie Anlehnung, keine Logos, kein Text im Bild.
- **Verbotene Inhalte:** sexuelle Inhalte, Hass und Hetze, extremistische Symbole, Gewalt gegen reale Gruppen, Selbstverletzung. Gewalt nur im Rahmen des Spiels (Fantasy-Kampf). Prüfung des Wunschs **und** des Ergebnisses (Text und Bild).
- **Melden-Knopf** im Spiel, Admin-Ansicht auf dem Server, Löschen von Bossen.
- **Steam:** KI-generierte Inhalte müssen bei Steam **angegeben** werden; für **live im Spiel erzeugte** Inhalte verlangt Steam eine Beschreibung der Schutzmaßnahmen gegen unzulässige Inhalte. Dieses Konzept (Baukasten, Moderation, Melden) ist genau diese Beschreibung.
- **Datenschutz:** Wünsche werden gespeichert (für Galerie, Moderation, Kosten). Speicherdauer festlegen, in der Datenschutzerklärung nennen, Löschen auf Wunsch (wie MP7).
- **Altersfreigabe:** Freie Spielereingaben können die Einstufung beeinflussen; vor dem Release prüfen.

## 10. Was das Feature später noch kann

- **Gilden-Albträume:** Die Gilde stimmt ab, welcher Albtraum im nächsten Gilden-Run kommt.
- **Albtraum der Woche:** Der beliebteste Community-Boss ist für alle spielbar, mit eigener Rangliste.
- **Wunsch-Effekte und -Waffen:** Mit demselben Baukasten-Prinzip könnten Spieler später auch Upgrades oder Waffen „erträumen“ (eigene Entscheidung, Balance-Risiko).
- **Modding:** Team und Community bauen Bosse direkt als JSON.

## 11. Offene Entscheidungen

| Punkt | Empfehlung |
| --- | --- |
| Feature überhaupt, und wann | nach Multiplayer (D-088); Baukasten KI1/KI2 schon vorher möglich |
| Umgang mit echten Personen und Marken | fiktive Hommage, nie Name oder Gesicht |
| Anbieter Bildgenerierung | nach Stilreferenz-Fähigkeit, Preis, Lizenz für kommerzielle Nutzung, Datenschutz (EU) auswählen |
| Kontingent und Kosten | Testphase 3 pro Tag, Tagesobergrenze auf dem Server; später ggf. Kristalle als Preis im Spiel |
| Wo im Run | Schrein nach Bossen, Wunschboss ersetzt einen Miniboss ≥3 Räume später |
| Eigener Modus „Arena der Albträume“ | ja, nach dem Einbau in den Run |
| Teilen und Community-Galerie | erst mit Melde- und Moderationswerkzeugen |

**Weiterlesen:** [ROADMAP_KI_BOSS.md](ROADMAP_KI_BOSS.md) · [PRD.md](PRD.md) · [ROADMAP_MULTIPLAYER.md](ROADMAP_MULTIPLAYER.md) · [SPRITES.md](SPRITES.md) · [DECISIONS.md](DECISIONS.md)
