# Glossar Deutsch ↔ Englisch

> **Stand:** 15.10.2026 · **Gilt für:** Spiel (`localization/translations.csv`), Website (`soulwick-platform/apps/web/messages/`) und Plattform (API-Verträge, Admin-Panel).

Dieses Glossar legt fest, wie Spielbegriffe auf Deutsch und Englisch heißen, damit Spiel, Website und Plattform dieselben Wörter benutzen. Englisch ist die Standardsprache, Deutsch die zweite Sprache (D-111). **Regel:** Ein neuer Begriff, den Spieler zu sehen bekommen, wird **zuerst hier** eingetragen, danach in `localization/translations.csv` (Spiel) und in `soulwick-platform/apps/web/messages/en|de/*.json` (Website). Code-Bezeichner (Klassen, Dateien, Enums, Vertragswerte) bleiben Englisch; Werte in `Backticks` stammen aus Code oder API-Verträgen und sind verbindlich. Die Begriffserklärungen in [PRODUKT.md](PRODUKT.md) §10 und die technischen Begriffe in [PRD.md](PRD.md) §8 bleiben bestehen, bei Abweichungen gilt dieses Glossar für die Wortwahl, [DECISIONS.md](DECISIONS.md) für die Regeln.

**Lesehilfe:** ⚠ uneinheitlich = die Quellen benutzen verschiedene Wörter; die Zeile nennt den gewählten Begriff, die Varianten sollen bei der nächsten Überarbeitung angeglichen werden. **Vorschlag** = es gibt noch keinen englischen Text in Spiel oder Website. **OFFEN** = nicht entschieden.
**Quellen-Kürzel:** TR = `localization/translations.csv` (Schlüssel) · WEB = `soulwick-platform/apps/web/messages/{en,de}/landing.json` (sonst Datei genannt) · API = `soulwick-platform/packages/contracts/src/common.ts` · KR = [KONZEPT_RAEUME.md](KONZEPT_RAEUME.md) (für Raumarten und Minispiele gilt [KONZEPT_RAEUME_V2.md](KONZEPT_RAEUME_V2.md), D-120).

## Spielablauf

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Run | run (`runs`) | ein Dungeon-Durchlauf vom Dorf bis Tod, Abbruch oder Portal; Waffen, Upgrades und Run-Gold gelten nur darin | PRD §8, PRODUKT §10, API `RunMode` |
| Raum | room | kleinste Einheit des Dungeons, gezählt ab 1; der höchste Raum zählt für Rekord und Rangliste | PRODUKT §10, TR `HUD_ROOM` |
| Fünferzyklus, Zyklus | cycle of five, cycle | Raum 1–3 Kampf (nach Raum 3 Upgrade-Wahl), 4 Spezialraum, 5 Miniboss bzw. Boss. ⚠ uneinheitlich: WEB `loopText`/`loopSteps` beschreibt „vier Kampfräume, dann Spezialraum“ und „jeder fünfte Raum ist Spezialraum“ | D-005, PRD §4.1, TR `HUD_ROOM_DETAIL`, WEB `loopTitle` |
| Endlosmodus | endless (Vorschlag) | der Dungeon geht nach jedem Boss unbegrenzt weiter; kein eigener Modus, keine Wahl bei Raum 45. ⚠ uneinheitlich: WEB `goldText` nennt noch die Wahl nach Raum 45 | D-073, KONZEPT_ENDLOS |
| Ausgangsportal | exit portal | Portal zurück ins Dorf mit 100 % Run-Gold; immer am Lagerfeuer, in 30 % der Spezialräume. ⚠ uneinheitlich: „Exit-Portal“ (D-073, D-103), im Spiel nur „Portal“ (TR `CONTROLS_INTERACT_NOTE`) | D-073, D-103, WEB `loopText` |
| Gold-Regel | gold rule | 100 % des Run-Golds am Portal, 50 % (aufgerundet) bei Tod oder Abbruch. ⚠ uneinheitlich: „ab Raum 45 bleibt Gold im Run“ (WEB `goldText`) ist durch D-073 überholt | D-039, D-062, PRODUKT §10 |
| Run-Ende: Gefallen, Run abgebrochen, Dungeon verlassen | Run over: You have fallen, Run abandoned, You left the dungeon | die drei Arten, einen Run zu beenden: Tod, Abbruch im Pausemenü, Ausstieg durchs Portal | TR `RUNEND_*`, `GAME_UI_ABORT_RUN` |
| Spielstand, Platz | save, slot | lokaler Spielstand mit Dorf-Fortschritt; mehrere Plätze im Hauptmenü | TR `MENU_SLOTS`, `SLOTS_SLOT_NUMBER` |

