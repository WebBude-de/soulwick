# Glossar Deutsch ↔ Englisch

> **Stand:** 23.10.2026 · **Gilt für:** Spiel (`localization/translations.csv`), Website (`soulwick-platform/apps/web/messages/`) und Plattform (API-Verträge, Admin-Panel).

Dieses Glossar legt fest, wie Spielbegriffe auf Deutsch und Englisch heißen, damit Spiel, Website und Plattform dieselben Wörter benutzen. Englisch ist die Standardsprache, Deutsch die zweite Sprache (D-111). **Regel:** Ein neuer Begriff, den Spieler zu sehen bekommen, wird **zuerst hier** eingetragen, danach in `localization/translations.csv` (Spiel) und in `soulwick-platform/apps/web/messages/en|de/*.json` (Website). Code-Bezeichner (Klassen, Dateien, Enums, Vertragswerte) bleiben Englisch; Werte in `Backticks` stammen aus Code oder API-Verträgen und sind verbindlich. Die frühere Begriffstabelle aus PRODUKT.md (§10) steht seit 17.10.2026 hier (D-178); bei Abweichungen gilt dieses Glossar für die Wortwahl, [DECISIONS.md](DECISIONS.md) für die Regeln. Ziel und Zielgruppe: [PRODUKT.md](PRODUKT.md).

**Lesehilfe:** ⚠ uneinheitlich = die Quellen benutzen verschiedene Wörter; die Zeile nennt den gewählten Begriff, die Varianten sollen bei der nächsten Überarbeitung angeglichen werden. **Vorschlag** = es gibt noch keinen englischen Text in Spiel oder Website. **OFFEN** = nicht entschieden.
**Quellen-Kürzel:** TR = `localization/translations.csv` (Schlüssel) · WEB = `soulwick-platform/apps/web/messages/{en,de}/landing.json` (sonst Datei genannt) · API = `soulwick-platform/packages/contracts/src/common.ts` · KR = früheres `KONZEPT_RAEUME.md` (aufgelöst, D-178; die Regeln stehen in den genannten D-Einträgen, für Raumarten und Minispiele gilt [RAEUME.md](RAEUME.md), D-120) · PRD = [PRD.md](PRD.md) (Designziele und Spielregeln mit Grund, D-178).

## Spielablauf

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Run | run (`runs`) | ein Dungeon-Durchlauf vom Dorf bis Tod, Abbruch oder Portal; Waffen, Upgrades und Run-Gold gelten nur darin | PRD §8, API `RunMode` |
| Raum | room | kleinste Einheit des Dungeons, gezählt ab 1; der höchste Raum zählt für Rekord und Rangliste | TR `HUD_ROOM` |
| Fünferzyklus, Zyklus | cycle of five, cycle | Raum 1–3 Kampf (nach Raum 3 Upgrade-Wahl), 4 Spezialraum, 5 Miniboss bzw. Boss. ⚠ uneinheitlich: WEB `loopText`/`loopSteps` beschreibt „vier Kampfräume, dann Spezialraum“ und „jeder fünfte Raum ist Spezialraum“ | D-005, PRD §4.1, TR `HUD_ROOM_DETAIL`, WEB `loopTitle` |
| Endlosmodus | endless (Vorschlag) | der Dungeon geht nach jedem Boss unbegrenzt weiter; kein eigener Modus, keine Wahl bei Raum 45. ⚠ uneinheitlich: WEB `goldText` nennt noch die Wahl nach Raum 45 | D-073 |
| Seelentor (bisher Ausgangsportal) | Soul Gate (Vorschlag; bisher exit portal) | Tor zurück ins Dorf mit 100 % der Beute = **Extraktion**; heute immer am Lagerfeuer und in 30 % der Spezialräume, künftig spätestens jeden zweiten Zyklus (KONZEPT §2). ⚠ uneinheitlich: „Exit-Portal“ (D-073, D-103), im Spiel nur „Portal“ (TR `CONTROLS_INTERACT_NOTE`) | D-073, D-103, WEB `loopText` |
| Gold-Regel | gold rule | 100 % des Run-Golds am Portal, 50 % (aufgerundet) bei Tod oder Abbruch; Vorschlag für die Vollversion: Tod 25 %, mit Seelenanker 50 % (KONZEPT §2). ⚠ uneinheitlich: „ab Raum 45 bleibt Gold im Run“ (WEB `goldText`) ist durch D-073 überholt | D-039, D-062 |
| Run-Ende: Gefallen, Run abgebrochen, Dungeon verlassen | Run over: You have fallen, Run abandoned, You left the dungeon | die drei Arten, einen Run zu beenden: Tod, Abbruch im Pausemenü, Ausstieg durchs Portal | TR `RUNEND_*`, `GAME_UI_ABORT_RUN` |
| Extraktion, extrahieren | extraction, extract (Vorschlag) | den Run bewusst durchs Seelentor beenden und die Beute ganz mitnehmen; Gegenteil: sterben und das meiste verlieren | D-194, KONZEPT §2 |
| Tiefenbonus | depth bonus (Vorschlag) | Gold je Gegner und Boss-Kristalle steigen je Fünferblock (Vorschlag +10 %) | D-194, KONZEPT §2 |
| Gefahrenstufe | danger level (Vorschlag) | Stufe G, mit der ein Run startet: aus Level (Deckel) und den letzten 5 Runs (Können), nicht wählbar, in der Gruppe aus den Stufen aller Spieler (D-196); macht Gegner stärker und Beute größer | D-194, KONZEPT §3 |
| Rang | rank (Vorschlag) | Name der eigenen Gefahrenstufe: Funke, Kerze, Flamme, Laterne, Leuchtfeuer (je I–III), Seelenmeister / Spark, Candle, Flame, Lantern, Beacon, Soul Master; zeigt, wie gut man gerade ist, kann fallen. Code: `tier` (`spark` … `soul_master`) + `step` (I–III bzw. Zahl); Texte `RANK_*` | D-194, KONZEPT §3.1 |
| Gruppen-Stufe | group danger level (nur intern) | Gefahrenstufe eines Koop-Runs: gerundeter Mittelwert der Stufen aller Spieler im Raum, rechnet der Host | D-196, `CoopRules.group_danger` |
| Beute-Bonus | loot bonus | +5 % Gold und Kristalle je Gefahrenstufe, einmal auf die Auszahlung am Run-Ende | D-197, `EconomySystem.apply_danger_loot` |
| Gast-Gegnerart | guest enemy type (nur intern) | ab Gefahrenstufe 6 je Biom eine Gegnerart aus dem nächsten Biom (12 % Anteil, Dungeon-RNG) | D-197, `EnemyScaling` |
| Solo-Charakter | solo character (nur intern) | Talente und Zauber des Kontos plus Schmiede und Proviant der Welt; gespielt allein und im Schnellen Spiel | D-194, KONZEPT §9 |
| Gilden-Charakter, Gilden-Level | guild character, guild level (Vorschlag) | eigener Charakter je Spieler und Gilde für Gilden-Runs: beginnt bei null, eigenes Level und eigener Talentbaum, Gilden-Schmiede aus der Gildenkasse; liegt auf dem Server | D-194, KONZEPT §9 |
| Übungsgang | practice run (Vorschlag) | kurzer Gang mit vier Stationen vor dem ersten Dungeon (laufen und angreifen, dashen, springen, Rechtsklick), nur einmal je Konto | D-194, KONZEPT §7.2 |
| Spielstand, Platz | save, slot | lokaler Spielstand mit Dorf-Fortschritt; mehrere Plätze im Hauptmenü | TR `MENU_SLOTS`, `SLOTS_SLOT_NUMBER` |

## Modi

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Abstieg | Descent (Vorschlag) | Hauptmodus: der endlose Dungeon, allein oder im Koop, mit Dorf und Meta-Fortschritt. ⚠ uneinheitlich: im Spiel heißt das Banner der Seitenwege schon „Abstieg“/„Descent“ (TR `SIDE_DESCENT_TITLE`), die Website nutzt „Der Abstieg“ für den Run und „Abstieg“ für die Seitenwege (WEB `descentEyebrow`, `descentStops`); OFFEN, ob die Seitenwege einen eigenen Namen bekommen; seit D-216 heißt der Abschnitt „Hindernislauf“ | PRODUKT §5 |
| Party-Modus, Party | Party mode, party (Vorschlag) | zweiter Modus nur aus Minispielen: 2–4 Spieler gegeneinander in kurzen Runden mit Punktestand, gleiche Grafik; ohne Schaden zwischen Spielern (Vorschlag) | D-179, KONZEPT |
| Traumweber, Wunschboss | Dreamweaver, wish boss (Vorschlag) | KI-Boss aus dem Wunsch des Spielers, gebaut aus einem festen Baukasten; Wunsch aus Bausteinen statt Freitext (Vorschlag) | D-179, KONZEPT |
| Clip, Clip teilen | clip, share a clip (Vorschlag) | kurzer Moment zum Zeigen (Boss-Auftritt, Sieg), als Bildkarte mit Link oder kurzes Video | D-173, ROADMAP KI9 |