## Räume

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Kampfraum | combat room (Banner: „Combat“) | öffnet erst, wenn alle Gegner besiegt sind; Plätze 1–3 im Zyklus | PRD §4.1, TR `ROOM_EYEBROW_COMBAT`, WEB `loopSteps` |
| Raumart | room kind | Aufbau eines normalen Kampfraums: Säubern bzw. Normal (`normal`), Arena (`arena`) und die Minispiele; Abgrund ist seit D-120 keine eigene Raumart mehr (Code `chasm` besteht weiter), Formen und Zutaten sind keine Raumarten | D-100, D-120, KR §3.1 |
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
| Schmiede | Forge | dauerhafte Verbesserungen gegen Gold | D-087, TR `VILLAGE_FORGE` |
| Verbesserung | upgrade (Schmiede) | dauerhafte Stufe in der Schmiede (Vitalität, Startschild, Schärfe, Goldgier, Dash-Training, Arsenal). ⚠ uneinheitlich: Deutsch trennt „Verbesserung“ vom Run-„Upgrade“, Englisch nutzt für beides „upgrade“ (TR `UNLOCK_FORGE_MORE`, WEB `villageList`) | D-087 |
| Handelsposten | Trading Post | Proviant gegen Seelenkristalle. ⚠ uneinheitlich: „Handelshaus“ (WEB de), „Trading post“ (WEB en) | D-078, D-087, TR `VILLAGE_TRADER` |
| Proviant | Provisions | Bonus nur für den nächsten Run: Heiltrank, Glücksamulett, Goldbeutel. ⚠ uneinheitlich: „Heiltrank“ ist im Spiel sowohl „Healing Potion“ (TR `BOOST_POTION_NAME`, dort de „Heiltrank-Proviant“) als auch „Healing Draught“ (TR `SHOP_HEAL_NAME`) | D-078, TR `VILLAGE_UI_PROVISIONS` |
| Chronik | Chronicle | Rekorde und Statistiken | D-087, TR `VILLAGE_CHRONICLE` |
| Gildenhaus | Guild hall | Dorfgebäude für Koop-Lobby und Gilden (in Vorbereitung). ⚠ uneinheitlich: im Spiel „Gilde“/„Guild“ (TR `VILLAGE_GUILD`), D-078 „Gilde“ | PRODUKT §3, WEB `villageList` |
| Zuhause | Home | eigenes Haus mit Kleiderschrank für die Kleidungsfarbe | TR `VILLAGE_HOME`, WEB `villageList` |

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
| Seelenkristall | Soul crystal (kurz: crystal) | zweite Währung für Proviant; von Bossen, Champions, makellosen Prüfungen, Wagnis-Altar, Elite-Nest und Geheimnischen | D-078, D-087, D-109, TR `RUNEND_CRYSTALS` |

## Online