## Räume

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Hindernislauf | Obstacle Run | Abschnitt in Seitenansicht zwischen zwei Räumen: kleines Jump-and-Run-Level von etwa 60 s mit schweren Sprüngen, zwei Wegen und Gegnern zum Stampfen, Stufe 1–3 nach Tiefe; etwa jeder vierte Weg. Ersetzt Sprungprobe und Sturmlauf (D-195) | D-144, D-216 |
| Anteil-Regel | share rule (nur intern) | wie oft ein Weg zwischen zwei Räumen ein Hindernislauf wird (etwa 25 %); Code `SideRules.SHARE_CHANCE` | D-216 |
| Schwung | momentum (nur intern) | Tempo steigt, solange man in der Seitenansicht ohne Halt durchläuft; bleibt im Sprung | D-195 |
| Stampfen | stomp | Gegner in der Seitenansicht besiegen durch Landen von oben; Umrennen gibt es nicht mehr (D-216) | D-195, D-216 |
| Kampfraum | combat room (Banner: „Combat“) | öffnet erst, wenn alle Gegner besiegt sind; Plätze 1–3 im Zyklus | PRD §4.1, TR `ROOM_EYEBROW_COMBAT`, WEB `loopSteps` |
| Raumart | room kind | Aufbau eines normalen Kampfraums: Säubern bzw. Normal (`normal`), Arena (`arena`) und die Minispiele; Abgrund ist seit D-120 keine eigene Raumart mehr (Code `chasm` besteht weiter), Formen und Zutaten sind keine Raumarten | D-100, D-120, KR §3.1 |
| Minispiel | minigame (Vorschlag) | Kampfraum mit eigener Aufgabe in einem Satz statt „alle Gegner besiegen“: Geleit, Flamme hüten, Reliquie holen, Seelen sammeln, Risse schließen, Jagd, Lichtfeuer, Einsturz; ab Zyklus 2 rund 35 % der Kampfräume; Grundlage des Party-Modus | D-120, RAEUME §3, TR `MODE_*_TITLE` |
| Raum-Genre | room genre (`room_genre`) | alles, was beim Betreten als Banner benannt und beim ersten Mal erklärt wird (Arena, Katakombe, Abgrund, Varianten, Spezialräume …) | D-110 |
| Arena, Hinterhalt | Arena, Ambush | Kampfraum mit 2–3 Gegnerwellen aus Toren; Hinterhalt = Arena, deren Gegner erst beim Schließen der Tür aus den Wänden brechen | D-100, D-113, TR `ROOM_ARENA_TITLE`, `ROOM_AMBUSH_TITLE` |
| Abgrund | Chasm | Raumart mit Lücken, die man per Dash überquert; Herunterfallen kostet ein Herz | D-086, D-115, TR `ROOM_CHASM_TITLE` |
| Katakombe | Catacomb | Form des normalen Kampfraums: enge Gänge, Sackgassen, Truhe in der tiefsten | D-113, TR `ROOM_CATACOMB_TITLE` |
| Kampf-Variante | combat variant (Vorschlag, Code `variants`) | Kampfraum mit Zusatzaufgabe und Bonus-Truhe: Seelenflamme (Soul Flame), Beschwörungsrisse (Summoning Rifts), Steinwächter (Stone Guardians), Laternenträger (Lantern Bearer), Totengräber (Gravedigger), Kopfgeld (Bounty), Fackelraum (Torch Room) | D-101, D-114, D-116, TR `ROOM_*_TITLE` |
| Elite-Nest | Elite Nest | nur über eine Weggabelung erreichbar: wenige starke Gegner, Bonus-Truhe und Seelenkristalle | D-117, TR `ROOM_ELITE_NEST_TITLE` |
| Bonus-Truhe | Bonus chest | Belohnung für erfüllte Variante, Prüfung oder Katakombe; enthält eine Upgrade-Wahl | D-109, TR `VARIANT_CHEST_TITLE` |
| Spezialraum | Special room | Platz 4 im Zyklus, gewichtet gezogen: Händler, Waffenauswahl, Brunnen, Upgrade-Altar, Prüfungsraum | D-102, TR `ROOM_EYEBROW_SPECIAL` |
| Händler | Trader | Spezialraum: Upgrades, Waffen, Heilung und Schild gegen Run-Gold. ⚠ uneinheitlich: „Shop“ (KR, D-102, WEB `loopText` de/en) | PRD §4.6, TR `ROOM_SHOP_TITLE` |
| Waffenauswahl | Armory | Spezialraum: eine von bis zu zwei neuen Waffen nehmen. ⚠ uneinheitlich: „Waffenwahl“ (WEB de), „weapon choice“ (WEB en) | PRD §4.6, TR `ROOM_WEAPON_TITLE` |
| Brunnen | Fountain | Spezialraum: einmal kostenlos heilen | PRD §4.6, TR `ROOM_FOUNTAIN_TITLE` |
| Upgrade-Altar | Upgrade Altar | Spezialraum: ein Upgrade geschenkt (eine von drei Karten). ⚠ uneinheitlich: „Extra-Upgrade“ (D-102, KR) | TR `ROOM_UPGRADE_ALTAR_TITLE`, WEB `loopText` |
| Prüfungsraum, Prüfung | Trial | Spezialraum ohne Kampf: freiwilliger Parcours zu einer Truhe, Fehler kosten ½ Herz, nie den Run. ⚠ uneinheitlich: „Prüfung“/„Trial“ heißt auch die Ziel-Bedingung am Wagnis-Altar (TR `ROOM_WAGER_SUB`, KR §5) | D-102, D-112, TR `ROOM_EYEBROW_TRIAL` |
| Spießrutenlauf | Gauntlet | Prüfung: Stacheln, Flammen und Pendelklingen im eigenen Takt | D-112, TR `ROOM_TRIAL_GAUNTLET_TITLE` |
| Lichtlauf | Light Run | Prüfung: Fackeln erlöschen nacheinander, Dunkelheit kostet Leben | D-112, TR `ROOM_TRIAL_LIGHT_RUN_TITLE` |
| Bröckelboden | Crumbling Floor | Prüfung: der Boden bricht hinter dem Spieler weg | D-115, TR `ROOM_TRIAL_CRUMBLE_TITLE` |
| makellos | flawless | Prüfung ohne Fehler; gibt zusätzlich einen Seelenkristall | D-109, D-112, TR `ROOM_TRIAL_SUB` |
| Pakt-Altar, Pakt | Pact Altar, pact | in ⅓ der Upgrade-Altäre: stärkeres Upgrade gegen einen Fluch bis zum Run-Ende | D-112, TR `ROOM_PACT_TITLE` |
| Fluch | Curse | Erschwernis: vom Pakt bis zum Run-Ende, vom Wagnis-Altar nur im Raum | D-104, D-112, TR `OVERVIEW_CURSES`, `WAGER_CURSE_*` |
| Wagnis-Altar, Wagnis | Wager Altar, wager | Altar am Eingang mancher Kampfräume: freiwillige Bedingung (Prüfung oder Fluch) gegen Seelenkristalle | D-104, D-114, TR `ROOM_WAGER_TITLE`, `WAGER_PROMPT` |
| Lagerfeuer, Rast | Campfire, Rest | Zwischenraum nach jedem Boss, zählt nicht als Raum: heilen oder ein Upgrade stärken, dazu Ausgangsportal. ⚠ uneinheitlich: WEB de `loopSteps` „Pause“ statt „Rast“ | D-103, TR `ROOM_CAMPFIRE_TITLE`, `CAMPFIRE_EYEBROW` |
| Weggabelung | Crossroads | höchstens einmal je Zyklus zwei Türen zur Wahl, beide führen zu Raum n+1. ⚠ uneinheitlich: „Abzweigung“ (D-105, D-117, KR §7.2; Code `branch`) | D-105, TR `BRANCH_TITLE` |
| Geheimnische, rissige Wand | secret niche (Vorschlag), Cracked wall | Nische hinter einer rissigen Wand, nur durch Explosionen zu öffnen; zählt nicht als Raum. ⚠ uneinheitlich: „Geheimraum“ (D-105, KR §7.3), Banner „Geheimnis!“/„Secret!“ (TR `ROOM_SECRET_TITLE`) | D-117, TR `SECRET_HINT_TITLE` |
| Wandernder Händler | Wandering merchant | seltener Händler in einer Geheimnische | D-109, D-117, TR `SECRET_MERCHANT_NAME` |
| Miniboss | Miniboss | Platz 5 im Zyklus; ist ein Champion mit Begleitern | D-077, TR `HUD_ROOM_TYPE_MINIBOSS` |
| Boss | Boss | Raum 15, 30, 45 …: Boss des Bioms mit zwei Phasen | D-065, D-076, TR `HUD_ROOM_TYPE_BOSS` |

## Welt

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Dungeon | Dungeon | der endlose, dunkle Teil des Spiels unter dem Dorf | PRODUKT §1, TR `VILLAGE_DUNGEON` |
| Biom | biome | 15-Raum-Abschnitt mit eigener Optik, Gegnern, Musik und Boss; die vier Biome wiederholen sich. ⚠ uneinheitlich: im Spiel „Gebiet“/„realm“ (TR `ROOM_EYEBROW_REST`, `ROOM_CAMPFIRE_INTRO_NO_PORTAL`) | D-075, WEB `biomesEyebrow` |
| Krypta · Knochenkönig | Crypt · Bone King | Biom 1 (Raum 1–15) und sein Boss | D-065, D-075, WEB `biomes`; Code `crypt`, `boss_bone_king` |
| Schleimgrotte · Schleimkönigin | Slime Grotto · Slime Queen | Biom 2 (Raum 16–30) und sein Boss | D-065, D-075, WEB `biomes`; Code `slime_grotto`, `boss_slime_queen` |
| Schattenreich · Schattenlord | Shadow Realm · Shadow Lord | Biom 3 (Raum 31–45) und sein Boss | D-065, D-075, WEB `biomes`; Code `shadow_realm`, `boss_shadow_lord` |
| Glutkammer · Glutgolem | Ember Forge · Ember Golem | Biom 4 (Raum 46–60) und sein Boss, danach wieder Krypta. ⚠ uneinheitlich: WEB nennt „Raum 46+“ | D-075, D-076, WEB `biomes`; Code `ember_forge`, `boss_ember_golem` |
| Dorf | Village | Start- und Rückkehrpunkt zwischen den Runs | D-078, D-087, TR `RUNEND_TO_VILLAGE` |
| Schmiede | Forge | dauerhafte Verbesserungen gegen Gold; in der Vollversion nur Waffen und Ausrüstung (Arsenal, Waffe schmieden I–V, Schildplatte, Laterne) | D-087, D-194, TR `VILLAGE_FORGE` |
| Verbesserung | upgrade (Schmiede) | dauerhafte Stufe in der Schmiede (Vitalität, Startschild, Schärfe, Goldgier, Dash-Training, Arsenal). ⚠ uneinheitlich: Deutsch trennt „Verbesserung“ vom Run-„Upgrade“, Englisch nutzt für beides „upgrade“ (TR `UNLOCK_FORGE_MORE`, WEB `villageList`) | D-087 |
| Handelsposten | Trading Post | Proviant gegen Seelenkristalle; in der Vollversion dazu dauerhafte Glücks- und Handelsstufen (Meta-Vorteile). ⚠ uneinheitlich: „Handelshaus“ (WEB de), „Trading post“ (WEB en) | D-078, D-087, TR `VILLAGE_TRADER` |
| Proviant | Provisions | Bonus nur für den nächsten Run: Heiltrank, Glücksamulett, Goldbeutel. ⚠ uneinheitlich: „Heiltrank“ ist im Spiel sowohl „Healing Potion“ (TR `BOOST_POTION_NAME`, dort de „Heiltrank-Proviant“) als auch „Healing Draught“ (TR `SHOP_HEAL_NAME`) | D-078, TR `VILLAGE_UI_PROVISIONS` |
| Chronik | Chronicle | Rekorde und Statistiken | D-087, TR `VILLAGE_CHRONICLE` |
| Gildenhaus | Guild hall | Dorfgebäude für Koop-Lobby und Gilden (in Vorbereitung). ⚠ uneinheitlich: im Spiel „Gilde“/„Guild“ (TR `VILLAGE_GUILD`), D-078 „Gilde“ | D-078, WEB `villageList` |
| Zuhause | Home | eigenes Haus; heute Spiegel für Name und Aussehen, in der Vollversion begehbar mit Kerzen-Altar (Talentbaum, Zauber), später Möbel und Pets | TR `VILLAGE_HOME`, WEB `villageList`, D-194 |
| Drei Säulen | three pillars (nur intern) | Schmiede (Gold → Waffen), Handelsposten (Kristalle → Glück und Meta), Zuhause (Talentpunkte → Charakter) | D-194, KONZEPT §5 |
| Talentbaum, Talent, Talentpunkt | talent tree, talent, talent point (Vorschlag) | Baum im Zuhause mit drei Pfaden (Wind = Tempo, Glut = Kraft, Seele = Zauber); je Level ein Punkt; Umskillen kostet Kristalle (D-196); gilt je Konto. Nicht verwechseln mit Run-Upgrades und Schmiede-Verbesserungen | D-194, KONZEPT §6 |
| Zauber | spell (Vorschlag) | aktive Fähigkeit mit Abklingzeit aus dem Pfad der Seele (Lichtblitz, Seelenschild, Flammenring, Irrlichter, Heilfunke); Flint wirkt ihn sichtbar | D-194, KONZEPT §6.2 |
| Schlussstein | capstone (Vorschlag) | letzter, stärkster Knoten eines Pfads im Talentbaum | KONZEPT §6.1 |
| Pfad, Ebene | path, tier (Vorschlag) | Pfad = Ast des Talentbaums (Wind `wind`, Glut `ember`, Seele `soul`); Ebene 1–4 öffnet nach 0/3/7/11 Punkten im Pfad. „Ebene“ statt „Rang“, damit es nicht mit dem Spieler-Rang verwechselt wird (im Code heißt es noch `rank`) | D-197, `talents/` |
| Zauberplatz | spell slot (Vorschlag) | Platz für einen ausgerüsteten Zauber; der erste kommt mit Lichtblitz, der zweite mit dem Schlussstein der Seele | KONZEPT §6.2, `TalentStats` |
| Umskillen | respec (Vorschlag) | Punkte im Talentbaum zurücknehmen; kostet 10 % der zurückgenommenen Punkte in Kristallen, mindestens 1 | D-196, `TalentState.respec_cost` |
| Glutwelle, Lichtspur | ember wave, light trail (Vorschlag) | Wirkungen der Schlusssteine Glutherz (Welle bei wenig HP) und Windläufer (Dash-Spur verlangsamt Gegner) | KONZEPT §6.1, `talents/` |
| Konto-Zustand | account state (nur intern) | Talente, Zauber und Gesehen-Merker am Konto: lokal `[state]` in `progress.cfg`, online `GET`/`PUT /me/state` | KF3b, `AccountProgress.get_state` |
| Erfolg | achievement (Vorschlag) | Sammelbare Auszeichnung für eine schwierige Leistung (z. B. alle 12 Seelen allein); je Konto, im Spiel sichtbar, später mit Steam abgeglichen; gibt nie Stärke | ROADMAP ER1 |
| Kontaktschaden | contact damage (Tag `contact`) | Schaden je Takt (1 s), solange ein Spieler einen Boss berührt | D-199 |
| Seelentor | soul gate (Code `SoulGate`) | Ausgang aus dem Dungeon mit voller Auszahlung; am Lagerfeuer und am Platz 4 (50 %, nie zwei Zyklen ohne Tor); Dialog „Jetzt sichern“ / „Weiter“ (en „Bank now“ / „Go on“) | D-204, KONZEPT §2 |
| Tiefenbonus | depth bonus | +10 % Gold je Gegner und Boss-Kristalle je Fünferblock | D-204 |
| Waffe schmieden, Meisterstück | forge a weapon, masterwork | Schmiede-Stufen I–V je Waffe (+8 % Schaden je Stufe, ab III stärkeres Spezial, V = Meisterstück) | D-204, KONZEPT §5.1 |
| Schildplatte, Laterne, Arsenal, Zweiter Startplatz | shield plate, lantern, arsenal, second start slot | Schmiede-Stufen: Start-Schild, Lichtradius, Waffen für die Startwahl, mit zwei Waffen starten | D-204 |
| Welt-ID | world id (nur intern) | `[world] id` im Spielstand v5, Schlüssel der Cloud-Welt | D-204, KF8 |
| Flint erklärt, Rundgang, Erstes-Mal-Hinweis | Flint explains, tour, first-time hint (nur intern) | Erklär-Baukasten: Flint fliegt in die Erklär-Ecke unten rechts; Rundgang mit Kamerafahrt und Schutz, Hinweis kurz ohne Sperre | WK8, KONZEPT §7.2 |
| Schwung, Stampfen | momentum, stomp | Seitenansicht: Tempo wächst beim Durchlaufen; Landen auf Gegnern besiegt sie (kein Umrennen, D-216) | D-195, D-216 |
| Stachel-Igel, Schildträger, Gegnerkette | spike hedgehog, shield bearer, enemy chain | Seiten-Gegner: Igel nicht stampfbar, Schildträger nur von oben; Ketten zum Umrennen | D-195, SV4 |
| Zauber wirken | cast a spell | Taste F (Zauber 2: R), Gamepad RB (LB), Touch eigener Knopf | D-203 |
| Empore, Plateau (halbe Höhe) | platform, plateau | erhöhte Fläche im Raum, 16 px hoch mit Treppe aus zwei Stufen, nie an der Außenwand | D-205, CR6 |
| Proviant | provision | Vorrat für den nächsten Run aus dem Handelsposten (Goldregen, Glücksamulett, Klarsicht, Heiltrank, Seelenanker, Rückkehrstein, Spürnase), wird beim Start verbraucht | D-208, KONZEPT §5.2 |
| Proviant-Platz, Glück, Händlerfreund | provision slot, luck, merchant friend | dauerhafte Handelsstufen | D-208 |
| Übungsgang, Station | practice run, station | Tutorial vor Raum 1 mit vier Stationen, einmal je Konto, überspringbar („Kenne ich schon“) | D-208, WK10 |
| Kippplattform, einstürzende Brücke, Dash-Lücke, Wandsprung-Schacht | tilt platform, collapsing bridge, dash gap, wall-jump shaft | Elemente der Sprungprobe (Stufe 1–3) | D-195, D-208 |
| Lava-Bälle, Stampf-Stun | lava balls, stomp stun (nur intern) | Druck-Angriffe des Glutgolems gegen Kiten bzw. Bedrängen; Code `BossPressure`, `LavaPool`, `LobShell` | D-209 |
| Dorf-Rundgang | village tour | Flints Kamerafahrt über das Dorf beim ersten Start je Konto; ersetzt die Chronisten-Eröffnung | D-211, WK9 |
| Lichtmittelpunkt | light centre (nur intern) | Mitte des Lichtkreises eines Spielers: die Flamme seines Flint (ohne Flint die Spielerposition); eine Stelle `LightQuery.get_player_light_center` | WK1, D-194 |
| Gesehen-Merker | seen flag (nur intern) | merkt je Konto, welche Erklärung schon kam (Vereinigung beim Abgleich) | D-194, `AccountSeen` |