| Deutsch | English | Bedeutung | Quelle |
| --- | --- | --- | --- |
| Konto | account | Soulwick-Konto = Spieler auf dem Server, ohne E-Mail und Passwort, im Spiel löschbar | D-108, PRODUKT §5 |
| Identität | identity (`player_identities`) | ein Plattform-Login am Konto: `steam`, `device`, `google_play`, `game_center` | D-108, PRODUKT §10 |
| Gilde | guild (`guild`, `guilds`) | dauerhafte Gruppe, eine je Spieler, höchstens 30 Mitglieder; hat Name und Kürzel (`GuildTag`, 2–5 Zeichen) | D-080, API `GuildName`, `GuildTag` |
| Gründer, Offizier, Mitglied | founder, officer, member (`GuildRole`) | Rollen in einer Gilde | API `GuildRole`, `apps/admin/src/lib/format.ts` |
| Einladungscode | invite code | Code für den Beitritt zu einer Gilde | D-080, API `InviteCode`, WEB `guildCardText` |
| Gildenkasse | Guild treasury | Gold der Gilde aus Gilden-Runs nach der Gold-Regel (Vorschlag D-081) | D-081, WEB `guildChips` |
| Gilden-Schmiede | Guild forge | Verbesserungen wie in der Schmiede, gelten in Gilden-Runs für alle Mitglieder (Vorschlag D-081) | D-081, WEB `guildChips` |
| Gilden-Run | guild run (`guild`) | Run nur mit Mitgliedern einer Gilde; zählt für Gildenkasse und Gilden-Rangliste | D-080, API `RunMode`, WEB `guildCardText` |
| Schnelles Spiel | quick play (`quick`) | Koop ohne Bindung, ohne Dorf-Boni und ohne Auszahlung | D-080, D-081, PRODUKT §10, API `RunMode` |
| gemeinsame Kasse | shared gold (Vorschlag) | im Multiplayer gehört das Run-Gold allen; jeder darf daraus kaufen | D-081 |
| Koop | co-op | 2–4 Spieler gemeinsam in einem Run, jeder in eigener Farbe | D-084, WEB `coopCardTitle` |
| Host, Client | host, client | der Host rechnet die Spielwelt, die anderen sind Clients | D-119, PRODUKT §10, TR `VILLAGE_UI_LOBBY_HOST` |
| Wiederbeleben | revive (Vorschlag) | gefallene Mitspieler durch 2 s Danebenstehen zurückholen | D-084 |
| Lobby | lobby | Sammelpunkt vor einem Koop-Run | TR `VILLAGE_UI_LOBBY_CREATE`, WEB `villageList` |
| Raumcode | room code (Vorschlag) | Code, mit dem man einer Lobby auf dem eigenen Relay (`soulwick-relay`) beitritt; nicht mit dem Dungeon-Raum verwechseln | D-119, ROADMAP_CROSSPLAY CP3 |
| Rangliste | leaderboard (`leaderboards`) | Wertung nach höchstem Raum, bei Gleichstand kürzere Zeit | D-082, WEB `leaderboards.json` |
| Tafel: Solo, Gruppe, Gilden | board: Solo, Group, Guilds (`solo`, `group`, `guild`) | Solo-Runs je Spieler; Gruppe = Schnelles Spiel und Gilden-Runs je Spieler; Gilden = Gilden-Runs je Gilde. ⚠ uneinheitlich: WEB `lbTabs` „Spieler Solo/Spieler Gruppe“ bzw. „Players solo/Players group“ | API `LeaderboardKind`, WEB `leaderboards.json` `kinds` |
| Saison, Allzeit | season, all-time (`season`, `all`) | Kalendermonat (`YYYY-MM`, UTC) bzw. gesamter Zeitraum | D-082, API `LeaderboardPeriod`, `SeasonId` |
| Run-Bericht | run report (Vorschlag) | Meldung des Hosts am Run-Ende (Modus, Teilnehmer, Raum, Zeit, Seed, Version); verdächtige Runs werden markiert und geprüft | D-082, PRODUKT §5 |
| Crossplay | crossplay | zusammen spielen über Steam, Google Play und App Store hinweg | D-108, D-119, WEB `platformNote` |

## Noch ohne englischen Text im Spiel

Diese deutschen Texte stehen im Spiel fest im Code statt in `translations.csv` und brauchen noch Schlüssel (englische Begriffe oben bzw. auf der Website):

- Biom-Namen (`dungeon/room_sequence.gd` `get_biome_name`, `dungeon/biomes/*.tres`) und alle Gegner- und Bossnamen (`enemies/data/*.tres` `display_name`, z. B. Skelett, Bogenschütze, Schattenwesen, Nekromant, Splitterschleim).
- Elite-Eigenschaften und Champion-Hinweis (`enemies/enemy_base.gd` `ELITE_NAMES`, `enemies/enemy_hints.gd`, dort auch „Zweite Phase“).
- Portal-Banner „Ein Portal ist erschienen“ (`dungeon/dungeon_manager.gd`) und „Raum %d · Champion/Boss“ (`ui/menus/dungeon_ui.gd`).