## Kampf und Werte

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Herz, HP | heart, HP | Lebensanzeige: 1 Herz = 2 HP, Anzeige in halben Herzen; Start mit drei Herzen | PRD §4.3, HANDOUT, TR `STATE_HP_FULL`, `ROOM_CHASM_INTRO` |
| Schild, Softcap | Shield, soft cap | wird vor HP abgezogen, lädt nicht von selbst auf; über dem Softcap wirken Gewinne nur halb. Farbe `#6cb2ec` | PRD §4.3, D-074, D-091, TR `OVERVIEW_STATS` |
| Dash | Dash | kurzer Sprint (Leertaste), kurz unverwundbar, überquert Abgründe | PRD §4.3, D-086, TR `CONTROLS_DASH` |
| Lichtkreis | light radius | sichtbarer Bereich um den Spieler im dunklen Dungeon. ⚠ uneinheitlich: „circle of light“ (WEB en `loopSteps`) | D-067, D-116, TR `WAGER_CURSE_GLOOM_RULE` |
| Spezialangriff, Abklingzeit | Special attack, cooldown | zweiter Angriff jeder Waffe auf der rechten Maustaste mit eigener Abklingzeit | D-090, TR `CONTROLS_SPECIAL`, `CONTROLS_SPECIAL_NOTE` |
| Waffe, Slot | Weapon, slot | zwei Waffen-Slots, Wechsel mit Q, kein Waffentyp doppelt | PRD §4.4, TR `WEAPON_SLOT` |
| Schwert, Bogen, Magierstab, Dolche, Kriegshammer | Sword, Bow, Mage Staff, Daggers, War Hammer | die fünf Waffen. ⚠ uneinheitlich: „Mage staff“ (WEB en), Kurzform „Staff“/„Stab“ (TR `META_WEAPON_STAFF`); WEB nennt nur drei Waffen | D-090, TR `WEAPON_*_NAME`, WEB `weapons` |
| Upgrade, Upgrade-Wahl | Upgrade, Choose an upgrade | runweite Verbesserung; Wahl aus drei nach Raum 3 jedes Zyklus, am Upgrade-Altar und aus Bonus-Truhen. ⚠ uneinheitlich: WEB `loopSteps`/`upgradesNote` sagt „nach jedem (gewonnenen) Kampf“ | PRD §4.5, TR `UPGRADE_EYEBROW` |
| Stufe | level | wie oft ein Upgrade genommen wurde. ⚠ uneinheitlich: „Stack(s)“ (TR `OVERVIEW_UPGRADES`, D-103), „Stapel“ (TR `UPGRADE_SHIELD_ON_KILL_DESC`) | TR `UPGRADE_STACKS_UNLIMITED`, `CAMPFIRE_STACK_UNLIMITED` |
| Attribut | Attribute | Upgrade-Kategorie für Werte (Schaden, Angriffsrate, Schild), unbegrenzt stapelbar; Farbe Blau `#6cb2ec` | PRD §4.5, HANDOUT, TR `CATEGORY_ATTRIBUTE` |
| Mechanik | Mechanic | Upgrade-Kategorie für Angriffsverhalten (Durchschlag, Wandabprall …), mit Limit; Farbe Grün `#5fcd62` | PRD §4.5, HANDOUT, TR `CATEGORY_MECHANIC` |
| Effekt | Effect | Upgrade-Kategorie für Zusatzwirkungen (Explosion, Heilung/Schild bei Tötung); Farbe Orange `#ff8a3c` | PRD §4.5, HANDOUT, TR `CATEGORY_EFFECT` |
| Waffe (Kategorie) | Weapon | Farbe Lila `#a66ef0`. OFFEN: steht nur im HANDOUT als Kategorie; PRD §4.5 kennt drei Upgrade-Kategorien | HANDOUT |
| Elite | Elite | stärkerer Gegner mit einer Eigenschaft, leuchtendem Umriss und doppeltem Gold | D-069, D-079 |
| Flink, Gepanzert, Explosiv | swift, armored, volatile | die drei Elite-Eigenschaften. ⚠ uneinheitlich: „Schnell“ statt „Flink“ (D-069) | WEB `biomesText`, HANDOUT; Code `Elite.SWIFT`, `ARMORED`, `VOLATILE` |
| Champion | Champion | Miniboss: Gegner des Bioms mit Elite-Eigenschaft, mehr HP und Gefolge; gibt einen Seelenkristall | D-077, D-078, TR `VILLAGE_UI_STAT_CHAMPIONS` |

## Währungen

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Gold | Gold | Währung in Run und Dorf; Farbe `#f2cf4a` | D-038, HANDOUT, TR `STATE_TOO_LITTLE_GOLD` |
| Run-Gold | Run gold | im Run gesammeltes Gold, nur dort ausgebbar; der Rest geht am Run-Ende nach der Gold-Regel ins Dorf | D-038, TR `GAME_UI_RUN_GOLD` |
| Dorfgold | village gold | dauerhaftes Gold im Spielstand, ausgegeben in der Schmiede. ⚠ uneinheitlich: „Gold im Dorf“/„Gold in the village“ (TR `RUNEND_VILLAGE_GOLD`), „Gold gesichert“/„Gold secured“ (TR `VILLAGE_UI_STAT_GOLD_BANKED`) | WEB `villageText` |
| Gutschrift | Banked | am Run-Ende ins Dorf übertragenes Gold (100 % oder 50 %) | D-039, TR `RUNEND_PAYOUT` |
| Seelenkristall | Soul crystal (kurz: crystal) | zweite Währung für Proviant, in der Lore Reste verloschener Seelen; von Bossen, Champions, makellosen Prüfungen, Wagnis-Altar, Elite-Nest und Geheimnischen | D-078, D-087, D-109, TR `RUNEND_CRYSTALS` |

## Online

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Konto | account | Soulwick-Konto = Spieler auf dem Server, im Spiel löschbar; startet still als Gast, Anmeldungen (Steam, Play Games, Game Center, Benutzername, Magic Link, Google, Apple, Discord) und Geräte hängen daran | D-108, D-121, D-122, D-188, PRODUKT §8 |
| Identität | identity (`player_identities`) | eine Anmeldeart am Konto: `steam`, `device`, `google_play`, `game_center`, dazu nach D-188 Benutzername, Magic Link, Google, Apple, Discord | D-108, D-121, D-188 |
| Anmeldung hinzufügen, Konto sichern | add a sign-in, secure your account (Vorschlag) | eine weitere Identität mit Nachweis ans eigene Konto hängen; „Konto sichern“ = Benutzername + Passwort für ein Gastkonto anlegen | D-188 |
| Benutzername | username (Vorschlag) | Login-Name für Benutzername + Passwort, eindeutig und privat; nicht der Anzeigename | D-188 |
| Magic Link | magic link (Vorschlag) | Anmelde-Link per E-Mail, einmal gültig | D-188 |
| Konto-Level, Level, XP | account level, level, XP (Vorschlag) | Level des Kontos über alle Welten, Solo und Koop; steigt mit XP aus Runs und fällt nie; je Level ein Talentpunkt (D-194 ersetzt „nur Optik“), alle 5 Level Kosmetik | D-188, D-194 |
| Cloud-Welt | cloud world (Vorschlag) | Kopie einer Welt am Konto auf dem Server, für alle Geräte des Kontos | D-188, CP5 |
| Gilde | guild (`guild`, `guilds`) | dauerhafte Gruppe, bis zu 5 je Spieler (D-147), höchstens 30 Mitglieder; hat Name und Kürzel (`GuildTag`, 2–5 Zeichen) | D-080, API `GuildName`, `GuildTag` |
| Gründer, Offizier, Mitglied | founder, officer, member (`GuildRole`) | Rollen in einer Gilde | API `GuildRole`, `apps/admin/src/lib/format.ts` |
| Einladungscode | invite code | Code für den Beitritt zu einer Gilde | D-080, API `InviteCode`, WEB `guildCardText` |
| Gildenkasse | Guild treasury | Gold der Gilde aus Gilden-Runs nach der Gold-Regel (Vorschlag D-081) | D-081, WEB `guildChips` |
| Gilden-Schmiede | Guild forge | Waffen- und Ausrüstungsstufen aus der Gildenkasse, gelten für alle Gilden-Charaktere der Gilde (Vorschlag D-081, D-194) | D-081, D-194, WEB `guildChips` |
| Gilden-Run | guild run (`guild`) | Run nur mit Mitgliedern einer Gilde; zählt für Gildenkasse und Gilden-Rangliste | D-080, API `RunMode`, WEB `guildCardText` |
| Schnelles Spiel | quick play (`quick`) | Koop ohne Bindung; jeder spielt seinen Solo-Charakter (seit D-194, vorher ohne Dorf-Boni); am Run-Ende geht Gold nach der Gold-Regel ins eigene Dorf | D-080, D-081, D-126, D-194, API `RunMode` |
| gemeinsame Kasse | shared gold (Vorschlag) | im Multiplayer gehört das Run-Gold allen; jeder darf daraus kaufen | D-081 |
| Koop | co-op | 2–4 Spieler gemeinsam in einem Run, jeder in eigener Farbe | D-084, WEB `coopCardTitle` |
| Host, Client | host, client | der Host rechnet die Spielwelt, die anderen sind Clients; der Relay leitet nur weiter | D-119, TR `VILLAGE_UI_LOBBY_HOST` |
| Wiederbeleben | revive (Vorschlag) | gefallene Mitspieler durch 2 s Danebenstehen zurückholen | D-084 |
| Lobby | lobby | Sammelpunkt vor einem Koop-Run | TR `VILLAGE_UI_LOBBY_CREATE`, WEB `villageList` |
| Raumcode | room code (Vorschlag) | Code, mit dem man einer Lobby auf dem eigenen Relay (`soulwick-relay`) beitritt; nicht mit dem Dungeon-Raum verwechseln | D-119, ROADMAP CP3 |
| Rangliste | leaderboard (`leaderboards`) | Wertung nach höchstem Raum, bei Gleichstand kürzere Zeit; markierte Runs und gesperrte Spieler zählen nicht | D-082, WEB `leaderboards.json` |
| Tafel: Solo, Gruppe, Gilden | board: Solo, Group, Guilds (`solo`, `group`, `guild`) | Solo-Runs je Spieler; Gruppe = Schnelles Spiel und Gilden-Runs je Spieler; Gilden = Gilden-Runs je Gilde. ⚠ uneinheitlich: WEB `lbTabs` „Spieler Solo/Spieler Gruppe“ bzw. „Players solo/Players group“ | API `LeaderboardKind`, WEB `leaderboards.json` `kinds` |
| Saison, Allzeit | season, all-time (`season`, `all`) | Kalendermonat (`YYYY-MM`, UTC) bzw. gesamter Zeitraum | D-082, API `LeaderboardPeriod`, `SeasonId` |
| Run-Bericht | run report (Vorschlag) | Meldung des Hosts am Run-Ende (Modus, Teilnehmer, Raum, Zeit, Seed, Version); verdächtige Runs werden markiert und geprüft | D-082, PRODUKT §8 |
| Crossplay | crossplay | zusammen spielen über Steam, Google Play, App Store und Browser hinweg | D-108, D-119, WEB `platformNote` |
| Relay | relay | eigener Server, der Koop-Pakete nur weiterleitet und Räume mit Raumcode verwaltet (`soulwick-relay`); rechnet nichts | D-119 |
| Einladen per Link, Einladungslink | invite link (Vorschlag) | Link mit dem Raumcode, der die Browser-Version direkt in der Lobby des Hosts öffnet, ohne Konto und ohne Code-Tippen. Nicht verwechseln mit dem Einladungscode einer Gilde | D-176, D-179, ROADMAP MP2b |

## Begleiter, Kosmetik und Dorf

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Flint | Flint | Maskottchen von Soulwick, ein kleines Docht-Wesen (lebende Kerze mit Flamme); im Spiel dein persönlicher Begleiter ab dem ersten Start, zum Release im Spiel (D-179). Name VERBINDLICH (D-198, vorher „Wick“); im Code `flint`. Nicht verwechseln mit der Spielfigur **Wick** (Code-ID `wick`) | D-175, D-198, KONZEPT |
| Flint-Schein | Flint glow (nur intern) | weicher, atmender warmer Schein und aufsteigende Funken an Flints Flamme nach der Website-Vorlage; Code `FlintShine`, `FlintAura`, `FlintSparks`; Stufe „Niedrig“ ohne Funken | D-217, LK8 |
| Pixel-Zeichenhilfe | pixel draw (nur intern) | gemeinsame Hilfe für Effekte, Markierungen und Linien als Pixel-Art auf dem Kunstpixel-Raster (D-218); Code `PixelDraw`, `PixelLine`, `PixelRingWave`, in der Seitenansicht noch `SidePixels` | D-218, FS1, FS2 |
| Wick | Wick | Standard-Spielfigur (eine der vier wählbaren Figuren neben Ember, Moss, Frost); in beiden Sprachen „Wick“ (Deutsch bisher „Docht“); Code-ID und Dateien `wick` | TR `CHARACTER_WICK`, D-198 |
| Dorftiere | village animals (Vorschlag) | Huhn, Katze und weitere Tiere im Dorf; reagieren auf Ansprechen (streicheln, füttern), nur Optik | WK12, D-196 |
| Füttern, Streicheln | feed, pet | Aktionen beim Ansprechen eines Dorftiers (Huhn füttern, Katze streicheln); TR `VILLAGE_ANIMAL_FEED`, `_PET`. ⚠ uneinheitlich: englisch „pet“ ist hier das Verb, „Pet“ (Haustier-Begleiter, WK4) das Nomen | WK12 |
| Dorfhund | village dog (Vorschlag) | drittes Dorftier (Code `dog`), erscheint erst mit eigener Grafik | WK12 |
| Begleiter | companion (Vorschlag) | Figur, die dem Spieler folgt und reagiert. Flint ist der erste Begleiter und die Quelle des Lichtkreises (D-194); Pets sind nur Optik (Vorschlag) | D-175, D-194 |
| Flint erklärt | Flint explains (nur intern) | Erklär-Baukasten: Flint fliegt aus der Welt ins UI unten rechts, spricht in einer Blase, die Kamera fliegt die Ziele ab (Dorf-Rundgang, Übungsgang, neue Raumart) | D-194, KONZEPT §7.2 |
| Gruppen-Hinweis | group hint (nur intern) | im Online-Koop bekommt jeder Erstes-Mal-Hinweis die ganze Gruppe, sobald ein Spieler ihn braucht; alle warten geschützt bis die Neulinge durch sind; Code `NetGuide` | Meldung 2b1a5a87, 23.10.2026 |
| freies Schweben | roaming (nur intern) | Flint schwebt locker um seinen Platz hinter dem Spieler und macht kleine Ausflüge, nur Optik; Code `FlintRoam` | Meldung 7adeacba, 23.10.2026 |
| Huhn | chicken | Neben-Maskottchen, taucht mit Flint auf (Dorf, Gags, selten im Dungeon, Geleit) | D-120, D-175 |
| Pet | pet | weiterer Begleiter auf dem Gerüst von Flint; freispielbar oder kaufbar OFFEN (WK0); nur Optik (Vorschlag) | D-175 |
| Kosmetik | cosmetics (Vorschlag) | Aussehen ohne Spielwert für Spielfigur, Flint und Dorf; freispielbar oder kaufbar, nie Stärke. ⚠ uneinheitlich: im Spiel heute „Anpassungen“/„customization“ (TR `CREATE_COSMETICS_NOTE`) | D-175, D-176 |
| Dorf-Deko | village decor (Vorschlag) | Gegenstände, die man im eigenen Dorf kauft (Gold) und frei aufstellt; je Welt gespeichert | D-174, KONZEPT |
| Dorf besuchen | visit a village (Vorschlag) | das Dorf eines Freundes oder Gildenmitglieds ansehen: gemeinsam im Koop-Raum oder allein als Schnappschuss vom Server, nur ansehen; zum Release im Spiel | D-174, D-179, KONZEPT |

## Käufe

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Werbefrei | Ad-free (Vorschlag) | Einmalkauf auf dem Handy, der die Banner zwischen Runs entfernt; neben Kosmetik das Einzige, was verkauft wird | D-176, ROADMAP CP6 |
| Belohnungsvideo | rewarded video (Vorschlag) | freiwillige Werbung auf dem Handy, nur auf Tipp des Spielers und nie im Kampf; was es gibt, ist OFFEN | D-176, ROADMAP CP6 |

## Noch ohne englischen Text im Spiel

Diese deutschen Texte stehen im Spiel fest im Code statt in `translations.csv` und brauchen noch Schlüssel (englische Begriffe oben bzw. auf der Website):

- Biom-Namen (`dungeon/room_sequence.gd` `get_biome_name`, `dungeon/biomes/*.tres`) und alle Gegner- und Bossnamen (`enemies/data/*.tres` `display_name`, z. B. Skelett, Bogenschütze, Schattenwesen, Nekromant, Splitterschleim).
- Elite-Eigenschaften und Champion-Hinweis (`enemies/enemy_base.gd` `ELITE_NAMES`, `enemies/enemy_hints.gd`, dort auch „Zweite Phase“).
- Portal-Banner „Ein Portal ist erschienen“ (`dungeon/dungeon_manager.gd`) und „Raum %d · Champion/Boss“ (`ui/menus/dungeon_ui.gd`).
